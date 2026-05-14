# Install schema (`.governance/install.yaml`)

`governance init` writes `.governance/install.yaml` after seeding directives. This file is the **install receipt** — it records the choices `init` made and the side effects it left in the repo. It does **not** record what packs are installed: that lives in [`.governance/packs.lock`](LOCK_SCHEMA.md).

`uninstall` reads it as the authoritative ownership ledger to know what to delete. `reset` reads it for hook-strategy and identity context, but reaches into `packs.lock` for pack provenance.

## v3 shape (current)

This is what `write_installed_manifest` in `governance/assets/packs/lib/install.sh` emits today.

```yaml
version: "3"
generated_at: 2026-04-29T16:45:34Z
owner: acme                      # GitHub owner of the bootstrapping repo (lowercased)
repo: widgets                    # GitHub repo name of the bootstrapping repo (lowercased)
kit_version: "0.3"               # KIT_VERSION that did the install or last `kit update` (optional within v3 — absent on pre-tracking installs)
hook_strategy: githooks          # or: husky | pre-commit
constitution: true               # CONSTITUTION.md was written at repo root
ci_workflow: .github/workflows/governance.yml
tests_dir: .governance
agents_md_snippet: true          # true when the marker-bounded block was inserted
agents_md_created: false         # true only when bootstrap Step 4b Case 2 ran (stub)
enable_governance_script: scripts/enable-governance.sh  # Path A only; omitted under Path B
install_assets_seeded:           # files seeded by directives' install-assets/
  - QUALITY.md
  - COSTS.md
collisions: []                   # empty list when Step 6 resolved nothing
# path_b: block below only present when hook_strategy != githooks
```

`owner:` and `repo:` are the GitHub-shaped identity of this repo, lowercased. They define **the default repo-local pack** at `.governance/packs/<owner>/<repo>/` — the pack `governance directive add` lands directives into when no `--pack` is given. They are detected at `governance init` from `git remote get-url origin`; if origin is missing or non-GitHub, `init` prompts and persists the answer here.

When `collisions` or `path_b` are non-empty, they look like:

```yaml
collisions:
  - path: .githooks/pre-commit
    resolution: wrap             # or: skip | overwrite
    extra: .githooks/pre-commit.userhook  # userhook path (wrap) or backup path (overwrite)
path_b:
  framework: husky               # or: pre-commit
  entries:
    - file: .husky/pre-commit
      fingerprint: bash .governance/run.sh
```

Notes on the emitted shape:

- `version` is a **quoted string** (`"3"`), not a bare integer. YAML treats both identically, but fixture byte-diffs depend on the exact form the emitter writes.
- `kit_version` is the `KIT_VERSION` constant ([packctl.py](../assets/packs/lib/packctl.py)) of the kit that did the install or last `kit update`. It mirrors the per-file `kit-version=<v>` marker each kit-owned file carries (runtime templates and hook dispatchers alike). The markers are the source of truth; this field is a cache so common `kit update` paths can read one file instead of scanning every managed file. If the manifest is missing or the field is absent, `kit update` reconstructs it by scanning markers (taking the min `kit-version=`) and rewrites the field on success. The field is **optional within v3** — repos bootstrapped before it existed simply omit it; `kit update` treats absence as "pre-tracking install" and offers to record the current `KIT_VERSION` on the next run. Quoted-string form (`"0.2"`).
- `collisions[*]` uses a flat `extra` field, not named `backup_path` / `userhook_path` sub-fields. Interpret `extra` based on `resolution`: `wrap` ⇒ userhook sibling path; `overwrite` ⇒ `.pre-governance.bak` backup path; `skip` ⇒ no extra.
- Keys appear in the emitter's fixed order (metadata → flags → `install_assets_seeded` → `collisions` → optional `path_b`). Do not rely on order when parsing, but **do** preserve it when regenerating fixtures — byte-diffs matter for the eval harness.
- The `packs:` block from v2 is gone. Pack pin state — id, version, source, ref, sha, directives — lives in `.governance/packs.lock`. See [LOCK_SCHEMA.md](LOCK_SCHEMA.md).

## Fields uninstall relies on

| Field | Purpose in uninstall |
|---|---|
| `owner` / `repo` | The repo's GitHub identity. Used to resolve the default repo-local pack at `.governance/packs/<owner>/<repo>/` for cleanup ordering and to prompt the user before deleting hand-authored packs. |
| `kit_version` | Read-only for uninstall — surfaced in the report so the user knows which kit version touched the repo last. Not used to gate behavior. |
| `constitution` | Whether to remove `CONSTITUTION.md`. |
| `ci_workflow` | Path of the workflow file to delete. |
| `tests_dir` | Parent directory whose `run.sh`, `lib.sh`, and empty-after-cleanup shell are removed. |
| `install_assets_seeded` | The paths soft mode preserves and hard mode deletes. |
| `agents_md_created` | In hard mode, only delete `AGENTS.md` entirely if this is `true`. |
| `agents_md_snippet` | Whether to attempt the marker-bounded-block strip. If `false`, skip the AGENTS.md step. |
| `hook_strategy` | Selects the uninstall branch (`.githooks/*` vs. `path_b.entries` editing). |
| `enable_governance_script` | Path A only — path of the one-time per-clone enable script to delete (bootstrap Step 6 Path A step 5). Omitted under Path B. |
| `path_b.framework` / `path_b.entries` | Which framework config to edit instead of `.githooks/`, and which entries to remove. |
| `collisions[*]` | Which hooks came from Path A wrap/overwrite resolution; drives *restore wrap* and *delete with backup* offers. |

The list of installed pack/directive folders comes from [`packs.lock`](LOCK_SCHEMA.md), not this file. Fields not listed here are reserved for future use; uninstall ignores them.

## Fields reset relies on

`reset` reads almost nothing from this file — pack provenance lives in `packs.lock`. Reset reads:

| Field | Purpose in reset |
|---|---|
| `hook_strategy` | Determines which dispatcher to regenerate after a successful restore. |
| `tests_dir` | Where to place `run.sh` / `lib.sh` if a restore puts them back. |

Everything else reset needs (which packs exist, which directives belong to each, where to copy from) it gets from `packs.lock`.

## Fields `kit update` relies on

`kit update` is the only verb that writes through this file beyond init. It reads:

| Field | Purpose in kit update |
|---|---|
| `kit_version` | The cached version pin. Compared against the `KIT_VERSION` of the kit on PATH to determine whether the repo is up-to-date, behind (forward update), or ahead (refused — no silent downgrades). Absence means pre-tracking install; the verb scans per-file markers to reconstruct the pin, falling back to "pre-tracking install" only if no versioned marker is found. |
| `hook_strategy` | Selects the dispatcher generator (`.githooks/`, `.husky/`, or `.governance/hooks/`) when regenerating hooks. |
| `tests_dir` | Where `run.sh` / `lib.sh` live, for the per-file diff-and-copy. |
| `enable_governance_script` | Path A only — the destination path for the `enable-governance.sh` re-sync. Omitted under Path B (the verb skips that file pair). |
| `ci_workflow` | The destination path for the `governance.yml` re-sync. |

After a successful run, `kit update` rewrites the manifest with the new `kit_version` and unchanged everything else. See [UPDATE_FLOW.md](UPDATE_FLOW.md).

## Legacy fallback — v0.1 / v2 manifests

Repos bootstrapped before v3 carry an older, flatter manifest. Common shapes:

- **v0.1** (pre-PR-#26): no `version` key, packs nested as a map.
- **v2** (PR-#26 through this change): single combined `installed-packs.yaml` with metadata **and** `packs:` block.

When `uninstall` reads a manifest whose top-level `version` field is not `"3"`:

1. Log a one-line warning: *"manifest schema v<found>; falling back to heuristic detection for fields absent in this version"*.
2. Treat any embedded `packs:` block as an authoritative directive list (still trustworthy — this is what the repo actually has installed). For v2 the block is in this same file; for v3 the block is gone and the user must have a corresponding `packs.lock`.
3. Fill every missing field from **heuristic evidence** (see below), with each assumption called out in the Step 6 report's `Assumptions:` line.
4. Do **not** refuse the uninstall. The alternative is a repo the user cannot uninstall, which is worse than a partial clean-up they can finish by hand.

`reset` handles legacy manifests differently: it can still parse a v2 `packs:` block and proceed, but if neither the legacy block nor a v3 `packs.lock` is present, it stops and tells the user to use `uninstall` + `init` instead. Reset is recovery, not archaeology.

## When the manifest is missing entirely

A repo where `install.yaml` was never written, or was deleted manually, is a **legitimate uninstall target** and a **conditionally-legitimate `kit update` target**. Pack provenance cannot be reconstructed without the manifest pair, so `reset` still refuses and routes the user to `uninstall` + `init`; `kit update` can reconstruct its single field of interest (`kit_version`) from per-file markers and proceeds when any kit-owned file carries a versioned `kit-version=` marker. The fallback order for `uninstall`:

1. **Heuristic detection.** Look for the artifacts in the uninstall matrix by exact path. For each one found, require independent ownership evidence before deleting:
   - Hooks: line-2 `governance-kit:managed` marker.
   - `CONSTITUTION.md`: the template's header sentinel line (look for the literal phrase from `assets/CONSTITUTION.template.md`'s lead paragraph).
   - `.governance/run.sh` / `lib.sh`: byte-for-byte match against the shipped copies in `governance/assets/dot-governance/`.
   - Pack directive folders under `.governance/packs/<pack-id>/directives/`: presence of a `check.sh` shebang line identical to the shipped one is a weak signal; absence of user-added sibling files is a stronger one.
   - `AGENTS.md`: see *opening-marker-only* heuristic below.
2. **Default mode = dry-run.** Present the plan and list each artifact with the evidence that classified it as kit-owned. Require explicit user confirmation to proceed in a destructive mode.
3. **No manifest, no artifacts ⇒ `none-detected`.** Report "nothing to remove" and exit.

### AGENTS.md opening-marker-only heuristic

The v1 snippet template (`governance/assets/AGENTS.snippet.md`) ships with **both** `<!-- governance: directives-to-follow -->` and `<!-- /governance: directives-to-follow -->` markers, so `uninstall` can strip the block by paired markers. Earlier bootstrap runs inserted only the opening marker.

When an AGENTS.md file contains the opening marker but **not** the closing one:

1. Classify as `directive-block-unbounded` at **lower confidence**.
2. Strip from the opening marker line up to (but not including) the next `^## ` heading, or to end-of-file if no such heading follows.
3. Require an **extra confirm** in Step 4 ("block boundary is inferred, not marker-bounded — proceed?"). A silent accept does not count.
4. Still run the byte-diff guard on everything outside the inferred block; abort if anything non-block-adjacent changed.
5. Record the heuristic in the Step 6 report's `Assumptions:` line.

The heuristic path must **never** guess. If evidence for a given path is ambiguous (e.g., `CONSTITUTION.md` exists but was rewritten by hand), surface it as a collision in the Step 4 confirmation and default to "leave alone".

## Forward compatibility

The manifest is versioned. `version: "3"` is the current shape. `uninstall` accepts unknown fields silently and unknown `version` values with a warning ("manifest written by a newer bootstrap; proceeding with best-effort field mapping"). A `version` mismatch never causes `uninstall` to refuse — the alternative is a repo the user cannot uninstall, which is worse than a partial clean-up they can finish by hand. `reset` is stricter: an unknown `version` triggers the same legacy-fallback path described above and may refuse if pack provenance cannot be read.
