#!/usr/bin/env bash
# governance-kit:managed kit-version=0.12.0
# .governance/sweep.sh — the at-rest half of the kit's ONE judgment primitive.
#
# The kit has exactly one semantic-judgment primitive: a rubric-framed model
# judgment declared once in a directive's `judge:` block, whose judge
# command lives right there — `judge.cmd.sweep`, a shell string that
# already encodes model + effort. The two lanes are two MOMENTS of the same
# judgment:
#
#   attest (commit, live session)  the live session's gate — `judge_attest`,
#                                   the remediation loop, `gate: record|verdict`.
#   sweep  (at rest, no session)   this driver: the same declaration, replayed
#                                   through the same lib.sh prompt builder and
#                                   the sweep judge resolution ladder below —
#                                   the directive's own `cmd.sweep` when it
#                                   declares one, else the repo-level
#                                   `GOVERNANCE_SWEEP_CMD` knob every bundled
#                                   directive rides on.
#
# Judges never block where they run; gates block where they read. This driver
# never fails a hook and never fails a push. It writes one of two things:
#
#   * an adjudication round into a not-yet-frozen receipt — which the EXISTING
#     `gate: verdict` commit/CI gate then reads, so an at-rest REFUTED turns
#     the next commit red through a mechanism that already exists; or
#   * a finding into the `governance-sweep` digest issue — the canonical
#     human → issue → agent → PR door — when the receipt is already frozen on
#     the trunk, or the directive names no `section:` at all (discovery).
#
# Honesty rule: no cmd resolves off the ladder (neither `cmd.sweep` nor
# `GOVERNANCE_SWEEP_CMD`) → the judgment is reported un-adjudicated and
# retried later. Never a downgraded judge, never a guessed verdict, never a
# keyword stub standing in for a model. A digest must never read as a clean
# bill for work that was not actually judged.
#
# Usage:
#   bash .governance/sweep.sh run [--range A..B] [--push-mode] [--dry-run]
#                                 [--no-gh] [--since '<git date expression>']
#   bash .governance/sweep.sh usage
#
# Environment:
#   GOVERNANCE_SWEEP_BUDGET    max judge calls this run (default 20; 3 with
#                              --push-mode). Over-budget work is REPORTED.
#   GOVERNANCE_PUSH_RANGE      the range --push-mode sweeps (exported by the
#                              generated pre-push dispatcher).
#   GOVERNANCE_SWEEP_TRUNK     the ref that decides which receipts are frozen
#                              (default: the first resolvable of origin/HEAD,
#                              origin/main, origin/master, main, master).
#   GOVERNANCE_SWEEP_CMD       the repo-level sweep judge command. Bundled
#                              directives carry NO `cmd.sweep` row — this is
#                              their judge. See the sweep judge resolution
#                              ladder below.
#   GH_TOKEN / `gh auth`       resume point, dedupe and digest filing. All
#                              optional: with no gh the digest goes to stderr.
#
# Sweep judge resolution ladder (per directive, checked in this order):
#   1. the directive's own `judge.cmd.sweep` — still valid schema, for a
#      third-party pack or a repo operator override; no bundled directive
#      declares it any more.
#   2. the repo-level knob `GOVERNANCE_SWEEP_CMD` — the judge command every
#      bundled directive rides on. The scheduled sweep workflow sets it from
#      a gated repo var/secret; a developer's `--push-mode` run inherits it
#      from their own environment.
#   3. neither resolves → the directive is skipped with one honest log line,
#      never guessed.
#
# Bash 3.2 + POSIX awk + git, plus `gh` when it is there. No python.

set -u

SWEEP_LABEL="governance-sweep"
DEFAULT_BUDGET=20
PUSH_BUDGET=3

usage() {
    cat >&2 <<'EOF'
governance sweep — at-rest re-adjudication of `judge:` declarations.

  bash .governance/sweep.sh run [--range A..B] [--push-mode] [--dry-run]
                                [--no-gh] [--since '<git date expression>']
  bash .governance/sweep.sh usage

`run` never fails its caller on a verdict. Findings land as adjudication rounds
in editable receipts (read by the existing gate: verdict gate) or as one
`governance-sweep` digest issue.
EOF
}

# ── Locate lib.sh: the prompt builder, the declaration reader, the round
#    appender, the cmd resolver/judge and the stamp all live there, and the
#    sweep reuses every one of them. A driver that carried its own copy would
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
    printf 'governance sweep: no lib.sh reachable (looked at $GOVERNANCE_ROOT/lib.sh, %s/lib.sh, %s/.governance/lib.sh) — nothing swept\n' \
        "$HERE" "$ROOT" >&2
    exit 0
fi
# shellcheck disable=SC1090
source "$LIB_SH"

# The field separator for this driver's multi-field records (the directive
# table, the batch rows, the prompt builder's batch spec). Shared with lib.sh so
# both ends of the spec agree; a tab would not survive `read`, which collapses
# runs of IFS whitespace and would shift every field after an empty one.
RS="${_JUDGE_RS:-$'\x1e'}"

# ── gh plumbing (all optional) ──────────────────────────────────────────────
# `gh` carries three things: the resume point, the dedupe set, and the digest
# itself. Every one of them degrades to "do the work anyway and print it".

_sweep_gh_read_ok() { [[ "$NO_GH" == "0" ]] && command -v gh >/dev/null 2>&1; }
_sweep_gh_write_ok() { _sweep_gh_read_ok && [[ "$DRY_RUN" == "0" ]]; }

# _sweep_issue_bodies <state> <limit> — the bodies of recent digest issues.
_sweep_issue_bodies() {
    gh issue list --label "$SWEEP_LABEL" --state "$1" --limit "$2" \
        --json body --jq '.[].body' 2>/dev/null || true
}

# _sweep_last_end_sha — the resume point recorded by the previous digest.
_sweep_last_end_sha() {
    _sweep_issue_bodies all 1 \
        | sed -n 's/.*governance-sweep:end=\([0-9a-f]\{7,40\}\).*/\1/p' \
        | head -n 1
}

# _sweep_open_pairs — `<directive>|<file>` pairs already reported in an OPEN
#   digest, so an unfixed finding does not multiply daily.
_sweep_open_pairs() {
    _sweep_issue_bodies open 20 \
        | sed -n 's/.*<!-- finding: \([^|]*\) | \([^>]*\) -->.*/\1|\2/p' \
        | sed 's/[[:space:]]*|[[:space:]]*/|/; s/[[:space:]]*$//' \
        | sort -u
}

# _sweep_ensure_label — idempotently create the digest label; 0 iff it exists
#   afterwards. Nothing in the install path creates it, so the first run must.
_sweep_ensure_label() {
    local err
    err="$(gh label create "$SWEEP_LABEL" \
        --description "Digest issues filed by the governance semantic sweep" \
        --color 5319E7 2>&1)" && return 0
    case "$err" in *"already exists"*) return 0 ;; esac
    return 1
}

# ── Directive discovery ─────────────────────────────────────────────────────
# Participation is one thing only: a `judge:` block whose sweep judge
# resolves to a real command — off its own `cmd.sweep` or, absent that, the
# repo-level `GOVERNANCE_SWEEP_CMD` knob. There is no `surface:` value that
# opts a directive into this lane any more — one declaration, two moments.
_sweep_directive_yamls() {
    local base
    for base in "$ROOT/.governance/packs" "$ROOT/packs"; do
        [[ -d "$base" ]] || continue
        find "$base" -type f -name directive.yaml -path '*/directives/*' 2>/dev/null | sort
        return 0
    done
}

# _sweep_lib_call <directive-dir> <function> [<args>…]
#   Call a lib.sh helper with $0 set to the directive's check.sh, because the
#   conf ladder derives the pack-qualified overlay path from $0. Resolving a
#   cmd any other way would read a different conf file than the commit lane
#   does for the same directive. Stdin/stdout/stderr of the caller pass
#   through untouched — the judge call pipes the prompt through this shim.
_sweep_lib_call() {
    local dir="$1"
    shift
    local fn="$1"
    shift
    GK_LIB="$LIB_SH" GK_FN="$fn" \
        bash -c 'set +u; source "$GK_LIB"; "$GK_FN" "$@"' "$dir/check.sh" "$@"
}

# _sweep_cmd_label <cmd> → the first word of a sweep cmd, for honest logging.
_sweep_cmd_label() { printf '%s' "${1%% *}"; }

# ── Judging ─────────────────────────────────────────────────────────────────

# _sweep_spend — consume one judge call from the run budget; 1 when spent.
_sweep_spend() {
    [[ "$BUDGET" -gt 0 ]] || return 1
    BUDGET=$((BUDGET - 1))
    JUDGED=$((JUDGED + 1))
    return 0
}

# _sweep_verdict <out-file> → PASS | REFUTED | (nothing)
#   The first VERDICT line of a normalized answer — which, for a batched call,
#   is read from that directive's demuxed block, never from the whole answer.
_sweep_verdict() {
    awk '/^VERDICT:/ { print $2; exit }' "$1"
}

# _sweep_reason <out-file> → one ASCII line, capped. Same normalization the
#   commit lane applies: a judge's prose is untrusted output like any other.
_sweep_reason() {
    local r
    r="$(awk '/^REASON:/ { sub(/^REASON:[ \t]*/, ""); printf "%s%s", (n++ ? " " : ""), $0 } END { print "" }' "$1" \
        | LC_ALL=C tr -d '\r' | LC_ALL=C tr '\n' ' ' \
        | LC_ALL=C tr -cd '[:print:] ' | cut -c1-200)"
    printf '%s' "${r%"${r##*[![:space:]]}"}"
}

# _sweep_unadj <row-index> <text>
#   Record work that was NOT judged, under the directive it belonged to. Every
#   path that skips a judgment goes through here: a digest that stays silent
#   about what it could not adjudicate reads as a clean bill, which is the one
#   thing this lane must never produce.
_sweep_unadj() {
    printf -- '  - %s\n' "$2" >> "$WORK/u.$1"
    UNADJ=$((UNADJ + 1))
}

# _sweep_record_finding <row-index> <directive-id> <fallback-file> <loc> <text>
#   One digest row plus its dedupe marker, filed under the directive that owns
#   it. <loc> is `<path>:<line>` as the judge reported it; the marker keys on
#   the path alone so a moved line does not file the same finding twice.
_sweep_record_finding() {
    local idx="$1" id="$2" fallback="$3" loc="$4" text="$5" file
    file="${loc%%:*}"
    [[ -n "$file" && "$file" != "-" ]] || { file="$fallback"; loc="$fallback"; }
    if grep -qxF "$id|$file" "$WORK/pairs" 2>/dev/null; then
        DUP=$((DUP + 1))
        return 0
    fi
    printf -- '- **%s** — %s\n' "$loc" "$text" >> "$WORK/f.$idx"
    printf -- '<!-- finding: %s | %s -->\n' "$id" "$file" >> "$WORK/markers"
    FINDINGS=$((FINDINGS + 1))
}

# _sweep_findings_from <block-file> <row-index> <directive-id> <fallback-file>
#                      <reason>
#   Turn a REFUTED answer into digest rows. A REFUTED with no FINDING line still
#   files one row built from the reason — a refutation the digest swallows is a
#   verdict nobody acts on.
_sweep_findings_from() {
    local out="$1" idx="$2" id="$3" fallback="$4" reason="$5" line loc text n=0
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        line="${line#FINDING:}"
        line="${line#"${line%%[![:space:]]*}"}"
        loc="${line%%[[:space:]]*}"
        text="${line#"$loc"}"
        text="${text#"${text%%[![:space:]]*}"}"
        [[ -n "$text" ]] || text="$reason"
        _sweep_record_finding "$idx" "$id" "$fallback" "$loc" "$text"
        n=$((n + 1))
    done < <(grep '^FINDING:' "$out" 2>/dev/null | cut -c1-300)
    [[ "$n" -gt 0 ]] || _sweep_record_finding "$idx" "$id" "$fallback" "$fallback" "$reason"
}

# The stamp a queued round carries until the file settles. It is a well-formed
# round line by construction, so it is stripped from the very hash it waits for.
_SWEEP_STAMP_TBD="000000000000"

# _sweep_queue_round <row-index> <id> <receipt> <section> <verdict> <reason>
_sweep_queue_round() {
    printf "%s${RS}%s${RS}%s${RS}%s${RS}%s${RS}%s\n" "$@" >> "$WORK/rounds"
}

# _sweep_flush_rounds <receipt-abs>
#   Write every round this judgment produced, then bind them all to the tree —
#   through the same two lib.sh helpers the commit lane uses, and with the two
#   differences that define this lane: the rounds are NOT staged (at rest, the
#   next commit picks them up), and the round line reads `lane=sweep` (matching
#   the commit lane's own round format — same field, same position).
#
#   Two phases, because a round line is only immune to the stamp while the rest
#   of the file holds still: creating a section adds a heading, and appending
#   into a NON-final section inserts a blank line — both are hashed. So every
#   section is created, then every round lands with a placeholder stamp, then
#   the settled file is hashed exactly ONCE and the placeholder is filled in.
#   One judgment, one stamp, and every round it produced verifies against the
#   tree the gate will later recompute — including the first of a batch, which
#   a naive per-round stamp would leave stale the moment the second was written.
_sweep_flush_rounds() {
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
            "- [round ${next}] ${verdict} lane=sweep stamp=${_SWEEP_STAMP_TBD} — sweep: ${reason}"; then
            printf "%s${RS}%s${RS}%s${RS}%s${RS}%s${RS}%s\n" \
                "$idx" "$id" "$receipt" "$section" "$next" "$verdict" >> "$WORK/rounds.done"
        else
            _sweep_unadj "$idx" "$receipt (the round could not be written)"
        fi
    done < "$WORK/rounds"
    : > "$WORK/rounds"
    [[ -s "$WORK/rounds.done" ]] || return 0

    stamp="$(_adjudication_stamp "$abs")" || stamp=""
    if [[ -z "$stamp" ]]; then
        while IFS="$RS" read -r idx id receipt section next verdict; do
            [[ -n "$idx" ]] || continue
            _sweep_unadj "$idx" "$receipt (no adjudication stamp could be computed — the round cannot be trusted)"
        done < "$WORK/rounds.done"
        return 0
    fi
    tmp="$(mktemp "${TMPDIR:-/tmp}/gk-sweep-stamp.XXXXXX")" || return 0
    if LC_ALL=C sed "s/stamp=${_SWEEP_STAMP_TBD}/stamp=${stamp}/g" "$abs" > "$tmp"; then
        cat "$tmp" > "$abs"
    fi
    rm -f "$tmp"
    while IFS="$RS" read -r idx id receipt section next verdict; do
        [[ -n "$idx" ]] || continue
        ROUNDS=$((ROUNDS + 1))
        printf 'governance sweep: %s → %s round %s in %s "## %s" (lane=sweep)\n' \
            "$id" "$verdict" "$next" "$receipt" "$section" >&2
    done < "$WORK/rounds.done"
}

# _sweep_trunk → the ref that decides "already frozen", or return 1.
_sweep_trunk() {
    if [[ -n "${GOVERNANCE_SWEEP_TRUNK:-}" ]]; then
        printf '%s' "$GOVERNANCE_SWEEP_TRUNK"
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

# _sweep_frozen <repo-relative-path> — 0 when the file already exists on the
#   trunk. Same notion doc-integrity uses: once a receipt is on the default
#   branch it is immutable, so a re-adjudication of it can only be filed, never
#   appended.
_sweep_frozen() {
    [[ -n "$TRUNK" ]] || return 1
    git cat-file -e "$TRUNK:$1" 2>/dev/null
}

# _sweep_receipts_in_range — receipts touched by the range, newest commit first
#   so a budget cut drops the oldest work rather than the freshest.
_sweep_receipts_in_range() {
    git log --pretty=format: --name-only --diff-filter=AMR "$RANGE" -- 'receipts/*.md' 2>/dev/null \
        | awk 'NF && !seen[$0]++'
}

# ── Batching: the `group:` label, at rest ───────────────────────────────────
# `isolation:` is gone. Its replacement is `group:` — an optional, free-form,
# repo-global label. Directives that carry the SAME group label are judged in
# one call, `DIRECTIVE:`-demuxed the same way a shared batch always was; a
# directive with no group label is always a solo invocation — there is no
# implicit sharing any more. The label is not the pack's last word: it is
# resolved through `_judge_group_resolve`, the operator conf ladder (env
# `GOVERNANCE_JUDGE_GROUP` > the user overlay row > the pack defaults row >
# the declared `judge.group`), because how much fidelity to trade for tokens
# is the consuming repo's call. A group is one invocation, one command: if its
# members resolved DIFFERENT sweep cmds, the driver refuses to silently split
# it — the whole group is reported un-adjudicated with one honest line, never
# partially judged.
#
# A batch row is RS-separated:
#   <row-index> ␞ <id> ␞ <section-or-empty> ␞ <yaml> ␞ <checks-US> ␞ <cmd>
# Fields 2–5 are exactly the prompt builder's batch spec.

_sweep_batch_rows() { awk 'NF' "$1" 2>/dev/null | wc -l | tr -d ' '; }

# _sweep_batch_key <keys-file> <label> → the batch key for <label>: an
#   existing key when this run has already seen this exact group label,
#   otherwise a new one. Purely a filename-safe handle for the group — the
#   label itself, byte for byte, is what decides membership.
_sweep_batch_key() {
    local keys="$1" label="$2" k c found="" next
    if [[ -f "$keys" ]]; then
        while IFS="$RS" read -r k c; do
            [[ -n "$k" ]] || continue
            if [[ "$c" == "$label" ]]; then
                found="$k"
                break
            fi
        done < "$keys"
    fi
    if [[ -n "$found" ]]; then
        printf '%s\n' "$found"
        return 0
    fi
    next=$(( $(wc -l < "$keys" 2>/dev/null | tr -d ' ') + 1 ))
    printf "%s${RS}%s\n" "$next" "$label" >> "$keys"
    printf '%s\n' "$next"
}

# _sweep_block <out-file> <id> <dest-file>
#   Demux one directive's block out of a batched answer. Lines belong to the
#   most recent `DIRECTIVE:` delimiter, so an answer that skips a directive
#   yields nothing for it — which the caller reports as un-adjudicated, never
#   as a PASS. Returns 1 when the block is absent.
_sweep_block() {
    awk -v want="$2" '
        function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
        /^DIRECTIVE:/ { cur = trim(substr($0, 11)); next }
        cur == want && /^(VERDICT|REASON|FINDING):/ { print }
    ' "$1" > "$3"
    [[ -s "$3" ]]
}

# _sweep_subject <lane> <receipt> — what a report line is about.
_sweep_subject() {
    if [[ "$1" == "attest" ]]; then printf '%s' "$2"; else printf 'the whole range'; fi
}

# _sweep_consume <lane> <row-index> <id> <section> <receipt> <abs> <block>
#                <cmd>
#   One directive's verdict, from its own block. Identical whether the block
#   came from a solo call or was demuxed out of a batch — the batching is a
#   transport detail, not a different judgment.
_sweep_consume() {
    local lane="$1" idx="$2" id="$3" section="$4" receipt="$5" abs="$6" block="$7" cmd="$8"
    local verdict reason subject label
    subject="$(_sweep_subject "$lane" "$receipt")"
    label="$(_sweep_cmd_label "$cmd")"

    verdict="$(_sweep_verdict "$block")"
    case "$verdict" in
        PASS | REFUTED) ;;
        *)
            _sweep_unadj "$idx" "$subject (cmd:$label answered outside the verdict grammar)"
            return 0
            ;;
    esac
    reason="$(_sweep_reason "$block")"
    [[ -n "$reason" ]] || reason="adjudicated at rest by cmd:$label"

    if [[ "$lane" == "discovery" ]]; then
        [[ "$verdict" == "REFUTED" ]] || return 0
        _sweep_findings_from "$block" "$idx" "$id" "$RANGE" "$reason"
        return 0
    fi

    if _sweep_frozen "$receipt"; then
        # Frozen on the trunk: the receipt is immutable, so the verdict travels
        # through the digest door instead of the gate.
        [[ "$verdict" == "REFUTED" ]] || return 0
        _sweep_findings_from "$block" "$idx" "$id" "$receipt" "$reason"
        printf 'governance sweep: %s is frozen on %s — %s REFUTED filed to the digest\n' \
            "$receipt" "$TRUNK" "$id" >&2
        return 0
    fi
    if [[ "$DRY_RUN" == "1" ]]; then
        printf 'governance sweep: would append a %s round for %s to %s "## %s"\n' \
            "$verdict" "$id" "$receipt" "$section" >&2
        return 0
    fi
    # Queued, not written: every round of one judgment lands together, so they
    # can share the single stamp taken once the file has settled.
    _sweep_queue_round "$idx" "$id" "$receipt" "$section" "$verdict" "$reason"
}

# _sweep_run_batch <lane> <batch-file> [<receipt>] [<receipt-abs>]
#   ONE judge call for every directive in the batch — the whole point of the
#   `shared` declaration. Every row in a batch carries the SAME cmd by
#   construction (batching key = cmd), so the call is issued with the first
#   row's cmd and no ranking is needed. A one-row batch is issued as a plain
#   single-directive call, so the unbatched prompt and the unbatched answer
#   grammar are exactly what they were before batching existed.
_sweep_run_batch() {
    local lane="$1" batch="$2" receipt="${3:-}" abs="${4:-}"
    local n idx id section yaml checks cmd dir0 label
    local r_idx r_id r_section r_yaml r_checks r_cmd block subject
    subject="$(_sweep_subject "$lane" "$receipt")"

    n="$(_sweep_batch_rows "$batch")"
    [[ "$n" -gt 0 ]] || return 0
    IFS="$RS" read -r idx id section yaml checks cmd < "$batch"
    [[ -n "$cmd" ]] || return 0
    dir0="$(dirname "$yaml")"
    label="$(_sweep_cmd_label "$cmd")"

    # A group is one invocation, one command. If its members did not all
    # resolve the SAME sweep cmd, the driver refuses to guess which one wins
    # and refuses to silently split the group into sub-calls — the whole
    # group is un-adjudicated, honestly, in one line.
    if [[ "$n" -gt 1 ]] && awk -F"$RS" -v c="$cmd" 'NF && $6 != c { bad = 1 } END { exit !bad }' "$batch"; then
        while IFS="$RS" read -r r_idx r_id r_section r_yaml r_checks r_cmd; do
            [[ -n "$r_idx" ]] || continue
            _sweep_unadj "$r_idx" "$subject (its group mixes different sweep cmds — never silently split)"
        done < "$batch"
        printf 'governance sweep: a shared group mixes different `judge.cmd.sweep` values — the whole group is un-adjudicated (one invocation, one command)\n' >&2
        return 0
    fi

    # Budget: one batched call is ONE unit. That is the saving batching exists
    # for — and when the budget is gone, every member is reported, not dropped.
    if ! _sweep_spend; then
        while IFS="$RS" read -r r_idx r_id r_section r_yaml r_checks r_cmd; do
            [[ -n "$r_idx" ]] || continue
            _sweep_unadj "$r_idx" "$subject (over the run budget — not judged)"
        done < "$batch"
        return 0
    fi

    if [[ "$n" -eq 1 ]]; then
        _judge_prompt "$abs" "$section" "$checks" "$yaml" "$RANGE" sweep > "$WORK/prompt"
    else
        cut -d "$RS" -f2-5 "$batch" > "$WORK/spec"
        _judge_prompt "$abs" "" "" "" "$RANGE" sweep "$WORK/spec" > "$WORK/prompt"
        printf 'governance sweep: batching %s shared directive(s) into one judgment of %s (cmd:%s)\n' \
            "$n" "$subject" "$label" >&2
    fi

    if ! _sweep_lib_call "$dir0" _judge_cmd_run "$cmd" < "$WORK/prompt" > "$WORK/out"; then
        while IFS="$RS" read -r r_idx r_id r_section r_yaml r_checks r_cmd; do
            [[ -n "$r_idx" ]] || continue
            _sweep_unadj "$r_idx" "$subject (cmd:$label rendered no verdict)"
        done < "$batch"
        return 0
    fi

    : > "$WORK/rounds"
    while IFS="$RS" read -r r_idx r_id r_section r_yaml r_checks r_cmd; do
        [[ -n "$r_idx" ]] || continue
        if [[ "$n" -eq 1 ]]; then
            block="$WORK/out"
        else
            block="$WORK/block"
            if ! _sweep_block "$WORK/out" "$r_id" "$block"; then
                _sweep_unadj "$r_idx" "$subject (the batched answer carried no \`DIRECTIVE: $r_id\` block)"
                continue
            fi
        fi
        _sweep_consume "$lane" "$r_idx" "$r_id" "$r_section" "$receipt" "$abs" "$block" "$r_cmd"
    done < "$batch"
    if [[ "$lane" == "attest" ]]; then
        _sweep_flush_rounds "$abs"
    fi
}

# ── The two lanes ───────────────────────────────────────────────────────────

# _sweep_lane_discovery
#   No `section:`: no gate, no receipt section, no check.sh. Discovery
#   directives that share a `group:` label read the SAME evidence — the range
#   diff — so they share one call; an unlabeled directive is always solo.
_sweep_lane_discovery() {
    local idx id dir yaml section group cmd checks summary key f
    : > "$WORK/dkeys"
    : > "$WORK/dids"
    rm -f "$WORK"/dbatch.*
    while IFS="$RS" read -r idx id dir yaml section group cmd checks summary; do
        [[ -z "$section" ]] || continue
        if [[ -z "$group" ]] || grep -qxF "$id" "$WORK/dids" 2>/dev/null; then
            printf "%s${RS}%s${RS}${RS}%s${RS}%s${RS}%s\n" \
                "$idx" "$id" "$yaml" "$checks" "$cmd" > "$WORK/dsolo"
            _sweep_run_batch discovery "$WORK/dsolo"
            continue
        fi
        key="$(_sweep_batch_key "$WORK/dkeys" "$group")"
        printf "%s${RS}%s${RS}${RS}%s${RS}%s${RS}%s\n" \
            "$idx" "$id" "$yaml" "$checks" "$cmd" >> "$WORK/dbatch.$key"
        printf '%s\n' "$id" >> "$WORK/dids"
    done < "$WORK/rows"
    for f in "$WORK"/dbatch.*; do
        [[ -e "$f" ]] || continue
        _sweep_run_batch discovery "$f"
    done
}

# _sweep_lane_attest
#   Attestation-backed (the declaration names a `section:`): per receipt the
#   range touched, every directive that shares a `group:` label is judged in one
#   call and each still gets its own round line in its own section. Unlabeled →
#   always solo.
_sweep_lane_attest() {
    local receipt abs idx id dir yaml section group cmd checks summary key f
    while IFS= read -r receipt; do
        [[ -n "$receipt" ]] || continue
        abs="$ROOT/$receipt"
        [[ -f "$abs" ]] || continue
        rm -f "$WORK"/abatch.*
        : > "$WORK/aids"
        : > "$WORK/akeys"
        while IFS="$RS" read -r idx id dir yaml section group cmd checks summary; do
            [[ -n "$section" ]] || continue
            if grep -qxF "$id|$receipt" "$WORK/pairs" 2>/dev/null; then
                DUP=$((DUP + 1))
                continue
            fi
            # An unlabeled directive is judged alone. So is a homonym: two
            # packs may ship the same directive id, and one `DIRECTIVE: <id>`
            # delimiter cannot address both unambiguously.
            if [[ -z "$group" ]] || grep -qxF "$id" "$WORK/aids" 2>/dev/null; then
                printf "%s${RS}%s${RS}%s${RS}%s${RS}%s${RS}%s\n" \
                    "$idx" "$id" "$section" "$yaml" "$checks" "$cmd" > "$WORK/asolo"
                _sweep_run_batch attest "$WORK/asolo" "$receipt" "$abs"
                continue
            fi
            key="$(_sweep_batch_key "$WORK/akeys" "$group")"
            printf "%s${RS}%s${RS}%s${RS}%s${RS}%s${RS}%s\n" \
                "$idx" "$id" "$section" "$yaml" "$checks" "$cmd" >> "$WORK/abatch.$key"
            printf '%s\n' "$id" >> "$WORK/aids"
        done < "$WORK/rows"
        for f in "$WORK"/abatch.*; do
            [[ -e "$f" ]] || continue
            _sweep_run_batch attest "$f" "$receipt" "$abs"
        done
    done < <(_sweep_receipts_in_range)
}

# ── The digest ──────────────────────────────────────────────────────────────
_sweep_render_digest() {
    printf 'Automated semantic sweep. Nothing here blocked a commit, a push or a PR:\n'
    printf 'these are candidates for the issue → agent → PR loop, judged at rest by\n'
    printf 'each directive'"'"'s sweep judge (its own `cmd.sweep` or the repo'"'"'s\n'
    printf '`GOVERNANCE_SWEEP_CMD`).\n\n'
    if [[ -s "$WORK/sections" ]]; then
        cat "$WORK/sections"
    else
        printf '_No findings this run._\n'
    fi
    printf '\n---\n\n'
    printf '### Footer\n'
    printf -- '- commit range: `%s`\n' "$RANGE"
    printf -- '- judge: per-directive `cmd.sweep`, else `GOVERNANCE_SWEEP_CMD`\n'
    printf -- '- directives swept: %s\n' "$DIRS"
    printf -- '- judge calls made: %s\n' "$JUDGED"
    printf -- '- un-adjudicated (NOT a clean bill): %s\n' "$UNADJ"
    printf -- '- rounds appended to editable receipts: %s\n' "$ROUNDS"
    printf -- '- skipped as duplicate of an open digest: %s\n' "$DUP"
    printf '\n<!-- governance-sweep:end=%s -->\n' "$HEAD_SHA"
    [[ -s "$WORK/markers" ]] && cat "$WORK/markers"
    return 0
}

# ── run ─────────────────────────────────────────────────────────────────────
cmd_run() {
    local explicit_range="" push_mode=0 since="24 hours ago"
    DRY_RUN=0
    NO_GH=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --range)      explicit_range="${2:-}"; shift; [[ $# -gt 0 ]] && shift ;;
            --range=*)    explicit_range="${1#--range=}"; shift ;;
            --since)      since="${2:-}"; shift; [[ $# -gt 0 ]] && shift ;;
            --since=*)    since="${1#--since=}"; shift ;;
            --push-mode)  push_mode=1; shift ;;
            --dry-run)    DRY_RUN=1; shift ;;
            --no-gh)      NO_GH=1; shift ;;
            *)
                printf 'governance sweep: unknown option %s\n' "$1" >&2
                usage
                return 2
                ;;
        esac
    done

    HEAD_SHA="$(git rev-parse HEAD 2>/dev/null)" || HEAD_SHA=""
    if [[ -z "$HEAD_SHA" ]]; then
        printf 'governance sweep: not a git repository with commits — nothing swept\n' >&2
        return 0
    fi

    # ── The range. Explicit beats the push refs beat the last digest's resume
    #    marker beats a time window; a repo with no history sweeps from its root.
    local start=""
    if [[ -n "$explicit_range" ]]; then
        RANGE="$explicit_range"
    else
        if [[ "$push_mode" == "1" && -n "${GOVERNANCE_PUSH_RANGE:-}" ]]; then
            RANGE="$GOVERNANCE_PUSH_RANGE"
        else
            _sweep_gh_read_ok && start="$(_sweep_last_end_sha)"
            [[ -n "$start" ]] || start="$(git rev-list -1 "--before=$since" HEAD 2>/dev/null)"
            [[ -n "$start" ]] || start="$(git rev-list --max-parents=0 HEAD 2>/dev/null | tail -n 1)"
            if [[ -n "$start" && "$start" != "$HEAD_SHA" ]]; then
                RANGE="$start..$HEAD_SHA"
            else
                RANGE="$HEAD_SHA"
            fi
        fi
    fi
    # The prompt builder's `range-diff` input reads this.
    export GOVERNANCE_SWEEP_RANGE="$RANGE"

    BUDGET="${GOVERNANCE_SWEEP_BUDGET:-}"
    if [[ -z "$BUDGET" ]]; then
        if [[ "$push_mode" == "1" ]]; then BUDGET="$PUSH_BUDGET"; else BUDGET="$DEFAULT_BUDGET"; fi
    fi
    [[ "$BUDGET" =~ ^[0-9]+$ ]] || BUDGET="$DEFAULT_BUDGET"

    TRUNK="$(_sweep_trunk)" || TRUNK=""

    WORK="$(mktemp -d "${TMPDIR:-/tmp}/gk-sweep.XXXXXX")" || return 0
    trap 'rm -rf "$WORK"' EXIT
    : > "$WORK/sections"
    : > "$WORK/markers"
    : > "$WORK/pairs"
    _sweep_gh_read_ok && _sweep_open_pairs > "$WORK/pairs"

    DIRS=0; JUDGED=0; UNADJ=0; DUP=0; ROUNDS=0; FINDINGS=0

    # ── The participating directive table, one TSV row per directive:
    #   <idx> ⇥ id ⇥ dir ⇥ yaml ⇥ section ⇥ group ⇥ cmd ⇥ checks-US ⇥ summary
    # Built once, then read by each lane: the lanes group by receipt and by
    # `group` label + cmd, which they cannot do while streaming one directive
    # at a time. `section` is also the lane selector — present = attest,
    # absent = discovery. A directive with no cmd anywhere on the ladder never
    # gets a row — it is skipped with one honest log line, not an error.
    : > "$WORK/rows"
    local yaml dir id defaults cmd section group checks c summary
    while IFS= read -r yaml; do
        [[ -n "$yaml" ]] || continue
        grep -qE '^judge:' "$yaml" || continue
        dir="$(dirname "$yaml")"
        id="$(basename "$dir")"
        defaults="$dir/defaults.conf"
        # The sweep judge resolution ladder (see the header comment): the
        # directive's own `cmd.sweep` first (a third-party/override), else
        # the repo-level `GOVERNANCE_SWEEP_CMD` knob every bundled directive
        # rides on, else skipped — honestly, never guessed.
        cmd="$(_sweep_lib_call "$dir" _judge_cmd_resolve "$yaml" sweep 2>/dev/null)"
        [[ -n "$cmd" ]] || cmd="${GOVERNANCE_SWEEP_CMD:-}"
        if [[ -z "$cmd" ]]; then
            printf 'governance sweep: %s has no sweep judge (no `cmd.sweep` and no `GOVERNANCE_SWEEP_CMD`) — skipped\n' "$id" >&2
            continue
        fi
        # The lane, straight off the declaration: a `section:` is the place a
        # verdict lands, so it is also the thing that decides whether this
        # directive is re-adjudicated (attest) or only discovered (findings).
        section="$(_judge_yaml "$yaml" section)"
        DIRS=$((DIRS + 1))
        # The batching knob: a free-form, repo-global label off the SAME
        # operator conf ladder the commit lane resolves (env
        # `GOVERNANCE_JUDGE_GROUP` > user overlay row > pack defaults row >
        # the directive's own `judge.group`), so a repo that batches on the
        # attest lane batches identically here. It goes through the lib shim
        # for the same reason the cmd does: the overlay path is derived from
        # `$0`, and resolving it any other way would read a different conf
        # file than the commit lane reads for this directive. The resolver
        # speaks the ledger's dialect — `-` for solo — while the batching code
        # below tests for an EMPTY label, so normalize the sentinel back here
        # rather than teaching every downstream test a second spelling.
        group="$(_sweep_lib_call "$dir" _judge_group_resolve "$id" "$defaults" "$yaml" 2>/dev/null)"
        [[ "$group" == "-" ]] && group=""
        checks=""
        while IFS= read -r c; do
            [[ -n "$c" ]] || continue
            if [[ -z "$checks" ]]; then checks="$c"; else checks="$checks$_JUDGE_US$c"; fi
        done < <(_judge_yaml "$yaml" checks)
        summary="$(awk '/^summary:/ { sub(/^summary:[ \t]*/, ""); gsub(/^["'"'"']|["'"'"']$/, ""); print; exit }' "$yaml")"
        printf "%s${RS}%s${RS}%s${RS}%s${RS}%s${RS}%s${RS}%s${RS}%s${RS}%s\n" \
            "$DIRS" "$id" "$dir" "$yaml" "$section" "$group" \
            "$cmd" "$checks" "$summary" \
            | LC_ALL=C tr -d '\r' >> "$WORK/rows"
        : > "$WORK/f.$DIRS"
        : > "$WORK/u.$DIRS"
    done < <(_sweep_directive_yamls)

    if [[ "$DIRS" == "0" ]]; then
        printf 'governance sweep: no directive resolved a sweep judge (no `cmd.sweep` and no `GOVERNANCE_SWEEP_CMD`) — nothing to judge\n' >&2
        return 0
    fi

    _sweep_lane_discovery
    _sweep_lane_attest

    # ── One digest section per directive that has something to say.
    local r_idx r_id r_dir r_yaml r_section r_group r_cmd r_checks r_summary
    while IFS="$RS" read -r r_idx r_id r_dir r_yaml r_section r_group r_cmd r_checks r_summary; do
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

    _sweep_render_digest > "$WORK/body"

    printf 'governance sweep: range %s — %s directive(s), %s judge call(s), %s round(s), %s finding(s), %s un-adjudicated\n' \
        "$RANGE" "$DIRS" "$JUDGED" "$ROUNDS" "$FINDINGS" "$UNADJ" >&2

    if [[ "$DRY_RUN" == "1" ]]; then
        cat "$WORK/body"
        return 0
    fi
    if [[ ! -s "$WORK/sections" ]]; then
        printf 'governance sweep: no new findings — no digest filed\n' >&2
        return 0
    fi
    if ! _sweep_gh_write_ok; then
        printf 'governance sweep: no `gh` available — the digest follows instead of being filed\n' >&2
        cat "$WORK/body" >&2
        return 0
    fi

    local title label_args out
    title="Governance sweep: $FINDINGS finding(s), $UNADJ un-adjudicated in $(printf '%.40s' "$RANGE")"
    # A digest filed unlabeled loses resume and dedupe; a digest not filed at all
    # loses the findings. So a label we cannot create only degrades.
    label_args="--label $SWEEP_LABEL"
    if ! _sweep_ensure_label; then
        printf 'governance sweep: could not create the `%s` label; filing unlabeled — the next run will not resume or dedupe from this digest\n' \
            "$SWEEP_LABEL" >&2
        label_args=""
    fi
    # shellcheck disable=SC2086
    if out="$(gh issue create $label_args --title "$title" --body-file "$WORK/body" 2>&1)"; then
        printf '%s\n' "$out"
        return 0
    fi
    printf 'governance sweep: `gh issue create` failed: %s\n' "$out" >&2
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
        printf 'governance sweep: unknown verb %s (supported: run, usage)\n' "$VERB" >&2
        usage
        exit 2
        ;;
esac
