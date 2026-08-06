#!/usr/bin/env bash
# Focused contract tests for semantics-only judge declarations and config-owned
# attestation execution. The deeper verdict grammar remains exercised through
# the public judge_attest path below.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB_SH="$ROOT/kit/assets/dot-governance/lib.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PASS=0 FAIL=0

ok() { printf '  ✓ %s\n' "$1"; PASS=$((PASS + 1)); }
nope() { printf '  ✗ %s\n' "$1"; FAIL=$((FAIL + 1)); }
assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then ok "$label"
    else nope "$label (expected '$expected', got '$actual')"; fi
}
assert_contains() {
    local label="$1" needle="$2" haystack="$3"
    if [[ "$haystack" == *"$needle"* ]]; then ok "$label"
    else nope "$label (missing '$needle')"; fi
}
lib() { bash -c "set +u; source '$LIB_SH'; $1"; }

repo="$WORK/repo"
dir="$repo/.governance/packs/acme/audit/directives/gated"
mkdir -p "$dir" "$repo/receipts"
git -C "$repo" init -q
git -C "$repo" config user.email test@example.com
git -C "$repo" config user.name Test

cat > "$dir/directive.yaml" <<'EOF'
category: AgentDiscipline
recommended: true
summary: test gate
surface: change-set
hook: pre-commit
triggers: [pre-commit, schedule]
config:
  - name: ATTEST_SECTION
    type: scalar
    doc: Receipt section populated by the attestation lane.
    default: Audit
    tunable: false
  - name: ATTEST_CMD
    type: scalar
    doc: Command used by the live attestation lane.
    default: harness
    tunable: false
  - name: SCHEDULE_CMD
    type: scalar
    doc: Command used by the scheduled lane.
    default: claude -p --model opus
    tunable: false
  - name: JUDGE_ROUNDS
    type: scalar
    doc: Maximum verdict remediation rounds.
    default: 5
    tunable: true
judge:
  inputs: [diff, receipt, issue]
  checks:
    - the receipt describes the diff
    - no unstated scope creep
  gate: record
EOF
cat > "$dir/check.sh" <<EOF
#!/usr/bin/env bash
set -u
source "$LIB_SH"
directive_start gated
judge_attest "\$1"
directive_end
EOF
chmod +x "$dir/check.sh"

printf '── semantics-only declaration reader ──────────────────\n'
assert_eq "inputs are read from judge" "diff receipt issue " \
    "$(lib "_judge_yaml '$dir/directive.yaml' inputs" | tr '\n' ' ')"
assert_eq "checks are read from judge" "2" \
    "$(lib "_judge_yaml '$dir/directive.yaml' checks" | wc -l | tr -d ' ')"
assert_eq "gate is read from judge" "record" \
    "$(lib "_judge_yaml '$dir/directive.yaml' gate")"
assert_eq "lane section is absent from judge" "" \
    "$(lib "_judge_yaml '$dir/directive.yaml' section")"
assert_eq "lane command is absent from judge" "" \
    "$(lib "_judge_yaml '$dir/directive.yaml' cmd")"

printf '── execution config resolution ─────────────────────────\n'
assert_eq "attest command comes from config" "harness" \
    "$(cd "$repo" && lib "_judge_cmd_resolve '$dir/directive.yaml' attest")"
assert_eq "schedule command comes from config" "claude -p --model opus" \
    "$(cd "$repo" && lib "_judge_cmd_resolve '$dir/directive.yaml' schedule")"
assert_eq "round ceiling comes from config" "5" \
    "$(cd "$repo" && lib "_judge_rounds_resolve gated '$dir/directive.yaml'")"

mkdir -p "$repo/.governance/conf/acme/audit"
cat > "$repo/.governance/conf/acme/audit/gated.conf" <<'EOF'
SCHEDULE_CMD=codex exec
JUDGE_ROUNDS=2
ATTEST_SECTION=Steering
EOF
cp "$repo/.governance/conf/acme/audit/gated.conf" "$repo/.governance/conf/gated.conf"
assert_eq "fixed schedule command ignores overlay" "claude -p --model opus" \
    "$(cd "$repo" && lib "_judge_cmd_resolve '$dir/directive.yaml' schedule")"
assert_eq "tunable rounds accept overlay" "2" \
    "$(cd "$repo" && lib "_judge_rounds_resolve gated '$dir/directive.yaml'")"
assert_eq "fixed section ignores overlay" "Audit" \
    "$(cd "$repo" && lib "conf_get gated ATTEST_SECTION '$dir/directive.yaml'")"
assert_eq "environment is not a config tier" "2" \
    "$(cd "$repo" && GOVERNANCE_JUDGE_ROUNDS=9 lib "_judge_rounds_resolve gated '$dir/directive.yaml'")"

printf '── public attestation path ──────────────────────────────\n'
receipt="$repo/receipts/issue-366-test.md"
ledger="$WORK/ledger.tsv"
printf '# Receipt\n\n## What changed\n\nImplemented the change.\n' > "$receipt"
: > "$ledger"
set +e
output="$(cd "$repo" && GOVERNANCE_ATTEST_LEDGER="$ledger" bash "$dir/check.sh" "$receipt" 2>&1)"
rc=$?
set -e
assert_eq "missing configured section blocks" "1" "$rc"
assert_contains "failure names configured section" "## Audit" "$output"
assert_eq "ledger records the attest lane" "attest" "$(cut -f1 "$ledger")"
remediation="$(lib "attestation_remediation '$ledger'" 2>&1)"
assert_contains "remediation requests a fresh-context sub-agent" "fresh-context sub-agent" "$remediation"

printf '\n## Audit\n\n- PASS — matches.\n' >> "$receipt"
: > "$ledger"
set +e
output="$(cd "$repo" && GOVERNANCE_ATTEST_LEDGER="$ledger" bash "$dir/check.sh" "$receipt" 2>&1)"
rc=$?
set -e
assert_eq "well-formed record passes" "0" "$rc"
assert_eq "passing gate registers nothing" "" "$(cat "$ledger")"

printf '\n────────────────────────────────────────\n'
if [[ "$FAIL" -eq 0 ]]; then
    printf '✓ test-subagent: %d assertion(s) passed\n' "$PASS"
    exit 0
fi
printf '✗ test-subagent: %d failed, %d passed\n' "$FAIL" "$PASS" >&2
exit 1
