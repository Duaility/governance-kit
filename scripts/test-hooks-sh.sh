#!/usr/bin/env bash
# scripts/test-hooks-sh.sh — direct tests for governance/assets/packs/lib/hooks.sh.
# Covers:
#   - hook_has_marker: marker detection on line 2
#   - collision_check: lists unmarked existing hooks
#   - generate_hooks: emits all 5 dispatchers with the ownership marker
#   - generate_hooks: refuses to clobber an unmarked existing hook
#   - generate_hooks: silently overwrites a marker-bearing hook
#   - generated dispatchers honor SKIP_GOVERNANCE=1 (smoke + bash -n parse)
#   - generated dispatchers route check.sh and hooks/<kind>.sh by directive.yaml `hook:`

set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOKS_LIB="$ROOT/governance/assets/packs/lib/hooks.sh"

# shellcheck disable=SC1090
source "$HOOKS_LIB"

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
        printf '  not ok - %s\n      missing substring: %q\n' "$1" "$2"
        FAIL=$((FAIL + 1))
    fi
}

assert_file_exists() {
    if [[ -e "$2" ]]; then
        printf '  ok - %s\n' "$1"; PASS=$((PASS + 1))
    else
        printf '  not ok - %s\n      missing path: %s\n' "$1" "$2"
        FAIL=$((FAIL + 1))
    fi
}

assert_executable() {
    if [[ -x "$2" ]]; then
        printf '  ok - %s\n' "$1"; PASS=$((PASS + 1))
    else
        printf '  not ok - %s\n      not executable: %s\n' "$1" "$2"
        FAIL=$((FAIL + 1))
    fi
}

assert_zero() {
    if "$@" >/dev/null 2>&1; then
        printf '  ok - exit-zero: %s\n' "$*"; PASS=$((PASS + 1))
    else
        printf '  not ok - expected zero exit: %s\n' "$*"
        FAIL=$((FAIL + 1))
    fi
}

# ---- hook_has_marker -------------------------------------------------------

printf '── hook_has_marker ─────────────────────────────────────\n'

unmarked="$WORK/unmarked"
cat > "$unmarked" <<'EOF'
#!/usr/bin/env bash
echo no-marker
EOF
if ! hook_has_marker "$unmarked"; then
    PASS=$((PASS + 1)); printf '  ok - file without governance-kit:managed line is unmarked\n'
else
    FAIL=$((FAIL + 1)); printf '  not ok - unmarked file misclassified as marked\n'
fi

marked="$WORK/marked"
cat > "$marked" <<'EOF'
#!/usr/bin/env bash
# governance-kit:managed kit-version=test generated=2026-04-29
echo marked
EOF
if hook_has_marker "$marked"; then
    PASS=$((PASS + 1)); printf '  ok - file with marker on line 2 is detected\n'
else
    FAIL=$((FAIL + 1)); printf '  not ok - marked file should be detected\n'
fi

if ! hook_has_marker "$WORK/no-such-file"; then
    PASS=$((PASS + 1)); printf '  ok - missing file is treated as unmarked\n'
else
    FAIL=$((FAIL + 1)); printf '  not ok - missing file should be unmarked\n'
fi

# Marker on line 3 (not line 2) → unmarked.
wrong_line="$WORK/wrong-line"
cat > "$wrong_line" <<'EOF'
#!/usr/bin/env bash
# some other comment
# governance-kit:managed kit-version=test generated=2026-04-29
EOF
if ! hook_has_marker "$wrong_line"; then
    PASS=$((PASS + 1)); printf '  ok - marker only counts when on line 2\n'
else
    FAIL=$((FAIL + 1)); printf '  not ok - marker on non-line-2 should not count\n'
fi

# ---- collision_check -------------------------------------------------------

printf '── collision_check ─────────────────────────────────────\n'
hook_dir="$WORK/hooks"
mkdir -p "$hook_dir"
# Pre-existing unmanaged pre-commit, no commit-msg, marker-bearing pre-push.
cat > "$hook_dir/pre-commit" <<'EOF'
#!/usr/bin/env bash
echo user-owned
EOF
chmod +x "$hook_dir/pre-commit"
cat > "$hook_dir/pre-push" <<'EOF'
#!/usr/bin/env bash
# governance-kit:managed kit-version=test generated=2026-04-29
echo ours
EOF
chmod +x "$hook_dir/pre-push"

collisions=$(collision_check "$hook_dir" pre-commit commit-msg pre-push)
assert_contains "lists unmarked pre-commit"   "pre-commit" "$collisions"
if [[ "$collisions" != *"commit-msg"* ]]; then
    PASS=$((PASS + 1)); printf '  ok - missing hook is not a collision\n'
else
    FAIL=$((FAIL + 1)); printf '  not ok - missing hook should not appear\n'
fi
if [[ "$collisions" != *"pre-push"* ]]; then
    PASS=$((PASS + 1)); printf '  ok - marker-bearing hook is not a collision\n'
else
    FAIL=$((FAIL + 1)); printf '  not ok - marker-bearing hook should not collide\n'
fi

# ---- generate_hooks: full dispatcher emission ------------------------------

printf '── generate_hooks: emits all five dispatchers ──────────\n'

target_hooks="$WORK/githooks"
mkdir -p "$target_hooks"
spec="$WORK/spec.tsv"
# Non-trivial spec: one directive per hook kind, plus a "none" directive.
{
    printf 'demo-pre\tpre-commit\trepo-state\t%s/dirs/demo-pre\n' "$WORK"
    printf 'demo-msg\tcommit-msg\tchange-set\t%s/dirs/demo-msg\n' "$WORK"
    printf 'demo-prep\tprepare-commit-msg\trepo-state\t%s/dirs/demo-prep\n' "$WORK"
    printf 'demo-post\tpost-commit\trepo-state\t%s/dirs/demo-post\n' "$WORK"
    printf 'demo-push\tpre-push\trepo-state\t%s/dirs/demo-push\n' "$WORK"
} > "$spec"

# Build directive folders so the helper-detection logic in _helper_ids_for_hook
# has something to find. Half ship a hooks/<kind>.sh helper.
for entry in demo-pre:pre-commit demo-msg:commit-msg demo-prep:prepare-commit-msg demo-post:post-commit demo-push:pre-push; do
    name="${entry%%:*}"
    kind="${entry#*:}"
    mkdir -p "$WORK/dirs/$name/hooks"
    cat > "$WORK/dirs/$name/directive.yaml" <<YAML
hook: $kind
surface: repo-state
YAML
    cat > "$WORK/dirs/$name/check.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$WORK/dirs/$name/check.sh"
    cat > "$WORK/dirs/$name/hooks/$kind.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$WORK/dirs/$name/hooks/$kind.sh"
done

generate_hooks "$target_hooks" "test-version" "$spec"

for kind in pre-commit commit-msg prepare-commit-msg post-commit pre-push; do
    assert_file_exists "emits $kind dispatcher" "$target_hooks/$kind"
    assert_executable  "$kind dispatcher is executable" "$target_hooks/$kind"
    line2="$(sed -n '2p' "$target_hooks/$kind")"
    assert_contains "$kind line-2 marker" '# governance-kit:managed' "$line2"
    assert_contains "$kind marker carries kit-version" 'kit-version=test-version' "$line2"
    # bash -n parse check
    if bash -n "$target_hooks/$kind"; then
        PASS=$((PASS + 1)); printf '  ok - %s parses with bash -n\n' "$kind"
    else
        FAIL=$((FAIL + 1)); printf '  not ok - %s fails bash -n\n' "$kind"
    fi
done

# ---- SKIP_GOVERNANCE=1 silences each dispatcher ----------------------------

printf '── SKIP_GOVERNANCE=1 honored ───────────────────────────\n'
# pre-commit / pre-push need a git rev-parse — exercise inside a fake repo.
fake_repo="$WORK/fake-repo"
mkdir -p "$fake_repo"
git -C "$fake_repo" init -q
mkdir -p "$fake_repo/.governance"
cp "$target_hooks/pre-commit" "$fake_repo/.governance/run-pre-commit.sh"

if (cd "$fake_repo" && SKIP_GOVERNANCE=1 bash "$target_hooks/pre-commit") >/dev/null 2>&1; then
    PASS=$((PASS + 1)); printf '  ok - pre-commit honors SKIP_GOVERNANCE=1\n'
else
    FAIL=$((FAIL + 1)); printf '  not ok - pre-commit should exit 0 under SKIP_GOVERNANCE=1\n'
fi

if (cd "$fake_repo" && SKIP_GOVERNANCE=1 bash "$target_hooks/commit-msg" /dev/null) >/dev/null 2>&1; then
    PASS=$((PASS + 1)); printf '  ok - commit-msg honors SKIP_GOVERNANCE=1\n'
else
    FAIL=$((FAIL + 1)); printf '  not ok - commit-msg should exit 0 under SKIP_GOVERNANCE=1\n'
fi

if (cd "$fake_repo" && SKIP_GOVERNANCE=1 bash "$target_hooks/post-commit") >/dev/null 2>&1; then
    PASS=$((PASS + 1)); printf '  ok - post-commit honors SKIP_GOVERNANCE=1\n'
else
    FAIL=$((FAIL + 1)); printf '  not ok - post-commit should exit 0 under SKIP_GOVERNANCE=1\n'
fi

# pre-push reads a refs file from stdin; piping nothing is fine under SKIP.
if (cd "$fake_repo" && SKIP_GOVERNANCE=1 bash "$target_hooks/pre-push" origin https://example.com </dev/null) >/dev/null 2>&1; then
    PASS=$((PASS + 1)); printf '  ok - pre-push honors SKIP_GOVERNANCE=1\n'
else
    FAIL=$((FAIL + 1)); printf '  not ok - pre-push should exit 0 under SKIP_GOVERNANCE=1\n'
fi

# ---- regenerate-on-marker, refuse-on-unmarked ------------------------------

printf '── overwrite policy ────────────────────────────────────\n'
clean_target="$WORK/regen"
mkdir -p "$clean_target"
generate_hooks "$clean_target" "v1" "$spec"
# Now overwrite — should succeed silently because we wrote them last.
generate_hooks "$clean_target" "v2" "$spec"
line2_v2="$(sed -n '2p' "$clean_target/pre-commit")"
assert_contains "regeneration updates the kit-version" "kit-version=v2" "$line2_v2"

unmarked_target="$WORK/unmarked-target"
mkdir -p "$unmarked_target"
cat > "$unmarked_target/pre-commit" <<'EOF'
#!/usr/bin/env bash
echo "user owned hook"
EOF
chmod +x "$unmarked_target/pre-commit"

# generate_hooks is `set -eu`; running under `if ...` to capture the failure
# mode without aborting this test runner.
if ! generate_hooks "$unmarked_target" "v3" "$spec" 2>/dev/null; then
    PASS=$((PASS + 1))
    printf '  ok - generate_hooks refuses to clobber unmarked hook\n'
else
    FAIL=$((FAIL + 1))
    printf '  not ok - generate_hooks should refuse to overwrite unmarked hook\n'
fi
# The user's content survived the abort.
preserved_text="$(cat "$unmarked_target/pre-commit")"
assert_contains "user content preserved" 'user owned hook' "$preserved_text"

# ---- spec routing: check.sh path appears in dispatcher --------------------

printf '── routing: dispatchers wire hook + check.sh ───────────\n'
# Each dispatcher should source its own discovery helper and reference the
# directive folder shape we built. That body is shipped via _emit_runtime_discovery_helpers,
# so check the dispatcher contains the marker text.
pre_commit_text="$(cat "$target_hooks/pre-commit")"
assert_contains "pre-commit defines directive_dirs_for_hook helper" 'directive_dirs_for_hook()' "$pre_commit_text"
assert_contains "pre-commit invokes check helper for pre-commit kind" 'directive_dirs_for_hook pre-commit check' "$pre_commit_text"
assert_contains "pre-commit invokes hook helper for pre-commit kind" 'directive_dirs_for_hook pre-commit helper' "$pre_commit_text"

commit_msg_text="$(cat "$target_hooks/commit-msg")"
assert_contains "commit-msg passes \$MSG_FILE to check.sh" '"$dir/check.sh" "$MSG_FILE"' "$commit_msg_text"

post_commit_text="$(cat "$target_hooks/post-commit")"
assert_contains "post-commit prints agent-readable failure banner" 'POST-COMMIT GOVERNANCE FAILED' "$post_commit_text"
assert_contains "post-commit always exits 0 (git ignores its exit anyway)" 'exit 0' "$post_commit_text"

pre_push_text="$(cat "$target_hooks/pre-push")"
assert_contains "pre-push slurps refs from stdin into a tempfile" 'cat > "$REFS_FILE"' "$pre_push_text"
assert_contains "pre-push replays refs to each check.sh" '< "$REFS_FILE"' "$pre_push_text"

# ---- generate_hooks_for_strategy: per-strategy install dir ----------------

printf '── generate_hooks_for_strategy: per-strategy install dir ───\n'

# Each strategy materializes the SAME dispatcher body — so populator wiring
# (`hooks/<kind>.sh` discovery + `hook:` filter on check.sh) is uniform across
# install paths. That parity is the whole point of the strategy wrapper:
# a husky or pre-commit.com repo cannot silently drop populators and pretend
# the validator-only chain is sufficient.
strategy_repo="$WORK/strategy-repo"
mkdir -p "$strategy_repo"

# githooks → .githooks/
generate_hooks_for_strategy "$strategy_repo" githooks "v-strat" "$spec"
for kind in pre-commit commit-msg prepare-commit-msg post-commit pre-push; do
    assert_file_exists "githooks strategy emits $kind"      "$strategy_repo/.githooks/$kind"
    assert_executable  "githooks strategy $kind executable" "$strategy_repo/.githooks/$kind"
done

# husky → .husky/ (the install dir husky itself manages via core.hooksPath)
generate_hooks_for_strategy "$strategy_repo" husky "v-strat" "$spec"
for kind in pre-commit commit-msg prepare-commit-msg post-commit pre-push; do
    assert_file_exists "husky strategy emits $kind"      "$strategy_repo/.husky/$kind"
    assert_executable  "husky strategy $kind executable" "$strategy_repo/.husky/$kind"
    line2_husky="$(sed -n '2p' "$strategy_repo/.husky/$kind")"
    assert_contains "husky $kind carries marker" '# governance-kit:managed' "$line2_husky"
done

# Populator wiring is identical in husky as in githooks — this is the
# regression issue #101 was opened for: husky used to land only check.sh
# wiring, never the directive-owned hooks/<kind>.sh populator. Assert the
# generated dispatcher invokes the helper-discovery loop.
husky_pre_commit="$(cat "$strategy_repo/.husky/pre-commit")"
assert_contains "husky pre-commit invokes populator helper loop" \
    'directive_dirs_for_hook pre-commit helper' "$husky_pre_commit"
husky_prepare="$(cat "$strategy_repo/.husky/prepare-commit-msg")"
assert_contains "husky prepare-commit-msg invokes populator helper loop" \
    'directive_dirs_for_hook prepare-commit-msg helper' "$husky_prepare"

# pre-commit → .governance/hooks/ (framework entries shell out to these)
generate_hooks_for_strategy "$strategy_repo" pre-commit "v-strat" "$spec"
for kind in pre-commit commit-msg prepare-commit-msg post-commit pre-push; do
    assert_file_exists "pre-commit strategy emits $kind under .governance/hooks/" \
        "$strategy_repo/.governance/hooks/$kind"
done

# Unknown strategy is rejected loudly.
if generate_hooks_for_strategy "$strategy_repo" no-such-thing "v" "$spec" 2>/dev/null; then
    FAIL=$((FAIL + 1)); printf '  not ok - unknown strategy should fail\n'
else
    PASS=$((PASS + 1)); printf '  ok - unknown strategy is rejected\n'
fi

# Re-running the same strategy regenerates silently (marker-bearing overwrite).
generate_hooks_for_strategy "$strategy_repo" husky "v-regen" "$spec"
line2_regen="$(sed -n '2p' "$strategy_repo/.husky/pre-commit")"
assert_contains "husky regen bumps kit-version" "kit-version=v-regen" "$line2_regen"

# An unmarked pre-existing husky hook is preserved (collision detector wins).
husky_collide_repo="$WORK/strategy-collide"
mkdir -p "$husky_collide_repo/.husky"
cat > "$husky_collide_repo/.husky/pre-commit" <<'EOF'
#!/usr/bin/env bash
echo "user-husky-hook"
EOF
chmod +x "$husky_collide_repo/.husky/pre-commit"
if ! generate_hooks_for_strategy "$husky_collide_repo" husky "v" "$spec" 2>/dev/null; then
    PASS=$((PASS + 1)); printf '  ok - husky strategy refuses to clobber unmarked hook\n'
else
    FAIL=$((FAIL + 1)); printf '  not ok - husky strategy should refuse unmarked clobber\n'
fi
preserved_husky="$(cat "$husky_collide_repo/.husky/pre-commit")"
assert_contains "husky user content preserved on collision" \
    'user-husky-hook' "$preserved_husky"

# ---- summary --------------------------------------------------------------

printf '\n────────────────────────────────────────\n'
if [[ $FAIL -eq 0 ]]; then
    printf '✓ test-hooks-sh: %d assertion(s) passed\n' "$PASS"
    exit 0
fi
printf '✗ test-hooks-sh: %d failed, %d passed\n' "$FAIL" "$PASS"
exit 1
