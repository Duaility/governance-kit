#!/usr/bin/env bash
# End-to-end smoke tests for the manifest-driven scheduled runtime.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PASS=0 FAIL=0
ok() { printf '  ✓ %s\n' "$1"; PASS=$((PASS + 1)); }
nope() { printf '  ✗ %s\n' "$1"; FAIL=$((FAIL + 1)); }
assert_eq() { [[ "$2" == "$3" ]] && ok "$1" || nope "$1 (expected '$2', got '$3')"; }
assert_contains() { [[ "$3" == *"$2"* ]] && ok "$1" || nope "$1 (missing '$2')"; }

repo="$WORK/repo"
mkdir -p "$repo/.governance" "$repo/.governance/packs/acme/audit/directives"
cp "$ROOT/kit/assets/dot-governance/lib.sh" "$repo/.governance/lib.sh"
cp "$ROOT/kit/assets/dot-governance/schedule.sh" "$repo/.governance/schedule.sh"
chmod +x "$repo/.governance/schedule.sh"
git -C "$repo" init -q
git -C "$repo" config user.email test@example.com
git -C "$repo" config user.name Test
printf 'one\n' > "$repo/source.txt"
git -C "$repo" add .
git -C "$repo" commit -qm initial
base="$(git -C "$repo" rev-parse HEAD)"
printf 'two\n' >> "$repo/source.txt"
git -C "$repo" add source.txt
git -C "$repo" commit -qm change
head="$(git -C "$repo" rev-parse HEAD)"

bindir="$WORK/bin"; mkdir -p "$bindir"
cat > "$bindir/judge-pass" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
printf 'VERDICT: PASS\nREASON: no concrete violation\n'
EOF
chmod +x "$bindir/judge-pass"

install_judge() {
    local id="$1" command="$2" evidence="${3:-range}" staleness="${4:-}"
    local dir="$repo/.governance/packs/acme/audit/directives/$id"
    mkdir -p "$dir/evals"
    cat > "$dir/directive.yaml" <<EOF
category: Audit
recommended: true
summary: scheduled audit
surface: repo-state
hook: none
triggers: [schedule]
config:
  - name: SCHEDULE_CMD
    type: scalar
    doc: Command used by the scheduled lane.
    default: $command
    tunable: false
  - name: SCHEDULE_EVIDENCE
    type: scalar
    doc: Evidence mode used by this directive.
    default: $evidence
    tunable: false
EOF
    if [[ -n "$staleness" ]]; then
        cat >> "$dir/directive.yaml" <<EOF
  - name: SCHEDULE_STALENESS_DAYS
    type: scalar
    doc: Advisory maximum age for the judged range.
    default: $staleness
    tunable: false
EOF
    fi
    cat >> "$dir/directive.yaml" <<'EOF'
judge:
  inputs: [range-diff]
  checks:
    - no concrete policy violation exists
  gate: record
EOF
}

printf '── scheduled judge config and explicit eligibility ─────\n'
install_judge discovery judge-pass range
set +e
output="$(cd "$repo" && PATH="$bindir:$PATH" bash .governance/schedule.sh run --lane nightly --range "$base..$head" --no-gh discovery 2>&1)"
rc=$?
set -e
assert_eq "configured schedule judge exits cleanly" "0" "$rc"
assert_contains "run reports per-member evidence" "per-member evidence" "$output"
assert_contains "judge call is counted" "judge call(s)" "$output"
assert_contains "clean judgment is not un-adjudicated" "0 un-adjudicated" "$output"

sed 's/triggers: \[schedule\]/triggers: []/' \
    "$repo/.governance/packs/acme/audit/directives/discovery/directive.yaml" \
    > "$repo/.governance/packs/acme/audit/directives/discovery/directive.tmp"
mv "$repo/.governance/packs/acme/audit/directives/discovery/directive.tmp" \
    "$repo/.governance/packs/acme/audit/directives/discovery/directive.yaml"
mkdir -p "$repo/.governance/conf/acme/audit"
printf 'TRIGGERS=schedule\n' > "$repo/.governance/conf/acme/audit/discovery.conf"
set +e
output="$(cd "$repo" && PATH="$bindir:$PATH" bash .governance/schedule.sh run --lane nightly --range "$base..$head" --no-gh discovery 2>&1)"
rc=$?
set -e
assert_eq "overlay cannot redefine author-owned triggers" "2" "$rc"
assert_contains "eligibility error points to manifest" "directive.yaml" "$output"

printf '── environment cannot supply a judge command ─────\n'
install_judge fallback "" commits
set +e
output="$(cd "$repo" && PATH="$bindir:$PATH" GOVERNANCE_JUDGE_CMD=judge-pass \
    bash .governance/schedule.sh run --lane nightly --range "$base..$head" --no-gh fallback 2>&1)"
rc=$?
set -e
assert_eq "missing fixed command remains an honest non-failure" "0" "$rc"
assert_contains "environment judge command is ignored" "1 un-adjudicated" "$output"
assert_contains "commits evidence is resolved per directive" "per-member evidence" "$output"

printf '── invalid evidence values fail loudly ────────────────\n'
install_judge bad-evidence judge-pass invalid
set +e
output="$(cd "$repo" && PATH="$bindir:$PATH" bash .governance/schedule.sh run --lane nightly --range "$base..$head" --no-gh bad-evidence 2>&1)"
rc=$?
set -e
assert_eq "invalid SCHEDULE_EVIDENCE exits 2" "2" "$rc"
assert_contains "invalid evidence names the accepted values" "expected \`range\` or \`commits\`" "$output"

printf '── staleness advisories remain visible on clean runs ─────\n'
install_judge stale-warning judge-pass range 0
set +e
output="$(cd "$repo" && PATH="$bindir:$PATH" bash .governance/schedule.sh run --lane nightly --range "$base..$head" --no-gh stale-warning 2>&1)"
rc=$?
set -e
assert_eq "stale advisory run exits cleanly" "0" "$rc"
assert_contains "clean run prints stale advisory" "stale members (advisory)" "$output"

printf '── clean runs advance a durable resume marker ──────────\n'
install_judge clean-state judge-pass range
fake_gh="$WORK/fake-gh"
cat > "$fake_gh" <<'EOF'
#!/usr/bin/env bash
set -u
state="${FAKE_GH_STATE:?}"
case "${1:-}" in
    label) exit 0 ;;
    issue)
        case "${2:-}" in
            list)
                if [[ "$*" == *"--json body"* ]] && [[ -f "$state" ]]; then
                    cat "$state"
                elif [[ "$*" == *"--json number,title"* ]] && [[ -f "$state" ]]; then
                    printf '123\n'
                fi
                exit 0
                ;;
            create|edit)
                body_file=""
                while [[ $# -gt 0 ]]; do
                    [[ "$1" == "--body-file" ]] && body_file="${2:-}" && shift
                    shift
                done
                [[ -n "$body_file" && -f "$body_file" ]] && cp "$body_file" "$state"
                printf 'https://example.invalid/issue/123\n'
                exit 0
                ;;
        esac
        ;;
esac
exit 0
EOF
chmod +x "$fake_gh"
ln -s "$fake_gh" "$WORK/gh"
state_file="$WORK/schedule-state"
set +e
output="$(cd "$repo" && PATH="$WORK:$bindir:$PATH" FAKE_GH_STATE="$state_file" bash .governance/schedule.sh run --lane clean --range "$base..$head" clean-state 2>&1)"
rc=$?
set -e
assert_eq "first clean run exits cleanly" "0" "$rc"
assert_contains "first clean run still reports no findings" "no new findings" "$output"
assert_contains "first clean run writes state marker" "governance-schedule-state:clean:end=" "$(cat "$state_file")"
set +e
output="$(cd "$repo" && PATH="$WORK:$bindir:$PATH" FAKE_GH_STATE="$state_file" bash .governance/schedule.sh run --lane clean clean-state 2>&1)"
rc=$?
set -e
assert_eq "second clean run exits cleanly" "0" "$rc"
assert_contains "second clean run still has no findings" "no new findings" "$output"

printf '── mechanical facts still fail the lane ────────────────\n'
mech="$repo/.governance/packs/acme/audit/directives/mechanical"
mkdir -p "$mech"
cat > "$mech/directive.yaml" <<'EOF'
category: Audit
recommended: true
summary: mechanical failure
surface: repo-state
hook: none
triggers: [schedule]
EOF
cat > "$mech/check.sh" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$mech/check.sh"
set +e
output="$(cd "$repo" && bash .governance/schedule.sh run --lane nightly --range "$base..$head" --no-gh mechanical 2>&1)"
rc=$?
set -e
assert_eq "mechanical failure makes the lane fail" "1" "$rc"
assert_contains "summary names the mechanical failure" "mechanical" "$output"

printf '\n────────────────────────────────────────\n'
if [[ "$FAIL" -eq 0 ]]; then
    printf '✓ test-schedule: %d assertion(s) passed\n' "$PASS"
    exit 0
fi
printf '✗ test-schedule: %d failed, %d passed\n' "$FAIL" "$PASS" >&2
exit 1
