#!/usr/bin/env bash
# scripts/test-install-sh.sh — direct tests for the bash helpers in
# governance/assets/packs/lib/install.sh. The "fresh repo install contract"
# block in test-packs.sh exercises the standard happy path; this file covers
# the matrix that block doesn't:
#   - copy_tree_without_evals excludes evals/ + install-assets/
#   - install_directive_folder writes to .governance/packs/<pack>/directives/<id>
#   - install_directive_assets respects augment vs overwrite mode
#   - directive_supports_hook_strategy passes/fails per requires_hook_strategy
#   - write_installed_manifest emits every flag-driven branch
#       (collisions, path_b, install_assets_seeded, agents_md_*, no-constitution,
#        setup-clone-script, multi-pack grouping, empty packs)

set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL_LIB="$ROOT/governance/assets/packs/lib/install.sh"
PACKS_LIB="$ROOT/governance/assets/packs/lib/packs.sh"

# shellcheck disable=SC1090
source "$PACKS_LIB"
# shellcheck disable=SC1090
source "$INSTALL_LIB"

PASS=0
FAIL=0

assert_eq() {
    local name="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        printf '  ok - %s\n' "$name"
        PASS=$((PASS + 1))
    else
        printf '  not ok - %s\n' "$name"
        printf '      expected: %q\n' "$expected"
        printf '      actual:   %q\n' "$actual"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    local name="$1" needle="$2" haystack="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        printf '  ok - %s\n' "$name"
        PASS=$((PASS + 1))
    else
        printf '  not ok - %s\n' "$name"
        printf '      missing substring: %q\n' "$needle"
        printf '      in:               %q\n' "$haystack"
        FAIL=$((FAIL + 1))
    fi
}

assert_not_contains() {
    local name="$1" needle="$2" haystack="$3"
    if [[ "$haystack" != *"$needle"* ]]; then
        printf '  ok - %s\n' "$name"
        PASS=$((PASS + 1))
    else
        printf '  not ok - %s\n' "$name"
        printf '      unexpected substring: %q\n' "$needle"
        printf '      in:                  %q\n' "$haystack"
        FAIL=$((FAIL + 1))
    fi
}

assert_file_exists() {
    local name="$1" path="$2"
    if [[ -e "$path" ]]; then
        printf '  ok - %s\n' "$name"
        PASS=$((PASS + 1))
    else
        printf '  not ok - %s\n' "$name"
        printf '      missing path: %s\n' "$path"
        FAIL=$((FAIL + 1))
    fi
}

assert_file_absent() {
    local name="$1" path="$2"
    if [[ ! -e "$path" ]]; then
        printf '  ok - %s\n' "$name"
        PASS=$((PASS + 1))
    else
        printf '  not ok - %s\n' "$name"
        printf '      should not exist: %s\n' "$path"
        FAIL=$((FAIL + 1))
    fi
}

# ---- fixture builder -------------------------------------------------------

# Build a minimal pack at <dir> with a single directive that ships:
#   - check.sh, constitution.md, directive.yaml
#   - evals/test.sh (must NOT be installed)
#   - install-assets/<file> (must NOT be installed by install_directive_folder)
#   - hooks/<kind>.sh (must be marked executable)
make_fixture_pack() {
    local pack_dir="$1" pack_id="$2" directive_id="$3"
    local requires_hook_strategy="${4:-}"

    rm -rf "$pack_dir"
    mkdir -p "$pack_dir/directives/$directive_id/evals"
    mkdir -p "$pack_dir/directives/$directive_id/install-assets/seeded"
    mkdir -p "$pack_dir/directives/$directive_id/hooks"

    cat > "$pack_dir/pack.yaml" <<EOF
id: $pack_id
name: Fixture
version: "0.0"
min_governance_kit: "0.1"
description: fixture pack
author: test
presets:
  minimal:
    directives: [$directive_id]
EOF

    cat > "$pack_dir/directives/$directive_id/directive.yaml" <<EOF
category: Foundation
recommended: true
summary: fixture directive
surface: repo-state
hook: pre-commit
${requires_hook_strategy:+requires_hook_strategy: $requires_hook_strategy}
EOF

    cat > "$pack_dir/directives/$directive_id/check.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$pack_dir/directives/$directive_id/check.sh"

    cat > "$pack_dir/directives/$directive_id/constitution.md" <<EOF
ref .governance/packs/$pack_id/directives/$directive_id/check.sh
EOF

    cat > "$pack_dir/directives/$directive_id/evals/test.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$pack_dir/directives/$directive_id/evals/test.sh"

    cat > "$pack_dir/directives/$directive_id/hooks/pre-commit.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    # Note: not chmod +x'd here — install_directive_folder must mark it executable.

    echo "asset-content" > "$pack_dir/directives/$directive_id/install-assets/seeded/seeded-file.md"
}

# ---- copy_tree_without_evals ----------------------------------------------

printf '── copy_tree_without_evals ─────────────────────────────\n'
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

make_fixture_pack "$WORK/fixture-pack" "acme/fixture-pack" "demo"
src="$WORK/fixture-pack/directives/demo"
dest="$WORK/copied"
copy_tree_without_evals "$src" "$dest"

assert_file_exists "copies check.sh"        "$dest/check.sh"
assert_file_exists "copies directive.yaml"  "$dest/directive.yaml"
assert_file_exists "copies constitution.md" "$dest/constitution.md"
assert_file_exists "copies hooks/pre-commit.sh" "$dest/hooks/pre-commit.sh"
assert_file_absent "excludes evals/"        "$dest/evals"
assert_file_absent "excludes install-assets/" "$dest/install-assets"

# Re-running into the same dest should overwrite cleanly (rm -rf in helper).
copy_tree_without_evals "$src" "$dest"
assert_file_exists "copy is re-runnable" "$dest/check.sh"

# ---- install_directive_folder ---------------------------------------------

printf '── install_directive_folder ────────────────────────────\n'
target="$WORK/target1"
mkdir -p "$target"
install_directive_folder "$WORK/fixture-pack" "demo" "$target"

assert_file_exists "writes to packs/<pack>/directives/<id>/check.sh" \
    "$target/.governance/packs/acme/fixture-pack/directives/demo/check.sh"
assert_file_exists "writes hooks/<kind>.sh" \
    "$target/.governance/packs/acme/fixture-pack/directives/demo/hooks/pre-commit.sh"
assert_file_absent "does not copy evals/" \
    "$target/.governance/packs/acme/fixture-pack/directives/demo/evals"
assert_file_absent "does not copy install-assets/" \
    "$target/.governance/packs/acme/fixture-pack/directives/demo/install-assets"

if [[ -x "$target/.governance/packs/acme/fixture-pack/directives/demo/check.sh" ]]; then
    PASS=$((PASS + 1)); printf '  ok - check.sh marked executable\n'
else
    FAIL=$((FAIL + 1)); printf '  not ok - check.sh not executable\n'
fi
if [[ -x "$target/.governance/packs/acme/fixture-pack/directives/demo/hooks/pre-commit.sh" ]]; then
    PASS=$((PASS + 1)); printf '  ok - hooks/pre-commit.sh marked executable\n'
else
    FAIL=$((FAIL + 1)); printf '  not ok - hooks/pre-commit.sh not executable\n'
fi

# ---- install_directive_assets (augment vs overwrite) ----------------------

printf '── install_directive_assets (augment vs overwrite) ─────\n'
target2="$WORK/target2"
mkdir -p "$target2"
install_directive_assets "$WORK/fixture-pack" "demo" "$target2"

assert_file_exists "seeds asset on first install" "$target2/seeded/seeded-file.md"

# Pre-write user content; augment mode must NOT overwrite it.
echo "user-modified-content" > "$target2/seeded/seeded-file.md"
install_directive_assets "$WORK/fixture-pack" "demo" "$target2"
augmented_content="$(cat "$target2/seeded/seeded-file.md")"
assert_eq "augment mode preserves user changes" "user-modified-content" "$augmented_content"

# overwrite mode replaces user content.
install_directive_assets "$WORK/fixture-pack" "demo" "$target2" "overwrite"
overwritten_content="$(cat "$target2/seeded/seeded-file.md")"
assert_eq "overwrite mode replaces user changes" "asset-content" "$overwritten_content"

# Pack with no install-assets/ → silent no-op.
mkdir -p "$WORK/empty-pack/directives/quiet"
touch "$WORK/empty-pack/directives/quiet/directive.yaml"
target3="$WORK/target3"
mkdir -p "$target3"
install_directive_assets "$WORK/empty-pack" "quiet" "$target3" || {
    FAIL=$((FAIL + 1))
    printf '  not ok - install_directive_assets returns non-zero on no-op pack\n'
}
PASS=$((PASS + 1))
printf '  ok - install_directive_assets is a silent no-op when install-assets/ is absent\n'

# ---- directive_supports_hook_strategy -------------------------------------

printf '── directive_supports_hook_strategy ────────────────────\n'
make_fixture_pack "$WORK/strict-pack" "strict" "demo" "githooks"
make_fixture_pack "$WORK/loose-pack" "loose" "demo"

if directive_supports_hook_strategy "$WORK/strict-pack" "demo" "githooks"; then
    PASS=$((PASS + 1)); printf '  ok - matching strategy → supported\n'
else
    FAIL=$((FAIL + 1)); printf '  not ok - matching strategy should be supported\n'
fi
if ! directive_supports_hook_strategy "$WORK/strict-pack" "demo" "husky"; then
    PASS=$((PASS + 1)); printf '  ok - mismatched strategy → unsupported\n'
else
    FAIL=$((FAIL + 1)); printf '  not ok - mismatched strategy should be unsupported\n'
fi
if directive_supports_hook_strategy "$WORK/loose-pack" "demo" "husky"; then
    PASS=$((PASS + 1)); printf '  ok - directive without requires_hook_strategy is portable\n'
else
    FAIL=$((FAIL + 1)); printf '  not ok - directive without requirement should be portable\n'
fi

# ---- write_installed_manifest: minimum-flag invocation --------------------
# install.yaml schema v3 — no `packs:` block, that lives in `.governance/packs.lock`.

printf '── write_installed_manifest: minimum invocation ────────\n'
target4="$WORK/target4"
mkdir -p "$target4"
write_installed_manifest "$target4" --owner acme --repo widgets
manifest="$target4/.governance/install.yaml"
assert_file_exists "install.yaml written" "$manifest"
assert_file_absent_helper() {
    local label="$1" path="$2"
    if [[ ! -e "$path" ]]; then
        PASS=$((PASS + 1)); printf '  ok - %s\n' "$label"
    else
        FAIL=$((FAIL + 1)); printf '  not ok - %s (path exists: %s)\n' "$label" "$path"
    fi
}
assert_file_absent_helper "old installed-packs.yaml not emitted" "$target4/.governance/installed-packs.yaml"

manifest_text="$(cat "$manifest")"
assert_contains "version: \"3\"" 'version: "3"' "$manifest_text"
assert_contains "emits owner" 'owner: acme' "$manifest_text"
assert_contains "emits repo" 'repo: widgets' "$manifest_text"
# Stack field must NOT be emitted (it was removed earlier).
assert_not_contains "no stack: line" "stack:" "$manifest_text"
# packs[] block moved to packs.lock — must not appear here.
assert_not_contains "no packs: block" "packs:" "$manifest_text"
assert_contains "default hook_strategy is githooks" 'hook_strategy: githooks' "$manifest_text"
assert_contains "constitution: true by default" 'constitution: true' "$manifest_text"
assert_contains "agents_md_directive: false by default" 'agents_md_directive: false' "$manifest_text"
assert_contains "agents_md_created: false by default" 'agents_md_created: false' "$manifest_text"
assert_contains "tests_dir defaults to .governance" 'tests_dir: .governance' "$manifest_text"
assert_contains "empty install_assets_seeded list" 'install_assets_seeded: []' "$manifest_text"
assert_contains "empty collisions list" 'collisions: []' "$manifest_text"
assert_not_contains "no path_b block when not requested" 'path_b:' "$manifest_text"
assert_not_contains "no setup_clone_script when not requested" 'setup_clone_script:' "$manifest_text"
assert_not_contains "no kit_version when not requested" 'kit_version:' "$manifest_text"

# ---- write_installed_manifest: every optional flag ------------------------

printf '── write_installed_manifest: full flag matrix ──────────\n'
target5="$WORK/target5"
mkdir -p "$target5"
write_installed_manifest "$target5" \
    --owner acme --repo widgets \
    --kit-version 0.2 \
    --hook-strategy husky \
    --ci-workflow .github/workflows/custom.yml \
    --tests-dir custom-governance \
    --no-constitution \
    --agents-md-directive \
    --agents-md-created \
    --install-asset QUALITY.md \
    --install-asset COSTS.md \
    --setup-clone-script scripts/setup.sh \
    --collision .githooks/pre-commit:wrap:.githooks/pre-commit.userhook \
    --collision .githooks/commit-msg:overwrite:.githooks/commit-msg.pre-governance.bak \
    --path-b-framework husky \
    --path-b-entry .husky/pre-commit:bash\ .governance/run.sh

manifest5="$target5/.governance/install.yaml"
manifest5_text="$(cat "$manifest5")"

assert_contains "honors --kit-version" 'kit_version: "0.2"' "$manifest5_text"
assert_contains "honors --hook-strategy" 'hook_strategy: husky' "$manifest5_text"
assert_contains "honors --ci-workflow" 'ci_workflow: .github/workflows/custom.yml' "$manifest5_text"
assert_contains "honors --tests-dir" 'tests_dir: custom-governance' "$manifest5_text"
assert_contains "honors --no-constitution" 'constitution: false' "$manifest5_text"
assert_contains "honors --agents-md-directive" 'agents_md_directive: true' "$manifest5_text"
assert_contains "honors --agents-md-created" 'agents_md_created: true' "$manifest5_text"
assert_contains "honors --setup-clone-script" 'setup_clone_script: scripts/setup.sh' "$manifest5_text"
assert_contains "lists first install asset" '  - QUALITY.md' "$manifest5_text"
assert_contains "lists second install asset" '  - COSTS.md' "$manifest5_text"
assert_contains "renders wrap collision path" 'path: .githooks/pre-commit' "$manifest5_text"
assert_contains "renders wrap collision resolution" 'resolution: wrap' "$manifest5_text"
assert_contains "renders wrap collision extra" 'extra: .githooks/pre-commit.userhook' "$manifest5_text"
assert_contains "renders overwrite collision resolution" 'resolution: overwrite' "$manifest5_text"
assert_contains "renders overwrite backup path" 'extra: .githooks/commit-msg.pre-governance.bak' "$manifest5_text"
assert_contains "renders path_b framework" 'framework: husky' "$manifest5_text"
assert_contains "renders path_b entry file" 'file: .husky/pre-commit' "$manifest5_text"
assert_contains "renders path_b entry fingerprint" 'fingerprint: bash .governance/run.sh' "$manifest5_text"

# ---- write_installed_manifest: rejects positional pack/directive pairs ----
# v3 schema killed the packs[] block — the old `-- <pack_dir> <directive>` tail
# is no longer accepted. Callers wire packs.lock separately via packverb.py.

printf '── write_installed_manifest: rejects positional pairs ──\n'
target6="$WORK/target6"
mkdir -p "$target6"
if write_installed_manifest "$target6" --owner acme --repo widgets -- "$WORK/fixture-pack" demo 2>/dev/null; then
    FAIL=$((FAIL + 1))
    printf '  not ok - positional pack/directive pairs should be rejected\n'
else
    PASS=$((PASS + 1))
    printf '  ok - positional pack/directive pairs rejected\n'
fi

# ---- write_installed_manifest: rejects unknown flag -----------------------

printf '── write_installed_manifest: unknown-flag rejection ────\n'
target8="$WORK/target8"
mkdir -p "$target8"
if write_installed_manifest "$target8" --not-a-real-flag bogus -- 2>/dev/null; then
    FAIL=$((FAIL + 1))
    printf '  not ok - unknown flag should return non-zero\n'
else
    PASS=$((PASS + 1))
    printf '  ok - unknown flag returns non-zero\n'
fi

# ---- stamp_managed_marker / read_marker_kit_version -----------------------

printf '── stamp_managed_marker / read_marker_kit_version ──────\n'

# Shebang script: marker on line 2.
script="$WORK/stamp-script.sh"
cat > "$script" <<'EOF'
#!/usr/bin/env bash
# governance-kit:managed
echo hi
EOF
stamp_managed_marker "$script" "9.9"
line2="$(sed -n '2p' "$script")"
assert_contains "shebang script: marker line 2 carries kit-version=" \
    "kit-version=9.9" "$line2"
assert_contains "shebang script: marker line 2 carries generated=" \
    "generated=" "$line2"
got="$(read_marker_kit_version "$script")"
assert_eq "shebang script: read_marker_kit_version round-trips" "9.9" "$got"

# Re-stamp is idempotent (kit-version updates in place).
stamp_managed_marker "$script" "10.1"
got2="$(read_marker_kit_version "$script")"
assert_eq "re-stamp updates kit-version in place" "10.1" "$got2"

# YAML file: marker on line 1 (no shebang).
yamlfile="$WORK/stamp.yml"
cat > "$yamlfile" <<'EOF'
# governance-kit:managed
name: test
EOF
stamp_managed_marker "$yamlfile" "0.5"
line1="$(sed -n '1p' "$yamlfile")"
assert_contains "YAML file: marker line 1 carries kit-version=" \
    "kit-version=0.5" "$line1"
got="$(read_marker_kit_version "$yamlfile")"
assert_eq "YAML file: read_marker_kit_version round-trips" "0.5" "$got"

# Bare marker (pre-versioning installs): read returns empty + exit 0.
bare="$WORK/bare.sh"
cat > "$bare" <<'EOF'
#!/usr/bin/env bash
# governance-kit:managed
echo bare
EOF
got_bare="$(read_marker_kit_version "$bare")"
assert_eq "bare marker: read_marker_kit_version returns empty" "" "$got_bare"

# No marker at all: read exits non-zero.
nomarker="$WORK/no-marker.sh"
cat > "$nomarker" <<'EOF'
#!/usr/bin/env bash
echo plain
EOF
if read_marker_kit_version "$nomarker" >/dev/null 2>&1; then
    PASS=$((PASS + 1))
    printf '  ok - unmarked file: read returns 0 (caller checks empty stdout)\n'
else
    PASS=$((PASS + 1))
    printf '  ok - unmarked file: read exits non-zero\n'
fi

# stamp on file without marker errors.
if stamp_managed_marker "$nomarker" "0.5" 2>/dev/null; then
    FAIL=$((FAIL + 1))
    printf '  not ok - stamp on unmarked file should fail\n'
else
    PASS=$((PASS + 1))
    printf '  ok - stamp on unmarked file returns non-zero\n'
fi

# stamp on missing file errors.
if stamp_managed_marker "$WORK/no-such-file" "0.5" 2>/dev/null; then
    FAIL=$((FAIL + 1))
    printf '  not ok - stamp on missing file should fail\n'
else
    PASS=$((PASS + 1))
    printf '  ok - stamp on missing file returns non-zero\n'
fi

# Marker past line 3 → unmarked / stamp refuses.
deep="$WORK/deep-marker.sh"
cat > "$deep" <<'EOF'
#!/usr/bin/env bash
# line two
# line three
# governance-kit:managed
echo deep
EOF
if stamp_managed_marker "$deep" "0.5" 2>/dev/null; then
    FAIL=$((FAIL + 1))
    printf '  not ok - stamp should refuse marker past line 3\n'
else
    PASS=$((PASS + 1))
    printf '  ok - stamp refuses marker past line 3\n'
fi

# ---- summary --------------------------------------------------------------

printf '\n────────────────────────────────────────\n'
if [[ $FAIL -eq 0 ]]; then
    printf '✓ test-install-sh: %d assertion(s) passed\n' "$PASS"
    exit 0
fi
printf '✗ test-install-sh: %d failed, %d passed\n' "$FAIL" "$PASS"
exit 1
