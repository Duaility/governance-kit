# Uninstall matrix

The canonical table of every artifact `governance init` can produce, and the exact action `governance uninstall` takes against it under each mode. When `init` learns a new artifact class, this matrix must gain a matching row in the same PR.

Legend:

- **Path** — tracked location of the artifact.
- **Installed by** — the step / directive / flag in [INIT_FLOW.md](INIT_FLOW.md) that creates it.
- **Ownership evidence** — what proves the artifact is kit-owned. Reset refuses to delete without evidence.
- **Soft** — behavior in `soft` mode (remove managed surface, preserve user-authored).
- **Hard** — behavior in `hard` mode (remove everything the kit touched).
- **Dry-run** — always prints the would-be action and changes nothing. Omitted from the table (it is a projection, not a mode-specific decision).

## Core artifacts

| Path | Installed by | Ownership evidence | Soft | Hard |
|---|---|---|---|---|
| `CONSTITUTION.md` | Step 4 | manifest: `constitution: true` OR header sentinel from the template | delete | delete |
| `.governance/run.sh` | Step 5 | manifest: `tests_dir: .governance` OR byte match against shipped `assets/dot-governance/run.sh` | delete | delete |
| `.governance/lib.sh` | Step 5 | manifest OR byte match against shipped `assets/dot-governance/lib.sh` | delete | delete |
| `.governance/packs/<pack-id>/directives/<id>/` | Step 3 (`install_directive_folder`) | lockfile: directive listed under `packs[*].directives[*]` | delete recursively | delete recursively |
| `.governance/freshness.conf` | Step 3 (`doc-freshness` selected) | manifest: `doc_freshness: true` OR header comment from shipped template | delete | delete |
| `.github/workflows/governance.yml` | Step 7 | manifest: `ci_workflow: .github/workflows/governance.yml` OR filename match | delete | delete |
| `scripts/setup-clone.sh` | Step 6 Path A step 5 | manifest: `setup_clone_script: scripts/setup-clone.sh` OR byte match against shipped `assets/setup-clone.sh` | delete; `rmdir scripts/` only if empty (it often is not) | same |
| `.governance/install.yaml` | Step 3 (`write_installed_manifest`) | file exists | delete **last** (after it has been read); `rmdir .governance/` if empty | same |
| `.governance/packs.lock` | Step 3 (`packverb lock-add` per installed pack) | file exists | delete **last** (after it has been read); `rmdir .governance/` if empty | same |

## Hooks (Path A — `.githooks/`)

| Path | Installed by | Ownership evidence | Soft | Hard |
|---|---|---|---|---|
| `.githooks/pre-commit` | Step 6 (`generate_hooks`) | line-2 marker `# governance-kit:managed kit-version=…` | delete if marker present; else **collision** (Step 4 of reset) | same |
| `.githooks/commit-msg` | Step 6 | line-2 marker | delete if marker present; else **collision** | same |
| `.githooks/prepare-commit-msg` | Step 6 | line-2 marker | delete if marker present; else **collision** | same |
| `.githooks/post-commit` | Step 6 | line-2 marker | delete if marker present; else **collision** | same |
| `.githooks/pre-push` | Step 6 | line-2 marker | delete if marker present; else **collision** | same |
| `.githooks/<name>.userhook` | Step 6 Path A, wrap-collision resolution | sibling of a managed hook with matching name | rename `<name>.userhook` → `<name>` (restore user's original) | same |
| `<any-path>.pre-governance.bak` | Step 6 Path A, overwrite-collision resolution | filename suffix | preserve; report as orphaned backup | delete |

## Hooks (Path B — husky / pre-commit.com)

| Path | Installed by | Ownership evidence | Soft | Hard |
|---|---|---|---|---|
| `.husky/<hook>` entry calling `bash .governance/run.sh` | Step 6 Path B | manifest: `path_b.framework: husky` with entry list | remove only the kit's entry; leave the rest of the file intact | same |
| `.pre-commit-config.yaml` governance repo block | Step 6 Path B | manifest: `path_b.framework: pre-commit` with entry fingerprint | remove only the kit's block; leave other repos intact | same |

Reset **never** unsets `core.hooksPath` under Path B — that config was never set by bootstrap in this path.

## Git config

| Config | Mutated by | Ownership evidence | Soft | Hard |
|---|---|---|---|---|
| `core.hooksPath=.githooks` | Step 6 Path A step 4 | current value == `.githooks` | unset | unset |
| `core.hooksPath=<other>` | not us | value ≠ `.githooks` | leave alone; warn in report | same |

## AGENTS.md

| Target | Installed by | Ownership evidence | Soft | Hard |
|---|---|---|---|---|
| The block bounded by `<!-- governance: directives-to-follow -->` | Step 4b | marker present | strip block; byte-diff verify everything else is unchanged | same |
| The entire `AGENTS.md` file (only when bootstrap created it as a stub, Step 4b Case 2) | Step 4b Case 2 | manifest: `agents_md_created: true` | leave in place (user may have added content) | offer to delete; default to leave if the file has grown past the stub length |

If the byte-diff guard fires (any non-block line changed between read and write), **abort the whole reset** with a loud error. The surgical-edit guarantee is non-negotiable; a partial reset that mangled the user's doc is worse than no reset at all.

## Pack-seeded docs (`install-assets/`)

These are user-owned after the copy — bootstrap does not overwrite them in augment mode, and the user is expected to edit them after seeding.

| Path | Seeded by | Ownership evidence | Soft | Hard |
|---|---|---|---|---|
| `QUALITY.md` | `issues-tracked` directive | manifest: `install_assets_seeded: [QUALITY.md, …]` | preserve; list as orphaned in the report | delete |
| `COSTS.md` | `agent-token-accounting` directive | manifest: `install_assets_seeded: […, COSTS.md]` | preserve; list as orphaned in the report | delete |
| any future `install-assets/<file>` | any future directive | manifest | preserve | delete |

Hard mode requires an **extra confirm** on top of the Step 4 confirmation because deleting a user-edited file (likely with hand-written content by the time reset runs) is the most destructive action the skill can take.

## Out of scope

These are **not** kit-owned and reset must not touch them:

- Any file not listed above and not present in the install manifest.
- Uncommitted changes in the working tree.
- Untracked files (including `.env`, editor state, etc.).
- `~/.claude/skills/`, `~/.codex/skills/` symlinks — user-machine state, not repo state.
- The `.github/workflows/` directory itself (only the `governance.yml` file), the `.githooks/` directory itself (only the managed hooks inside), etc. — leave container directories alone unless they are empty after the delete.
