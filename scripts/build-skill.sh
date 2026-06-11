#!/usr/bin/env bash
# Assemble the published thin skill (skill/) from the kit source tree (governance/).
#
# `npx skills` installs the whole directory that holds SKILL.md — it has no
# file-exclude mechanism — so the published skill must BE thin on disk, not just
# in authority. This script defines exactly what rides along: skill/SKILL.md (a
# hand-authored installer doc) plus a DERIVED subset of the kit — the engine lib
# (the local bootstrap that resolves + fetches a kit, and the uninstall engine)
# and a version anchor. NO reference docs ship: every flow doc, template, pack,
# and eval lives in governance/ (the kit) and is read from the fetched/pinned
# kit tree at run time (issue #198).
#
# skill/SKILL.md is SOURCE and is never touched here. skill/assets/** is
# DERIVED — regenerated wholesale on every run. The `skill-build-sync` dogfood
# directive fails CI if the committed derived tree drifts from what this script
# emits, so governance/ stays the single source of truth and skill/ is a
# reproducible artifact (the same contract the consumed pack trees use).
#
# Usage: bash scripts/build-skill.sh [DEST]      # DEST defaults to skill/
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "build-skill: not inside a git repo" >&2; exit 1; }
cd "$ROOT"

DEST="${1:-skill}"
SRC_LIB="kit/assets/packs/lib"

[[ -d "$SRC_LIB" ]] || { echo "build-skill: missing $SRC_LIB" >&2; exit 1; }

# Regenerate the derived subtree only — SKILL.md is source and stays put.
rm -rf "$DEST/assets" "$DEST/references"
mkdir -p "$DEST/assets/packs"

# Version anchor: the skill ships the kit version it was built from. The vendored
# lib reads KIT_VERSION from <skill>/assets/kit.yaml (parents[2] of the lib dir),
# so the relative layout below mirrors kit/ exactly.
cp kit/assets/kit.yaml "$DEST/assets/kit.yaml"

# Fetch-only bootstrap — the rustup contract: just enough code to resolve,
# fetch, and cache kit trees (kit-resolve / kit-current / kit-pin / fetch-kit)
# plus their import closure. The apply engines (init/pack/reset/uninstall and
# the bash helpers) are kit code and run from the fetched/pinned tree, never
# from the shim. kitapply rides along only because kitverb.main() registers its
# subcommand at dispatch time.
BOOTSTRAP=(kitverb.py kitresolve.py kitapply.py packverb.py packctl.py applylib.py)
mkdir -p "$DEST/assets/packs/lib"
for f in "${BOOTSTRAP[@]}"; do
    [[ -f "$SRC_LIB/$f" ]] || { echo "build-skill: missing $SRC_LIB/$f" >&2; exit 1; }
    cp "$SRC_LIB/$f" "$DEST/assets/packs/lib/$f"
done

echo "build-skill: assembled $DEST (fetch-only bootstrap, ${#BOOTSTRAP[@]} modules + kit.yaml)"
