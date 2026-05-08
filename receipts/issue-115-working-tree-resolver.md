# issue-115 — working-tree resolver for self-referential pack fetches

Closes [#115](https://github.com/Duaility/governance-kit/issues/115). First slice of [#114](https://github.com/Duaility/governance-kit/issues/114).

## Checklist

- [x] New module `governance/assets/packs/lib/working_tree.py` housing `origin_matches_target` and `resolve_from_working_tree`
- [x] `packverb.fetch_ref` calls the resolver before falling through to the clone path; existing clone path unchanged
- [x] New test layer `scripts/test-working-tree.py` covering URL-shape variants and 5 integration tests against tmp git repos
- [x] `scripts/test.sh` wires the new layer in alongside `test-packverb.py`
- [x] Both new modules + the existing `packverb.py` stay under the 500-line `repo-hygiene` threshold
- [x] Full kit suite (`bash scripts/test.sh`) and this repo's dogfood (`bash .governance/run.sh`) green

## What changed

- New module `governance/assets/packs/lib/working_tree.py` housing `origin_matches_target` and `resolve_from_working_tree`. The 122-line module exports two callables. `origin_matches_target(origin_url, owner, repo)` normalises both https (`https://github.com/o/r.git`) and ssh (`git@github.com:o/r.git`) remote URL shapes — lowercases for case-insensitive comparison, strips trailing `.git`, and anchors the suffix on `/` or `:` so substring matches like `xacme/repo` against owner `acme` correctly fail. `resolve_from_working_tree(parsed, cache_root_path, *, slugify, pack_id_re, read_pack_id)` walks `git rev-parse --show-toplevel` from cwd, checks `git remote get-url origin` against the parsed owner/repo, locates the pack subdir, validates `pack.yaml`, captures `git rev-parse HEAD` as the SHA pin, and copies the entire working tree (minus `.git`) into `<cache>/<id-slug>@<sha>/` — the same shape `fetch_ref`'s clone path produces, so downstream consumers see one cache layout. The slugify / regex / read-pack-id callables are injected by `packverb.py` so this module has no import dependency on `packverb` (avoids a cycle). Returns `None` (not an error) when cwd isn't a git repo, origin doesn't match, the subpath has no `pack.yaml`, or any git invocation fails — callers fall through to the network clone.
- `packverb.fetch_ref` calls the resolver before falling through to the clone path; existing clone path unchanged. The edited file at `governance/assets/packs/lib/packverb.py` adds `from working_tree import resolve_from_working_tree` and a small `_read_pack_id(pack_sub)` helper (lifts the `id:` scalar out of `pack.yaml` via the existing `pack_manifest` / `scalar` helpers) so the resolver stays free of `packctl` imports. `fetch_ref` now calls `resolve_from_working_tree(...)` immediately after `parse_ref` + cache-root prep; on a non-`None` result it returns the working-tree shape directly. On `None` the existing clone code path runs unchanged — no behaviour change for any URL that doesn't match the current repo's origin. Total file size 453 lines.
- New test layer `scripts/test-working-tree.py` covering URL-shape variants and 5 integration tests against tmp git repos. The 271-line file exercises 5 `origin_matches_target` cases (https with/without `.git`, ssh form, mismatched owner/repo, substring-owner rejection) and 5 `resolve_from_working_tree` integration cases against real `git init` tmp repos: outside-git no-op, mismatched-origin no-op, missing-pack-subpath no-op, happy-path with HEAD-sha pin and `.git`-excluded cache copy, plus a `fetch_ref`-level test that mocks `subprocess.run` to assert no `git clone` / `fetch` / `checkout` is invoked when the resolver applies. Uses an enhanced stdlib-only `MonkeyPatch` stand-in that records undos, supports `setattr` + `chdir`, and is dispatched per-test by the harness via `inspect.signature` to detect the `monkeypatch` parameter — so global state doesn't leak between cases.
- `scripts/test.sh` wires the new layer in alongside `test-packverb.py`. A new `run_layer "working-tree resolver (Python)"` invocation lands between the existing `test-packverb.py` layer and `test-install-sh.sh`. The header comment block is updated to list the new layer (`2a. test-working-tree.py`).
- Both new modules + the existing `packverb.py` stay under the 500-line `repo-hygiene` threshold. Final sizes: `packverb.py` 453, `working_tree.py` 122, `test-working-tree.py` 271, `test-packverb.py` byte-identical to HEAD at 498. Splitting was necessary because the 90-line resolver inline pushed `packverb.py` to 531; extracting it gives both files breathing room and signals the architectural seam (a different fetch *mode*, distinct from the clone path).
- Full kit suite (`bash scripts/test.sh`) and this repo's dogfood (`bash .governance/run.sh`) green. The full umbrella runs every layer (`packctl`, `packverb`, the new `working-tree resolver`, `install.sh`, `hooks.sh`, runtime, schema-split, packs) and exits 0; the dogfood enforces all 14 directives against the working tree and exits 0 with no violations.

## Out of scope

- Relocating `governance/assets/packs/core/` to `packs/core/`. That move sits in the next slice (phase 2 of #114) because removing `assets/packs/` from the skill bundle requires `init` to fetch via the new resolver, which is a coupled change.
- Dropping the `builtin` source type. Lockfile entries and `INIT_FLOW` / `RESET_FLOW` continue to read `source: builtin` for `governance-kit/core` until phase 2 lands.
- Reconstruction at `run.sh` start. Today `run.sh` walks committed `.governance/packs/*/directives/*/check.sh` files; reconstruction-from-cache lands in phase 3.
- Gitignoring the reconstructed expanded tree. Phase 4.
- Fork-not-patch amendments (`replaces:` field, `directive disable`, `directive sync`). Phase 5.
- Retiring this repo's dual-edit dogfood mirror at `.governance/packs/governance-kit/core/`. Phase 6, after reconstruction works end-to-end.

## Verification

- `bash scripts/test.sh` exits 0 — every layer (`packctl`, `packverb`, the new `working-tree resolver`, `install.sh`, `hooks.sh`, runtime, schema-split, packs) passes.
- `uv run --quiet --isolated --with PyYAML python scripts/test-working-tree.py` exits 0 — 10 cases run, all `ok`.
- `bash .governance/run.sh` exits 0 with all 14 directives green; `repo-hygiene`'s file-size sub-check confirms `packverb.py` (453), `working_tree.py` (122), and `test-working-tree.py` (271) are all under the 500-line limit.
- `wc -l scripts/test-packverb.py` returns 498 — the file is byte-identical to HEAD, so the existing packverb test surface is untouched.
- Reviewer can confirm the additive nature by reading the `fetch_ref` diff: the only logic change is two new lines that call the resolver and return its result if non-`None`; the entire clone branch is unchanged below.
