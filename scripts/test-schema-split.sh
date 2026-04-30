#!/usr/bin/env bash
# scripts/test-schema-split.sh — end-to-end contract for the install.yaml +
# packs.lock split.
#
# Asserts the cross-file invariants no single-component test can prove on its own:
#   - install.yaml v3 carries init choices but NO packs[] block (the block moved
#     to packs.lock).
#   - packs.lock v2 records every source — builtin (governance-kit/core), gh
#     (community), local (repo-local) — alongside each pack's version + directive
#     list.
#   - lock-list --long prints the right columns for each source.
#   - lock-remove takes a pack out without disturbing the others.
#
# Run via scripts/test.sh; standalone invocation also works.

set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PV="$ROOT/governance/assets/packs/lib/packverb.py"
INSTALL_LIB="$ROOT/governance/assets/packs/lib/install.sh"
PACKS_LIB="$ROOT/governance/assets/packs/lib/packs.sh"

# shellcheck disable=SC1090
source "$PACKS_LIB"
# shellcheck disable=SC1090
source "$INSTALL_LIB"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0

assert() {
    local label="$1"; shift
    if "$@" >/dev/null 2>&1; then
        PASS=$((PASS + 1)); printf '  ok - %s\n' "$label"
    else
        FAIL=$((FAIL + 1)); printf '  not ok - %s\n' "$label"
    fi
}

assert_grep() {
    local label="$1" pattern="$2" file="$3"
    if grep -qE "$pattern" "$file" 2>/dev/null; then
        PASS=$((PASS + 1)); printf '  ok - %s\n' "$label"
    else
        FAIL=$((FAIL + 1)); printf '  not ok - %s (pattern: %s)\n' "$label" "$pattern"
    fi
}

assert_no_grep() {
    local label="$1" pattern="$2" file="$3"
    if ! grep -qE "$pattern" "$file" 2>/dev/null; then
        PASS=$((PASS + 1)); printf '  ok - %s\n' "$label"
    else
        FAIL=$((FAIL + 1)); printf '  not ok - %s (pattern present: %s)\n' "$label" "$pattern"
    fi
}

pv() {
    uv run --quiet --isolated --with PyYAML python "$PV" "$@"
}

target="$WORK/repo"
mkdir -p "$target/.governance"

printf '── install.yaml: writer emits v3 with no packs[] block ──\n'

write_installed_manifest "$target" \
    --owner acme --repo widgets \
    --hook-strategy githooks \
    --agents-md-directive \
    --install-asset QUALITY.md

install_yaml="$target/.governance/install.yaml"
assert "install.yaml created" test -f "$install_yaml"
assert_grep "install.yaml emits version: \"3\"" '^version: "3"$' "$install_yaml"
assert_grep "install.yaml carries owner" '^owner: acme$' "$install_yaml"
assert_grep "install.yaml carries hook_strategy" '^hook_strategy: githooks$' "$install_yaml"
assert_grep "install.yaml carries install_assets_seeded" '^install_assets_seeded:' "$install_yaml"
assert_no_grep "install.yaml has no packs: block (moved to packs.lock)" '^packs:' "$install_yaml"
assert_grep "install.yaml has empty collisions: []" '^collisions: \[\]$' "$install_yaml"

printf '\n── packs.lock: writer records builtin + gh + local sources ──\n'

lock="$target/.governance/packs.lock"

# 1) builtin (governance-kit/core)
pv lock-add "$lock" governance-kit/core --source builtin --version 0.2 \
    --directive required-docs --directive secrets-hygiene >/dev/null

# 2) gh (community pack with full pin)
SHA="0123456789abcdef0123456789abcdef01234567"
pv lock-add "$lock" acme/soc2 --source gh --version 0.3 \
    --ref "gh:acme/soc2@main" --sha "$SHA" --min-kit "0.2" \
    --directive soc2-audit-logs --directive soc2-retention >/dev/null

# 3) local (repo-local pack — no upstream pin)
pv lock-add "$lock" acme/widgets --source local --version 0.1 \
    --directive no-relative-imports >/dev/null

assert "packs.lock created" test -f "$lock"
assert_grep "packs.lock emits version: '2'" "^version: '2'$" "$lock"

# Each source kind appears.
assert_grep "lockfile carries governance-kit/core" "id: governance-kit/core" "$lock"
assert_grep "lockfile carries acme/soc2" "id: acme/soc2" "$lock"
assert_grep "lockfile carries acme/widgets" "id: acme/widgets" "$lock"

# Source-specific fields.
assert_grep "gh entry carries ref" "ref: gh:acme/soc2@main" "$lock"
assert_grep "gh entry carries sha" "sha: $SHA" "$lock"
assert_grep "gh entry carries installed_at" "installed_at: " "$lock"

# builtin/local must NOT have ref/sha/installed_at (no upstream pin).
core_block="$(awk '/^- id: governance-kit\/core$/,/^- id: |^[a-z]/' "$lock" | sed -n '/^- id: governance-kit\/core/,/^- id: /p' | sed '$d')"
[[ -n "$core_block" ]] || core_block="$(awk '/^- id: governance-kit\/core$/{flag=1} flag{print} /^- id: [a-z0-9]/{if (NR>1 && flag) exit}' "$lock")"

local_block="$(awk '/^- id: acme\/widgets$/{flag=1} flag{print}' "$lock")"

assert "builtin entry has no ref" bash -c "! echo \"\$0\" | grep -q '^  ref:'" "$core_block"
assert "builtin entry has no sha" bash -c "! echo \"\$0\" | grep -q '^  sha:'" "$core_block"
assert "local entry has no ref" bash -c "! echo \"\$0\" | grep -q '^  ref:'" "$local_block"
assert "local entry has no sha" bash -c "! echo \"\$0\" | grep -q '^  sha:'" "$local_block"

printf '\n── lock-list --long: emits id\\tsource\\tversion\\tsha\\tref ──\n'

listing="$(pv lock-list "$lock" --long)"

# Sorted by id: acme/soc2, acme/widgets, governance-kit/core
expected_soc2=$'acme/soc2\tgh\t0.3\t'"$SHA"$'\tgh:acme/soc2@main'
expected_widgets=$'acme/widgets\tlocal\t0.1\t\t'
expected_core=$'governance-kit/core\tbuiltin\t0.2\t\t'

if echo "$listing" | grep -qF "$expected_soc2"; then
    PASS=$((PASS + 1)); printf '  ok - long listing carries gh row with ref+sha\n'
else
    FAIL=$((FAIL + 1)); printf '  not ok - long listing missing gh row\n'
    printf '    listing was:\n%s\n' "$listing"
fi
if echo "$listing" | grep -qF "$expected_widgets"; then
    PASS=$((PASS + 1)); printf '  ok - long listing carries local row with empty sha/ref\n'
else
    FAIL=$((FAIL + 1)); printf '  not ok - long listing missing local row\n'
fi
if echo "$listing" | grep -qF "$expected_core"; then
    PASS=$((PASS + 1)); printf '  ok - long listing carries builtin row with empty sha/ref\n'
else
    FAIL=$((FAIL + 1)); printf '  not ok - long listing missing builtin row\n'
fi

printf '\n── lock-remove: removes one entry, leaves the others intact ──\n'

pv lock-remove "$lock" acme/soc2 >/dev/null
assert_no_grep "soc2 entry gone after remove" "id: acme/soc2" "$lock"
assert_grep "core still present" "id: governance-kit/core" "$lock"
assert_grep "widgets still present" "id: acme/widgets" "$lock"

printf '\n── version-mismatch: load_lockfile rejects v1 lockfile ──\n'

bad_lock="$WORK/legacy.lock"
cat >"$bad_lock" <<'YAML'
version: "1"
packs: []
YAML
if pv lock-read "$bad_lock" 2>/dev/null; then
    FAIL=$((FAIL + 1)); printf '  not ok - load_lockfile must reject v1 lockfile\n'
else
    PASS=$((PASS + 1)); printf '  ok - load_lockfile rejects v1 lockfile (no migration shim)\n'
fi

printf '\n────────────────────────────────────────\n'
if (( FAIL > 0 )); then
    printf '✗ test-schema-split: %d failed, %d passed\n' "$FAIL" "$PASS"
    exit 1
fi
printf '✓ test-schema-split: %d assertion(s) passed\n' "$PASS"
