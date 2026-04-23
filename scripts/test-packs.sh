#!/usr/bin/env bash
# scripts/test-packs.sh — pack-author CI entrypoint.
#
# Two jobs:
#   1. Smoke-test the loader against every pack in
#      governance-bootstrap/assets/packs/*. Confirms the manifest parses,
#      each listed rule resolves, every declared preset unrolls, and
#      referenced script/snippet files exist on disk.
#   2. Run every packs/*/evals/*/test.sh — pack-author tests that prove
#      the shipped rules pass on clean fixtures and fail on dirty ones.
#
# Failures in either half fail the script. This is the gate that stops
# a broken pack from shipping.

set -u

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PACKS_ROOT="$ROOT/governance-bootstrap/assets/packs"
LOADER="$PACKS_ROOT/lib/packs.sh"

if [[ ! -f "$LOADER" ]]; then
    echo "✗ loader missing: $LOADER" >&2
    exit 1
fi
# shellcheck disable=SC1090
source "$LOADER"

fail=0
pack_count=0
rule_count=0
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

    # Count rules (for the summary at the end).
    while IFS= read -r rid; do
        [[ -z "$rid" ]] && continue
        rule_count=$(( rule_count + 1 ))
    done < <(rules_for "$pack_dir")

    # always_install is reserved to core — validate_pack already enforced
    # this above.
done < <(list_packs "$PACKS_ROOT")

printf '\n── pack evals ────────────────────────────────────────────\n'

while IFS= read -r eval_script; do
    [[ -z "$eval_script" ]] && continue
    eval_count=$(( eval_count + 1 ))
    label="${eval_script#$PACKS_ROOT/}"
    printf '  eval: %s\n' "$label"
    if ! bash "$eval_script"; then
        fail=1
        printf '    ✗ eval failed\n'
    fi
done < <(find "$PACKS_ROOT" -type f -path '*/evals/*/test.sh' 2>/dev/null | sort)

printf '\n────────────────────────────────────────\n'
if [[ $fail -ne 0 ]]; then
    printf '✗ test-packs: failures in %d pack(s), %d rule(s), %d eval(s)\n' \
        "$pack_count" "$rule_count" "$eval_count"
    exit 1
fi
printf '✓ test-packs: %d pack(s), %d rule(s), %d eval(s) passed\n' \
    "$pack_count" "$rule_count" "$eval_count"
