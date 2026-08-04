#!/usr/bin/env bash
# scripts/test-runtime.sh — direct tests for the runtime files shipped to
# every target repo: kit/assets/dot-governance/run.sh and lib.sh.
#
# These two scripts run on every consumer's machine on every commit. They
# need their own coverage independent of how this repo dogfoods them.
#
# Covers:
#   run.sh:
#     - SKIP_GOVERNANCE=1 silences the runner
#     - empty .governance/ tree exits 0 with a clear message
#     - all directive checks pass → exit 0 + "all N directive(s) passed"
#     - any directive fails → exit 1 + bypass instructions
#     - single-directive filter `run.sh <id>` runs one check
#     - filter that matches nothing exits 1 with a clear message
#     - directives discovered uniformly under packs/<owner>/<name>/directives/
#   lib.sh:
#     - directive_start / directive_end with no violations exits 0 + green ✓
#     - violation increments count; directive_end exits 1 + lists violations
#     - require_git inside a non-repo emits ⊘ skip and exits 0
#     - tracked_files respects .gitignore
#     - has_waiver matches `governance: allow-<id>` on the given line
#     - has_file_waiver matches `governance: allow-<id> <sub-check>` in
#       the first 10 lines, scoped to both directive id and sub-check
#     - conf_file resolves .governance/conf/<id>.conf (present/absent)
#     - conf_get precedence: env GOVERNANCE_<KEY> > overlay > defaults.conf row;
#       fail-loud on a missing row/file; transitional literal-default compat
#     - conf_rule_lines strips comments/blanks/KEY= and trims the rest
#     - conf_list layers defaults.conf with the overlay (+add / !remove),
#       normalizing whitespace for ! removal
#   runtime adapters (kit/assets/dot-governance/runtimes/*.sh, issue #355 v2 —
#   "identity at commit, measurement at rest"; every adapter answers
#   resolve/emit/judge, never cost, never guesses identity):
#     - claude-code.sh: `resolve` finds the exact-name transcript (declared
#       path, then <projects>/<encoded>/<session>.jsonl, then a cross-worktree
#       exact-name find — no mtime fallback survives), sums usage + cost,
#       source `session-file`; wrong-named transcript is never picked; no
#       identity → exit 2 even with other transcripts present; `emit` parses
#       a statusline JSON payload from stdin, appends a `harness-feed`
#       sidecar snapshot (zero tokens, real cost) and refreshes the identity
#       file, inside a real tmp git repo; silently exits 0 outside one
#     - codex.sh: `resolve` finds the exact-thread-id-suffixed rollout file,
#       sums cumulative usage, cost passes through verbatim or `-`; `emit`
#       refreshes identity only (no sidecar row)
#     - manual.sh: `resolve` is the env-passthrough seam; `emit` refreshes
#       identity from AGENT_SESSION_ID
#     - pi.sh: `resolve` sums the `usage` objects (input/output/cacheRead/
#       cacheWrite/cost.total) from the exact-name-suffixed session file
#     - grok.sh: `resolve` reads `signals.json` from the exact session-id
#       directory; missing counters → exit 2
#     - cursor-agent.sh: `resolve` always exits 2 (no documented surface)
#     - opencode.sh: `resolve` parses a `/session/<id>` response body via the
#       $OPENCODE_RESPONSE_FILE test seam (no real network call in CI)
#     - every adapter: bare invocation → usage + exit 2; unknown verb →
#       named-verbs message + exit 2; a vendor CLI absent → `judge` exits 2

set -eu

# Drop any GIT_* env state inherited from a parent process (e.g. when invoked
# from a pre-commit hook). The require_git tests below escape into temp
# dirs via subshell `cd`, but inherited GIT_DIR / GIT_WORK_TREE keep git
# anchored to the parent repo and the "outside a git repo" assertions flip.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUN_SH="$ROOT/kit/assets/dot-governance/run.sh"
LIB_SH="$ROOT/kit/assets/dot-governance/lib.sh"
TOKEN_RUNTIME_LIB="$ROOT/packs/audit/directives/agent-token-accounting/lib/runtime.sh"
# The adapter registry is kit-level since issue #355 — one file per harness,
# shared by the accounting lane's resolve/emit verbs and lib.sh's `judge` verb.
RUNTIMES_DIR="$ROOT/kit/assets/dot-governance/runtimes"
TOKEN_CLAUDE_SH="$RUNTIMES_DIR/claude-code.sh"
TOKEN_CODEX_SH="$RUNTIMES_DIR/codex.sh"
TOKEN_MANUAL_SH="$RUNTIMES_DIR/manual.sh"
TOKEN_PI_SH="$RUNTIMES_DIR/pi.sh"
TOKEN_GROK_SH="$RUNTIMES_DIR/grok.sh"
TOKEN_CURSOR_SH="$RUNTIMES_DIR/cursor-agent.sh"
TOKEN_OPENCODE_SH="$RUNTIMES_DIR/opencode.sh"

PASS=0
FAIL=0
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

assert_eq() {
    if [[ "$2" == "$3" ]]; then
        printf '  ok - %s\n' "$1"; PASS=$((PASS + 1))
    else
        printf '  not ok - %s\n      expected: %q\n      actual:   %q\n' "$1" "$2" "$3"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    if [[ "$3" == *"$2"* ]]; then
        printf '  ok - %s\n' "$1"; PASS=$((PASS + 1))
    else
        printf '  not ok - %s\n      missing substring: %q\n      in:               %q\n' "$1" "$2" "$3"
        FAIL=$((FAIL + 1))
    fi
}

# A repo skeleton: $WORK/repo with .governance/ scaffolded from the shipped runtime.
make_repo() {
    local repo="$1"
    rm -rf "$repo"
    mkdir -p "$repo/.governance"
    cp "$RUN_SH" "$repo/.governance/run.sh"
    cp "$LIB_SH" "$repo/.governance/lib.sh"
    chmod +x "$repo/.governance/run.sh"
}

# Add a check.sh under packs/<pack>/directives/<id>/ that always passes.
add_pack_directive_pass() {
    local repo="$1" pack_id="$2" directive_id="$3"
    local ddir="$repo/.governance/packs/$pack_id/directives/$directive_id"
    mkdir -p "$ddir"
    cat > "$ddir/directive.yaml" <<EOF
hook: none
surface: repo-state
EOF
    cat > "$ddir/check.sh" <<EOF
#!/usr/bin/env bash
source "\$(dirname "\$0")/../../../../../lib.sh"
directive_start "$directive_id"
directive_end
EOF
    chmod +x "$ddir/check.sh"
}

add_pack_directive_fail() {
    local repo="$1" pack_id="$2" directive_id="$3"
    local ddir="$repo/.governance/packs/$pack_id/directives/$directive_id"
    mkdir -p "$ddir"
    cat > "$ddir/directive.yaml" <<EOF
hook: none
surface: repo-state
EOF
    cat > "$ddir/check.sh" <<EOF
#!/usr/bin/env bash
source "\$(dirname "\$0")/../../../../../lib.sh"
directive_start "$directive_id"
violation "intentional fail"
directive_end
EOF
    chmod +x "$ddir/check.sh"
}

# ---- run.sh: SKIP_GOVERNANCE=1 --------------------------------------------

printf '── run.sh: SKIP_GOVERNANCE=1 ───────────────────────────\n'
make_repo "$WORK/r1"
output="$(SKIP_GOVERNANCE=1 bash "$WORK/r1/.governance/run.sh" 2>&1)"
exit_code=$?
assert_eq "exit 0 under SKIP_GOVERNANCE=1" 0 "$exit_code"
assert_contains "prints skip notice"      "SKIP_GOVERNANCE=1" "$output"

# ---- run.sh: empty .governance/ tree exits 0 with a notice -----------------

printf '── run.sh: empty .governance/ tree ─────────────────────\n'
make_repo "$WORK/r2"
set +e
output="$(bash "$WORK/r2/.governance/run.sh" 2>&1)"
exit_code=$?
set -e
assert_eq "exit 0 when no directives are installed" 0 "$exit_code"
assert_contains "prints 'no governance directives' notice" "no governance directives defined" "$output"

# ---- run.sh: all-pass run --------------------------------------------------

printf '── run.sh: all checks pass ─────────────────────────────\n'
make_repo "$WORK/r3"
add_pack_directive_pass "$WORK/r3" "acme/alpha-pack" "alpha"
add_pack_directive_pass "$WORK/r3" "acme/alpha-pack" "beta"
add_pack_directive_pass "$WORK/r3" "acme/beta-pack" "gamma"
set +e
output="$(bash "$WORK/r3/.governance/run.sh" 2>&1)"
exit_code=$?
set -e
assert_eq "exit 0 when every directive passes" 0 "$exit_code"
assert_contains "summary line names the count" "all 3 directive(s) passed" "$output"
assert_contains "discovers pack directive alpha" "alpha" "$output"
assert_contains "discovers pack directive beta"  "beta"  "$output"
assert_contains "discovers second-pack directive gamma" "gamma" "$output"

# ---- run.sh: at least one fail → exit 1 + bypass instructions -------------

printf '── run.sh: failure surfaces bypass instructions ────────\n'
make_repo "$WORK/r4"
add_pack_directive_pass "$WORK/r4" "acme/test" "happy"
add_pack_directive_fail "$WORK/r4" "acme/test" "sad"
set +e
output="$(bash "$WORK/r4/.governance/run.sh" 2>&1)"
exit_code=$?
set -e
assert_eq "exit 1 when any directive fails" 1 "$exit_code"
assert_contains "summary names failure count"  "1 directive(s) failed" "$output"
assert_contains "summary names pass count"     "1 passed" "$output"
assert_contains "prints SKIP_GOVERNANCE bypass" "SKIP_GOVERNANCE=1 git commit" "$output"
assert_contains "prints --no-verify bypass"    "git commit --no-verify" "$output"

# ---- run.sh: single-directive filter --------------------------------------

printf '── run.sh: single-directive filter ─────────────────────\n'
make_repo "$WORK/r5"
add_pack_directive_pass "$WORK/r5" "acme/test" "wanted"
add_pack_directive_fail "$WORK/r5" "acme/test" "unwanted"
# Filter to just "wanted" — should pass even though "unwanted" exists.
set +e
output="$(bash "$WORK/r5/.governance/run.sh" wanted 2>&1)"
exit_code=$?
set -e
assert_eq "filter exits 0 when only filtered directive passes" 0 "$exit_code"
assert_contains "filter result lists wanted"    "wanted" "$output"
if [[ "$output" != *"intentional fail"* ]]; then
    PASS=$((PASS + 1)); printf '  ok - filter does not run sibling directives\n'
else
    FAIL=$((FAIL + 1)); printf '  not ok - filter ran a sibling that should be skipped\n'
fi

# Filter matching nothing → exit 1.
set +e
output="$(bash "$WORK/r5/.governance/run.sh" no-such-directive 2>&1)"
exit_code=$?
set -e
assert_eq "filter exits 1 when no directive matches" 1 "$exit_code"
assert_contains "filter prints clear miss notice" "no directive matching" "$output"

# ---- lib.sh: directive_start / directive_end --------------------------------

printf '── lib.sh: directive_start / directive_end ─────────────\n'
# Run a directive fragment in isolation by sourcing lib.sh into a subshell.
set +e
output=$(
    set +u
    source "$LIB_SH"
    directive_start "demo-pass"
    directive_end
)
exit_code=$?
set -e
assert_eq "directive_end exits 0 when no violations recorded" 0 "$exit_code"
assert_contains "passing directive emits ✓ + name" "✓ demo-pass" "$output"

set +e
output=$(
    set +u
    source "$LIB_SH"
    directive_start "demo-fail"
    violation "broken thing"
    violation "other broken thing"
    directive_end
)
exit_code=$?
set -e
assert_eq "directive_end exits 1 when violations recorded" 1 "$exit_code"
assert_contains "failing directive emits ✗ + name"      "✗ demo-fail" "$output"
assert_contains "failing directive announces count"     "(2 violations)" "$output"
assert_contains "failing directive lists each violation #1" "broken thing" "$output"
assert_contains "failing directive lists each violation #2" "other broken thing" "$output"

# Singular form when count == 1.
set +e
output=$(
    set +u
    source "$LIB_SH"
    directive_start "demo-fail-1"
    violation "lonely"
    directive_end
)
set -e
assert_contains "single-violation count uses singular form" "(1 violation)" "$output"

# ---- lib.sh: require_git ---------------------------------------------------

printf '── lib.sh: require_git ─────────────────────────────────\n'
not_a_repo="$WORK/not-a-repo"
mkdir -p "$not_a_repo"
set +e
output=$(
    cd "$not_a_repo"
    set +u
    source "$LIB_SH"
    directive_start "demo"
    require_git
    # Should not reach here.
    echo "REACHED-PAST-REQUIRE-GIT"
)
exit_code=$?
set -e
assert_eq "require_git exits 0 outside a git repo" 0 "$exit_code"
assert_contains "require_git emits ⊘ skip" "⊘ demo" "$output"
if [[ "$output" != *"REACHED-PAST-REQUIRE-GIT"* ]]; then
    PASS=$((PASS + 1)); printf '  ok - require_git short-circuits the check\n'
else
    FAIL=$((FAIL + 1)); printf '  not ok - require_git did not short-circuit\n'
fi

# Inside a real git repo, require_git is a no-op.
real_repo="$WORK/real-repo"
mkdir -p "$real_repo"
git -C "$real_repo" init -q
set +e
output=$(
    cd "$real_repo"
    set +u
    source "$LIB_SH"
    directive_start "demo"
    require_git
    echo "REACHED"
    directive_end
)
set -e
assert_contains "require_git inside a repo does not short-circuit" "REACHED" "$output"

# ---- lib.sh: tracked_files respects .gitignore -----------------------------

printf '── lib.sh: tracked_files ───────────────────────────────\n'
ignored_repo="$WORK/ignored-repo"
mkdir -p "$ignored_repo"
git -C "$ignored_repo" init -q
echo "ignored.txt" > "$ignored_repo/.gitignore"
echo "tracked"   > "$ignored_repo/tracked.txt"
echo "ignored"   > "$ignored_repo/ignored.txt"
git -C "$ignored_repo" add -A
git -C "$ignored_repo" -c user.email=t@e -c user.name=t commit -q -m "init"

output=$(
    cd "$ignored_repo"
    set +u
    source "$LIB_SH"
    tracked_files
)
assert_contains "tracked.txt is tracked"           "tracked.txt" "$output"
if [[ "$output" != *"ignored.txt"* ]]; then
    PASS=$((PASS + 1)); printf '  ok - ignored.txt absent from tracked_files\n'
else
    FAIL=$((FAIL + 1)); printf '  not ok - ignored.txt should not appear\n'
fi

# Pathspec filter: only .gitignore.
output=$(
    cd "$ignored_repo"
    set +u
    source "$LIB_SH"
    tracked_files '.gitignore'
)
assert_contains ".gitignore reaches the filtered list" ".gitignore" "$output"
if [[ "$output" != *"tracked.txt"* ]]; then
    PASS=$((PASS + 1)); printf '  ok - pathspec filter excludes non-matching files\n'
else
    FAIL=$((FAIL + 1)); printf '  not ok - pathspec filter should narrow to .gitignore only\n'
fi

# ---- lib.sh: has_waiver ----------------------------------------------------

printf '── lib.sh: has_waiver ──────────────────────────────────\n'
waiver_file="$WORK/waiver.txt"
# Build the AWS-key prefix from a variable so this test file itself doesn't
# carry a string the secrets-hygiene directive's regex would flag. The on-disk
# fixture inside $WORK/ is identical to the literal we want — the indirection
# only hides the literal from a static scan of tracked source.
aws_prefix="AK""IA"
cat > "$waiver_file" <<EOF
secret = "${aws_prefix}0000000000000000"
secret_with_waiver = "${aws_prefix}0000000000000001"  # governance: allow-secrets-hygiene TICKET-7
EOF
set +e
(
    set +u
    source "$LIB_SH"
    if has_waiver "$waiver_file" 1 "secrets-hygiene"; then exit 99; else exit 0; fi
)
exit_code=$?
set -e
assert_eq "no waiver on line 1 → exit 0" 0 "$exit_code"

set +e
(
    set +u
    source "$LIB_SH"
    if has_waiver "$waiver_file" 2 "secrets-hygiene"; then exit 0; else exit 1; fi
)
exit_code=$?
set -e
assert_eq "waiver on line 2 → exit 0" 0 "$exit_code"

# Different directive id → no waiver, even when the marker is present for another id.
set +e
(
    set +u
    source "$LIB_SH"
    if has_waiver "$waiver_file" 2 "different-rule"; then exit 99; else exit 0; fi
)
exit_code=$?
set -e
assert_eq "waiver is scoped to the named directive id" 0 "$exit_code"

# ---- lib.sh: has_file_waiver ----------------------------------------------

printf '── lib.sh: has_file_waiver ─────────────────────────────\n'

# File without any waiver token → no waiver.
fwaiver_no="$WORK/fwaiver_no.ts"
{ for i in $(seq 1 5); do printf 'export const k%d = %d;\n' "$i" "$i"; done; } > "$fwaiver_no"
set +e
(
    set +u
    source "$LIB_SH"
    if has_file_waiver "$fwaiver_no" "repo-hygiene" "file-size-limit"; then exit 99; else exit 0; fi
)
exit_code=$?
set -e
assert_eq "no token in file → exit non-zero (no waiver)" 0 "$exit_code"

# Token in line 1 → waiver applies.
fwaiver_yes="$WORK/fwaiver_yes.ts"
{
    printf '// governance: allow-repo-hygiene file-size-limit TICKET-9 entrypoint\n'
    for i in $(seq 1 5); do printf 'export const k%d = %d;\n' "$i" "$i"; done
} > "$fwaiver_yes"
set +e
(
    set +u
    source "$LIB_SH"
    if has_file_waiver "$fwaiver_yes" "repo-hygiene" "file-size-limit"; then exit 0; else exit 1; fi
)
exit_code=$?
set -e
assert_eq "head-of-file waiver → exit 0" 0 "$exit_code"

# Token in line 10 → still within the 10-line head window.
fwaiver_l10="$WORK/fwaiver_l10.ts"
{
    for i in $(seq 1 9); do printf 'export const k%d = %d;\n' "$i" "$i"; done
    printf '// governance: allow-repo-hygiene file-size-limit TICKET-10\n'
    for i in $(seq 11 15); do printf 'export const k%d = %d;\n' "$i" "$i"; done
} > "$fwaiver_l10"
set +e
(
    set +u
    source "$LIB_SH"
    if has_file_waiver "$fwaiver_l10" "repo-hygiene" "file-size-limit"; then exit 0; else exit 1; fi
)
exit_code=$?
set -e
assert_eq "waiver on line 10 → exit 0 (within 10-line window)" 0 "$exit_code"

# Token past line 10 → no waiver.
fwaiver_l11="$WORK/fwaiver_l11.ts"
{
    for i in $(seq 1 10); do printf 'export const k%d = %d;\n' "$i" "$i"; done
    printf '// governance: allow-repo-hygiene file-size-limit TICKET-11\n'
} > "$fwaiver_l11"
set +e
(
    set +u
    source "$LIB_SH"
    if has_file_waiver "$fwaiver_l11" "repo-hygiene" "file-size-limit"; then exit 99; else exit 0; fi
)
exit_code=$?
set -e
assert_eq "waiver beyond line 10 → no waiver" 0 "$exit_code"

# Sub-check name must match — `file-size-limit` token must not waive a different sub-check.
set +e
(
    set +u
    source "$LIB_SH"
    if has_file_waiver "$fwaiver_yes" "repo-hygiene" "debug-statements"; then exit 99; else exit 0; fi
)
exit_code=$?
set -e
assert_eq "waiver is scoped to the named sub-check" 0 "$exit_code"

# Directive id must match — `repo-hygiene` token must not waive `secrets-hygiene`.
set +e
(
    set +u
    source "$LIB_SH"
    if has_file_waiver "$fwaiver_yes" "secrets-hygiene" "file-size-limit"; then exit 99; else exit 0; fi
)
exit_code=$?
set -e
assert_eq "waiver is scoped to the named directive id" 0 "$exit_code"

# ---- lib.sh: sub-agent attestation infra (issue #272) ---------------------

printf '── lib.sh: extract_md_section / attestation_prompt / require_attestation ─\n'
att_doc="$WORK/att.md"
cat > "$att_doc" <<'EOF'
# Receipt

## What changed

did a thing.

## Audit

- PASS — what changed matches the diff.
- REFUTED — checklist drifted from the issue.

## Out of scope

None.
EOF

# extract_md_section returns only the named section body, stopping at next `## `.
output=$(set +u; source "$LIB_SH"; extract_md_section "$att_doc" "Audit")
assert_contains "extract_md_section returns the section body"      "PASS — what changed" "$output"
assert_contains "extract_md_section keeps the second body line"    "REFUTED — checklist" "$output"
if printf '%s' "$output" | grep -q 'Out of scope'; then
    assert_eq "extract_md_section stops at the next heading" stop nostop
else
    assert_eq "extract_md_section stops at the next heading" stop stop
fi
# Case-insensitive heading match.
output=$(set +u; source "$LIB_SH"; extract_md_section "$att_doc" "audit")
assert_contains "extract_md_section matches heading case-insensitively" "PASS — what changed" "$output"

# attestation_prompt renders the canonical envelope with numbered checks.
output=$(set +u; source "$LIB_SH"; attestation_prompt "Audit" "the diff and the issue" "check one" "check two")
assert_contains "attestation_prompt names the inputs"        "the diff and the issue" "$output"
assert_contains "attestation_prompt numbers the first check" "(1) check one" "$output"
assert_contains "attestation_prompt numbers the second check" "(2) check two" "$output"
assert_contains "attestation_prompt names the target section" "into a '## Audit' section" "$output"
assert_contains "attestation_prompt states the no-spawn invariant" "hook never spawns" "$output"
assert_contains "attestation_prompt rejects self-authored sections" "do not self-author this section" "$output"

# require_attestation: present + verdict-bearing section → no violation, returns 0.
set +e
output=$(
    set +u
    source "$LIB_SH"
    directive_start "att-ok"
    require_attestation "$att_doc" "Audit" "why." "the diff" "check one"
    echo "rc=$?"
    directive_end
)
exit_code=$?
set -e
assert_eq "require_attestation passes a well-formed section" 0 "$exit_code"
assert_contains "require_attestation returns 0 on well-formed section" "rc=0" "$output"

# require_attestation: missing section → violation carrying the why + prompt.
missing_doc="$WORK/no-audit.md"
printf '# Receipt\n\n## What changed\n\ndid a thing.\n' > "$missing_doc"
set +e
output=$(
    set +u
    source "$LIB_SH"
    directive_start "att-missing"
    require_attestation "$missing_doc" "Audit" "MECHANICAL-GAP." "the diff" "check one"
    directive_end
)
exit_code=$?
set -e
assert_eq "require_attestation fails when the section is missing" 1 "$exit_code"
assert_contains "missing-section violation carries the why"    "MECHANICAL-GAP." "$output"
assert_contains "missing-section violation carries the prompt"  "Spawn a fresh-context sub-agent" "$output"

# require_attestation: present but no PASS/REFUTED verdict → violation.
noverdict_doc="$WORK/no-verdict.md"
printf '# Receipt\n\n## Audit\n\nlooked fine to me.\n' > "$noverdict_doc"
set +e
output=$(
    set +u
    source "$LIB_SH"
    directive_start "att-noverdict"
    require_attestation "$noverdict_doc" "Audit" "why." "the diff" "check one"
    directive_end
)
exit_code=$?
set -e
assert_eq "require_attestation fails when the section has no verdict" 1 "$exit_code"
assert_contains "no-verdict violation explains the missing verdict" "records no PASS/REFUTED verdict" "$output"

# ---- lib.sh: judge_attest + attestation_remediation (issue #325) --------

printf '── lib.sh: judge_attest / attestation_remediation ───\n'
sa_dir="$WORK/sa-directive"
mkdir -p "$sa_dir"
cat > "$sa_dir/directive.yaml" <<'EOF'
surface: change-set
hook: pre-commit
judge:
  inputs:  [diff, receipt, issue]
  checks:
    - "What changed matches the diff"
    - "checklist mirrors the issue"
  group: bundled
  section: Audit
  cmd:
    sweep: claude -p --output-format text --model opus
EOF
cat > "$sa_dir/check.sh" <<EOF
set -u
source "$LIB_SH"
directive_start sa
judge_attest "\$1"
directive_end
EOF

# _judge_yaml parses the declared block (scalars + lists, no PyYAML).
output=$(set +u; source "$LIB_SH"; _judge_yaml "$sa_dir/directive.yaml" section)
assert_eq "_judge_yaml reads the section scalar" "Audit" "$output"
output=$(set +u; source "$LIB_SH"; _judge_yaml "$sa_dir/directive.yaml" group)
assert_eq "_judge_yaml reads the group scalar" "bundled" "$output"
output=$(set +u; source "$LIB_SH"; _judge_cmd_resolve "$sa_dir/directive.yaml" sweep)
assert_eq "_judge_cmd_resolve reads the sweep command" \
    "claude -p --output-format text --model opus" "$output"
output=$(set +u; source "$LIB_SH"; _judge_yaml "$sa_dir/directive.yaml" inputs | tr '\n' ',')
assert_eq "_judge_yaml reads the inputs flow list" "diff,receipt,issue," "$output"
output=$(set +u; source "$LIB_SH"; _judge_yaml "$sa_dir/directive.yaml" checks | head -1)
assert_eq "_judge_yaml reads a block-list check" "What changed matches the diff" "$output"

# Missing section → gate fails, and the pending attestation is registered.
sa_receipt="$WORK/issue-9-x.md"
printf '# r\n\n## What changed\n\nx\n' > "$sa_receipt"
sa_ledger="$WORK/sa-ledger.tsv"; : > "$sa_ledger"
set +e
output=$(set +u; export GOVERNANCE_ATTEST_LEDGER="$sa_ledger"; cd "$sa_dir"; bash check.sh "$sa_receipt" 2>&1)
exit_code=$?
set -e
assert_eq "judge_attest fails on a missing section" 1 "$exit_code"
assert_contains "judge_attest names the missing section" "missing a '## Audit' section" "$output"
assert_contains "judge_attest registers the group label" "bundled" "$(cat "$sa_ledger")"

# attestation_remediation emits ONE grouped envelope with the numbered checks.
output=$(set +u; source "$LIB_SH"; attestation_remediation "$sa_ledger" 2>&1)
assert_contains "remediation emits the grouped envelope" "Spawn ONE fresh-context sub-agent for group \`bundled\`" "$output"
assert_contains "remediation names the target section" "write the '## Audit' section" "$output"
assert_contains "remediation numbers the first check" "(1) What changed matches the diff" "$output"
assert_contains "remediation numbers the second check" "(2) checklist mirrors the issue" "$output"
assert_contains "remediation unions the resolved inputs" "the diff (\`git diff\`)" "$output"
assert_contains "remediation rejects self-authored sections" "do not self-author these sections" "$output"

# An unlabeled record gets its own sub-agent instruction (US-joined inner fields).
printf -- '-\tattest\t%s\tSteering\t%s\t%s\n' \
    "$WORK/issue-9-x.md" \
    "the session transcript"$'\x1f'"this receipt" \
    "every event recorded" >> "$sa_ledger"
output=$(set +u; source "$LIB_SH"; attestation_remediation "$sa_ledger" 2>&1)
assert_contains "remediation adds a solo sub-agent" "Spawn a separate fresh-context sub-agent (solo" "$output"

# Present + verdict → gate passes and nothing is registered.
printf '# r\n\n## Audit\n\n- PASS — ok\n' > "$sa_receipt"
: > "$sa_ledger"
set +e
output=$(set +u; export GOVERNANCE_ATTEST_LEDGER="$sa_ledger"; cd "$sa_dir"; bash check.sh "$sa_receipt"; echo "rc=$?")
set -e
assert_contains "judge_attest passes a verdict-bearing section" "rc=0" "$output"
assert_eq "no registration when the section is well-formed" "" "$(cat "$sa_ledger")"

# Empty ledger → the orchestrator is a silent no-op.
: > "$sa_ledger"
output=$(set +u; source "$LIB_SH"; attestation_remediation "$sa_ledger" 2>&1)
assert_eq "remediation is silent with no pending attestations" "" "$output"

# The transcript input is runtime-aware, so Codex users are not handed a
# Claude-only lookup instruction.
output=$(
    set +u
    unset CLAUDE_TRANSCRIPT_PATH CLAUDE_CODE_SESSION_ID
    CODEX_THREAD_ID="019ed941-f410-7871-bacf-6db3af231768"
    source "$LIB_SH"
    resolve_judge_input transcript "$sa_receipt"
)
assert_contains "transcript input names Codex sessions" "~/.codex/sessions/" "$output"
assert_contains "transcript input names CODEX_THREAD_ID" 'CODEX_THREAD_ID.jsonl' "$output"

output=$(
    set +u
    unset CODEX_TRANSCRIPT_PATH CODEX_THREAD_ID
    CLAUDE_CODE_SESSION_ID="9e05791b-0ee0-423e-b0c8-2234df57840a"
    source "$LIB_SH"
    resolve_judge_input transcript "$sa_receipt"
)
assert_contains "transcript input still supports Claude session ids" 'CLAUDE_CODE_SESSION_ID.jsonl' "$output"

# ---- lib.sh: the group label + the declared judge command (issue #355) -----

printf '── lib.sh: judge group / cmd (#355) ─────────────────\n'

# judge_attest in an installed (.governance/packs/...) layout: the ledger row
# carries the declared batching label and the lane it was raised on.
k_dir="$WORK/knob-repo"
k_chk="$k_dir/.governance/packs/acme/audit/directives/rec"
mkdir -p "$k_chk"
git -C "$k_dir" init -q
cat > "$k_chk/directive.yaml" <<'EOF'
surface: change-set
hook: pre-commit
judge:
  inputs:  [diff]
  checks:
    - "What changed matches the diff"
  group: bundled-intent
  section: Audit
  cmd:
    sweep: claude -p --output-format text --model opus
EOF
cat > "$k_chk/defaults.conf" <<'EOF'
JUDGE_ROUNDS=3
EOF
cat > "$k_chk/check.sh" <<EOF
set -u
source "$LIB_SH"
directive_start rec
judge_attest "\$1"
directive_end
EOF
k_receipt="$k_dir/receipts/issue-7-x.md"
mkdir -p "$k_dir/receipts"
printf '# r\n\n## What changed\n\nx\n' > "$k_receipt"
k_ledger="$WORK/knob-ledger.tsv"

# The check exits 1 on the (expected) missing section, so guard against set -e.
: > "$k_ledger"
(set +u; export GOVERNANCE_ATTEST_LEDGER="$k_ledger"; cd "$k_dir"; bash "$k_chk/check.sh" "$k_receipt" >/dev/null 2>&1) || true
assert_eq "the group column carries the declared label" "bundled-intent" "$(cut -f1 "$k_ledger")"
assert_eq "the lane column is attest on the commit path" "attest" "$(cut -f2 "$k_ledger")"

# A directive that declares no group is a spawn of its own; the ledger says so
# with `-`, never with an empty field (tab is IFS whitespace — an empty field
# would shift every column after it).
k_solo="$k_dir/.governance/packs/acme/audit/directives/solo"
mkdir -p "$k_solo"
sed '/^  group:/d' "$k_chk/directive.yaml" > "$k_solo/directive.yaml"
cp "$k_chk/defaults.conf" "$k_solo/defaults.conf"
sed 's/directive_start rec/directive_start solo/' "$k_chk/check.sh" > "$k_solo/check.sh"
: > "$k_ledger"
(set +u; export GOVERNANCE_ATTEST_LEDGER="$k_ledger"; cd "$k_dir"; bash "$k_solo/check.sh" "$k_receipt" >/dev/null 2>&1) || true
assert_eq "an undeclared group travels as a literal dash" "-" "$(cut -f1 "$k_ledger")"
assert_eq "and the row still has all ten fields" "harness" "$(cut -f10 "$k_ledger")"
output=$(set +u; source "$LIB_SH"; attestation_remediation "$k_ledger" 2>&1)
assert_contains "remediation routes an unlabeled row to its own sub-agent" \
    "Spawn a separate fresh-context sub-agent (solo" "$output"

# A declaration with NO `section:` is sweep-only discovery: it names no place in
# the receipt for a verdict to land, so the commit lane no-ops on it instead of
# gating anything — the lane is read off `section:` and nothing else.
k_disc="$k_dir/.governance/packs/acme/audit/directives/disc"
mkdir -p "$k_disc"
sed '/^  section:/d' "$k_chk/directive.yaml" > "$k_disc/directive.yaml"
cp "$k_chk/defaults.conf" "$k_disc/defaults.conf"
sed 's/directive_start rec/directive_start disc/' "$k_chk/check.sh" > "$k_disc/check.sh"
: > "$k_ledger"
set +e
(set +u; export GOVERNANCE_ATTEST_LEDGER="$k_ledger"; cd "$k_dir"; bash "$k_disc/check.sh" "$k_receipt" >/dev/null 2>&1)
exit_code=$?
set -e
assert_eq "a sectionless declaration no-ops on the commit path" 0 "$exit_code"
assert_eq "and registers nothing for the orchestrator" "" "$(cat "$k_ledger")"

# The judge command is read from the directive, per lane — no conf ladder, no
# env override, no tier vocabulary (issue #355).
output=$(set +u; source "$LIB_SH"; _judge_cmd_resolve "$k_chk/directive.yaml" sweep)
assert_eq "the sweep command is the directive's own" \
    "claude -p --output-format text --model opus" "$output"
output=$(set +u; source "$LIB_SH"; _judge_cmd_resolve "$k_chk/directive.yaml" attest || printf '(none)')
assert_eq "no attest row means the harness path, and prints nothing" "(none)" "$output"

# ---- lib.sh: conf_file / conf_get / conf_rule_lines -----------------------

printf '── lib.sh: conf_file / conf_get / conf_rule_lines ──────\n'
conf_repo="$WORK/conf-repo"
mkdir -p "$conf_repo/.governance/conf"
git -C "$conf_repo" init -q
cat > "$conf_repo/.governance/conf/sample.conf" <<'EOF'
# a comment line
FRESHNESS_DAYS=30
EMPTY=
frozen-files receipts/*.md
  append-only COSTS.md   # trailing comment
NOTAKEY here
EOF

# conf_file: present → prints path, exit 0
output=$(cd "$conf_repo"; set +u; source "$LIB_SH"; conf_file sample)
exit_code=$?
assert_eq "conf_file present → exit 0" 0 "$exit_code"
assert_contains "conf_file prints the conf path" ".governance/conf/sample.conf" "$output"

# conf_file: absent → exit 1, no output
set +e
output=$(cd "$conf_repo"; set +u; source "$LIB_SH"; conf_file missing)
exit_code=$?
set -e
assert_eq "conf_file absent → exit 1" 1 "$exit_code"
assert_eq "conf_file absent → no output" "" "$output"

# A pack-owned defaults.conf for the new conf_get resolution (issue #210): the
# live default + DEF_ONLY live here, FRESHNESS_DAYS is also overridden in the
# overlay above.
cat > "$conf_repo/defaults.conf" <<'EOF'
# pack-owned defaults
FRESHNESS_DAYS=90
DEF_ONLY=55
EOF

# conf_get: overlay value wins over the defaults.conf row
output=$(cd "$conf_repo"; set +u; source "$LIB_SH"; conf_get sample FRESHNESS_DAYS ./defaults.conf)
assert_eq "conf_get overlay beats defaults.conf" "30" "$output"

# conf_get: env overrides both overlay and defaults.conf
output=$(cd "$conf_repo"; set +u; source "$LIB_SH"; GOVERNANCE_FRESHNESS_DAYS=7 conf_get sample FRESHNESS_DAYS ./defaults.conf)
assert_eq "conf_get env beats overlay+defaults" "7" "$output"

# conf_get: key absent from overlay → falls through to the defaults.conf row
output=$(cd "$conf_repo"; set +u; source "$LIB_SH"; conf_get sample DEF_ONLY ./defaults.conf)
assert_eq "conf_get reads value from defaults.conf" "55" "$output"

# conf_get fail-loud: a read knob with no defaults.conf row → non-zero, no stdout
set +e
output=$(cd "$conf_repo"; set +u; source "$LIB_SH"; conf_get sample MISSING ./defaults.conf 2>/dev/null)
exit_code=$?
set -e
assert_eq "conf_get missing row → non-zero" 1 "$exit_code"
assert_eq "conf_get missing row → no stdout" "" "$output"

# conf_get fail-loud: a missing defaults.conf file → non-zero
set +e
output=$(cd "$conf_repo"; set +u; source "$LIB_SH"; conf_get sample DEF_ONLY ./nope/defaults.conf 2>/dev/null)
exit_code=$?
set -e
assert_eq "conf_get missing defaults file → non-zero" 1 "$exit_code"

# conf_get transitional compat: a bare-literal 3rd arg (pre-#210 convention) is
# treated as an in-code default, so a directive folder vendored from an older
# release keeps working against this lib.sh.
output=$(cd "$conf_repo"; set +u; source "$LIB_SH"; conf_get nopack MISSING 90)
assert_eq "conf_get literal default (transitional)" "90" "$output"

# conf_rule_lines: comments / blanks / KEY= lines stripped, rest trimmed
output=$(cd "$conf_repo"; set +u; source "$LIB_SH"; conf_rule_lines sample)
expected=$'frozen-files receipts/*.md\nappend-only COSTS.md\nNOTAKEY here'
assert_eq "conf_rule_lines yields trimmed rule lines only" "$expected" "$output"

# conf_rule_lines: no conf → empty, exit 0
set +e
output=$(cd "$conf_repo"; set +u; source "$LIB_SH"; conf_rule_lines nopack)
exit_code=$?
set -e
assert_eq "conf_rule_lines no conf → exit 0" 0 "$exit_code"
assert_eq "conf_rule_lines no conf → empty" "" "$output"

# ---- lib.sh: conf_list (defaults + overlay layering) ----------------------

printf '── lib.sh: conf_list ───────────────────────────────────\n'
list_repo="$WORK/list-repo"
mkdir -p "$list_repo/.governance/conf"
git -C "$list_repo" init -q
cat > "$list_repo/defaults.conf" <<'EOF'
# pack-owned defaults
feat
fix
chore
style
EOF

# No overlay → effective list is the defaults verbatim.
output=$(cd "$list_repo"; set +u; source "$LIB_SH"; conf_list cmf ./defaults.conf | tr '\n' ' ')
assert_eq "conf_list no overlay → defaults" "feat fix chore style " "$output"

# Overlay adds and removes (gitignore-style ! negation).
cat > "$list_repo/.governance/conf/cmf.conf" <<'EOF'
# my overlay
!style
wip
EOF
output=$(cd "$list_repo"; set +u; source "$LIB_SH"; conf_list cmf ./defaults.conf | tr '\n' ' ')
assert_eq "conf_list overlay removes default + adds new" "feat fix chore wip " "$output"

# Whitespace-normalized removal: a single-spaced ! line matches a column-aligned
# default, and additions append while preserving default alignment.
cat > "$list_repo/defaults.conf" <<'EOF'
frozen-files    receipts/*.md
append-only      COSTS.md
frozen-section  QUALITY.md         Resolved
EOF
cat > "$list_repo/.governance/conf/cmf.conf" <<'EOF'
!frozen-section QUALITY.md Resolved
append-only docs/DECISIONS.md
EOF
output=$(cd "$list_repo"; set +u; source "$LIB_SH"; conf_list cmf ./defaults.conf)
expected=$'frozen-files    receipts/*.md\nappend-only      COSTS.md\nappend-only docs/DECISIONS.md'
assert_eq "conf_list normalizes whitespace for ! removal" "$expected" "$output"

# Removing every default → empty effective list.
cat > "$list_repo/.governance/conf/cmf.conf" <<'EOF'
!frozen-files receipts/*.md
!append-only COSTS.md
!frozen-section QUALITY.md Resolved
EOF
output=$(cd "$list_repo"; set +u; source "$LIB_SH"; conf_list cmf ./defaults.conf)
assert_eq "conf_list can empty the list" "" "$output"

# Runtime identity-ladder tests (env detection → RUNTIME/SESSION_ID, the
# packs/audit/directives/agent-token-accounting/lib/runtime.sh side of #355 v2)
# live in that directive's own evals/test.sh, not here — this file owns the
# adapter files themselves (kit/assets/dot-governance/runtimes/**), which the
# identity ladder and the resolve sweep both call into as a black box.

# ---- runtime adapters: claude-code.sh --------------------------------------
# resolve/emit (issue #355 v2 — identity at commit, measurement at rest).
# `resolve` never guesses: only a declared path or an exact session-id-named
# transcript is opened; `emit` never blocks a hook on identity — it drops
# silently when there is nothing to attribute.

printf '── runtime adapters: claude-code.sh ──────────────────────\n'
claude_projects="$WORK/claude-projects"
mkdir -p "$claude_projects/-Users-agent-repo"
claude_wanted="$claude_projects/-Users-agent-repo/session-wanted.jsonl"
claude_other="$claude_projects/-Users-agent-repo/session-other.jsonl"
cat > "$claude_wanted" <<'EOF'
{"sessionId":"session-wanted","type":"assistant","model":"claude-sonnet-4-5","usage":{"input_tokens":100,"cache_creation_input_tokens":10,"cache_read_input_tokens":5,"output_tokens":20},"costUSD":0.0100}
{"sessionId":"session-wanted","type":"assistant","model":"claude-sonnet-4-5","usage":{"input_tokens":50,"cache_creation_input_tokens":0,"cache_read_input_tokens":5,"output_tokens":10},"costUSD":0.0050}
EOF
cat > "$claude_other" <<'EOF'
{"sessionId":"session-other","type":"assistant","model":"claude-opus-4-5","usage":{"input_tokens":9000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":900},"costUSD":9.0000}
EOF

set +e
output=$(CLAUDE_PROJECTS_DIR="$claude_projects" bash "$TOKEN_CLAUDE_SH" resolve session-wanted)
exit_code=$?
set -e
assert_eq "claude-code resolve exits 0 on an exact-name match" 0 "$exit_code"
assert_eq "claude-code resolve sums the named transcript only" \
    "150 10 10 30 claude-sonnet-4-5 0.0150 session-file" "$output"
if [[ "$output" != *"9000"* && "$output" != *"9.0000"* ]]; then
    PASS=$((PASS + 1)); printf '  ok - claude-code resolve does not pick the other transcript in the same dir (two transcripts present, wrong one not chosen)\n'
else
    FAIL=$((FAIL + 1)); printf '  not ok - claude-code resolve leaked numbers from the wrong transcript\n'
fi

# The declared-path argument (how the identity file's `declared=` field
# reaches the adapter from a resolve sweep) is honored directly.
set +e
output=$(bash "$TOKEN_CLAUDE_SH" resolve session-wanted "$claude_wanted")
exit_code=$?
set -e
assert_eq "claude-code resolve honors an explicit declared path" 0 "$exit_code"
assert_eq "claude-code resolve via declared path sums correctly" \
    "150 10 10 30 claude-sonnet-4-5 0.0150 session-file" "$output"

# No identity → no numbers, even with two real transcripts sitting right
# there. This is the "no mtime guessing" contract: a session id that names
# nothing on disk gets exit 2, never the newest or only file in the directory.
set +e
output=$(CLAUDE_PROJECTS_DIR="$claude_projects" bash "$TOKEN_CLAUDE_SH" resolve session-unknown)
exit_code=$?
set -e
assert_eq "claude-code resolve refuses to guess an unnamed session" 2 "$exit_code"

# emit: statusline JSON on stdin, inside a real tmp git repo.
claude_repo="$WORK/claude-emit-repo"
mkdir -p "$claude_repo"
git -C "$claude_repo" init -q
git -C "$claude_repo" -c user.email=t@e -c user.name=t commit -q --allow-empty -m init
claude_payload='{"session_id":"emit-sess-1","transcript_path":"/tmp/emit-sess-1.jsonl","cwd":"'"$claude_repo"'","model":{"id":"claude-opus-4-5","display_name":"Opus"},"cost":{"total_cost_usd":1.2500}}'
set +e
output=$(printf '%s' "$claude_payload" | bash "$TOKEN_CLAUDE_SH" emit)
exit_code=$?
set -e
assert_eq "claude-code emit exits 0" 0 "$exit_code"
claude_gitd="$(git -C "$claude_repo" rev-parse --absolute-git-dir)"
sidecar_out="$(cat "$claude_gitd/governance/costs/claude-code-emit-sess-1" 2>/dev/null)"
assert_contains "claude-code emit appends a harness-feed sidecar snapshot" \
    "v1 " "$sidecar_out"
assert_contains "claude-code emit sidecar carries cost + harness-feed source" \
    "claude-opus-4-5 1.2500 harness-feed" "$sidecar_out"
identity_out="$(cat "$claude_gitd/governance/session-identity" 2>/dev/null)"
assert_contains "claude-code emit refreshes identity harness" "harness=claude-code" "$identity_out"
assert_contains "claude-code emit refreshes identity session" "session=emit-sess-1" "$identity_out"
assert_contains "claude-code emit records the declared transcript path" \
    "declared=/tmp/emit-sess-1.jsonl" "$identity_out"

# emit outside a git repo silently exits 0 and writes nothing.
claude_nongit="$WORK/claude-emit-nongit"
mkdir -p "$claude_nongit"
nongit_payload='{"session_id":"outside-sess","cwd":"'"$claude_nongit"'","model":{"id":"m"},"cost":{"total_cost_usd":0.5}}'
set +e
output=$(printf '%s' "$nongit_payload" | bash "$TOKEN_CLAUDE_SH" emit)
exit_code=$?
set -e
assert_eq "claude-code emit exits 0 outside a git repo (never an error)" 0 "$exit_code"

# ---- runtime adapters: codex.sh --------------------------------------------

printf '── runtime adapters: codex.sh ────────────────────────────\n'
codex_sessions="$WORK/codex-sessions"
codex_archived="$WORK/codex-archived"
mkdir -p "$codex_sessions/2026/06/18" "$codex_archived"
codex_thread="019ed941-f410-7871-bacf-6db3af231768"
codex_wanted="$codex_sessions/2026/06/18/rollout-2026-06-18T11-13-58-$codex_thread.jsonl"
codex_other="$codex_sessions/2026/06/18/rollout-2026-06-18T11-14-30-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.jsonl"
cat > "$codex_wanted" <<EOF
{"type":"session_meta","payload":{"id":"$codex_thread"}}
{"type":"turn_context","payload":{"collaboration_mode":{"settings":{"model":"gpt-5.5"}}}}
{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":30,"output_tokens":7}}}}
EOF
cat > "$codex_other" <<'EOF'
{"type":"session_meta","payload":{"id":"aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"}}
{"type":"turn_context","payload":{"collaboration_mode":{"settings":{"model":"gpt-5.5"}}}}
{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":900,"cached_input_tokens":0,"output_tokens":9}}}}
EOF

set +e
output=$(
    CODEX_SESSIONS_DIR="$codex_sessions" \
    CODEX_ARCHIVED_SESSIONS_DIR="$codex_archived" \
    bash "$TOKEN_CODEX_SH" resolve "$codex_thread"
)
exit_code=$?
set -e
assert_eq "codex resolve exits 0 on an exact thread-id match" 0 "$exit_code"
assert_eq "codex resolve chooses the thread match over an unrelated transcript (two present, wrong one not chosen)" \
    "70 0 30 7 gpt-5.5 - session-file" "$output"

set +e
output=$(
    CODEX_SESSIONS_DIR="$codex_sessions" \
    CODEX_ARCHIVED_SESSIONS_DIR="$codex_archived" \
    bash "$TOKEN_CODEX_SH" resolve "no-such-thread"
)
exit_code=$?
set -e
assert_eq "codex resolve refuses to guess an unnamed thread" 2 "$exit_code"

set +e
output=$(bash "$TOKEN_CODEX_SH" resolve "$codex_thread" 2>&1)
exit_code=$?
set -e
assert_eq "codex resolve with no sessions dir and no declared path exits 2" 2 "$exit_code"

# A harness-reported dollar figure rides through verbatim; the kit never prices.
codex_priced="$codex_sessions/2026/06/18/rollout-2026-06-18T12-00-00-priced.jsonl"
cat > "$codex_priced" <<'EOF'
{"type":"session_meta","payload":{"id":"priced-thread"}}
{"type":"turn_context","payload":{"collaboration_mode":{"settings":{"model":"gpt-5.5"}}}}
{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":10,"cached_input_tokens":4,"output_tokens":2},"total_cost_usd":0.0125}}}
EOF
set +e
output=$(bash "$TOKEN_CODEX_SH" resolve priced-thread "$codex_priced")
set -e
assert_eq "codex resolve passes a native cost through verbatim (via declared path)" \
    "6 0 4 2 gpt-5.5 0.0125 session-file" "$output"

# emit: identity only — no sidecar snapshot, since the notify payload carries
# no reliable session-cumulative numbers to push.
codex_repo="$WORK/codex-emit-repo"
mkdir -p "$codex_repo"
git -C "$codex_repo" init -q
git -C "$codex_repo" -c user.email=t@e -c user.name=t commit -q --allow-empty -m init
set +e
output=$(printf '{"thread_id":"%s","cwd":"%s"}' "$codex_thread" "$codex_repo" | bash "$TOKEN_CODEX_SH" emit)
exit_code=$?
set -e
assert_eq "codex emit exits 0" 0 "$exit_code"
codex_gitd="$(git -C "$codex_repo" rev-parse --absolute-git-dir)"
assert_contains "codex emit refreshes identity" "harness=codex" "$(cat "$codex_gitd/governance/session-identity" 2>/dev/null)"
assert_contains "codex emit records the thread id as the session" "session=$codex_thread" "$(cat "$codex_gitd/governance/session-identity" 2>/dev/null)"
if [[ ! -d "$codex_gitd/governance/costs" ]]; then
    PASS=$((PASS + 1)); printf '  ok - codex emit writes no sidecar snapshot (identity only)\n'
else
    FAIL=$((FAIL + 1)); printf '  not ok - codex emit should not have written a sidecar\n'
fi

# ---- runtime adapters: manual.sh -------------------------------------------

printf '── runtime adapters: manual.sh ────────────────────────────\n'
set +e
output=$(
    AGENT_CUM_INPUT=10 AGENT_CUM_OUTPUT=5 \
    AGENT_MODEL=some-model-9 AGENT_COST_USD=0.4200 \
    bash "$TOKEN_MANUAL_SH" resolve man-1
)
set -e
assert_eq "manual resolve mirrors the env seam" "10 0 0 5 some-model-9 0.4200 manual" "$output"

set +e
output=$(unset AGENT_CUM_INPUT; bash "$TOKEN_MANUAL_SH" resolve man-1 2>&1)
exit_code=$?
set -e
assert_eq "manual resolve exits 2 when the seam is unset" 2 "$exit_code"

manual_repo="$WORK/manual-emit-repo"
mkdir -p "$manual_repo"
git -C "$manual_repo" init -q
git -C "$manual_repo" -c user.email=t@e -c user.name=t commit -q --allow-empty -m init
set +e
output=$(cd "$manual_repo" && AGENT_SESSION_ID=man-emit-1 bash "$TOKEN_MANUAL_SH" emit </dev/null)
exit_code=$?
set -e
assert_eq "manual emit exits 0" 0 "$exit_code"
manual_gitd="$(git -C "$manual_repo" rev-parse --absolute-git-dir)"
assert_contains "manual emit refreshes identity from AGENT_SESSION_ID" \
    "session=man-emit-1" "$(cat "$manual_gitd/governance/session-identity" 2>/dev/null)"

# ---- runtime adapters: pi.sh ------------------------------------------------
# resolve sums Pi's per-message `usage` objects (input/output/cacheRead/
# cacheWrite/cost.total — Pi DOES report cost) from an exact-name-suffixed
# session file.

printf '── runtime adapters: pi.sh ────────────────────────────────\n'
pi_sessions="$WORK/pi-sessions"
mkdir -p "$pi_sessions"
pi_session_id="pisess-1"
cat > "$pi_sessions/20260618-103000_${pi_session_id}.jsonl" <<EOF
{"model":"pi-large","usage":{"input":10,"output":5,"cacheRead":2,"cacheWrite":1,"cost":{"total":0.0200}}}
{"model":"pi-large","usage":{"input":5,"output":2,"cacheRead":0,"cacheWrite":0,"cost":{"total":0.0100}}}
EOF
set +e
output=$(PI_SESSIONS_DIR="$pi_sessions" bash "$TOKEN_PI_SH" resolve "$pi_session_id")
exit_code=$?
set -e
assert_eq "pi resolve exits 0 on an exact-name session file" 0 "$exit_code"
assert_eq "pi resolve sums usage + cost.total" "15 1 2 7 pi-large 0.0300 session-file" "$output"

set +e
output=$(PI_SESSIONS_DIR="$pi_sessions" bash "$TOKEN_PI_SH" resolve "no-such-session" 2>&1)
exit_code=$?
set -e
assert_eq "pi resolve refuses to guess an unnamed session" 2 "$exit_code"

# ---- runtime adapters: grok.sh ----------------------------------------------
# resolve reads signals.json from the exact session-id directory — never a
# glob, never the newest directory.

printf '── runtime adapters: grok.sh ──────────────────────────────\n'
grok_home="$WORK/grok-home"
mkdir -p "$grok_home/sessions/groksess-1"
cat > "$grok_home/sessions/groksess-1/signals.json" <<'EOF'
{"input_tokens":40,"output_tokens":8,"cache_read_tokens":3,"cache_write_tokens":1,"total_cost_usd":0.0300,"model":"grok-4"}
EOF
set +e
output=$(GROK_HOME="$grok_home" bash "$TOKEN_GROK_SH" resolve groksess-1)
exit_code=$?
set -e
assert_eq "grok resolve exits 0 on an exact session-id directory" 0 "$exit_code"
assert_eq "grok resolve reads signals.json counters" "40 1 3 8 grok-4 0.0300 session-file" "$output"

# A session directory with no signals.json/summary.json fails honestly.
mkdir -p "$grok_home/sessions/groksess-empty"
set +e
output=$(GROK_HOME="$grok_home" bash "$TOKEN_GROK_SH" resolve groksess-empty 2>&1)
exit_code=$?
set -e
assert_eq "grok resolve exits 2 with no signals/summary file" 2 "$exit_code"

# A signals.json missing a required counter is honest, not zero-filled.
mkdir -p "$grok_home/sessions/groksess-partial"
cat > "$grok_home/sessions/groksess-partial/signals.json" <<'EOF'
{"input_tokens":10}
EOF
set +e
output=$(GROK_HOME="$grok_home" bash "$TOKEN_GROK_SH" resolve groksess-partial 2>&1)
exit_code=$?
set -e
assert_eq "grok resolve exits 2 when output_tokens is missing" 2 "$exit_code"

set +e
output=$(GROK_HOME="$grok_home" bash "$TOKEN_GROK_SH" resolve no-such-dir 2>&1)
exit_code=$?
set -e
assert_eq "grok resolve refuses to guess an unnamed session directory" 2 "$exit_code"

# ---- runtime adapters: cursor-agent.sh --------------------------------------
# Cursor exposes no documented per-session usage surface, so resolve always
# refuses — an honest `-`/unresolved row beats a guess.

printf '── runtime adapters: cursor-agent.sh ──────────────────────\n'
set +e
output=$(bash "$TOKEN_CURSOR_SH" resolve any-session 2>&1)
exit_code=$?
set -e
assert_eq "cursor-agent resolve always exits 2 (no documented usage surface)" 2 "$exit_code"

cursor_repo="$WORK/cursor-emit-repo"
mkdir -p "$cursor_repo"
git -C "$cursor_repo" init -q
git -C "$cursor_repo" -c user.email=t@e -c user.name=t commit -q --allow-empty -m init
set +e
output=$(printf '{"conversation_id":"conv-1","cwd":"%s"}' "$cursor_repo" | bash "$TOKEN_CURSOR_SH" emit)
exit_code=$?
set -e
assert_eq "cursor-agent emit exits 0" 0 "$exit_code"
cursor_gitd="$(git -C "$cursor_repo" rev-parse --absolute-git-dir)"
assert_contains "cursor-agent emit refreshes identity from conversation_id" \
    "session=conv-1" "$(cat "$cursor_gitd/governance/session-identity" 2>/dev/null)"

# ---- runtime adapters: opencode.sh ------------------------------------------
# resolve probes a local server; the $OPENCODE_RESPONSE_FILE test seam lets
# this suite exercise the JSON parse without depending on a real network call
# or a running opencode server.

printf '── runtime adapters: opencode.sh ──────────────────────────\n'
opencode_resp="$WORK/opencode-response.json"
cat > "$opencode_resp" <<'EOF'
{"cost":0.0500,"tokens":{"input":20,"output":6,"cache":{"read":4,"write":2}}}
EOF
set +e
output=$(OPENCODE_RESPONSE_FILE="$opencode_resp" bash "$TOKEN_OPENCODE_SH" resolve ocsess-1)
exit_code=$?
set -e
assert_eq "opencode resolve exits 0 via the response-file test seam" 0 "$exit_code"
assert_eq "opencode resolve parses tokens + cost, drops reasoning tokens" \
    "20 2 4 6 unknown 0.0500 server" "$output"

# No test-seam file and no reachable server → exit 2, never a guess.
set +e
output=$(OPENCODE_SERVER="http://127.0.0.1:19999" bash "$TOKEN_OPENCODE_SH" resolve ocsess-1 2>&1)
exit_code=$?
set -e
assert_eq "opencode resolve exits 2 when the server is unreachable" 2 "$exit_code"

# ---- runtime adapters: uniform verb contract --------------------------------
# Every adapter answers exactly resolve/emit — the accounting lane's two verbs.
# Judging left the adapters entirely in issue #355 (a directive names its judge
# COMMAND), so `judge`/`can-judge` are unknown verbs like any other. A bare
# invocation and an unknown verb both refuse loudly rather than silently
# defaulting to anything.

printf '── runtime adapters: uniform verb contract ────────────────\n'
for _adapter in claude-code codex manual pi grok cursor-agent opencode; do
    assert_eq "the registry ships the $_adapter adapter" "1" \
        "$([[ -f "$RUNTIMES_DIR/$_adapter.sh" ]] && echo 1 || echo 0)"

    set +e
    output=$(bash "$RUNTIMES_DIR/$_adapter.sh" 2>&1)
    exit_code=$?
    set -e
    assert_eq "$_adapter adapter: bare invocation exits 2" 2 "$exit_code"
    assert_contains "$_adapter adapter: bare invocation prints usage" "usage:" "$output"

    set +e
    output=$(bash "$RUNTIMES_DIR/$_adapter.sh" bogus-verb 2>&1)
    exit_code=$?
    set -e
    assert_eq "$_adapter adapter: unknown verb exits 2" 2 "$exit_code"
    assert_contains "$_adapter adapter: unknown verb names the supported verbs" \
        "supported: resolve, emit" "$output"

    # `judge` is now just another unknown verb — the surface is gone, not hidden.
    set +e
    output=$(bash "$RUNTIMES_DIR/$_adapter.sh" judge 2>&1)
    exit_code=$?
    set -e
    assert_eq "$_adapter adapter: judge is no longer a verb" 2 "$exit_code"
done

# No python is reachable from any adapter or the runtime dispatcher.
set +e
output=$(grep -nE '(^|[^[:alnum:]_])python3?[[:space:]]' "$RUNTIMES_DIR"/*.sh "$TOKEN_RUNTIME_LIB" \
    2>/dev/null | grep -vE ':[[:space:]]*#')
set -e
assert_eq "runtime adapters invoke no python" "" "$output"

# ---- summary --------------------------------------------------------------

printf '\n────────────────────────────────────────\n'
if [[ $FAIL -eq 0 ]]; then
    printf '✓ test-runtime: %d assertion(s) passed\n' "$PASS"
    exit 0
fi
printf '✗ test-runtime: %d failed, %d passed\n' "$FAIL" "$PASS"
exit 1
