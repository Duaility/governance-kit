#!/usr/bin/env bash
# Directive: kit-version-consistency (dogfood) — the governance-kit SOURCE tree's
# kit-version stamps and the kit/pack axis invariant agree. Complements the
# shipped `version-consistency` directive (which validates an INSTALLED repo's
# install.yaml vs its managed-file markers); this one guards the kit-authoring
# sources that only exist in this repo:
#
#   - kit/assets/kit.yaml `version`  ==  skill/SKILL.md frontmatter `version`
#   - every packs/<pack>/pack.yaml `min_governance_kit`  <=  kit.yaml `version`  (axis floor)
#
# Source of truth for the kit axis is kit.yaml; SKILL.md's frontmatter version is
# a derived copy that scripts/release.sh re-stamps. See VERSIONING.md.
set -u
source "$(dirname "$0")/../../../../../lib.sh"
directive_start "kit-version-consistency"
require_git
ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT" || exit 1

scalar() { sed -nE "s/^[[:space:]]*$2:[[:space:]]*\"?([^\"#[:space:]]*)\"?.*/\1/p" "$1" | head -1; }
ver_le() { [[ "$1" == "$2" ]] || [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" == "$1" ]]; }

kit="$(scalar kit/assets/kit.yaml version)"
skill="$(scalar skill/SKILL.md version)"

[[ -n "$kit" ]] || violation "kit/assets/kit.yaml has no version field"
if [[ -n "$kit" && -n "$skill" && "$kit" != "$skill" ]]; then
    violation "skill/SKILL.md version ($skill) != kit/assets/kit.yaml version ($kit) — both are bumped together by scripts/release.sh kit <v>"
fi
# Axis floor for every bundled pack: no concern pack may declare a
# min_governance_kit newer than the kit it ships in. Post core→concern split
# (#192) there are seven packs under packs/, not one.
if [[ -n "$kit" ]]; then
    shopt -s nullglob
    for pf in packs/*/pack.yaml; do
        pmin="$(scalar "$pf" min_governance_kit)"
        [[ -n "$pmin" ]] || continue
        if ! ver_le "$pmin" "$kit"; then
            violation "$pf min_governance_kit ($pmin) is newer than kit.yaml version ($kit) — violates the axis invariant pack.min_governance_kit <= KIT_VERSION"
        fi
    done
    shopt -u nullglob
fi

directive_end
