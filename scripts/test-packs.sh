#!/usr/bin/env bash
# scripts/test-packs.sh — pack-author CI entrypoint.
#
# Two jobs:
#   1. Smoke-test the loader against every pack in
#      governance/assets/packs/*. Confirms the manifest parses,
#      each listed directive resolves, every declared preset unrolls, and
#      referenced script/snippet files exist on disk.
#   2. Run every packs/*/evals/*/test.sh — pack-author tests that prove
#      the shipped directives pass on clean fixtures and fail on dirty ones.
#
# Failures in either half fail the script. This is the gate that stops
# a broken pack from shipping.

set -u

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PACKS_ROOT="$ROOT/governance/assets/packs"
# Pack-search roots. `governance/assets/packs/` hosts the in-tree
# `core` pack plus the shared lib. `extensions/packs/` is the monorepo home
# for community-shaped packs (authored in the `<author>/<slug>` id form) that
# ship alongside the kit.
PACK_ROOTS=(
    "$PACKS_ROOT"
    "$ROOT/extensions/packs"
)
LOADER="$PACKS_ROOT/lib/packs.sh"
HOOKS_LIB="$PACKS_ROOT/lib/hooks.sh"
INSTALL_LIB="$PACKS_ROOT/lib/install.sh"

list_packs_all() {
    local root
    for root in "${PACK_ROOTS[@]}"; do
        [[ -d "$root" ]] || continue
        list_packs "$root" || true
    done
}

if [[ ! -f "$LOADER" ]]; then
    echo "✗ loader missing: $LOADER" >&2
    exit 1
fi
if [[ ! -f "$HOOKS_LIB" ]]; then
    echo "✗ hooks lib missing: $HOOKS_LIB" >&2
    exit 1
fi
if [[ ! -f "$INSTALL_LIB" ]]; then
    echo "✗ install lib missing: $INSTALL_LIB" >&2
    exit 1
fi
# shellcheck disable=SC1090
source "$LOADER"
# shellcheck disable=SC1090
source "$HOOKS_LIB"
# shellcheck disable=SC1090
source "$INSTALL_LIB"

fail=0
pack_count=0
directive_count=0
eval_count=0

printf '── pack smoke tests ───────────────────────────────────────\n'

while IFS=$'\t' read -r pack_id pack_dir; do
    [[ -z "$pack_id" ]] && continue
    pack_count=$(( pack_count + 1 ))

    printf '  pack: %s\n' "$pack_id"

    # Structural validation (id matches dir, scripts + snippets exist, etc.)
    if ! errors="$(validate_pack "$pack_dir")"; then
        fail=1
        printf '%s\n' "$errors" | sed 's/^/    ✗ /'
    fi

    # Every preset declared on the pack must unroll to a non-empty list.
    for preset in minimal standard strict; do
        if preset_resolve "$pack_dir" "$preset" >/dev/null 2>&1; then
            count=$(preset_resolve "$pack_dir" "$preset" | wc -l | tr -d ' ')
            if [[ "$count" -eq 0 ]]; then
                printf '    ✗ preset %s resolved to empty list\n' "$preset"
                fail=1
            fi
        fi
    done

    # Count directives (for the summary at the end).
    while IFS= read -r rid; do
        [[ -z "$rid" ]] && continue
        directive_count=$(( directive_count + 1 ))
    done < <(directives_for "$pack_dir")

    # always_install is reserved to core — validate_pack already enforced
    # this above.
done < <(list_packs_all)

pack_dirs=()
while IFS=$'\t' read -r _ pack_dir; do
    [[ -n "$pack_dir" ]] && pack_dirs+=("$pack_dir")
done < <(list_packs_all)
if ! errors="$(validate_pack_set "${pack_dirs[@]}")"; then
    fail=1
    printf '%s\n' "$errors" | sed 's/^/  ✗ /'
fi

printf '\n── hook generation smoke ─────────────────────────────────\n'

# Build a spec file covering every directive with a non-none hook across all
# packs, then ask the generator to emit hooks for them. This proves the
# generator survives the manifest shapes our packs actually ship.
hook_tmp="$(mktemp -d)"
hook_spec="$hook_tmp/spec.tsv"
: > "$hook_spec"
while IFS=$'\t' read -r pack_id pack_dir; do
    [[ -z "$pack_id" ]] && continue
    while IFS= read -r rid; do
        [[ -z "$rid" ]] && continue
        hk=$(directive_field "$pack_dir" "$rid" hook 2>/dev/null || true)
        surface=$(directive_field "$pack_dir" "$rid" surface 2>/dev/null || true)
        directive_folder="$pack_dir/directives/$rid"
        has_helper=0
        for kind in pre-commit commit-msg prepare-commit-msg; do
            [[ -f "$directive_folder/hooks/$kind.sh" ]] && has_helper=1
        done
        # Include the directive in the spec if it declares a hook OR ships any
        # directive-owned helper. Both paths route through the generator.
        if [[ -z "$hk" || "$hk" == "none" ]] && [[ $has_helper -eq 0 ]]; then
            continue
        fi
        printf '%s\t%s\t%s\t%s\n' "$rid" "${hk:-none}" "$surface" "$directive_folder" >> "$hook_spec"
    done < <(directives_for "$pack_dir")
done < <(list_packs_all)

hook_out="$hook_tmp/hooks"
mkdir -p "$hook_out"
if generate_hooks "$hook_out" "test" "$hook_spec"; then
    for h in "$hook_out"/*; do
        [[ -f "$h" ]] || continue
        if ! bash -n "$h"; then
            printf '  ✗ generated %s fails syntax check\n' "$(basename "$h")"
            fail=1
        elif ! hook_has_marker "$h"; then
            printf '  ✗ generated %s missing ownership marker\n' "$(basename "$h")"
            fail=1
        else
            printf '  ✓ %s\n' "$(basename "$h")"
        fi
    done
else
    printf '  ✗ generate_hooks failed\n'
    fail=1
fi
rm -rf "$hook_tmp"

printf '\n── fresh repo install contract ───────────────────────────\n'

fresh_tmp="$(mktemp -d)"
(
    cd "$fresh_tmp" || exit 1
    git init --quiet --initial-branch=main .
    git config user.email eval@example.com
    git config user.name "Eval Harness"

    cat > README.md <<'EOF'
# Fresh Contract Repo

This fixture proves that installing the core standard preset into a new
repository leaves a governed tree that can run its installed checks and
generated hooks successfully.
EOF

    cat > CONSTITUTION.md <<'EOF'
# Constitution

This fixture constitution is intentionally small but non-empty. The real
bootstrap skill writes selected directive snippets here; this contract test
cares that the installed directives and hooks agree on the target tree shape.

## Principles

- Governance checks must be executable locally and in CI.

## Directives

- Placeholder directive for the fixture.

## Evolution Log

- 2026-04-23 — test harness — Seed fixture constitution.
EOF

    cat > AGENTS.md <<'EOF'
# AGENTS.md

Entry point for agents working in this fixture repository. Read the linked
documents before making changes, then run the governance suite before commit.

## Links

- [README](README.md) — fixture overview.
- [Constitution](CONSTITUTION.md) — governance directives.
- [Workflow](.github/workflows/ci.yml) — CI entrypoint.
- [Gitignore](.gitignore) — local file policy.

## Working Notes

This file is deliberately long enough for the agents-md-exists directive. It is
part of the fresh-repo install contract rather than a pack-author eval.

Agents should preserve the installed governance folder shape:
`tests/governance/directives/<id>/check.sh`.

Generated hooks discover installed `directive.yaml` files at runtime, so
post-install amendments can add compatible directive folders without rewriting
the dispatcher for every directive.

The contract also keeps seed files explicit. Directives that need a repo-root
artifact ship that artifact under `install-assets/`, and the installer copies
it before the first governance run.

This fixture intentionally avoids project-specific source code. It proves the
governance surface itself is coherent before any application stack is present.

Keep this document boring. The directive under test is the bootstrap contract, not
the prose in this file.
EOF

    cat > LICENSE <<'EOF'
MIT License

Copyright (c) 2026 governance-kit test harness

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files, to deal in the Software
without restriction.
EOF

    cat > SECURITY.md <<'EOF'
# Security

Report vulnerabilities to security@example.com.
EOF

    cat > ARCHITECTURE.md <<'EOF'
# Architecture

## Overview

Fixture architecture doc for the fresh-repo install contract. The real
bootstrap skill writes repo-specific content; this file only exists to
satisfy `required-docs` at the expected line-count floor.

## Layers

- surface — the tree shape installed by bootstrap
- directives — executable checks under `tests/governance/directives/<id>/`
- hooks — `.githooks/*` dispatchers generated from the installed manifest

## Directives

Directive folders are self-contained. The hook generator discovers installed
directive metadata at runtime. Adding or removing a directive is a single directory
operation on `tests/governance/directives/`.

## Notes

This fixture is deliberately terse but long enough to clear the
`required-docs` line-count floor.
EOF

    cat > .gitignore <<'EOF'
.env
*.log
EOF

    mkdir -p .github/workflows tests/governance/directives
    cat > .github/workflows/ci.yml <<'EOF'
name: CI
on: [push, pull_request]
permissions:
  contents: read
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: bash tests/governance/run.sh
EOF

    cp "$ROOT/governance/assets/tests-bash/run.sh" tests/governance/run.sh
    cp "$ROOT/governance/assets/tests-bash/lib.sh" tests/governance/lib.sh
    chmod +x tests/governance/run.sh

    core_pack="$PACKS_ROOT/core"
    selected=()
    while IFS= read -r rid; do
        [[ -n "$rid" ]] && selected+=("$rid")
    done < <(preset_resolve "$core_pack" standard)
    while IFS= read -r rid; do
        [[ -n "$rid" ]] && selected+=("$rid")
    done < <(always_install_directives "$core_pack")

    installed_pairs=()
    seen_directives=" "
    for rid in "${selected[@]}"; do
        case "$seen_directives" in
            *" $rid "*) continue ;;
        esac
        seen_directives="$seen_directives$rid "
        if ! directive_supports_hook_strategy "$core_pack" "$rid" "githooks"; then
            continue
        fi
        install_directive_folder "$core_pack" "$rid" "$fresh_tmp"
        install_directive_assets "$core_pack" "$rid" "$fresh_tmp"
        installed_pairs+=("$core_pack" "$rid")
    done

    write_installed_manifest "$fresh_tmp" \
        --hook-strategy githooks \
        --stack bash \
        --agents-md-directive \
        -- "${installed_pairs[@]}"

    hook_spec="$fresh_tmp/hook-spec.tsv"
    build_hook_spec_from_installed_directives "$fresh_tmp" "$hook_spec"
    generate_hooks "$fresh_tmp/.githooks" "test" "$hook_spec"
    git config core.hooksPath .githooks

    git add -A
    bash tests/governance/run.sh
    bash -n .githooks/pre-commit .githooks/commit-msg .githooks/prepare-commit-msg
    printf 'feat: missing issue\n' > bad-msg.txt
    printf 'feat(test): valid message (#23)\n' > good-msg.txt
    .githooks/commit-msg bad-msg.txt && exit 1
    .githooks/commit-msg good-msg.txt
    rm bad-msg.txt good-msg.txt
    [[ -f .governance-kit/installed-packs.yaml ]]
)
fresh_status=$?
if [[ $fresh_status -eq 0 ]]; then
    printf '  ✓ core.standard installs into a fresh repo and runs green\n'
else
    printf '  ✗ core.standard fresh-repo contract failed\n'
    fail=1
fi
rm -rf "$fresh_tmp"

printf '\n── pack verb contract ────────────────────────────────────\n'

if uv run --quiet --isolated --with PyYAML python "$ROOT/scripts/test-packverb.py"; then
    printf '  ✓ packverb public contract smoke passed\n'
else
    printf '  ✗ packverb public contract smoke failed\n'
    fail=1
fi

printf '\n── pack evals ────────────────────────────────────────────\n'

while IFS= read -r eval_script; do
    [[ -z "$eval_script" ]] && continue
    eval_count=$(( eval_count + 1 ))
    label="$eval_script"
    for root in "${PACK_ROOTS[@]}"; do
        label="${label#$root/}"
    done
    printf '  eval: %s\n' "$label"
    if ! bash "$eval_script"; then
        fail=1
        printf '    ✗ eval failed\n'
    fi
done < <(for root in "${PACK_ROOTS[@]}"; do
    [[ -d "$root" ]] && find "$root" -type f -path '*/directives/*/evals/test.sh' 2>/dev/null
done | sort)

printf '\n────────────────────────────────────────\n'
if [[ $fail -ne 0 ]]; then
    printf '✗ test-packs: failures in %d pack(s), %d directive(s), %d eval(s)\n' \
        "$pack_count" "$directive_count" "$eval_count"
    exit 1
fi
printf '✓ test-packs: %d pack(s), %d directive(s), %d eval(s) passed\n' \
    "$pack_count" "$directive_count" "$eval_count"
