<!-- last-verified: 2026-04-24 -->

# governance pack * — verb flows

Authoritative flow for the `governance pack {search,add,update,remove,list}` verbs. The unified `governance` skill dispatches to these flows; the supporting helpers live in `governance-bootstrap/assets/packs/lib/packverb.py` (and reuse pack/rule manifest loaders from `packctl.py`).

## Common concepts

### Pack refs

`gh:<owner>/<repo>[/<subpath>][@<rev>]`

- `subpath` points at the directory containing `pack.yaml` (for monorepos).
- `rev` can be a branch, tag, or 40-char SHA. `@main` at add-time is resolved to a concrete SHA and pinned in the lockfile.

Resolve with `python packverb.py parse-ref <ref>`.

### Lockfile (`.governance/packs.lock`)

YAML, `version: "1"`. One entry per installed non-core pack:

```yaml
version: "1"
packs:
  - id: acme/soc2
    ref: gh:acme/soc2-pack@main
    sha: 5f3c...
    subpath: ""
    min_governance_kit: "0.2"
    installed_at: 2026-04-24T12:00:00Z
    rules:
      - soc2-audit-logs
      - soc2-retention
```

**`core` is not recorded here** — it ships in-tree and its rules are owned by the install manifest (`.governance-kit/installed-packs.yaml`). The lockfile is the community-pack pin record; together they cover every installed rule.

Lockfile I/O goes through `packverb lock-{read,add,remove,list}`. Never hand-edit — the canonical key order and timestamp format are set by the helper.

### Shared cache

`${GOVERNANCE_KIT_HOME:-$HOME/.governance-kit}/packs/<pack-id-slug>@<sha>/`

`/` in the pack id is encoded as `__` on disk. Cache entries are SHA-addressed and immutable — hitting a SHA already in the cache skips the network round-trip. `packverb fetch <ref>` emits a JSON envelope with `sha`, `pack_dir`, `cache_dir`, `id`.

### Capability declarations (`reads:` / `writes:` in `rule.yaml`)

A rule that declares either list is asserting that its `check.sh` stays within those path globs. `packverb capability-check <rule-dir>` performs a static sweep (heuristic grep for quoted path-like tokens) and flags references outside declared bounds. A rule that declares **neither** opts out of the check — this keeps the field backward compatible with pre-v0.2 rules.

During `pack add`, every rule in the fetched pack is capability-checked before any files are written. A single violation aborts the install with no partial state.

## `pack search [query]`

1. Read the built-in community catalog at `extensions/catalog.community.json` (in the governance-kit checkout).
2. Run `packverb catalog-search <catalog> [query]`. Each line is `<id>\t<ref>\t<summary>`.
3. Render the table to the user.

If `query` is omitted, print the full catalog. If the catalog file is missing, fall back to telling the user no catalog is available.

## `pack add <ref>`

1. **Parse + pre-flight.** `packverb parse-ref <ref>` to confirm the syntax, then refuse to run if:
   - not inside a git repo;
   - `CONSTITUTION.md` or `tests/governance/` are missing (run `governance init` first);
   - the ref's `@rev` is an unqualified branch name (`@main`, `@master`) → accept, but warn that the pinned SHA — not the branch — is what gets recorded.
2. **Fetch.** `packverb fetch <ref>` clones the requested rev shallowly into the shared cache, drops `.git`, and returns the resolved SHA + `pack_dir`.
3. **Validate pack.** `packverb validate-pack <pack_dir>` — rejects on missing required fields, preset cycles, `min_governance_kit > KIT_VERSION`, bad capability fields, etc.
4. **Capability-check every rule.** For each rule folder under `<pack_dir>/rules/`, run `packverb capability-check <rule_dir>`. Any violation aborts the install with the violating path surfaced to the user.
5. **Diff-before-exec.** For each rule that would install:
   - If a rule with the same id is already installed (from `.governance-kit/installed-packs.yaml`), show `diff -ruN <installed-rule-dir> <fetched-rule-dir>/<rule-id>` so the user sees exactly what `check.sh` code is about to start running on their commits.
   - If the rule is new, show the rule folder tree and the first 50 lines of `check.sh`.
   - **Confirm before proceeding.** This step is the user's last chance to reject.
6. **Install.** Reuse `install_rule_folder` from `governance-bootstrap/assets/packs/lib/install.sh`: copy each rule folder into `tests/governance/rules/<rule-id>/` minus the `evals/` directory, make scripts executable, lay down `install-assets/` where applicable.
7. **Regenerate the hook dispatcher.** Reuse the hook-generation path from `governance-bootstrap/assets/packs/lib/hooks.sh`. A pack add may introduce rules with `hook: commit-msg` or `hook: prepare-commit-msg` that require adding dispatchers.
8. **Update the lockfile.** `packverb lock-add .governance/packs.lock <pack-id> <ref> <sha> [--subpath <s>] [--min-kit <v>] --rule <id> ...` for each installed rule.
9. **Update the install manifest.** Append the new rules to `.governance-kit/installed-packs.yaml` under the pack id, using the existing `write_installed_manifest` contract. The manifest is the ownership ledger `uninstall` trusts.
10. **Report.** Print the pinned SHA, the rule ids installed, and the updated hook scripts.

Failure modes: any step 2–5 fails → abort with the fetched cache entry intact (future retries are cache-hits). Failure at step 6+ → roll back any already-copied rule folders before returning non-zero.

## `pack update [<pack-id>]`

Default target: every lockfile entry. With a `<pack-id>` argument, update only that pack.

1. Read the lockfile with `packverb lock-read`.
2. For each entry: re-fetch using the original `ref` string (which carries the floating rev like `@main`). If the resolved SHA matches the locked SHA → skip.
3. For entries whose SHA drifted, run validation + capability-check + diff-before-exec against the already-installed rule folders. The diff is the meat of this verb: the user sees precisely what changed in `check.sh` before the update lands.
4. On confirmation, overwrite the rule folders, regenerate the hook dispatcher, and `lock-add` the new SHA (upsert replaces the existing entry).

## `pack remove <pack-id>`

1. Read `.governance-kit/installed-packs.yaml` and `.governance/packs.lock`; confirm the pack id exists in both.
2. List the rules the manifest attributes to this pack. Preview to the user which rule folders will be deleted.
3. On confirmation, for each rule:
   - `rm -rf tests/governance/rules/<rule-id>/`
   - Remove the rule's invariant subsection from `CONSTITUTION.md` if present (ownership marker guarded — same discipline as `governance uninstall`).
4. Regenerate the hook dispatcher so removed rules are no longer invoked.
5. `packverb lock-remove .governance/packs.lock <pack-id>`.
6. Rewrite the installed-packs manifest without the pack block.

Never remove `core` — it is not recorded in the lockfile and has no `pack remove` path. Removing `core` rules is done with `governance rule remove <id>` instead.

## `pack list`

1. If `.governance/packs.lock` exists, `packverb lock-list <lockfile>` — prints `<id>\t<sha>\t<ref>`.
2. Also print the `core` pack line from `.governance-kit/installed-packs.yaml` so the user sees the full picture.
3. If neither file exists, tell the user there are no installed packs and suggest `governance init`.

## Error discipline

- **No partial state.** Every mutation either lands fully or rolls back. The lockfile is written last in `pack add`, first in `pack remove`, so a crash mid-flight never leaves the lock claiming rules that aren't installed.
- **Network only inside verbs.** No rule's `check.sh` is allowed to fetch; all network I/O is gated through `packverb fetch`. The `network-at-commit-time` concern is structural — the hook dispatcher never invokes `packctl`.
- **SHA is the trust unit.** A tag can move. A branch can move. Only a resolved 40-char SHA is pinned. `pack update` is the supported path for picking up new SHAs.
