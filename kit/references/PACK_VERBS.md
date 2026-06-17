<!-- last-verified: 2026-06-17 -->

# governance pack * — verb flows

Authoritative flow for the `governance pack {search,create,add,update,remove,list}` verbs. The unified `governance` skill dispatches to these flows; the supporting helpers live in the resolved kit's `packverb.py` (and reuse pack/directive manifest loaders from `packctl.py`).

> **Routed verb — runs from the repo-pinned kit (issue #194).** The thin `governance` skill carries no engines of its own. Before the first step, resolve the kit the repo pins via `bootstrap.py current` (see the installed skill's `SKILL.md` ("Delegate everything else to the pinned kit")), then run every `packverb.py` invocation below from the resolved kit's `<lib_dir>` and read its `catalog.community.json` / bundled `packs/` from `<assets_dir>`, reading this flow from `<references_dir>`. Where this doc writes `kit/assets/packs/lib/…` or `kit/assets/…`, read `<lib_dir>/…` / `<assets_dir>/…`. When the resolve is `refused` (no recorded pin, or offline + uncached), stop and route the user to `governance update` (online once) — the shim has nothing to run from (issue #198).

## Pack identity

Every pack — kit-bundled, community-installed, or hand-authored in this repo — lives at `.governance/packs/<owner>/<name>/` mirroring its GitHub identity at `github.com/<owner>/<name>`. Two-level on disk, no exceptions.

**Installed vs local.** Packs are distinguished only by their `pack.yaml`:

- **Installed packs** carry a `source:` field in `pack.yaml` and a lockfile entry with `source: gh`. The pack came from a fetched ref and `pack update` will re-pin it.
- **Repo-local packs** have no `source:` field in `pack.yaml`. They appear in the lockfile with `source: local` (no ref/sha) so `reset` can still find their directive list. `pack update` skips them.
- **The kit's bundled concern packs** (`governance-kit/{foundation,docs,commits,audit}`) are fetched the same way community packs are — from `gh:duaility/governance-kit/packs/<pack>@<rev>`. Their lockfile entries have `source: gh`. `pack update` re-pins them like any other community pack. (The retired `builtin` source type — phase 2 of #114, #117 — is no longer accepted by `lock-add`.)

The runner walks `.governance/packs/*/*/directives/*/check.sh` uniformly — it does not branch on installed-vs-local.

## Common concepts

### Pack refs

`gh:<owner>/<repo>[/<subpath>][@<rev>]`

- `subpath` points at the directory containing `pack.yaml` (for monorepos).
- `rev` can be a branch, tag, or 40-char SHA. `@main` at add-time is resolved to a concrete SHA and pinned in the lockfile.
- **Prefer a release tag over a floating branch.** A branch like `@main` resolves to whatever the tip is at add-time and silently tracks latest on every `pack update`. Packs cut with the release tooling publish prefixed tags (`@<name>/vX.Y.Z`, e.g. `gh:duaility/governance-kit/packs/commits@commits/v0.2.0`) — a readable, immutable pin that lets a repo choose and hold a specific version. See [VERSIONING.md](VERSIONING.md#tag-scheme). Pin a tag (or a SHA) for any repo that wants a deliberate version rather than the moving tip.

Resolve with `python packverb.py parse-ref <ref>`.

### Lockfile (`.governance/packs.lock`)

YAML, `version: "2"`. **Every** installed pack — community, kit-core, repo-local — has an entry. Each entry carries a `source` discriminator (`gh` | `local`) that decides which other fields are present. See [LOCK_SCHEMA.md](LOCK_SCHEMA.md) for the full contract.

```yaml
version: "2"
packs:
  - id: governance-kit/foundation
    version: "0.4"
    source: gh
    ref: gh:duaility/governance-kit/packs/foundation@foundation/v0.4.0
    sha: b33ec7a05be6c157a63b5f1a22d0102a1bf5a50c
    subpath: packs/foundation
    directives:
      - required-docs
      - internal-doc-links

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

`local` entries carry only `id` / `version` / `source` / `directives` — no `ref` / `sha` / `installed_at`, since there is no upstream to pin. `gh` entries carry the full pin set, including the kit's own `governance-kit/core`. The lockfile is the single source of truth for pack provenance; companion file [`install.yaml`](INSTALL_SCHEMA.md) carries the init receipt (hook strategy, ci_workflow, side effects) but no pack pin state.

Lockfile I/O goes through `packverb lock-{read,add,remove,list}`. Never hand-edit — the canonical key order and timestamp format are set by the helper.

### Shared cache

`${GOVERNANCE_KIT_HOME:-$HOME/.governance/cache}/packs/<pack-id-slug>@<sha>/`

`/` in the pack id is encoded as `__` on disk. Cache entries are SHA-addressed and immutable — hitting a SHA already in the cache skips the network round-trip. `packverb fetch <ref>` emits a JSON envelope with `sha`, `pack_dir`, `cache_dir`, `id`.

### Capability declarations (`reads:` / `writes:` in `directive.yaml`)

A directive that declares either list is asserting that its `check.sh` stays within those path globs. `packverb capability-check <directive-dir>` performs a static sweep (heuristic grep for quoted path-like tokens) and flags references outside declared bounds. A directive that declares **neither** opts out of the check — this keeps the field backward compatible with pre-v0.2 directives.

During `pack add`, every directive in the fetched pack is capability-checked before any files are written. A single violation aborts the install with no partial state.

## `pack search [query]`

1. Read the built-in community catalog at `kit/assets/catalog.community.json` (in the governance-kit checkout).
2. Run `packverb catalog-search <catalog> [query]`. Each line is `<id>\t<ref>\t<summary>`.
3. Render the table to the user.

If `query` is omitted, print the full catalog. If the catalog file is missing, fall back to telling the user no catalog is available.

## `pack create <name>`

Scaffolds an empty repo-local pack at `.governance/packs/<repo-owner>/<name>/` for hand-authored team-scoped directives. `<repo-owner>` is read from the top-level `owner:` field in `.governance/install.yaml` (set at `governance init` from the GitHub origin remote, or via `--owner` if `init` couldn't auto-detect).

1. **Pre-flight.** Refuse if `.governance/install.yaml` is absent (run `governance init` first), if a pack already exists at the target path, or if `<name>` is not a slug-safe lowercase token (`^[a-z0-9][a-z0-9._-]*$`).
2. **Resolve the target path.** Read the manifest's `owner:`. Compute the install path `.governance/packs/<owner>/<name>/`.
3. **Scaffold.** Create the directory and write a minimal `pack.yaml`, led by a pointer comment so an author who never opened the docs still lands on them:

   ```yaml
   # Authoring guide: kit/references/PACK_AUTHORING.md (layout, directive.yaml
   # schema, presets, capabilities, replaces/homonyms, the eval mandate).
   # lib.sh helpers available to every check.sh: kit/references/LIB_API.md
   # (set min_governance_kit to the newest helper your directives use).
   id: <owner>/<name>
   name: <human-readable name>
   version: "0.1"
   min_governance_kit: "0.2"
   description: <one-line description>
   author: <owner>
   ```

   No `source:` field — that is the marker that distinguishes a repo-local pack from an installed one. Also create an empty `directives/` subdirectory.

4. **Report.** Tell the user the pack is empty and that `governance directive add --pack <owner>/<name> <id>` is the next step. Point them at the authoring references for the full contract before they write a directive: [PACK_AUTHORING.md](PACK_AUTHORING.md) (pack-level schema, presets, capabilities, eval mandate), [DIRECTIVE_AUTHORING.md](DIRECTIVE_AUTHORING.md) (writing a good check), and [LIB_API.md](LIB_API.md) (the `lib.sh` helper surface).

`pack create` does **not** edit `.governance/install.yaml` or `.governance/packs.lock` or any hook scripts — the pack has no directives yet, so nothing to register or wire. The first `directive add --pack <owner>/<name>` is the step that adds the pack entry to `packs.lock` (with `source: local`) and regenerates hooks.

## Deterministic plan/apply

`pack add`, `pack update`, and `pack remove` follow the same terraform-style
split as `kit update` (issue #172): a pure **plan** that resolves everything
before any write, and a tested **apply** engine that executes it in one call.
The skill never hand-executes `cp` / `rm` / lockfile edits / hook regen.

- **Plan.** `packverb pack-plan {add|update|remove} <root> [<ref-or-id>] [--diff]`
  fetches (add/update), validates, capability-checks, classifies each directive
  `add`/`update`/`remove`, and — with `--diff` — emits the per-directive folder
  diff. It writes nothing to the working tree (fetch only populates the
  SHA-addressed cache). The engine lives in `packplan.py`.
- **Diff-before-exec.** The skill shows the plan's per-directive diffs and asks
  for an explicit `yes`. This is the user's last chance to reject, and the only
  step that stays the operator's.
- **Apply.** `packverb pack-apply {add|update|remove} <root> [<ref-or-id>]
  [--decisions <json>] [--dry-run] [--force]` recomputes the plan and executes:
  for add/update it installs the approved directive folders (`install.sh`
  `install_directive_folder` + `install_directive_assets`), records seeded files
  in `install_assets_seeded`, seeds each freshly-**added** configurable
  directive's user overlay `.governance/conf/<id>.conf` from the generic conf
  stub (never on update — an existing overlay is sacrosanct; the seeded paths are reported under
  `conf_seeded`, not the ledger), regenerates the hook dispatcher, and upserts
  the lockfile pin **last**; for remove it deletes the directive folders **and
  their `.governance/conf/<id>.conf` overlays**, strips each CONSTITUTION.md
  subsection (`docsurgery`), drops the empty pack root, regenerates hooks, and
  prunes the lock entry **first**. The engine lives in
  `packapply.py`. `--decisions {"<directive-id>": "skip"}` holds individual
  directives back; everything else installs by default.
- **One atomic commit.** The apply writes and reports; staging and the commit
  stay with the operator.

The apply enforces in code every gate that used to be prose: refuse on pack
validation or capability violations, on a dirty working tree without `--force`,
on removing `governance-kit/core` wholesale, on a pack absent from the lockfile.
Exit 0 applied/up-to-date/dry-run, 2 refused, 1 error. The dirty-tree gate is the
rollback story: every path written is tracked, so `git checkout -- . && git
clean -fd .governance/packs` restores a clean tree if a late step fails.

## `pack add <ref>`

1. **Parse + pre-flight.** `packverb parse-ref <ref>` to confirm the syntax, then refuse to run if:
   - not inside a git repo;
   - `CONSTITUTION.md` or `.governance/` are missing (run `governance init` first);
   - the ref's `@rev` is an unqualified branch name (`@main`, `@master`) → accept, but warn that the pinned SHA — not the branch — is what gets recorded.
2. **Plan.** `packverb pack-plan add <root> <ref> --diff` fetches into the shared
   cache, validates the pack, capability-checks every directive, and classifies
   each one `add` (new) or `update` (same id already installed) with its diff.
3. **Diff-before-exec.** Show the per-directive diffs (new directives show the
   full `check.sh` as an addition) and ask for an explicit `yes`.
4. **Apply.** `packverb pack-apply add <root> <ref>` installs the approved
   directive folders, lays down any `install-assets/` and records them in
   `install_assets_seeded`, seeds each configurable directive's
   `.governance/conf/<id>.conf` overlay from the generic conf stub (augment-only; reported under `conf_seeded`),
   regenerates the hook dispatcher (so new `hook:` declarations and
   `hooks/<kind>.sh` populators are picked up by the runtime-discovery loop),
   and upserts the lockfile pin with the resolved SHA.
5. **Report & commit.** The report carries the pinned SHA, the directive ids
   installed, and the regenerated hooks. Stage and commit.

A pack that fails validation or capability-check is refused before any write,
with the fetched cache entry left intact (future retries are cache-hits).

## `pack update [<pack-id>]`

Default target: every lockfile entry. With a `<pack-id>` argument, update only that pack. Repo-local packs (no `source:` in `pack.yaml`) are silently skipped — they have no upstream to re-pin.

> Distinct from `governance reset --pack <id>`: `pack update` re-pins to a **newer** SHA (picks up upstream changes); `reset` restores to the **currently pinned** SHA (undoes local drift). Reach for `pack update` when the user wants newer rules, `reset` when they want pristine ones. See [RESET_FLOW.md](RESET_FLOW.md).

1. **Plan.** `packverb pack-plan update <root> [<pack-id>] --diff` reads the
   lockfile, re-fetches each `gh` entry via its stored `ref`, and classifies any
   whose SHA drifted as `update` (SHA unchanged → `skip`; `local` packs → skipped
   with a reason). The per-directive diff is the meat of this verb.
2. **Diff-before-exec.** Show the diffs and ask for an explicit `yes`. If every
   pack's SHA is unchanged, `pack-apply` reports `up-to-date` and writes nothing.
   When the plan flags `config_drift` on an updated directive (its `defaults.conf`
   changed), tell the user the shipped defaults moved and that
   they should reconcile their `.governance/conf/<id>.conf` overlay by hand —
   `pack update` refreshes the pack-owned `defaults.conf` but never rewrites the overlay.
3. **Apply.** `packverb pack-apply update <root> [<pack-id>]` overwrites the
   drifted directive folders (refreshing their `defaults.conf`
   while leaving every `.governance/conf/<id>.conf` overlay untouched),
   regenerates the hook dispatcher, and upserts the new SHA into the lockfile.

## `pack remove <pack-id>`

Works on installed (`source: gh`) and repo-local (`source: local`) packs.

1. **Plan.** `packverb pack-plan remove <root> <pack-id>` (offline) reads the
   lockfile, lists the directive folders attributed to the pack, and flags which
   of their CONSTITUTION.md subsections are present. Preview the deletions.
2. **Apply.** On confirmation, `packverb pack-apply remove <root> <pack-id>`
   deletes each directive folder **and its `.governance/conf/<id>.conf` overlay**
   (pruning an emptied `.governance/conf/`), strips its CONSTITUTION.md subsection
   (`docsurgery`, exact-heading-matched so a prefix id never aliases), drops the
   now-empty `<owner>/<name>/` pack root, regenerates the hook dispatcher so
   removed directives are no longer invoked, and prunes the lock entry.

Never remove `governance-kit/core` wholesale — even though its lockfile entry is now `source: gh` like any other pack (post-#117), the kit pack is the bedrock of every governance-kit setup. `pack-apply remove governance-kit/core` is refused; remove individual core directives with `governance directive remove <id>` instead.

## `pack list`

1. `packverb lock-list .governance/packs.lock --long` → `<id>\t<source>\t<version>\t<sha>\t<ref>`. The single source of truth — every kind of pack appears in this listing.
2. If `.governance/packs.lock` is missing, tell the user there is no governance setup and suggest `governance init`.

## Error discipline

- **No partial state.** Every mutation either lands fully or rolls back. The lockfile is written last in `pack add`, first in `pack remove`, so a crash mid-flight never leaves the lock claiming directives that aren't installed.
- **Network only inside verbs.** No directive's `check.sh` is allowed to fetch; all network I/O is gated through `packverb fetch`. The `network-at-commit-time` concern is structural — the hook dispatcher never invokes `packctl`.
- **SHA is the trust unit.** A tag can move. A branch can move. Only a resolved 40-char SHA is pinned. `pack update` is the supported path for picking up new SHAs.
