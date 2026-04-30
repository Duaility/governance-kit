# `governance uninstall` — activation flow

The 6-step recipe `governance uninstall` runs. Dispatched from
[`../SKILL.md`](../SKILL.md).

`uninstall` is the inverse of `governance init` — for every side-effect `init` can produce, `uninstall` knows how to reverse it, and it refuses to touch anything it does not recognize as kit-owned.

Three source-of-truth layers drive what `uninstall` deletes, in priority order:

1. **Install state pair** at `.governance/install.yaml` (init receipt) and `.governance/packs.lock` (pack pin record) — the authoritative record of packs, directives, and paths `init` installed.
2. **Ownership marker** — `.githooks/` dispatchers carry the line-2 marker `# governance-kit:managed pack-version=<v> generated=<date>`. The marker is a contract that the file is regeneratable, and symmetrically, safe to delete.
3. **Heuristic fallback** — when neither file pair nor marker is present but governance artifacts are detected, `uninstall` defaults to **dry-run** and requires explicit opt-in before deleting anything.

Leaving intact: files the user owns (pack-seeded docs like `QUALITY.md` / `COSTS.md` in soft mode), hooks without the ownership marker (those belong to someone else), user-authored content inside `AGENTS.md` (only the marker-bounded directive block is stripped), and every uncommitted change in the working tree.

## Interaction policy

| Situation | Action |
|---|---|
| Repo is not a git repo | Stop. `uninstall` operates on a tracked governance surface, which requires git. |
| Manifest present, artifacts present, markers consistent | Proceed. Manifest is the source of truth. |
| Manifest missing, artifacts detected (`CONSTITUTION.md` + `.governance/` + marked hooks) | Force **dry-run** by default. Require explicit opt-in before executing a destructive mode. |
| Manifest present but `version` ≠ `"3"` (legacy v0.1 / v2 shapes) | Fall back to heuristic detection for fields absent in older shapes. Proceed; log every assumption in the Step 6 report. See [INSTALL_SCHEMA.md](INSTALL_SCHEMA.md#legacy-fallback--v01--v2-manifests). |
| `AGENTS.md` has the opening `<!-- governance: directives-to-follow -->` but **not** the matching closing marker | Classify as `directive-block-unbounded`. Strip from the opening marker up to the next `^## ` heading. Require an extra confirm (the block boundary is inferred, not marker-bounded). See [INSTALL_SCHEMA.md](INSTALL_SCHEMA.md#agentsmd-opening-marker-only-heuristic). |
| Manifest missing, no artifacts detected | Report "nothing to remove" and exit. Idempotent no-op. |
| Unmarked hook at a path we would delete | Stop. Offer the same three choices `init`'s collision flow offers (wrap, skip, overwrite with backup) — but here they are *restore wrap*, *leave alone*, *delete with backup*. |
| `core.hooksPath` points somewhere other than `.githooks/` | Do **not** unset. The user changed it themselves. Warn in the report. |
| Structured question tools are unavailable | Ask concise free-text questions. If no answer, stop — `uninstall` is destructive enough that assumed defaults are unsafe. |

---

## Activation flow

Run these steps in order. Do not skip steps unless noted.

### Step 1 — Survey the repository

Before touching anything, run these in parallel:

- `git rev-parse --show-toplevel` to confirm this is a git repo and find the root.
- Read `.governance/install.yaml` if present (schema in [INSTALL_SCHEMA.md](INSTALL_SCHEMA.md)) and `.governance/packs.lock` if present (schema in [LOCK_SCHEMA.md](LOCK_SCHEMA.md)).
- `ls -la` at the root and at `.githooks/`, `.github/workflows/`, `.governance/`.
- Check for each artifact in the uninstall matrix (see [UNINSTALL_MATRIX.md](UNINSTALL_MATRIX.md)):
  - `CONSTITUTION.md`
  - `.governance/run.sh`, `.governance/lib.sh`, every `.governance/packs/<pack-id>/directives/<id>/`
  - `.governance/freshness.conf`
  - `.github/workflows/governance.yml`
  - `.governance/install.yaml`
  - `.governance/packs.lock`
  - `.githooks/pre-commit`, `.githooks/commit-msg`, `.githooks/prepare-commit-msg`, `.githooks/post-commit`, `.githooks/pre-push`
  - `.githooks/*.userhook` (Path A wrap leftovers)
  - `<any>.pre-governance.bak` files (Path A overwrite backups)
  - `AGENTS.md` and whether it contains `<!-- governance: directives-to-follow -->`
  - `.husky/` or `.pre-commit-config.yaml` with governance entries (Path B)
- Read `git config --get core.hooksPath` (empty string is fine — it means no override).

**Hook-marker survey.** For each `.githooks/<name>` that exists, read line 2 and match against the regex `^# governance-kit:managed `. Record `marker=present|absent` per file. Do the same for any legacy `.git/hooks/<name>` — a marker there is a bug but still signals ownership.

Record findings as a structured inventory for Step 2.

### Step 2 — Classify repository state

Based on the survey, pick exactly one classification:

| Classification | Conditions | Implication |
|---|---|---|
| `fully-installed` | Manifest present; every artifact it names exists; every managed hook carries the marker. | Safe path. All modes available. |
| `partial` | Manifest present but some listed artifacts are missing, OR manifest missing but ≥ 2 artifacts present with markers intact. | Proceed with the subset found. Note discrepancies in the report. |
| `unmarked-collision` | A managed-path hook exists **without** the marker, OR a manifest-listed file has been heavily modified since install (best-effort detection). | Stop before executing. Resolve collisions per Step 4. |
| `none-detected` | No manifest, no marked hooks, no `CONSTITUTION.md`, no `.governance/`. | Report "nothing to remove" and exit. |

Idempotency contract: `none-detected` is the expected outcome of running `uninstall` on a repo that never had governance installed, or on one where `uninstall` already ran. Treat it as success, not an error.

### Step 3 — Mode selection

Ask the user one `AskUserQuestion` with three mutually exclusive options:

| Mode | Intent | Leaves untouched |
|---|---|---|
| `dry-run` | Print the plan, change nothing. | Everything. |
| `soft` (default) | Remove managed surface (constitution, tests, workflow, managed hooks, manifest, AGENTS.md block). | Pack-seeded `install-assets/` docs (`QUALITY.md`, `COSTS.md`, others). Backup `.bak` files. |
| `hard` | Remove **everything** governance-kit touched, including seeded docs, `.bak` backups from overwrite-collision resolution, and an AGENTS.md stub if manifest records it as kit-created. | Uncommitted work in the working tree. |

Forced overrides:

- If Step 2 classified the repo as `unmarked-collision`, the only legal option is to resolve collisions first (Step 4) — do not present `soft` or `hard` yet.
- If the manifest is missing AND artifacts are detected, lock the default to `dry-run` and require the user to **explicitly** pick `soft` or `hard` to proceed. A silent acceptance of the default (no answer) must not execute a destructive mode.

### Step 4 — Confirmation

Show the user the exact plan before acting. Build a structured preview from the inventory in Step 1 and the uninstall matrix:

```
Files to delete:
  CONSTITUTION.md
  .governance/run.sh
  .governance/lib.sh
  .governance/packs/<pack-id>/directives/<directive-a>/ (4 files)
  .governance/packs/<owner>/<repo>/directives/<directive-b>/           (4 files)
  .github/workflows/governance.yml
  .governance/install.yaml
  .governance/packs.lock
  .githooks/pre-commit       (marker present)
  .githooks/commit-msg       (marker present)

Hooks to restore (Path A userhook wraps):
  .githooks/pre-commit.userhook → .githooks/pre-commit  [original filename]

AGENTS.md edit:
  strip block bounded by <!-- governance: directives-to-follow --> … <!-- /governance: directives-to-follow -->
  byte-diff verify: ensure every other line is identical pre/post

Git config:
  unset core.hooksPath  (current value: .githooks — will reset)

Seeded docs (preserved in soft mode; deleted in hard):
  QUALITY.md
  COSTS.md
```

The preview is informational. Ask for an explicit `yes` to execute — this is destructive, and the cost of a misclicked default is higher than the friction of an extra keystroke.

**Unmarked-collision resolution.** When Step 2 found hook collisions, resolve each one before the main confirmation:

| Choice | Action |
|---|---|
| `leave alone` (default) | Keep the hook as-is. `uninstall` does not touch it. Note in the report. |
| `delete with backup` | Move the hook to `<path>.pre-reset.bak`, then remove the reference from `core.hooksPath` if it becomes empty. |
| `restore wrap` (only if a `<name>.userhook` sibling exists) | Delete the managed hook (if any) and rename `<name>.userhook` back to `<name>`. |

### Step 5 — Execute

Delete and restore in this order (deliberate — the manifest is read last so its absence is the idempotency signal for subsequent runs):

1. **Hooks first.** Delete `.githooks/<name>` that carry the marker. Rename `<name>.userhook` siblings back to `<name>`. Never delete unmarked hooks — those were resolved in Step 4 or skipped.
2. **Git config.** If `core.hooksPath` still equals `.githooks`, run `git config --unset core.hooksPath`. If the value changed since install or was cleared manually, leave it alone and note in the report.
3. **AGENTS.md surgery.** Read the file and remove the directive block.
   - **Paired-marker path (v1 directive):** locate `<!-- governance: directives-to-follow -->` and `<!-- /governance: directives-to-follow -->` and delete the span (inclusive of both marker lines, plus the blank line immediately after the closing marker if present).
   - **Opening-marker-only path (pre-PR-#26 directive):** if only the opening marker is present, strip from that line up to — but not including — the next `^## ` heading (or end-of-file). Record the heuristic in the report's `Assumptions:` line.
   - Run a byte-diff on the remainder and abort the whole `uninstall` if any non-block line changed.
   - If the manifest records `agents_md_created: true` (init's Step 4b Case 2), offer to delete the file entirely in hard mode; keep it in soft mode.
4. **Tree deletes.** `CONSTITUTION.md`, `.governance/` (recursive), `.github/workflows/governance.yml`.
5. **Path B.** If the repo uses husky or `pre-commit`, remove only the governance entries from the framework's config file (keep every other hook intact). Use the manifest's `path_b_entries` list if present; otherwise grep for entries that invoke `.governance/run.sh`.
6. **Seeded docs.** In soft mode: preserve, report as orphaned. In hard mode: delete `QUALITY.md`, `COSTS.md`, and every path the manifest lists under `install_assets_seeded`.
7. **Backups.** In soft mode: preserve `*.pre-governance.bak`, report them. In hard mode: delete them.
8. **Manifest pair.** Delete `.governance/install.yaml` and `.governance/packs.lock`. If `.governance/` is now empty, `rmdir` it.

All deletes use plain `rm` / `git rm` against tracked paths. Never `git clean`, `git reset --hard`, or stash — those can touch the user's uncommitted work.

**Leave changes unstaged.** Do not `git commit`. The user reviews the diff and commits intentionally, same discipline as `governance init`. The pre-commit hook is also gone now, so `git diff` is the only guard rail — which is the desired end state of an uninstall.

### Step 6 — Report

Print a concise summary:

- `Mode:` `dry-run` | `soft` | `hard`.
- `Classification:` `fully-installed` | `partial` | `unmarked-collision` | `none-detected`.
- `Source of truth:` `manifest` | `heuristic`.
- `Files deleted:` list.
- `Files preserved:` seeded docs, user-authored backups, unmarked hooks.
- `Hooks restored:` `<name>.userhook` → `<name>` pairs, or `none`.
- `AGENTS.md:` `directive block stripped` | `stub deleted (hard mode)` | `left untouched (no marker)` | `skipped — non-block content would have changed`.
- `Git config:` `core.hooksPath unset` | `left as-is — pointed at <path>`.
- `Collisions:` per-file resolution, or `none`.
- `Assumptions:` any heuristic fallback used, or `none`.
- `Next command:` `git status` — let the user see exactly what changed before they commit.

Do **not** commit the changes. The user's first commit after an uninstall is the one that ratifies it; they own it.

---

## Required final output

Every successful `uninstall` run should leave the user with a summary that includes:

- `Mode:` the mode actually executed (dry-run leaves the rest of the summary prefixed "would-").
- `Source of truth:` `manifest` (authoritative) or `heuristic` (fallback, with a note on each decision).
- `Files deleted:` file-backed list.
- `Files preserved:` seeded docs, unmarked hooks, backups.
- `AGENTS.md:` verb describing the edit outcome.
- `Collisions:` resolution per file, or `none`.
- `Assumptions:` material assumptions, or `none`.
- `Next command:` `git status`

---

## Key design principles

- **Symmetry with `init`.** Every file `init` can create, `uninstall` can remove. Every config mutation `init` performs, `uninstall` can reverse. If `init` adds a new artifact class, `uninstall` must learn it in the same PR.
- **Manifest first, marker second, heuristic last.** The manifest is authoritative; the ownership marker is the contract; heuristics are a fallback and degrade to dry-run by default.
- **Never delete without ownership evidence.** An unmarked hook at a path we would manage is somebody else's file — surface it, do not touch it. The cost of a false-positive delete is high; the cost of an extra confirm prompt is low.
- **Dry-run is a real mode, not a debug affordance.** When the state is ambiguous (manifest missing, artifacts present), dry-run is the default and destructive modes must be explicitly opted into. Silence is not consent.
- **No destructive git ops.** No `git clean`, no `git reset --hard`, no stash. `uninstall` touches tracked governance artifacts and one git config — nothing else.
- **AGENTS.md edits are surgical.** Strip only the marker-bounded block. Byte-diff the rest. Abort if anything else changed — there is no safe way to guess the user's intent inside their own doc.
- **Idempotent.** Running `uninstall` on a repo with nothing installed is a success, not an error. Running it twice in a row is identical to running it once.
- **Leave the result unstaged.** Same discipline as `init` — the user's commit is intentional, not automatic.
- **Report what was skipped and why.** Seeded docs in soft mode, unmarked hooks, a `core.hooksPath` the user redirected — these are deliberate preservations, not oversights. Surface them so the user does not discover them later and wonder.

## References

- [UNINSTALL_MATRIX.md](UNINSTALL_MATRIX.md) — canonical table of every artifact the kit can produce and the exact `uninstall` action under soft vs. hard mode.
- [INSTALL_SCHEMA.md](INSTALL_SCHEMA.md) — schema of `.governance/install.yaml` (the init receipt) that `uninstall` reads, plus the fallback heuristic when the manifest is absent.
- [LOCK_SCHEMA.md](LOCK_SCHEMA.md) — schema of `.governance/packs.lock` (the pack pin record) that `uninstall` reads in tandem.
