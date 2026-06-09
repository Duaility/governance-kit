#!/usr/bin/env bash
# reconcile.sh — rebuild expanded pack trees from packs.lock.
#
# Walks `.governance/packs.lock`. For every entry with `source: gh`,
# ensures `.governance/packs/<id>/` matches the locked SHA's content:
#
#   1. Call `packverb fetch <ref>@<sha>` to populate (or hit) the cache at
#      `${GOVERNANCE_KIT_HOME:-$HOME/.governance/cache}/packs/<id-slug>@<sha>/`
#      via a network clone of the ref.
#   2. Copy the cached subpath into `.governance/packs/<id>/`. Existing
#      files are clobbered; that's the point — reconcile is the *rebuild*
#      step, not a merge.
#
# Entries with `source: local` are left alone — those are first-party
# hand-authored packs, committed to the consumer's repo.
#
# Designed to be invoked via the `governance` skill before `governance pack`
# verbs and before suite runs in fresh clones / post-`pack update` states.
# Not auto-invoked from `run.sh` to keep the runner shell-only and
# packverb-free for consumers that don't have the kit installed locally
# (those are validated in CI, where the kit is installed by enable-governance.sh
# and the agent calls reconcile explicitly).
#
# Usage:
#   bash <kit>/governance/assets/packs/lib/reconcile.sh <repo-root>

set -eu

REPO_ROOT="${1:-}"
if [[ -z "$REPO_ROOT" ]]; then
    echo "reconcile: missing argument <repo-root>" >&2
    exit 1
fi
if [[ ! -d "$REPO_ROOT/.governance" ]]; then
    echo "reconcile: $REPO_ROOT/.governance not found" >&2
    exit 1
fi

LOCK="$REPO_ROOT/.governance/packs.lock"
if [[ ! -f "$LOCK" ]]; then
    echo "reconcile: $LOCK not found — nothing to reconcile" >&2
    exit 0
fi

KIT_LIB="$(cd "$(dirname "$0")" && pwd)"
PACKVERB="$KIT_LIB/packverb.py"

# install_directive_folder is the canonical consumed-tree materializer shared
# with `governance pack add`; reusing it keeps a reconciled tree byte-identical
# to a freshly-installed one (directives only, evals/ and install-assets/
# stripped) instead of a raw subtree copy that would carry author-side files.
# shellcheck disable=SC1091
source "$KIT_LIB/install.sh"

pv() {
    uv run --quiet --isolated --with PyYAML python "$PACKVERB" "$@"
}

# Snapshot the lockfile as JSON to a tempfile so we can pipe it to python
# multiple times without a heredoc interacting badly with process
# substitution (older bash + a heredoc inside `< <(...)` produced an empty
# stream during testing).
lock_tmp="$(mktemp)"
trap 'rm -f "$lock_tmp"' EXIT
pv lock-read "$LOCK" > "$lock_tmp"

reconciled=0

# Walk every gh-source entry. Each line: <id>\t<ref>\t<sha>\t<subpath>
# Each gh row: <id>\t<ref>\t<sha>\t<subpath>\t<dir1,dir2,...>
# The directives list is comma-joined to round-trip cleanly through a
# tab-separated read; the lockfile constrains which directives we copy
# into the expanded tree (a pack can ship 14 directives but a consumer
# may only install 13).
gh_rows="$(python3 -c '
import json, sys
data = json.load(sys.stdin)
for pack in data.get("packs", []):
    if pack.get("source") != "gh":
        continue
    dirs = pack.get("directives") or []
    print("\t".join([
        str(pack.get("id", "")),
        str(pack.get("ref", "")),
        str(pack.get("sha", "")),
        str(pack.get("subpath", "")),
        ",".join(str(d) for d in dirs),
    ]))
' < "$lock_tmp")"

while IFS=$'\t' read -r pack_id ref sha subpath directives_csv; do
    [[ -z "$pack_id" ]] && continue

    # Pin to the locked SHA for a deterministic rebuild. The lock `ref` already
    # carries a human-readable `@<rev>` (e.g. `@main`); strip it before
    # appending `@<sha>` so we fetch the exact commit, not a malformed
    # `@<rev>@<sha>`.
    base_ref="${ref%@*}"
    fetch_json="$(pv fetch "${base_ref}@${sha}")"
    pack_dir="$(printf '%s' "$fetch_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["pack_dir"])')"

    if [[ ! -d "$pack_dir" ]]; then
        echo "reconcile: cache pack_dir missing for $pack_id: $pack_dir" >&2
        exit 1
    fi

    target="$REPO_ROOT/.governance/packs/$pack_id"

    # Rebuild atomically. Materialize each locked directive through the SAME
    # installer path `governance pack add` uses (install_directive_folder →
    # copy_tree_without_evals), so a reconciled tree is byte-identical to a
    # freshly-installed one: directives only, with author-side evals/ and
    # install-assets/ stripped. A pack may ship more directives than the lock
    # selects, so only the locked set is materialized. Any hand edit to the
    # expanded copy is intentionally lost — amendments belong in a local pack
    # with `replaces:`, not in-place edits to a fetched tree.
    rm -rf "$target"
    if [[ -n "$directives_csv" ]]; then
        IFS=',' read -ra keep <<< "$directives_csv"
        for directive_id in "${keep[@]}"; do
            [[ -z "$directive_id" ]] && continue
            install_directive_folder "$pack_dir" "$directive_id" "$REPO_ROOT"
        done
    fi

    reconciled=$((reconciled + 1))
done <<< "$gh_rows"

# Local-source packs need no reconciliation — they're committed source.
skipped="$(python3 -c '
import json, sys
data = json.load(sys.stdin)
print(sum(1 for p in data.get("packs", []) if p.get("source") == "local"))
' < "$lock_tmp")"

echo "reconcile: $reconciled gh pack(s) rebuilt; $skipped local pack(s) skipped"
