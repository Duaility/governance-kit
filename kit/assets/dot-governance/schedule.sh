#!/usr/bin/env bash
# governance-kit:managed kit-version=0.13.0
# .governance/schedule.sh — the engine behind `run.sh --scheduled`, the at-rest
# half of the kit's ONE judgment primitive.
#
# The kit has exactly one semantic-judgment primitive: a rubric-framed model
# judgment declared once in a directive's `judge:` block, whose judge
# execution lives in typed config. The two lanes are two MOMENTS of the same
# judgment:
#
#   attest   (commit, live session)  the live session's gate — `judge_attest`,
#                                    the remediation loop, `gate: record|verdict`.
#   schedule (at rest, no session)   this driver: the same declaration, replayed
#                                    through the same lib.sh prompt builder and
#                                    the schedule judge resolution ladder below —
#                                    the directive's author-fixed `SCHEDULE_CMD`.
#
# A cadence is a directive-owned cron group: the generated workflow names its
# members and the runtime keeps state partitioned by a stable cadence id. Every
# piece of state this driver keeps is cadence-scoped — the digest label, the
# resume marker, and the issue title — so different crons over the same
# directive never collide.
#
# Judges never block where they run; gates block where they read. A judgment
# rendered here writes one of two things:
#
#   * an adjudication round into a not-yet-frozen receipt — which the EXISTING
#     `gate: verdict` commit/CI gate then reads, so an at-rest REFUTED turns
#     the next commit red through a mechanism that already exists; or
#   * a finding into the `governance-schedule-<lane>` digest issue — the
#     canonical human → issue → agent → PR door — when the receipt is already
#     frozen on the trunk, or the directive names no `section:` at all
#     (discovery).
#
# MECHANICAL members are the one exception, and it is not an exception to the
# rule but the other half of it: a `check.sh` failure is a FACT, not a
# judgment, and facts fail jobs. Any mechanical member failing makes this run
# exit non-zero, so the lane's workflow goes red like any other CI failure.
#
# Honesty rule: no `SCHEDULE_CMD` resolves → the judgment is reported
# un-adjudicated and retried
# later. Never a downgraded judge, never a guessed verdict, never a keyword stub
# standing in for a model. A digest must never read as a clean bill for work
# that was not actually judged.
#
# Usage (the documented entry point is `run.sh --scheduled`):
#   bash .governance/schedule.sh run --lane <name>
#                                    [--range A..B] [--dry-run]
#                                    [--no-gh] [--since '<git date expression>']
#                                    <member>...
#   bash .governance/schedule.sh usage
#
# Environment:
#   GOVERNANCE_SCHEDULE_TRUNK   the ref that decides which receipts are frozen
#                               (default: the first resolvable of origin/HEAD,
#                               origin/main, origin/master, main, master).
#   GH_TOKEN / `gh auth`        resume point, dedupe and digest filing. All
#                               optional: with no gh the digest goes to stderr.
#
# Schedule judge resolution ladder (per directive, checked in this order):
#   1. the directive's fixed `SCHEDULE_CMD` config.
#   2. nothing resolves → the directive is skipped with one honest log line and
#      reported un-adjudicated in the digest, never guessed.
#
# Bash 3.2 + POSIX awk + git, plus `gh` when it is there. No python.

set -u

usage() {
    cat >&2 <<'EOF'
governance schedule — at-rest adjudication of a named lane's members.

  bash .governance/run.sh --scheduled --lane <name> \
      [--range A..B] [--dry-run] [--no-gh] \
      [--since '<git date expression>'] <member>...

Members are positional and at least one is required: a bare `<id>` (every
homonym across packs) or a qualified `<owner>/<pack>/<id>`. A member that
matches nothing, or that is not eligible for the `schedule` trigger, exits 2.

Mechanical `check.sh` members fail the run (facts fail jobs). Judge members
never do: their findings land as adjudication rounds in editable receipts (read
by the existing gate: verdict gate) or in one `governance-schedule-<lane>`
digest issue.
EOF
}

# ── Locate lib.sh: the prompt builder, the declaration reader, the round
#    appender, the cmd resolver/judge and the stamp all live there, and this
#    driver reuses every one of them. A driver that carried its own copy would
#    be a second engine, which is the thing this file exists to delete.
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
LIB_SH=""
for _cand in \
    "${GOVERNANCE_ROOT:+$GOVERNANCE_ROOT/lib.sh}" \
    "$HERE/lib.sh" \
    "$ROOT/.governance/lib.sh"
do
    [[ -n "$_cand" && -f "$_cand" ]] || continue
    LIB_SH="$_cand"
    break
done
if [[ -z "$LIB_SH" ]]; then
    printf 'governance schedule: no lib.sh reachable (looked at $GOVERNANCE_ROOT/lib.sh, %s/lib.sh, %s/.governance/lib.sh) — nothing judged\n' \
        "$HERE" "$ROOT" >&2
    exit 0
fi
# shellcheck disable=SC1090
source "$LIB_SH"

# The field separator for this driver's directive table. Shared with lib.sh so
# both ends of the spec agree; a tab would not survive `read`, which collapses
# runs of IFS whitespace and would shift every field after an empty one.
RS="${_JUDGE_RS:-$'\x1e'}"

# ── gh plumbing (all optional) ──────────────────────────────────────────────
# `gh` carries three things: the resume point, the dedupe set, and the digest
# itself. Every one of them degrades to "do the work anyway and print it".

_schedule_gh_read_ok() { [[ "$NO_GH" == "0" ]] && command -v gh >/dev/null 2>&1; }
_schedule_gh_write_ok() { _schedule_gh_read_ok && [[ "$DRY_RUN" == "0" ]]; }

# _schedule_issue_bodies <state> <limit> — the bodies of this LANE's recent
#   digest issues. Another lane's digests carry another label and are invisible
#   here, which is what keeps two cadences from clobbering each other.
_schedule_issue_bodies() {
    gh issue list --label "$LABEL" --state "$1" --limit "$2" \
        --json body --jq '.[].body' 2>/dev/null || true
}

# _schedule_last_end_sha — the resume point recorded by this lane's previous
#   digest. The marker is lane-scoped for the same reason the label is.
_schedule_last_end_sha() {
    _schedule_issue_bodies all 1 \
        | sed -n "s/.*governance-schedule:$LANE:end=\([0-9a-f]\{7,40\}\).*/\1/p" \
        | head -n 1
}

# _schedule_open_pairs — `<directive>|<file>` pairs already reported in an OPEN
#   digest of this lane, so an unfixed finding does not multiply daily.
_schedule_open_pairs() {
    _schedule_issue_bodies open 20 \
        | sed -n 's/.*<!-- finding: \([^|]*\) | \([^>]*\) -->.*/\1|\2/p' \
        | sed 's/[[:space:]]*|[[:space:]]*/|/; s/[[:space:]]*$//' \
        | sort -u
}

# _schedule_ensure_label — idempotently create this lane's digest label; 0 iff
#   it exists afterwards. Nothing in the install path creates it, so the first
#   run of a new lane must.
_schedule_ensure_label() {
    local err
    err="$(gh label create "$LABEL" \
        --description "Digest issues filed by the governance scheduled lane \`$LANE\`" \
        --color 5319E7 2>&1)" && return 0
    case "$err" in *"already exists"*) return 0 ;; esac
    return 1
}

# ── Directive discovery ─────────────────────────────────────────────────────
# Membership is explicit: the lane names its members and this driver resolves
# each token against the installed (or source) directive tree. There is no
# `surface:` value and no `judge:` block that opts a directive in by itself —
# `triggers:` decides ELIGIBILITY, the member list decides membership.
_schedule_directive_yamls() {
    local base
    for base in "$ROOT/.governance/packs" "$ROOT/packs"; do
        [[ -d "$base" ]] || continue
        find "$base" -type f -name directive.yaml -path '*/directives/*' 2>/dev/null | sort
        return 0
    done
}

# _schedule_lib_call <directive-dir> <function> [<args>…]
#   Call a lib.sh helper with $0 set to the directive's check.sh, because the
#   conf ladder derives the pack-qualified overlay path from $0 whenever it is
#   handed no full id. Stdin/stdout/stderr of the caller pass through untouched.
_schedule_lib_call() {
    local dir="$1"
    shift
    local fn="$1"
    shift
    GK_LIB="$LIB_SH" GK_FN="$fn" \
        bash -c 'set +u; source "$GK_LIB"; "$GK_FN" "$@"' "$dir/check.sh" "$@"
}

# _schedule_cmd_label <cmd> → the first word of a judge cmd, for honest logging.
_schedule_cmd_label() { printf '%s' "${1%% *}"; }

# ── Judging ─────────────────────────────────────────────────────────────────

# _schedule_record_call — record one judge invocation for the digest footer.
_schedule_record_call() {
    JUDGED=$((JUDGED + 1))
}

# _schedule_verdict <out-file> → PASS | REFUTED | (nothing)
#   The first VERDICT line of the normalized answer for one directive.
_schedule_verdict() {
    awk '/^VERDICT:/ { print $2; exit }' "$1"
}

# _schedule_reason <out-file> → one ASCII line, capped. Same normalization the
#   commit lane applies: a judge's prose is untrusted output like any other.
_schedule_reason() {
    local r
    r="$(awk '/^REASON:/ { sub(/^REASON:[ \t]*/, ""); printf "%s%s", (n++ ? " " : ""), $0 } END { print "" }' "$1" \
        | LC_ALL=C tr -d '\r' | LC_ALL=C tr '\n' ' ' \
        | LC_ALL=C tr -cd '[:print:] ' | cut -c1-200)"
    printf '%s' "${r%"${r##*[![:space:]]}"}"
}

# _schedule_unadj <row-index> <text>
#   Record work that was NOT judged, under the directive it belonged to. Every
#   path that skips a judgment goes through here: a digest that stays silent
#   about what it could not adjudicate reads as a clean bill, which is the one
#   thing this lane must never produce.
_schedule_unadj() {
    printf -- '  - %s\n' "$2" >> "$WORK/u.$1"
    UNADJ=$((UNADJ + 1))
}

# _schedule_record_finding <row-index> <directive-id> <fallback-file> <loc>
#                          <text>
#   One digest row plus its dedupe marker, filed under the directive that owns
#   it. <loc> is `<path>:<line>` as the judge reported it; the marker keys on
#   the path alone so a moved line does not file the same finding twice. In
#   With per-directive `commits` evidence the row carries the short sha prefix, so
#   a per-commit lane's digest reads as a timeline.
_schedule_record_finding() {
    local idx="$1" id="$2" fallback="$3" loc="$4" text="$5" file
    file="${loc%%:*}"
    [[ -n "$file" && "$file" != "-" ]] || { file="$fallback"; loc="$fallback"; }
    if grep -qxF "$id|$file" "$WORK/pairs" 2>/dev/null; then
        DUP=$((DUP + 1))
        return 0
    fi
    printf -- '- **%s** — %s%s\n' "$loc" "$SHA_PREFIX" "$text" >> "$WORK/f.$idx"
    printf -- '<!-- finding: %s | %s -->\n' "$id" "$file" >> "$WORK/markers"
    FINDINGS=$((FINDINGS + 1))
}

# _schedule_findings_from <block-file> <row-index> <directive-id>
#                         <fallback-file> <reason>
#   Turn a REFUTED answer into digest rows. A REFUTED with no FINDING line still
#   files one row built from the reason — a refutation the digest swallows is a
#   verdict nobody acts on.
_schedule_findings_from() {
    local out="$1" idx="$2" id="$3" fallback="$4" reason="$5" line loc text n=0
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        line="${line#FINDING:}"
        line="${line#"${line%%[![:space:]]*}"}"
        loc="${line%%[[:space:]]*}"
        text="${line#"$loc"}"
        text="${text#"${text%%[![:space:]]*}"}"
        [[ -n "$text" ]] || text="$reason"
        _schedule_record_finding "$idx" "$id" "$fallback" "$loc" "$text"
        n=$((n + 1))
    done < <(grep '^FINDING:' "$out" 2>/dev/null | cut -c1-300)
    [[ "$n" -gt 0 ]] || _schedule_record_finding "$idx" "$id" "$fallback" "$fallback" "$reason"
}

# The stamp a queued round carries until the file settles. It is a well-formed
# round line by construction, so it is stripped from the very hash it waits for.
_SCHEDULE_STAMP_TBD="000000000000"

# _schedule_queue_round <row-index> <id> <receipt> <section> <verdict> <reason>
_schedule_queue_round() {
    printf "%s${RS}%s${RS}%s${RS}%s${RS}%s${RS}%s\n" "$@" >> "$WORK/rounds"
}

# _schedule_flush_rounds <receipt-abs>
#   Write every round this judgment produced, then bind them all to the tree —
#   through the same two lib.sh helpers the commit lane uses, and with the two
#   differences that define this lane: the rounds are NOT staged (at rest, the
#   next commit picks them up), and the round line reads `lane=schedule`
#   (matching the commit lane's own round format — same field, same position).
#
#   Two phases, because a round line is only immune to the stamp while the rest
#   of the file holds still: creating a section adds a heading, and appending
#   into a NON-final section inserts a blank line — both are hashed. So every
#   section is created, then every round lands with a placeholder stamp, then
#   the settled file is hashed exactly ONCE and the placeholder is filled in.
#   One judgment, one stamp, and every round it produced verifies against the
#   tree the gate will later recompute.
_schedule_flush_rounds() {
    local abs="$1" idx id receipt section verdict reason next stamp tmp
    [[ -s "$WORK/rounds" ]] || return 0

    while IFS="$RS" read -r idx id receipt section verdict reason; do
        [[ -n "$section" ]] || continue
        _judge_ensure_section "$abs" "$section" || true
    done < "$WORK/rounds"

    : > "$WORK/rounds.done"
    while IFS="$RS" read -r idx id receipt section verdict reason; do
        [[ -n "$idx" ]] || continue
        next="$(_judge_round_lines "$abs" "$section" \
            | awk '{ n = $0; sub(/^- \[round /, "", n); sub(/\].*$/, "", n); if (n + 0 > m) m = n + 0 } END { print m + 1 }')"
        [[ "$next" =~ ^[0-9]+$ ]] || next=1
        if _judge_append_round "$abs" "$section" \
            "- [round ${next}] ${verdict} lane=schedule stamp=${_SCHEDULE_STAMP_TBD} — schedule[${LANE}]: ${reason}"; then
            printf "%s${RS}%s${RS}%s${RS}%s${RS}%s${RS}%s\n" \
                "$idx" "$id" "$receipt" "$section" "$next" "$verdict" >> "$WORK/rounds.done"
        else
            _schedule_unadj "$idx" "$receipt (the round could not be written)"
        fi
    done < "$WORK/rounds"
    : > "$WORK/rounds"
    [[ -s "$WORK/rounds.done" ]] || return 0

    stamp="$(_adjudication_stamp "$abs")" || stamp=""
    if [[ -z "$stamp" ]]; then
        while IFS="$RS" read -r idx id receipt section next verdict; do
            [[ -n "$idx" ]] || continue
            _schedule_unadj "$idx" "$receipt (no adjudication stamp could be computed — the round cannot be trusted)"
        done < "$WORK/rounds.done"
        return 0
    fi
    tmp="$(mktemp "${TMPDIR:-/tmp}/gk-schedule-stamp.XXXXXX")" || return 0
    if LC_ALL=C sed "s/stamp=${_SCHEDULE_STAMP_TBD}/stamp=${stamp}/g" "$abs" > "$tmp"; then
        cat "$tmp" > "$abs"
    fi
    rm -f "$tmp"
    while IFS="$RS" read -r idx id receipt section next verdict; do
        [[ -n "$idx" ]] || continue
        ROUNDS=$((ROUNDS + 1))
        printf 'governance schedule: %s → %s round %s in %s "## %s" (lane=schedule)\n' \
            "$id" "$verdict" "$next" "$receipt" "$section" >&2
    done < "$WORK/rounds.done"
}

# _schedule_trunk → the ref that decides "already frozen", or return 1.
_schedule_trunk() {
    if [[ -n "${GOVERNANCE_SCHEDULE_TRUNK:-}" ]]; then
        printf '%s' "$GOVERNANCE_SCHEDULE_TRUNK"
        return 0
    fi
    local c
    for c in origin/HEAD origin/main origin/master main master; do
        if git rev-parse --verify --quiet "$c" >/dev/null 2>&1; then
            printf '%s' "$c"
            return 0
        fi
    done
    return 1
}

# _schedule_frozen <repo-relative-path> — 0 when the file already exists on the
#   trunk. Same notion doc-integrity uses: once a receipt is on the default
#   branch it is immutable, so a re-adjudication of it can only be filed, never
#   appended.
_schedule_frozen() {
    [[ -n "$TRUNK" ]] || return 1
    git cat-file -e "$TRUNK:$1" 2>/dev/null
}

# _schedule_receipts_in_range — receipts touched by the range under judgment,
#   newest commit first so a later run always revisits the freshest work first.
_schedule_receipts_in_range() {
    git log --pretty=format: --name-only --diff-filter=AMR "$RANGE" -- 'receipts/*.md' 2>/dev/null \
        | awk 'NF && !seen[$0]++'
}

# ── Independent directive judgments ─────────────────────────────────────────
# Every scheduled directive is judged in its own command invocation. Directives
# that share a cron only share the workflow trigger; they never share a prompt,
# rubric, or response stream.

# _schedule_subject <lane-kind> <receipt> — what a report line is about.
_schedule_subject() {
    if [[ "$1" == "attest" ]]; then printf '%s' "$2"; else printf 'the range %s' "$RANGE"; fi
}

# _schedule_consume <lane-kind> <row-index> <id> <section> <receipt> <abs>
#                   <answer-file> <cmd>
#   Consume one directive's normalized answer and either queue its receipt round
#   or file its findings. Each answer belongs to exactly one directive.
_schedule_consume() {
    local lane="$1" idx="$2" id="$3" section="$4" receipt="$5" abs="$6" answer="$7" cmd="$8"
    local verdict reason subject label
    subject="$(_schedule_subject "$lane" "$receipt")"
    label="$(_schedule_cmd_label "$cmd")"

    verdict="$(_schedule_verdict "$answer")"
    case "$verdict" in
        PASS | REFUTED) ;;
        *)
            _schedule_unadj "$idx" "$subject (cmd:$label answered outside the verdict grammar)"
            return 0
            ;;
    esac
    reason="$(_schedule_reason "$answer")"
    [[ -n "$reason" ]] || reason="adjudicated at rest by cmd:$label"

    if [[ "$lane" == "discovery" ]]; then
        [[ "$verdict" == "REFUTED" ]] || return 0
        _schedule_findings_from "$answer" "$idx" "$id" "$RANGE" "$reason"
        return 0
    fi

    if _schedule_frozen "$receipt"; then
        [[ "$verdict" == "REFUTED" ]] || return 0
        _schedule_findings_from "$answer" "$idx" "$id" "$receipt" "$reason"
        printf 'governance schedule: %s is frozen on %s — %s REFUTED filed to the digest\n' \
            "$receipt" "$TRUNK" "$id" >&2
        return 0
    fi
    if [[ "$DRY_RUN" == "1" ]]; then
        printf 'governance schedule: would append a %s round for %s to %s "## %s"\n' \
            "$verdict" "$id" "$receipt" "$section" >&2
        return 0
    fi
    _schedule_queue_round "$idx" "$id" "$receipt" "$section" "$verdict" "$reason"
}

# _schedule_run_one <lane-kind> <row-file> [<receipt>] [<receipt-abs>]
#   Run exactly one directive judge. The row is RS-separated:
#   <index> ␞ <id> ␞ <section-or-empty> ␞ <directive.yaml> ␞ <checks-US> ␞ <cmd>
_schedule_run_one() {
    local lane="$1" row="$2" receipt="${3:-}" abs="${4:-}"
    local idx id section yaml checks cmd
    IFS="$RS" read -r idx id section yaml checks cmd < "$row"
    [[ -n "$idx" && -n "$cmd" ]] || return 0
    local dir0
    dir0="$(dirname "$yaml")"
    _schedule_record_call
    _judge_prompt "$abs" "$section" "$checks" "$yaml" "$RANGE" schedule > "$WORK/prompt"
    if ! _schedule_lib_call "$dir0" _judge_cmd_run "$cmd" < "$WORK/prompt" > "$WORK/out"; then
        _schedule_unadj "$idx" "$(_schedule_subject "$lane" "$receipt") (cmd:$(_schedule_cmd_label "$cmd") rendered no verdict)"
        return 0
    fi
    _schedule_consume "$lane" "$idx" "$id" "$section" "$receipt" "$abs" "$WORK/out" "$cmd"
    [[ "$lane" == "attest" ]] && _schedule_flush_rounds "$abs"
}
# ── The two judge lanes ─────────────────────────────────────────────────────

# _schedule_lane_discovery
#   No section means discovery-only. Each eligible directive gets its own
#   command invocation, even when another directive uses the same cron.
_schedule_lane_discovery() {
    local idx id dir yaml section cmd checks summary
    while IFS="$RS" read -r idx id dir yaml section cmd checks summary; do
        [[ -z "$section" ]] || continue
        [[ -n "$cmd" ]] || continue
        printf "%s${RS}%s${RS}${RS}%s${RS}%s${RS}%s\n" \
            "$idx" "$id" "$yaml" "$checks" "$cmd" > "$WORK/one"
        _schedule_run_one discovery "$WORK/one"
    done < "${ROWS_FILE:-$WORK/rows}"
}

# _schedule_lane_attest
#   Attestation-backed directives are judged independently for each receipt.
_schedule_lane_attest() {
    local receipt abs idx id dir yaml section cmd checks summary
    while IFS= read -r receipt; do
        [[ -n "$receipt" ]] || continue
        abs="$ROOT/$receipt"
        [[ -f "$abs" ]] || continue
        while IFS="$RS" read -r idx id dir yaml section cmd checks summary; do
            [[ -n "$section" ]] || continue
            [[ -n "$cmd" ]] || continue
            if grep -qxF "$id|$receipt" "$WORK/pairs" 2>/dev/null; then
                DUP=$((DUP + 1))
                continue
            fi
            printf "%s${RS}%s${RS}%s${RS}%s${RS}%s${RS}%s\n" \
                "$idx" "$id" "$section" "$yaml" "$checks" "$cmd" > "$WORK/one"
            _schedule_run_one attest "$WORK/one" "$receipt" "$abs"
        done < "${ROWS_FILE:-$WORK/rows}"
    done < <(_schedule_receipts_in_range)
}

# _schedule_judge_pass — one full judging pass over the current $RANGE: the
#   discovery lane, then the attestation lane. Called once for range evidence
#   and once per commit for commits evidence, which is the only
#   difference between the two modes on the judge side.
_schedule_judge_pass() {
    export GOVERNANCE_SCHEDULE_RANGE="$RANGE"
    _schedule_lane_discovery
    _schedule_lane_attest
}

# ── The mechanical members ──────────────────────────────────────────────────
# A `check.sh` is a fact, and facts fail jobs. These members are run exactly the
# way run.sh runs them — same script, same exit convention — with the change-set
# base pointed at the evidence this lane judges, so a change-set directive
# measures the scheduled range instead of the branch it would measure at commit
# time.

# _schedule_run_check <dir> <id> <base> <cwd> <what>
#   Run one mechanical member. A non-zero exit is collected (MECH_FAIL) and
#   reported; it never stops the run, because every member's facts are worth
#   collecting before the job goes red.
_schedule_run_check() {
    local dir="$1" id="$2" base="$3" cwd="$4" what="$5"
    if ( cd "$cwd" && GOVERNANCE_CHANGE_SET_BASE="$base" bash "$dir/check.sh" ); then
        return 0
    fi
    MECH_FAIL=$((MECH_FAIL + 1))
    printf 'governance schedule: %s FAILED over %s — a mechanical check is a fact, so this run fails\n' \
        "$id" "$what" >&2
    return 1
}

# _schedule_mech_pass <base> <cwd> <what>
#   Every mechanical member, once, against one piece of evidence.
_schedule_mech_pass() {
    local base="$1" cwd="$2" what="$3" id dir
    [[ -s "${MECH_FILE:-$WORK/mech}" ]] || return 0
    while IFS="$RS" read -r id dir; do
        [[ -n "$id" ]] || continue
        _schedule_run_check "$dir" "$id" "$base" "$cwd" "$what" || true
    done < "${MECH_FILE:-$WORK/mech}"
}

# _schedule_mech_at_commit <commit> <parent>
#   The per-directive `commits` shape: mechanical members see the repo AS IT
#   WAS at <commit>, with the change-set base at its parent — which is the state
#   the commit's own pre-commit hook saw. A detached `git worktree` is the only
#   way to get that without touching the caller's checkout, and it is removed
#   whatever happens, including on a check that kills the shell.
_schedule_mech_at_commit() {
    local commit="$1" parent="$2" wt rc=0
    [[ -s "${MECH_FILE:-$WORK/mech}" ]] || return 0
    wt="$(mktemp -d "${TMPDIR:-/tmp}/gk-schedule-wt.XXXXXX")" || return 0
    rm -rf "$wt"
    if ! git worktree add --detach "$wt" "$commit" >/dev/null 2>&1; then
        printf 'governance schedule: could not check out %s in a temporary worktree — its mechanical members were not run\n' \
            "$commit" >&2
        return 0
    fi
    trap 'git worktree remove --force "$wt" >/dev/null 2>&1; rm -rf "$wt"; rm -rf "$WORK"' EXIT
    _schedule_mech_pass "$parent" "$wt" "commit $SHORT_SHA" || rc=$?
    git worktree remove --force "$wt" >/dev/null 2>&1 || true
    rm -rf "$wt"
    trap 'rm -rf "$WORK"' EXIT
    return "$rc"
}

# ── The digest ──────────────────────────────────────────────────────────────
_schedule_render_digest() {
    printf 'Automated scheduled adjudication (lane `%s`). Nothing here blocked a commit,\n' "$LANE"
    printf 'a push or a PR: these are candidates for the issue → agent → PR loop, judged\n'
    printf 'at rest by each directive'"'"'s fixed `SCHEDULE_CMD`.\n\n'
    if [[ -s "$WORK/sections" ]]; then
        cat "$WORK/sections"
    else
        printf '_No findings this run._\n'
    fi
    printf '\n---\n\n'
    printf '### Footer\n'
    printf -- '- lane: `%s`\n' "$LANE"
    printf -- '- commit range: `%s`\n' "$FULL_RANGE"
    printf -- '- evidence: per member (`SCHEDULE_EVIDENCE`, else derived from `surface`)\n'
    printf -- '- judge: per-directive fixed `SCHEDULE_CMD`\n'
    printf -- '- judge directives in this lane: %s\n' "$DIRS"
    printf -- '- mechanical directives in this lane: %s (failed: %s)\n' "$MECH" "$MECH_FAIL"
    printf -- '- judge calls made: %s\n' "$JUDGED"
    printf -- '- un-adjudicated (NOT a clean bill): %s\n' "$UNADJ"
    printf -- '- rounds appended to editable receipts: %s\n' "$ROUNDS"
    printf -- '- skipped as duplicate of an open digest: %s\n' "$DUP"
    if [[ -s "$WORK/stale" ]]; then
        printf -- '- stale members (advisory):\n'
        sed 's/^/  - /' "$WORK/stale"
    fi
    printf '\n<!-- governance-schedule:%s:end=%s -->\n' "$LANE" "$HEAD_SHA"
    [[ -s "$WORK/markers" ]] && cat "$WORK/markers"
    return 0
}

# ── run ─────────────────────────────────────────────────────────────────────
cmd_run() {
    local explicit_range="" since="24 hours ago"
    local members=()
    LANE=""
    DRY_RUN=0
    NO_GH=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --lane)       LANE="${2:-}"; shift; [[ $# -gt 0 ]] && shift ;;
            --lane=*)     LANE="${1#--lane=}"; shift ;;
            --range)      explicit_range="${2:-}"; shift; [[ $# -gt 0 ]] && shift ;;
            --range=*)    explicit_range="${1#--range=}"; shift ;;
            --since)      since="${2:-}"; shift; [[ $# -gt 0 ]] && shift ;;
            --since=*)    since="${1#--since=}"; shift ;;
            --dry-run)    DRY_RUN=1; shift ;;
            --no-gh)      NO_GH=1; shift ;;
            -*)
                printf 'governance schedule: unknown option %s\n' "$1" >&2
                usage
                return 2
                ;;
            *)            members+=("$1"); shift ;;
        esac
    done

    # ── The lane names every piece of state this run reads or writes, so an
    #    unnamed or oddly-named lane is a config bug, not a default to guess.
    if [[ -z "$LANE" ]]; then
        printf 'governance schedule: --lane <name> is required — every digest label, resume marker and round line is lane-scoped\n' >&2
        usage
        return 2
    fi
    if [[ ! "$LANE" =~ ^[a-z0-9-]+$ ]]; then
        printf 'governance schedule: invalid lane name `%s` — lowercase letters, digits and hyphens only (it names a workflow file, a label and a marker)\n' \
            "$LANE" >&2
        return 2
    fi
    if [[ ${#members[@]} -eq 0 ]]; then
        printf 'governance schedule: at least one member is required — a lane names its members explicitly (eligibility is not membership)\n' >&2
        usage
        return 2
    fi

    LABEL="governance-schedule-$LANE"

    HEAD_SHA="$(git rev-parse HEAD 2>/dev/null)" || HEAD_SHA=""
    if [[ -z "$HEAD_SHA" ]]; then
        printf 'governance schedule: not a git repository with commits — nothing judged\n' >&2
        return 0
    fi

    # ── The range. Explicit beats this lane's resume marker beats a time
    #    window; a repo with no history judges from its root commit.
    local start=""
    if [[ -n "$explicit_range" ]]; then
        RANGE="$explicit_range"
    else
        _schedule_gh_read_ok && start="$(_schedule_last_end_sha)"
        [[ -n "$start" ]] || start="$(git rev-list -1 "--before=$since" HEAD 2>/dev/null)"
        [[ -n "$start" ]] || start="$(git rev-list --max-parents=0 HEAD 2>/dev/null | tail -n 1)"
        if [[ -n "$start" && "$start" != "$HEAD_SHA" ]]; then
            RANGE="$start..$HEAD_SHA"
        else
            RANGE="$HEAD_SHA"
        fi
    fi
    # The whole lane's range, kept while $RANGE narrows to one commit's diff in
    # commits evidence. The footer and the resume marker speak about this
    # one; a judgment speaks about whatever it actually read.
    FULL_RANGE="$RANGE"
    # The start of the range, which is the change-set base a mechanical member
    # measures against in range evidence — empty for a single-commit range,
    # where the member falls back to lib.sh's own base resolution.
    local range_start=""
    case "$FULL_RANGE" in *..*) range_start="${FULL_RANGE%%..*}" ;; esac

    TRUNK="$(_schedule_trunk)" || TRUNK=""

    WORK="$(mktemp -d "${TMPDIR:-/tmp}/gk-schedule.XXXXXX")" || return 0
    trap 'rm -rf "$WORK"' EXIT
    : > "$WORK/sections"
    : > "$WORK/markers"
    : > "$WORK/pairs"
    : > "$WORK/rows"
    : > "$WORK/mech"
    : > "$WORK/rows.range"
    : > "$WORK/rows.commits"
    : > "$WORK/mech.range"
    : > "$WORK/mech.commits"
    : > "$WORK/stale"
    : > "$WORK/matched"
    _schedule_gh_read_ok && _schedule_open_pairs > "$WORK/pairs"

    DIRS=0; MECH=0; MECH_FAIL=0; JUDGED=0; UNADJ=0; DUP=0; ROUNDS=0; FINDINGS=0
    # Prefixed onto every finding for commits evidence so the digest reads as
    # a timeline; empty for range evidence, where there is one blended diff.
    SHA_PREFIX=""

    # ── The member table. Every directive the lane names, resolved once:
    #   judge members  → one RS row per directive in $WORK/rows
    #     <idx> ␞ id ␞ dir ␞ yaml ␞ section ␞ cmd ␞ checks-US ␞ summary
    #   mechanical ones → `<id> ␞ <dir>` in $WORK/mech
    # `section` is also the judge lane selector — present = attest, absent =
    # discovery. A judge member that resolves no cmd keeps its row (with an
    # empty cmd) and is reported un-adjudicated: it was NAMED by the lane, so
    # silently dropping it would let the digest read as a clean bill.
    local yaml dir id full_id hook triggers cmd section checks c summary tok hit evidence surface staleness
    while IFS= read -r yaml; do
        [[ -n "$yaml" ]] || continue
        dir="$(dirname "$yaml")"
        id="$(basename "$dir")"
        full_id="$(_judge_full_id "$dir")"

        # Membership: a bare token matches every homonym across packs, a
        # qualified one matches exactly one directive — the same breadth
        # `run.sh <filter>` already has.
        hit=""
        for tok in ${members[@]+"${members[@]}"}; do
            case "$tok" in
                */*/*) [[ "$full_id" == "$tok" ]] && hit="$tok" ;;
                *)     [[ "$id" == "$tok" ]] && hit="$tok" ;;
            esac
            [[ -n "$hit" ]] && break
        done
        [[ -n "$hit" ]] || continue
        printf '%s\n' "$hit" >> "$WORK/matched"

        # Eligibility: the effective trigger list must carry `schedule`.
        # Naming an ineligible directive is a config bug — refused loudly here
        # rather than quietly running something the author never scoped for a
        # lane with no session, no index and no staged tree.
        hook="$(_yaml_top_list "$yaml" hook)"
        triggers="$(_schedule_lib_call "$dir" _directive_triggers_resolve \
            "$full_id" "$id" "$yaml" "$hook")"
        case " $triggers " in
            *" schedule "*) ;;
            *)
                printf 'governance schedule: %s is not eligible for the scheduled lane (effective triggers: %s). Add `schedule` to its explicit `triggers:` in directive.yaml\n' \
                    "${full_id:-$id}" "${triggers:-<none>}" >&2
                return 2
                ;;
        esac

        # Mechanical or judge — the `judge:` block decides. A directive with no
        # block is run as the fact it is; one with a block is adjudicated.
        if ! grep -qE '^judge:' "$yaml"; then
            if [[ ! -f "$dir/check.sh" ]]; then
                printf 'governance schedule: %s has neither a `judge:` block nor a check.sh — there is nothing for a lane to run\n' \
                    "${full_id:-$id}" >&2
                return 2
            fi
            MECH=$((MECH + 1))
            surface="$(_yaml_top_list "$yaml" surface)"
            evidence="$( _schedule_lib_call "$dir" conf_get "$id" SCHEDULE_EVIDENCE "$yaml" 2>/dev/null )" || evidence=""
            [[ -n "$evidence" ]] || { [[ "$surface" == "change-set" ]] && evidence=commits || evidence=range; }
            printf "%s${RS}%s\n" "$id" "$dir" >> "$WORK/mech"
            printf "%s${RS}%s\n" "$id" "$dir" >> "$WORK/mech.$evidence"
            continue
        fi

        # Command choice is author-owned. The environment is not a parallel
        # config channel.
        cmd="$(_schedule_lib_call "$dir" _judge_cmd_resolve "$yaml" schedule 2>/dev/null)"
        section="$( _schedule_lib_call "$dir" conf_get "$id" ATTEST_SECTION "$yaml" 2>/dev/null )" || section=""
        surface="$(_yaml_top_list "$yaml" surface)"
        evidence="$( _schedule_lib_call "$dir" conf_get "$id" SCHEDULE_EVIDENCE "$yaml" 2>/dev/null )" || evidence=""
        [[ -n "$evidence" ]] || { [[ "$surface" == "change-set" ]] && evidence=commits || evidence=range; }
        staleness="$( _schedule_lib_call "$dir" conf_get "$id" SCHEDULE_STALENESS_DAYS "$yaml" 2>/dev/null )" || staleness=""
        DIRS=$((DIRS + 1))
        checks=""
        while IFS= read -r c; do
            [[ -n "$c" ]] || continue
            if [[ -z "$checks" ]]; then checks="$c"; else checks="$checks$_JUDGE_US$c"; fi
        done < <(_judge_yaml "$yaml" checks)
        summary="$(awk '/^summary:/ { sub(/^summary:[ \t]*/, ""); gsub(/^["'"'"']|["'"'"']$/, ""); print; exit }' "$yaml")"
        printf "%s${RS}%s${RS}%s${RS}%s${RS}%s${RS}%s${RS}%s${RS}%s\n" \
            "$DIRS" "$id" "$dir" "$yaml" "$section" \
            "$cmd" "$checks" "$summary" \
            | LC_ALL=C tr -d '\r' >> "$WORK/rows"
        tail -n 1 "$WORK/rows" >> "$WORK/rows.$evidence"
        if [[ "$staleness" =~ ^[0-9]+$ ]]; then
            oldest_epoch="$(git log -1 --format=%ct "${FULL_RANGE%%..*}" 2>/dev/null)" || oldest_epoch=""
            now_epoch="$(date +%s)"
            if [[ "$oldest_epoch" =~ ^[0-9]+$ ]] && (( (now_epoch - oldest_epoch) / 86400 > staleness )); then
                printf '%s (declared maximum %s day(s))\n' "${full_id:-$id}" "$staleness" >> "$WORK/stale"
            fi
        fi
        : > "$WORK/f.$DIRS"
        : > "$WORK/u.$DIRS"
        if [[ -z "$cmd" ]]; then
            printf 'governance schedule: %s resolved no schedule judge (`SCHEDULE_CMD` is empty) — reported un-adjudicated, never guessed\n' \
                "${full_id:-$id}" >&2
            _schedule_unadj "$DIRS" "no schedule judge resolved for this lane — declare fixed \`SCHEDULE_CMD\` config"
        fi
    done < <(_schedule_directive_yamls)

    # A member token that matched nothing is a config bug in the lane's own
    # workflow — fail loud rather than judging a silently smaller lane.
    for tok in ${members[@]+"${members[@]}"}; do
        grep -qxF "$tok" "$WORK/matched" && continue
        printf 'governance schedule: no directive matching `%s` — a lane member is a bare `<id>` or an `<owner>/<pack>/<id>`\n' \
            "$tok" >&2
        return 2
    done

    # ── Evidence is resolved per member. Range members run together once;
    # commit members replay the same range one commit at a time.
    ROWS_FILE="$WORK/rows.range"; MECH_FILE="$WORK/mech.range"
    _schedule_mech_pass "$range_start" "$ROOT" "the range $FULL_RANGE"
    _schedule_judge_pass

    if [[ -s "$WORK/rows.commits" || -s "$WORK/mech.commits" ]]; then
        ROWS_FILE="$WORK/rows.commits"; MECH_FILE="$WORK/mech.commits"
        local commit parent
        # A range enumerates its own commits; a bare sha (the degenerate range
        # a repo with one commit resolves to) would enumerate every ancestor,
        # so it is capped to the one commit it actually names.
        local rev_args=()
        case "$FULL_RANGE" in
            *..*) rev_args=("$FULL_RANGE") ;;
            *)    rev_args=(--max-count=1 "$FULL_RANGE") ;;
        esac
        while IFS= read -r commit; do
            [[ -n "$commit" ]] || continue
            parent="$(git rev-parse --verify --quiet "$commit^" 2>/dev/null)" || parent=""
            SHORT_SHA="$(git rev-parse --short "$commit" 2>/dev/null)" || SHORT_SHA="$commit"
            SHA_PREFIX="[$SHORT_SHA] "
            if [[ -n "$parent" ]]; then
                RANGE="$parent..$commit"
                _schedule_mech_at_commit "$commit" "$parent"
            else
                # The root commit has no parent, so there is no P..C diff to
                # judge and no base to measure a change set against.
                RANGE="$commit"
                _schedule_mech_at_commit "$commit" ""
            fi
            _schedule_judge_pass
        done < <(git rev-list --reverse ${rev_args[@]+"${rev_args[@]}"} 2>/dev/null)
        RANGE="$FULL_RANGE"
        SHA_PREFIX=""
    fi
    ROWS_FILE="$WORK/rows"; MECH_FILE="$WORK/mech"

    # ── One digest section per judge directive that has something to say.
    local r_idx r_id r_dir r_yaml r_section r_cmd r_checks r_summary
    while IFS="$RS" read -r r_idx r_id r_dir r_yaml r_section r_cmd r_checks r_summary; do
        [[ -n "$r_idx" ]] || continue
        [[ -s "$WORK/f.$r_idx" || -s "$WORK/u.$r_idx" ]] || continue
        {
            printf '## `%s`\n\n' "$r_id"
            [[ -n "$r_summary" ]] && printf '%s\n\n' "$r_summary"
            [[ -s "$WORK/f.$r_idx" ]] && cat "$WORK/f.$r_idx"
            if [[ -s "$WORK/u.$r_idx" ]]; then
                printf '\n_Un-adjudicated — not a clean bill:_\n'
                cat "$WORK/u.$r_idx"
            fi
            printf '\n'
        } >> "$WORK/sections"
    done < "$WORK/rows"

    _schedule_render_digest > "$WORK/body"

    printf 'governance schedule[%s]: range %s (per-member evidence) — %s judge directive(s), %s mechanical (%s failed), %s judge call(s), %s round(s), %s finding(s), %s un-adjudicated\n' \
        "$LANE" "$FULL_RANGE" "$DIRS" "$MECH" "$MECH_FAIL" \
        "$JUDGED" "$ROUNDS" "$FINDINGS" "$UNADJ" >&2

    # The exit status of this run is decided by the FACTS alone: a mechanical
    # member failed, or it did not. No verdict, finding or un-adjudicated
    # judgment ever moves it — judges never block where they run.
    local rc=0
    [[ "$MECH_FAIL" -eq 0 ]] || rc=1

    if [[ "$DRY_RUN" == "1" ]]; then
        cat "$WORK/body"
        return "$rc"
    fi
    if [[ ! -s "$WORK/sections" ]]; then
        printf 'governance schedule[%s]: no new findings — no digest filed\n' "$LANE" >&2
        return "$rc"
    fi
    if ! _schedule_gh_write_ok; then
        printf 'governance schedule[%s]: no `gh` available — the digest follows instead of being filed\n' "$LANE" >&2
        cat "$WORK/body" >&2
        return "$rc"
    fi

    local title label_args out
    title="Governance schedule[$LANE]: $FINDINGS finding(s), $UNADJ un-adjudicated in $(printf '%.40s' "$FULL_RANGE")"
    # A digest filed unlabeled loses resume and dedupe; a digest not filed at all
    # loses the findings. So a label we cannot create only degrades.
    label_args="--label $LABEL"
    if ! _schedule_ensure_label; then
        printf 'governance schedule: could not create the `%s` label; filing unlabeled — the next run of this lane will not resume or dedupe from this digest\n' \
            "$LABEL" >&2
        label_args=""
    fi
    # shellcheck disable=SC2086
    if out="$(gh issue create $label_args --title "$title" --body-file "$WORK/body" 2>&1)"; then
        printf '%s\n' "$out"
        return "$rc"
    fi
    printf 'governance schedule: `gh issue create` failed: %s\n' "$out" >&2
    cat "$WORK/body" >&2
    return 1
}

VERB="${1:-}"
[[ $# -gt 0 ]] && shift
case "$VERB" in
    run)
        cmd_run "$@"
        exit $?
        ;;
    usage | "")
        usage
        exit 2
        ;;
    *)
        printf 'governance schedule: unknown verb %s (supported: run, usage)\n' "$VERB" >&2
        usage
        exit 2
        ;;
esac
