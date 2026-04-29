#!/usr/bin/env bash
# scripts/test.sh — umbrella entrypoint for every test that covers the kit's
# own product code. Wired into both local git hooks (via the kit-tests-pass
# directive in .governance/local/) and the CI workflow.
#
# Layers:
#   1. test-packctl.py     — packctl.py library + CLI (preset, validation)
#   2. test-packverb.py    — packverb.py (refs, capability glob, lockfile, catalog)
#   3. test-install-sh.sh  — install.sh helpers (copy_tree_without_evals,
#                            install_directive_folder, install_directive_assets,
#                            write_installed_manifest flag matrix)
#   4. test-hooks-sh.sh    — hooks.sh dispatcher generation, marker policy,
#                            SKIP_GOVERNANCE handling
#   5. test-runtime.sh     — runtime files shipped to consumer repos
#                            (dot-governance/run.sh + lib.sh)
#   6. test-packs.sh       — pack smoke + hook generation smoke + fresh repo
#                            install contract + pack evals
#
# All layers are non-destructive: each builds its own tmpdirs and tears down.

set -eu

# When invoked from a git hook (or any context where git env vars are exported),
# the pre-commit hook sets GIT_DIR / GIT_INDEX_FILE / GIT_PREFIX / etc. that
# override cwd-based discovery. If we leave those set, every `git -C $tmp init`
# call in the layers below would re-init the host repo's gitdir instead of the
# tmpdir, and write `core.bare = true` to the shared config. Strip them so each
# layer starts from a clean git environment.
for var in $(git rev-parse --local-env-vars 2>/dev/null || true); do
    unset "$var"
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

run_layer() {
    local label="$1"; shift
    printf '\n══ %s ══════════════════════════════════════════\n' "$label"
    if "$@"; then
        return 0
    else
        return 1
    fi
}

failed_layers=()

run_layer "packctl: preset/CLI (Python)" \
    uv run --quiet --isolated --with PyYAML python "$ROOT/scripts/test-packctl.py" \
    || failed_layers+=("test-packctl.py")

run_layer "packctl: validate_pack_dir matrix (Python)" \
    uv run --quiet --isolated --with PyYAML python "$ROOT/scripts/test-packctl-validate.py" \
    || failed_layers+=("test-packctl-validate.py")

run_layer "packverb (Python)" \
    uv run --quiet --isolated --with PyYAML python "$ROOT/scripts/test-packverb.py" \
    || failed_layers+=("test-packverb.py")

run_layer "install.sh helpers (bash)" \
    bash "$ROOT/scripts/test-install-sh.sh" \
    || failed_layers+=("test-install-sh.sh")

run_layer "hooks.sh dispatcher generation (bash)" \
    bash "$ROOT/scripts/test-hooks-sh.sh" \
    || failed_layers+=("test-hooks-sh.sh")

run_layer "shipped runtime: run.sh + lib.sh (bash)" \
    bash "$ROOT/scripts/test-runtime.sh" \
    || failed_layers+=("test-runtime.sh")

run_layer "pack smoke + hook generation + evals (bash)" \
    bash "$ROOT/scripts/test-packs.sh" \
    || failed_layers+=("test-packs.sh")

printf '\n════════════════════════════════════════════════════\n'
if [[ ${#failed_layers[@]} -eq 0 ]]; then
    printf '✓ all kit-internal test layers passed\n'
    exit 0
fi
printf '✗ kit-internal tests: %d layer(s) failed:\n' "${#failed_layers[@]}"
for layer in "${failed_layers[@]}"; do
    printf '    - %s\n' "$layer"
done
exit 1
