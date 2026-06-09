#!/usr/bin/env bash
# Directive: kit-version-consistency (dogfood) — the governance-kit SOURCE tree's
# kit-version stamps and the kit/pack axis invariant agree. Complements the
# shipped `version-consistency` directive (which validates an INSTALLED repo's
# install.yaml vs its managed-file markers); this one guards the kit-authoring
# sources that only exist in this repo:
#
#   - governance/assets/kit.yaml `version`  ==  governance/SKILL.md frontmatter `version`
#   - packs/core/pack.yaml `min_governance_kit`  <=  kit.yaml `version`   (axis floor)
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

kit="$(scalar governance/assets/kit.yaml version)"
skill="$(scalar governance/SKILL.md version)"
coremin="$(scalar packs/core/pack.yaml min_governance_kit)"

[[ -n "$kit" ]] || violation "governance/assets/kit.yaml has no version field"
if [[ -n "$kit" && -n "$skill" && "$kit" != "$skill" ]]; then
    violation "governance/SKILL.md version ($skill) != governance/assets/kit.yaml version ($kit) — both are bumped together by scripts/release.sh kit <v>"
fi
if [[ -n "$kit" && -n "$coremin" ]] && ! ver_le "$coremin" "$kit"; then
    violation "packs/core/pack.yaml min_governance_kit ($coremin) is newer than kit.yaml version ($kit) — violates the axis invariant core.min_governance_kit <= KIT_VERSION"
fi

directive_end
