#!/usr/bin/env bash
# scripts/test.sh — umbrella entrypoint for every test that covers the kit's
# own product code. Wired into both local git hooks (via the
# pre-commit-test-gate directive in .governance/packs/duaility/governance-kit/)
# and the CI workflow.
#
# Layers:
#   0. test-kityaml.py        — kityaml.py restricted-YAML parser/writer
#                               (grammar, coercion, packs.lock byte parity,
#                               shipped-corpus walk)
#   1. test-packctl.py        — packctl.py library + CLI (preset, validation)
#   1a. test-packctl-validate.py — validate_pack_dir structural matrix (pack/
#                               directive shape, presets, check.sh/evals)
#   1b. test-packctl-subagent.py — judge/config separation
#                               matrix (issue #355 cmd collapse)
#   1c. test-packctl-triggers.py — validate_pack_dir triggers:/judge-cmd-lane
#                               matrix (scheduled-trigger redesign)
#   2. test-packverb.py       — packverb.py (refs, capability glob, lockfile, catalog)
#   2b. test-kitverb.py       — kitverb.py (kit-plan: version delta, manifest
#                               reconstruction, managed-file inventory/status)
#   2b'. test-kitresolve.py   — kitresolve.py (kit-resolve/kit-pin: target
#                               resolution, floor/downgrade gates, delegation)
#   2b''. test-bootstrap.py   — skill/bootstrap.py (the published shim's
#                               fetch-only bootstrap + its cache-layout
#                               contract with the kit engines)
#   2c. test-packverb-apply.py — packplan.py/packapply.py (pack-plan/pack-apply
#                               add/update/remove) + docsurgery.py CONSTITUTION
#                               subsection surgery
#   2d. test-schedulelib.py   — workflowlib.py (directive-owned cron
#                               compilation into the single generated
#                               schedule workflow)
#   3. test-install-sh.sh     — install.sh helpers (copy_tree_without_evals,
#                               install_directive_folder, install_directive_assets,
#                               write_installed_manifest flag matrix)
#   4. test-hooks-sh.sh       — hooks.sh dispatcher generation, marker policy,
#                               SKIP_GOVERNANCE handling
#   5. test-runtime.sh        — runtime files shipped to consumer repos
#                               (dot-governance/run.sh + lib.sh)
#   5a. test-subagent.sh      — lib.sh judgment surface: the awk
#                               `judge:` reader, independent remediation
#                               instruction, and the `gate: verdict`
#                               adjudication gate (log, stamp, ladder)
#   5b. test-schedule.sh      — schedule.sh at-rest driver contract (adapter
#                               resolution, range resolution, digest filing,
#                               the lane-scoped governance-schedule-<lane>
#                               label, unlabeled fallback)
#   6. test-schema-split.sh   — install.yaml + packs.lock cross-file invariants
#                               (no packs[] in install.yaml; every source kind
#                               recorded in packs.lock with the right fields)
#   7. test-packs.sh          — pack smoke + hook generation smoke + fresh repo
#                               install contract + pack evals
#
# All layers are non-destructive: each builds its own tmpdirs and tears down.
# Every Python layer runs on a bare `python3` — the kit's tooling is
# stdlib-only (no PyYAML, no uv, no package manager; issue #355).

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

run_layer "kityaml: restricted-YAML load/dump parity (Python)" \
    python3 "$ROOT/scripts/test-kityaml.py" \
    || failed_layers+=("test-kityaml.py")

run_layer "packctl: preset/CLI (Python)" \
    python3 "$ROOT/scripts/test-packctl.py" \
    || failed_layers+=("test-packctl.py")

run_layer "packctl: validate_pack_dir matrix (Python)" \
    python3 "$ROOT/scripts/test-packctl-validate.py" \
    || failed_layers+=("test-packctl-validate.py")

run_layer "packctl: validate_pack_dir triggers/judge-cmd-lane matrix (Python)" \
    python3 "$ROOT/scripts/test-packctl-triggers.py" \
    || failed_layers+=("test-packctl-triggers.py")

run_layer "packctl: judge semantics/config separation (Python)" \
    python3 "$ROOT/scripts/test-packctl-subagent.py" \
    || failed_layers+=("test-packctl-subagent.py")

run_layer "packverb (Python)" \
    python3 "$ROOT/scripts/test-packverb.py" \
    || failed_layers+=("test-packverb.py")

run_layer "kitverb: kit-plan delta/reconstruction/inventory (Python)" \
    python3 "$ROOT/scripts/test-kitverb.py" \
    || failed_layers+=("test-kitverb.py")

run_layer "kitresolve: resolve/pin/delegation params (Python)" \
    python3 "$ROOT/scripts/test-kitresolve.py" \
    || failed_layers+=("test-kitresolve.py")

run_layer "skill bootstrap: fetch-only shim + cache contract (Python)" \
    python3 "$ROOT/scripts/test-bootstrap.py" \
    || failed_layers+=("test-bootstrap.py")

run_layer "digestlib: digest determinism + bash digest parity (Python)" \
    python3 "$ROOT/scripts/test-digestlib.py" \
    || failed_layers+=("test-digestlib.py")

run_layer "docsurgery: pure CONSTITUTION.md transforms (Python)" \
    python3 "$ROOT/scripts/test-docsurgery.py" \
    || failed_layers+=("test-docsurgery.py")

run_layer "pack-apply: plan/apply add/update/remove + doc surgery (Python)" \
    python3 "$ROOT/scripts/test-packverb-apply.py" \
    || failed_layers+=("test-packverb-apply.py")

run_layer "workflowlib: workflow generate (Python)" \
    python3 "$ROOT/scripts/test-schedulelib.py" \
    || failed_layers+=("test-schedulelib.py")

run_layer "reset/uninstall: plan/apply engines (Python)" \
    python3 "$ROOT/scripts/test-reset-uninstall.py" \
    || failed_layers+=("test-reset-uninstall.py")

run_layer "init: plan/apply engine + CONSTITUTION assembly (Python)" \
    python3 "$ROOT/scripts/test-init.py" \
    || failed_layers+=("test-init.py")

run_layer "install.sh helpers (bash)" \
    bash "$ROOT/scripts/test-install-sh.sh" \
    || failed_layers+=("test-install-sh.sh")

run_layer "hooks.sh dispatcher generation (bash)" \
    bash "$ROOT/scripts/test-hooks-sh.sh" \
    || failed_layers+=("test-hooks-sh.sh")

run_layer "shipped runtime: run.sh + lib.sh (bash)" \
    bash "$ROOT/scripts/test-runtime.sh" \
    || failed_layers+=("test-runtime.sh")

run_layer "sub-agent judgment: declaration reader + adjudication gate (bash)" \
    bash "$ROOT/scripts/test-subagent.sh" \
    || failed_layers+=("test-subagent.sh")

run_layer "schedule driver: adapter resolution + digest filing + label ensure (bash)" \
    bash "$ROOT/scripts/test-schedule.sh" \
    || failed_layers+=("test-schedule.sh")

run_layer "schema split: install.yaml + packs.lock (bash)" \
    bash "$ROOT/scripts/test-schema-split.sh" \
    || failed_layers+=("test-schema-split.sh")

run_layer "pack smoke + hook generation + evals (bash)" \
    bash "$ROOT/scripts/test-packs.sh" \
    || failed_layers+=("test-packs.sh")

run_layer "kit-version-consistency: axis floor (bash)" \
    bash "$ROOT/scripts/test-kit-version-consistency.sh" \
    || failed_layers+=("test-kit-version-consistency.sh")

run_layer "pre-commit-test-gate: hook wiring (bash)" \
    bash "$ROOT/scripts/test-precommit-gate.sh" \
    || failed_layers+=("test-precommit-gate.sh")

run_layer "conf-registry-sync: helper reads <-> directive.yaml (bash)" \
    bash "$ROOT/scripts/test-conf-knob-doc-sync.sh" \
    || failed_layers+=("test-conf-knob-doc-sync.sh")

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
