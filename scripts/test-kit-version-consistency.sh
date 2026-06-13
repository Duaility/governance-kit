#!/usr/bin/env bash
# scripts/test-kit-version-consistency.sh — the governance-kit SOURCE tree's
# kit/pack axis floor invariant holds. Ported from the former dogfood directive
# `kit-version-consistency` (issue #251): this checks THIS project's own source,
# not a consumer repo's state, so it belongs in the test umbrella, not the
# directive set.
#
# Invariants:
#   - kit/assets/kit.yaml carries a `version` (the kit axis's single source of truth)
#   - every packs/<pack>/pack.yaml `min_governance_kit`  <=  kit.yaml `version`
#     (no bundled pack may demand a kit newer than the one it ships in)
#
# The published skill (skill/) versions independently and carries no kit version
# (#198), so its frontmatter is out of scope. See VERSIONING.md.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

fail=0
note() { printf '  ✗ %s\n' "$1" >&2; fail=1; }

scalar() { sed -nE "s/^[[:space:]]*$2:[[:space:]]*\"?([^\"#[:space:]]*)\"?.*/\1/p" "$1" | head -1; }
ver_le() { [[ "$1" == "$2" ]] || [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" == "$1" ]]; }

kit="$(scalar kit/assets/kit.yaml version)"
if [[ -z "$kit" ]]; then
    note "kit/assets/kit.yaml has no version field"
else
    shopt -s nullglob
    for pf in packs/*/pack.yaml; do
        pmin="$(scalar "$pf" min_governance_kit)"
        [[ -n "$pmin" ]] || continue
        if ! ver_le "$pmin" "$kit"; then
            note "$pf min_governance_kit ($pmin) is newer than kit.yaml version ($kit) — violates pack.min_governance_kit <= KIT_VERSION"
        fi
    done
    shopt -u nullglob
fi

if [[ $fail -eq 0 ]]; then
    printf '  ✓ kit-version-consistency: kit.yaml version >= every pack min_governance_kit\n'
fi
exit $fail
