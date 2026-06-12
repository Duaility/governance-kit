#!/usr/bin/env bash
# scripts/dogfood-smoke.sh — Lane 2 of the two-lane dogfood (issue #200).
#
# Lane 1 (the committed `.governance/`) is an honest customer of the *last
# release*: its lock pins real tags and its consumed tree is regenerated only by
# `governance pack update` in post-release PRs. That makes `.governance/` a true
# specimen of the product, but it lags `packs/` by one release — by design, so
# every release exercises the `update` flow.
#
# Lane 2 closes the dev-loop gap. It materializes a consumed tree from the
# *working tree's* `packs/` (HEAD), against a throwaway copy of this repo, and
# runs the suite — entirely ephemeral, nothing committed. So "my new/edited
# directive in packs/ breaks our own repo" surfaces in the *same* PR instead of
# only after release, and the materialization primitive
# (`copy_tree_without_evals`, the same function the product's install/reconcile
# uses) is smoke-tested on every PR.
#
# Scope, stated plainly (no silent caps): Lane 2 exercises the *reconcile*
# primitive + `run.sh` discovery + every enforced directive against HEAD
# content. It does NOT exercise the gh-fetch / lockfile-writing path — there is
# no local-source `pack add`, and that path is dogfooded for real by Lane 1's
# `governance pack update` at release time. Lane 2 materializes exactly the
# directive set the committed lock enforces (read from `.governance/packs.lock`),
# so it is "Lane 1, but sourced from HEAD instead of the pinned tag".
#
# Usage: bash scripts/dogfood-smoke.sh
# Exit:  0 if the HEAD-sourced suite passes, non-zero otherwise.

set -euo pipefail

# A throwaway git repo must never touch the host gitdir. Strip every git-env
# override the surrounding hook/CI shell may have exported, or `git init` +
# commits below would corrupt the real repository.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
      GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_PREFIX 2>/dev/null || true

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

# shellcheck disable=SC1091
source "$ROOT/kit/assets/packs/lib/install.sh"   # copy_tree_without_evals

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

echo "dogfood-smoke: building a throwaway consumer at $TMP from HEAD"

# 1. Lay down a clean tree of every tracked file at HEAD. This includes the
#    committed Lane-1 consumed tree, run.sh, lib.sh, conf overlays, and the repo
#    content the directives inspect — i.e. a faithful consumer checkout.
git archive --format=tar HEAD | tar -x -C "$TMP"

# 2. Re-materialize the consumed tree from HEAD `packs/`, replacing Lane 1's
#    pinned copy with the working-tree source. We rebuild exactly the directive
#    set the committed lock enforces, so the smoke matches the real dogfood.
#    The lock is parsed with a stdlib-only python helper (the repo's python
#    ships no yaml, and so must the hook/CI path).
parse="$(python3 - "$ROOT/.governance/packs.lock" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
def strip(s):
    s = s.strip()
    if len(s) >= 2 and s[0] in "\"'" and s[-1] == s[0]:
        s = s[1:-1]
    return s
packs, cur, indir = [], None, False
for raw in text.splitlines():
    if not raw.strip() or raw.lstrip().startswith("#"):
        continue
    if raw.startswith("- id:"):
        cur = {"id": strip(raw[5:]), "directives": []}; packs.append(cur); indir = False; continue
    if raw.startswith("  ") and cur is not None:
        body = raw[2:]
        if body.startswith("- "):
            if indir: cur["directives"].append(strip(body[2:]))
            continue
        m = re.match(r"([A-Za-z_]+):\s*(.*)$", body)
        if m:
            k, v = m.group(1), m.group(2)
            if k == "directives": indir = True
            else: indir = False; cur[k] = strip(v)
        continue
    indir = False
for p in packs:
    if p.get("source") != "gh":
        continue
    for d in p["directives"]:
        print(f"{p['id']}\t{p.get('subpath','')}\t{d}")
PY
)"

# Drop the committed (Lane-1, pinned) gh consumed tree wholesale, so the smoke
# runs ONLY what we re-materialize from HEAD — no stale leftover (e.g. a directive
# renamed in HEAD would otherwise run under both its old and new id).
while IFS= read -r pid; do
    [[ -n "$pid" ]] && rm -rf "$TMP/.governance/packs/$pid"
done <<< "$(printf '%s\n' "$parse" | cut -f1 | sort -u)"

# consumed-tree-integrity is a Lane-1 invariant: it asserts the committed lock's
# pins resolve to released tags in this repo's history. The throwaway repo is a
# fresh `git init` with no tags and no upstream, so the pins can't resolve there
# — it would always fail and says nothing about whether HEAD packs/ are sound.
# It is enforced on the committed tree by run.sh/CI; drop it from the smoke.
rm -rf "$TMP/.governance/packs/duaility/governance-kit/directives/consumed-tree-integrity"

# Materialize the lock-enforced directive set from HEAD packs/. We run only
# `surface: repo-state` directives here: a `change-set` directive (commit
# message format, token/steering accounting) inspects the commit under review,
# which in a throwaway `git init` is a synthetic smoke commit — failing it would
# say nothing about HEAD packs/. Those are dogfooded by their own evals
# (scripts/test-packs.sh) and the live commit hook in normal dev. We log the
# skips rather than hide them.
count=0; skipped=""
while IFS=$'\t' read -r pack_id subpath did; do
    [[ -z "$pack_id" ]] && continue
    src="$ROOT/$subpath/directives/$did"
    if [[ ! -d "$src" ]]; then
        echo "dogfood-smoke: FAIL — HEAD packs/ has no source for $pack_id/$did at $subpath/directives/$did" >&2
        exit 1
    fi
    surface="$(sed -nE 's/^surface:[[:space:]]*"?([a-z-]+)"?.*/\1/p' "$src/directive.yaml" | head -1)"
    if [[ "$surface" != "repo-state" ]]; then
        skipped+=" $pack_id/$did(${surface:-?})"
        continue
    fi
    dest="$TMP/.governance/packs/$pack_id/directives/$did"
    copy_tree_without_evals "$src" "$dest"
    chmod +x "$dest/check.sh" 2>/dev/null || true
    [[ -d "$dest/hooks" ]] && chmod +x "$dest/hooks/"*.sh 2>/dev/null || true
    [[ -d "$dest/runtimes" ]] && chmod +x "$dest/runtimes/"*.sh 2>/dev/null || true
    count=$((count + 1))
done <<< "$parse"
echo "dogfood-smoke: materialized $count repo-state directive(s) from HEAD packs/"
[[ -n "$skipped" ]] && echo "dogfood-smoke: skipped change-set directive(s) (tested by evals + live hook):$skipped"

# 3. The throwaway tree must be a git repo with the materialized content
#    committed — the directives are repo-state checks that call git. Point it at
#    the tracked .githooks/ (required-docs asserts the consumer wired the hooks).
(
    cd "$TMP"
    git init -q
    git config user.email smoke@governance-kit.local
    git config user.name "dogfood-smoke"
    git config core.hooksPath .githooks
    git add -A
    git commit -q -m "dogfood-smoke: HEAD-sourced consumed tree" --no-verify
)

# 4. Run the suite against the HEAD-sourced consumed tree.
echo "dogfood-smoke: running suite against HEAD-sourced tree"
set +e
suite_out="$(cd "$TMP" && SKIP_GOVERNANCE=0 bash .governance/run.sh 2>&1)"
rc=$?
set -e
echo "$suite_out"

if [[ $rc -ne 0 ]]; then
    echo "dogfood-smoke: FAIL — the suite is red when sourced from HEAD packs/." >&2
    echo "dogfood-smoke: a directive you changed in packs/ no longer passes on this repo." >&2
    exit 1
fi
echo "dogfood-smoke: PASS — HEAD-sourced suite is green."
