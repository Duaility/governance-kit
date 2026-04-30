<!-- last-verified: 2026-04-24 -->

# governance pack * — verb flows

Authoritative flow for the `governance pack {search,create,add,update,remove,list}` verbs. The unified `governance` skill dispatches to these flows; the supporting helpers live in `governance/assets/packs/lib/packverb.py` (and reuse pack/directive manifest loaders from `packctl.py`).

## Pack identity

Every pack — kit-bundled, community-installed, or hand-authored in this repo — lives at `.governance/packs/<owner>/<name>/` mirroring its GitHub identity at `github.com/<owner>/<name>`. Two-level on disk, no exceptions.

**Installed vs local.** Packs are distinguished only by their `pack.yaml`:

- **Installed packs** carry a `source:` field in `pack.yaml` and a lockfile entry with `source: gh`. The pack came from a fetched ref and `pack update` will re-pin it.
- **Repo-local packs** have no `source:` field in `pack.yaml`. They appear in the lockfile with `source: local` (no ref/sha) so `reset` can still find their directive list. `pack update` skips them.
- **`governance-kit/core`** ships in-tree with the kit and appears in the lockfile with `source: builtin`. `pack update` skips it; the kit version updates with the kit itself.

The runner walks `.governance/packs/*/*/directives/*/check.sh` uniformly — it does not branch on installed-vs-local.

## Common concepts

### Pack refs

`gh:<owner>/<repo>[/<subpath>][@<rev>]`

- `subpath` points at the directory containing `pack.yaml` (for monorepos).
- `rev` can be a branch, tag, or 40-char SHA. `@main` at add-time is resolved to a concrete SHA and pinned in the lockfile.

Resolve with `python packverb.py parse-ref <ref>`.

### Lockfile (`.governance/packs.lock`)

YAML, `version: "2"`. **Every** installed pack — kit-bundled, community, repo-local — has an entry. Each entry carries a `source` discriminator (`builtin` | `gh` | `local`) that decides which other fields are present. See [LOCK_SCHEMA.md](LOCK_SCHEMA.md) for the full contract.

```yaml
version: "2"
packs:
  - id: governance-kit/core
    version: "0.2"
    source: builtin
    directives:
      - required-docs
      - secrets-hygiene

  - id: acme/soc2
    version: "0.3"
    source: gh
    ref: gh:acme/soc2-pack@main
    sha: 5f3c...
    subpath: ""
    min_governance_kit: "0.2"
    installed_at: 2026-04-24T12:00:00Z
    directives:
      - soc2-audit-logs
      - soc2-retention

  - id: duaility/governance-kit
    version: "0.1"
    source: local
    directives:
      - pre-commit-test-gate
```

`builtin` and `local` entries carry only `id` / `version` / `source` / `directives` — no `ref` / `sha` / `installed_at`, since there is no upstream to pin. `gh` entries carry the full pin set. The lockfile is the single source of truth for pack provenance; companion file [`install.yaml`](INSTALL_SCHEMA.md) carries the init receipt (hook strategy, ci_workflow, side effects) but no pack pin state.

Lockfile I/O goes through `packverb lock-{read,add,remove,list}`. Never hand-edit — the canonical key order and timestamp format are set by the helper.

### Shared cache

`${GOVERNANCE_KIT_HOME:-$HOME/.governance/cache}/packs/<pack-id-slug>@<sha>/`

`/` in the pack id is encoded as `__` on disk. Cache entries are SHA-addressed and immutable — hitting a SHA already in the cache skips the network round-trip. `packverb fetch <ref>` emits a JSON envelope with `sha`, `pack_dir`, `cache_dir`, `id`.

### Capability declarations (`reads:` / `writes:` in `directive.yaml`)

A directive that declares either list is asserting that its `check.sh` stays within those path globs. `packverb capability-check <directive-dir>` performs a static sweep (heuristic grep for quoted path-like tokens) and flags references outside declared bounds. A directive that declares **neither** opts out of the check — this keeps the field backward compatible with pre-v0.2 directives.

During `pack add`, every directive in the fetched pack is capability-checked before any files are written. A single violation aborts the install with no partial state.

## `pack search [query]`

1. Read the built-in community catalog at `governance/assets/catalog.community.json` (in the governance-kit checkout).
2. Run `packverb catalog-search <catalog> [query]`. Each line is `<id>\t<ref>\t<summary>`.
3. Render the table to the user.

If `query` is omitted, print the full catalog. If the catalog file is missing, fall back to telling the user no catalog is available.

## `pack create <name>`

Scaffolds an empty repo-local pack at `.governance/packs/<repo-owner>/<name>/` for hand-authored team-scoped directives. `<repo-owner>` is read from the top-level `owner:` field in `.governance/install.yaml` (set at `governance init` from the GitHub origin remote, or via `--owner` if `init` couldn't auto-detect).

1. **Pre-flight.** Refuse if `.governance/install.yaml` is absent (run `governance init` first), if a pack already exists at the target path, or if `<name>` is not a slug-safe lowercase token (`^[a-z0-9][a-z0-9._-]*$`).
2. **Resolve the target path.** Read the manifest's `owner:`. Compute the install path `.governance/packs/<owner>/<name>/`.
3. **Scaffold.** Create the directory and write a minimal `pack.yaml`:

   ```yaml
   id: <owner>/<name>
   name: <human-readable name>
   version: "0.1"
   min_governance_kit: "0.2"
   description: <one-line description>
   author: <owner>
   ```

   No `source:` field — that is the marker that distinguishes a repo-local pack from an installed one. Also create an empty `directives/` subdirectory.

4. **Report.** Tell the user the pack is empty and that `governance directive add --pack <owner>/<name> <id>` is the next step.

`pack create` does **not** edit `.governance/install.yaml` or `.governance/packs.lock` or any hook scripts — the pack has no directives yet, so nothing to register or wire. The first `directive add --pack <owner>/<name>` is the step that adds the pack entry to `packs.lock` (with `source: local`) and regenerates hooks.

## `pack add <ref>`

1. **Parse + pre-flight.** `packverb parse-ref <ref>` to confirm the syntax, then refuse to run if:
   - not inside a git repo;
   - `CONSTITUTION.md` or `.governance/` are missing (run `governance init` first);
   - the ref's `@rev` is an unqualified branch name (`@main`, `@master`) → accept, but warn that the pinned SHA — not the branch — is what gets recorded.
2. **Fetch.** `packverb fetch <ref>` clones the requested rev shallowly into the shared cache, drops `.git`, and returns the resolved SHA + `pack_dir`.
3. **Validate pack.** `packverb validate-pack <pack_dir>` — rejects on missing required fields, preset cycles, `min_governance_kit > KIT_VERSION`, bad capability fields, etc.
4. **Capability-check every directive.** For each directive folder under `<pack_dir>/directives/`, run `packverb capability-check <directive_dir>`. Any violation aborts the install with the violating path surfaced to the user.
5. **Diff-before-exec.** For each directive that would install:
   - If a directive with the same id is already installed (cross-checked against `.governance/packs.lock`), show `diff -ruN <installed-directive-dir> <fetched-directive-dir>/<directive-id>` so the user sees exactly what `check.sh` code is about to start running on their commits.
   - If the directive is new, show the directive folder tree and the first 50 lines of `check.sh`.
   - **Confirm before proceeding.** This step is the user's last chance to reject.
6. **Install.** Reuse `install_directive_folder` from `governance/assets/packs/lib/install.sh`: copy each directive folder into `.governance/packs/<pack-id>/directives/<directive-id>/` minus the `evals/` directory, make scripts executable, lay down `install-assets/` where applicable. If any directive seeds an `install-asset/`, append the path to `install_assets_seeded` in `.governance/install.yaml`.
7. **Regenerate the hook dispatcher.** Reuse `generate_hooks_for_strategy` from `governance/assets/packs/lib/hooks.sh`, passing `install.yaml`'s `hook_strategy` value so husky and pre-commit.com installs land identical dispatchers (with populator wiring) rather than the validator-only shim that pre-issue-#101 husky paths produced. A pack add may introduce directives with new `hook:` declarations or new `hooks/<kind>.sh` populators — both are picked up automatically by the runtime-discovery loop in the regenerated dispatcher.
8. **Update the lockfile.** `packverb lock-add .governance/packs.lock <pack-id> --source gh --version <v> --ref <ref> --sha <sha> [--subpath <s>] [--min-kit <v>] --directive <id> ...` for each installed directive. The lockfile is the ownership ledger `uninstall` and `reset` trust for pack provenance.
9. **Report.** Print the pinned SHA, the directive ids installed, and the updated hook scripts.

Failure modes: any step 2–5 fails → abort with the fetched cache entry intact (future retries are cache-hits). Failure at step 6+ → roll back any already-copied directive folders before returning non-zero.

## `pack update [<pack-id>]`

Default target: every lockfile entry. With a `<pack-id>` argument, update only that pack. Repo-local packs (no `source:` in `pack.yaml`) are silently skipped — they have no upstream to re-pin.

> Distinct from `governance reset --pack <id>`: `pack update` re-pins to a **newer** SHA (picks up upstream changes); `reset` restores to the **currently pinned** SHA (undoes local drift). Reach for `pack update` when the user wants newer rules, `reset` when they want pristine ones. See [RESET_FLOW.md](RESET_FLOW.md).

1. Read the lockfile with `packverb lock-read`.
2. For each entry: re-fetch using the original `ref` string (which carries the floating rev like `@main`). If the resolved SHA matches the locked SHA → skip.
3. For entries whose SHA drifted, run validation + capability-check + diff-before-exec against the already-installed directive folders. The diff is the meat of this verb: the user sees precisely what changed in `check.sh` before the update lands.
4. On confirmation, overwrite the directive folders, regenerate the hook dispatcher, and `lock-add` the new SHA (upsert replaces the existing entry).

## `pack remove <pack-id>`

Works on installed (`source: gh`) and repo-local (`source: local`) packs.

1. Read `.governance/packs.lock`; confirm the pack id is present and is not `source: builtin`.
2. List the directives the lockfile attributes to this pack. Preview to the user which directive folders will be deleted.
3. On confirmation, for each directive:
   - `rm -rf .governance/packs/<pack-id>/directives/<directive-id>/`
   - Remove the directive's subsection from `CONSTITUTION.md` if present (ownership marker guarded — same discipline as `governance uninstall`).
4. Remove the pack's `pack.yaml` (and the now-empty `<owner>/<name>/` directory).
5. Regenerate the hook dispatcher so removed directives are no longer invoked.
6. `packverb lock-remove .governance/packs.lock <pack-id>`.
7. If any of the pack's directives seeded files listed in `.governance/install.yaml`'s `install_assets_seeded`, prune those entries.

Never remove `governance-kit/core` — its lockfile entry has `source: builtin` and the kit owns the source tree. Removing `governance-kit/core` directives is done with `governance directive remove <id>` instead.

## `pack list`

1. `packverb lock-list .governance/packs.lock --long` → `<id>\t<source>\t<version>\t<sha>\t<ref>`. The single source of truth — every kind of pack appears in this listing.
2. If `.governance/packs.lock` is missing, tell the user there is no governance setup and suggest `governance init`.

## Error discipline

- **No partial state.** Every mutation either lands fully or rolls back. The lockfile is written last in `pack add`, first in `pack remove`, so a crash mid-flight never leaves the lock claiming directives that aren't installed.
- **Network only inside verbs.** No directive's `check.sh` is allowed to fetch; all network I/O is gated through `packverb fetch`. The `network-at-commit-time` concern is structural — the hook dispatcher never invokes `packctl`.
- **SHA is the trust unit.** A tag can move. A branch can move. Only a resolved 40-char SHA is pinned. `pack update` is the supported path for picking up new SHAs.
