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
#     - conf_get enforces manifest defaults/tunability with no env tier;
#       fail-loud on a missing row/file; transitional literal-default compat
#     - conf_rule_lines strips comments/blanks/KEY= and trims the rest
#     - conf_list layers manifest list defaults with the tunable overlay,
#       normalizing whitespace for ! removal
#   session identity is covered by the audit directive's own eval; this suite
#   intentionally contains no harness adapters or private-session readers.

set -eu

# Drop any GIT_* env state inherited from a parent process (e.g. when invoked
# from a pre-commit hook). The require_git tests below escape into temp
# dirs via subshell `cd`, but inherited GIT_DIR / GIT_WORK_TREE keep git
# anchored to the parent repo and the "outside a git repo" assertions flip.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUN_SH="$ROOT/kit/assets/dot-governance/run.sh"
LIB_SH="$ROOT/kit/assets/dot-governance/lib.sh"

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
config:
  - name: ATTEST_SECTION
    type: scalar
    doc: Receipt section populated by the attestation lane.
    default: Audit
    tunable: false
  - name: SCHEDULE_CMD
    type: scalar
    doc: Command used by the scheduled lane.
    default: claude -p --output-format text --model opus
    tunable: false
EOF
cat > "$sa_dir/check.sh" <<EOF
set -u
source "$LIB_SH"
directive_start sa
judge_attest "\$1"
directive_end
EOF

# _judge_yaml parses the declared block (scalars + lists, no PyYAML).
output=$(set +u; source "$LIB_SH"; conf_get sa ATTEST_SECTION "$sa_dir/directive.yaml")
assert_eq "conf_get reads the fixed section" "Audit" "$output"
output=$(set +u; source "$LIB_SH"; _judge_cmd_resolve "$sa_dir/directive.yaml" schedule)
assert_eq "_judge_cmd_resolve reads the schedule command" \
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
assert_eq "judge_attest records the attest lane" "attest" "$(cut -f1 "$sa_ledger")"

# attestation_remediation emits an independent envelope with the numbered checks.
output=$(set +u; source "$LIB_SH"; attestation_remediation "$sa_ledger" 2>&1)
assert_contains "remediation emits an independent envelope" "Spawn a fresh-context sub-agent" "$output"
assert_contains "remediation names the target section" "write the '## Audit' section" "$output"
assert_contains "remediation numbers the first check" "(1) What changed matches the diff" "$output"
assert_contains "remediation numbers the second check" "(2) checklist mirrors the issue" "$output"
assert_contains "remediation unions the resolved inputs" "the diff (\`git diff\`)" "$output"
assert_contains "remediation rejects self-authored sections" "do not self-author these sections" "$output"

# A second record gets its own independent instruction (US-joined inner fields).
printf -- 'attest\t%s\tSteering\t%s\t%s\n' \
    "$WORK/issue-9-x.md" \
    "the issue"$'\x1f'"this receipt" \
    "every event recorded" >> "$sa_ledger"
output=$(set +u; source "$LIB_SH"; attestation_remediation "$sa_ledger" 2>&1)
assert_contains "remediation adds a second independent sub-agent" "Spawn a fresh-context sub-agent" "$output"

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

# The manifest registry is the sole source of defaults and config docs.
cat > "$conf_repo/directive.yaml" <<'EOF'
# a column-zero comment before the registry
config: # inline header comment

# comments and blank lines are legal inside the registry
  - name: FRESHNESS_DAYS
    type: scalar
    doc: Maximum age accepted by the directive.
    default: 90
    tunable: true
  - name: DEF_ONLY
    type: scalar
    doc: Fixed author-owned value.
    default: 55 # fixed value with an inline YAML comment
    tunable: false
  - name: FLOW_VALUES
    type: list
    doc: Flow-style list used to exercise the runtime reader.
    default: [one, "two # literal"]
    tunable: true
  - name: BOOL_VALUE
    type: scalar
    doc: Boolean spelling accepted by YAML.
    default: 1
    tunable: Yes
EOF

# conf_get: a declared tunable overlay wins over the manifest default.
output=$(cd "$conf_repo"; set +u; source "$LIB_SH"; conf_get sample FRESHNESS_DAYS ./directive.yaml)
assert_eq "conf_get tunable overlay beats manifest default" "30" "$output"

# The environment is not a configuration tier.
output=$(cd "$conf_repo"; set +u; source "$LIB_SH"; GOVERNANCE_FRESHNESS_DAYS=7 conf_get sample FRESHNESS_DAYS ./directive.yaml)
assert_eq "conf_get ignores environment values" "30" "$output"

# Fixed entries ignore overlay rows.
cat > "$conf_repo/.governance/conf/sample.conf" <<'EOF'
FRESHNESS_DAYS=30 # inline overlay comment
DEF_ONLY=99
frozen-files receipts/*.md
append-only COSTS.md
NOTAKEY here
EOF
output=$(cd "$conf_repo"; set +u; source "$LIB_SH"; conf_get sample DEF_ONLY ./directive.yaml)
assert_eq "conf_get fixed value ignores overlay and inline YAML comment" "55" "$output"

# The reader normalizes YAML boolean spellings and supports flow-style lists.
printf 'FRESHNESS_DAYS=30\nDEF_ONLY=99\n' > "$conf_repo/.governance/conf/sample.conf"
output=$(cd "$conf_repo"; set +u; source "$LIB_SH"; conf_get sample BOOL_VALUE ./directive.yaml)
assert_eq "conf_get accepts YAML Yes for tunability" "1" "$output"
output=$(cd "$conf_repo"; set +u; source "$LIB_SH"; conf_list sample ./directive.yaml FLOW_VALUES | tr '\n' '|')
assert_eq "conf_list reads flow-style list defaults" "one|two # literal|" "$output"
cat > "$conf_repo/.governance/conf/sample.conf" <<'EOF'
FRESHNESS_DAYS=30
DEF_ONLY=99
frozen-files receipts/*.md
append-only COSTS.md
NOTAKEY here
EOF

# conf_get fail-loud: an undeclared key → non-zero, no stdout
set +e
output=$(cd "$conf_repo"; set +u; source "$LIB_SH"; conf_get sample MISSING ./directive.yaml 2>/dev/null)
exit_code=$?
set -e
assert_eq "conf_get missing row → non-zero" 1 "$exit_code"
assert_eq "conf_get missing row → no stdout" "" "$output"

# conf_get fail-loud: a missing manifest → non-zero
set +e
output=$(cd "$conf_repo"; set +u; source "$LIB_SH"; conf_get sample DEF_ONLY ./nope/directive.yaml 2>/dev/null)
exit_code=$?
set -e
assert_eq "conf_get missing manifest → non-zero" 1 "$exit_code"

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

# ---- lib.sh: conf_list (manifest defaults + tunable overlay) -------------

printf '── lib.sh: conf_list ───────────────────────────────────\n'
list_repo="$WORK/list-repo"
mkdir -p "$list_repo/.governance/conf"
git -C "$list_repo" init -q
cat > "$list_repo/directive.yaml" <<'EOF'
config:
  - name: TYPES
    type: list
    doc: Accepted conventional commit types.
    default:
      - feat
      - fix
      - chore
      - style
    tunable: true
  - name: SCOPES
    type: list
    doc: Accepted conventional commit scopes.
    default:
      - api
      - docs
    tunable: true
EOF

# No overlay → effective list is the defaults verbatim.
output=$(cd "$list_repo"; set +u; source "$LIB_SH"; conf_list cmf ./directive.yaml TYPES | tr '\n' ' ')
assert_eq "conf_list no overlay → defaults" "feat fix chore style " "$output"

# Overlay adds and removes (gitignore-style ! negation).
cat > "$list_repo/.governance/conf/cmf.conf" <<'EOF'
# my overlay
TYPES-=style
TYPES+=wip
SCOPES-=docs
SCOPES+=cli
EOF
output=$(cd "$list_repo"; set +u; source "$LIB_SH"; conf_list cmf ./directive.yaml TYPES | tr '\n' ' ')
assert_eq "conf_list named overlay changes only its key" "feat fix chore wip " "$output"
output=$(cd "$list_repo"; set +u; source "$LIB_SH"; conf_list cmf ./directive.yaml SCOPES | tr '\n' ' ')
assert_eq "conf_list second key is isolated" "api cli " "$output"

# Whitespace-normalized removal: a single-spaced ! line matches a column-aligned
# default, and additions append while preserving default alignment.
cat > "$list_repo/directive.yaml" <<'EOF'
config:
  - name: RULES
    type: list
    doc: Integrity rules evaluated by the directive.
    default:
      - frozen-files receipts/*.md
      - append-only COSTS.md
      - frozen-section QUALITY.md Resolved
    tunable: true
EOF
cat > "$list_repo/.governance/conf/cmf.conf" <<'EOF'
!frozen-section QUALITY.md Resolved
append-only docs/DECISIONS.md
EOF
output=$(cd "$list_repo"; set +u; source "$LIB_SH"; conf_list cmf ./directive.yaml RULES)
expected=$'frozen-files receipts/*.md\nappend-only COSTS.md\nappend-only docs/DECISIONS.md'
assert_eq "conf_list normalizes whitespace for ! removal" "$expected" "$output"

# Removing every default → empty effective list.
cat > "$list_repo/.governance/conf/cmf.conf" <<'EOF'
!frozen-files receipts/*.md
!append-only COSTS.md
!frozen-section QUALITY.md Resolved
EOF
output=$(cd "$list_repo"; set +u; source "$LIB_SH"; conf_list cmf ./directive.yaml RULES)
assert_eq "conf_list can empty the list" "" "$output"

# A keyed item may itself begin with '#'; only a line whose first non-space
# character is '#' is an overlay comment.
cat > "$list_repo/directive.yaml" <<'EOF'
config:
  - name: MARKERS
    type: list
    doc: Suppression markers checked by the directive.
    default:
      - '# noqa'
      - '# type: ignore'
    tunable: true
EOF
cat > "$list_repo/.governance/conf/cmf.conf" <<'EOF'
# an actual comment
MARKERS-=# noqa
EOF
output=$(cd "$list_repo"; set +u; source "$LIB_SH"; conf_list cmf ./directive.yaml MARKERS | tr '\n' '|')
assert_eq "conf_list preserves hash-prefixed keyed values" "# type: ignore|" "$output"

# Session identity is owned by the audit directive and tested in its eval;
# this runtime suite intentionally has no harness adapters or transcript/usage
# readers. The kit runtime only provides generic hook and directive plumbing.

# ---- summary --------------------------------------------------------------

printf '\n────────────────────────────────────────\n'
if [[ $FAIL -eq 0 ]]; then
    printf '✓ test-runtime: %d assertion(s) passed\n' "$PASS"
    exit 0
fi
printf '✗ test-runtime: %d failed, %d passed\n' "$FAIL" "$PASS"
exit 1
