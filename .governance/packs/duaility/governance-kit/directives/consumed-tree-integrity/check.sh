#!/usr/bin/env bash
# Directive: consumed-tree-integrity (dogfood) — the vendored consumed tree
# under `.governance/packs/` is an honest materialization of the pins in
# `.governance/packs.lock`. Asserts (for every `source: gh` pack) that the
# pinned sha is a real commit in this repo, the ref's @rev is a real tag
# resolving to that sha, the claimed subpath exists at the sha, and every
# vendored directive folder byte-matches what the product's
# `copy_tree_without_evals` would materialize from the pin (minus evals/ and
# install-assets/). For `source: local` packs it checks the vendored directive
# set matches the lock. This is the directive that makes the #200 fiction — a
# lock that pins a sha at which the claimed paths don't exist, plus a
# hand-drifted consumed tree — impossible to commit.
#
# The heavy lifting (lock parse + git plumbing + byte-compare) lives in
# lib/integrity.py: stdlib only, prints one violation per line, exits 0 unless
# it crashes. The dogfood pins point at this same repo (gh:duaility/…), so the
# pinned commits are always present offline — no network in the hook or CI.
set -u
source "$(dirname "$0")/../../../../../lib.sh"
directive_start "consumed-tree-integrity"
require_git
ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT" || exit 1
HERE="$(cd "$(dirname "$0")" && pwd)"

if ! out="$(python3 "$HERE/lib/integrity.py")"; then
    violation "consumed-tree-integrity helper crashed — see stderr above"
fi
while IFS= read -r line; do
    [[ -n "$line" ]] && violation "$line"
done <<< "$out"

directive_end
