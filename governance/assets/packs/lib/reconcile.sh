#!/usr/bin/env bash
# reconcile.sh — rebuild expanded pack trees from packs.lock.
#
# Walks `.governance/packs.lock`. For every entry with `source: gh`,
# ensures `.governance/packs/<id>/` matches the locked SHA's content:
#
#   1. Call `packverb fetch <ref>@<sha>` to populate (or hit) the cache at
#      `${GOVERNANCE_KIT_HOME:-$HOME/.governance/cache}/packs/<id-slug>@<sha>/`.
#      The working-tree resolver (#115) short-circuits this to read from
#      the consumer's own monorepo when the URL points at it — that's the
#      dogfood / inner-loop dev case.
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
# (those are validated in CI, where the kit is installed by setup-clone.sh
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

    fetch_json="$(pv fetch "${ref}@${sha}")"
    pack_dir="$(printf '%s' "$fetch_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["pack_dir"])')"

    if [[ ! -d "$pack_dir" ]]; then
        echo "reconcile: cache pack_dir missing for $pack_id: $pack_dir" >&2
        exit 1
    fi

    target="$REPO_ROOT/.governance/packs/$pack_id"
    mkdir -p "$(dirname "$target")"

    # Rebuild atomically — clear and copy the whole subtree, then prune
    # `directives/<id>/` entries that aren't in the lockfile's list. Anything
    # the user hand-modified in the expanded copy is intentionally lost;
    # modify amendments belong in a local pack with `replaces:` (phase 5 of
    # #114), not in-place edits to a fetched pack's tree.
    rm -rf "$target"
    mkdir -p "$target"
    cp -R "$pack_dir/." "$target/"

    if [[ -n "$directives_csv" && -d "$target/directives" ]]; then
        # Build a "keep" set; remove every directives/<id>/ that isn't in it.
        IFS=',' read -ra keep <<< "$directives_csv"
        keep_lookup=" ${keep[*]} "
        for d in "$target"/directives/*/; do
            [[ -d "$d" ]] || continue
            id="$(basename "$d")"
            case "$keep_lookup" in
                *" $id "*) ;;
                *) rm -rf "$d" ;;
            esac
        done
    fi

    chmod +x "$target"/directives/*/check.sh 2>/dev/null || true
    for kind_dir in "$target"/directives/*/hooks "$target"/directives/*/runtimes; do
        [[ -d "$kind_dir" ]] || continue
        chmod +x "$kind_dir"/*.sh 2>/dev/null || true
    done

    reconciled=$((reconciled + 1))
done <<< "$gh_rows"

# Local-source packs need no reconciliation — they're committed source.
skipped="$(python3 -c '
import json, sys
data = json.load(sys.stdin)
print(sum(1 for p in data.get("packs", []) if p.get("source") == "local"))
' < "$lock_tmp")"

echo "reconcile: $reconciled gh pack(s) rebuilt; $skipped local pack(s) skipped"
