# `governance uninstall` — activation flow

The 6-step recipe `governance uninstall` runs. Dispatched from
the installed skill's `SKILL.md`.

> **Runs from a resolved kit tree (issue #198).** The thin `governance` skill
> carries no uninstall engine. It resolves the repo's pinned kit via
> `bootstrap.py current` (or the latest release via `bootstrap.py resolve`
> when no pin is recorded) and runs every `packverb` invocation below from
> that tree's `<lib_dir>`. Offline with nothing cached → the shim refuses
> with connect-once guidance.

`uninstall` is the inverse of `governance init` — for every side-effect `init` can produce, `uninstall` knows how to reverse it, and it refuses to touch anything it does not recognize as kit-owned.

Three source-of-truth layers drive what `uninstall` deletes, in priority order:

1. **Install state pair** at `.governance/install.yaml` (init receipt) and `.governance/packs.lock` (pack pin record) — the authoritative record of packs, directives, and paths `init` installed.
2. **Ownership marker** — `.githooks/` dispatchers carry the line-2 marker `# governance-kit:managed kit-version=<v>` — the same shape runtime templates (`run.sh`, `lib.sh`, `governance.yml`, `enable-governance.sh`) carry. The marker is a contract that the file is regeneratable, and symmetrically, safe to delete.
3. **Heuristic fallback** — when neither file pair nor marker is present but governance artifacts are detected, `uninstall` defaults to **dry-run** and requires explicit opt-in before deleting anything.

Leaving intact: files the user owns (pack-seeded docs like `QUALITY.md` in soft mode), hooks without the ownership marker (those belong to someone else), user-authored content inside `AGENTS.md` (only the marker-bounded directive block is stripped), and every uncommitted change in the working tree.

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

## Deterministic plan/apply

`uninstall` follows the same terraform-style split as `kit update`, `pack *`, and
`reset` (issue #172): a pure **plan** that surveys + classifies, and a tested
**apply** engine that executes the reversal. The skill never hand-executes the
`rm` / `mv` / `git config` / AGENTS.md edits.

- **Plan.** `packverb uninstall-plan <root> [--mode soft|hard|dry-run]` surveys
  the repo against the UNINSTALL_MATRIX, classifies it (`fully-installed` /
  `partial` / `unmarked-collision` / `none-detected`), records the source-of-truth
  (`manifest` / `heuristic`), and emits the exact deletion/restore inventory:
  marked hooks, `.userhook` restores, unmarked-hook collisions, the AGENTS.md
  marker state, tree deletes, Path-B entries, seeded docs, and `.pre-governance.bak`
  backups. It writes nothing. Engine: `uninstallplan.py`.
- **Apply.** `packverb uninstall-apply <root> [--mode soft|hard|dry-run]
  [--allow-heuristic]` recomputes the plan and executes the reversal in the fixed
  Step-5 order. Engine: `uninstallapply.py`. It does no destructive git ops and no
  commit.
- The apply enforces in code: `none-detected` → idempotent no-op; an
  `unmarked-collision` → refuse and surface the colliding hooks (never delete
  somebody else's hook); a missing manifest (heuristic) → refuse a destructive
  mode unless `--allow-heuristic` (silence is not consent; `--mode dry-run` is
  always allowed). Soft preserves seeded docs + backups; hard deletes them. Exit 0
  applied/no-op/dry-run, 2 refused.

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
  - `.governance/conf/` (per-directive user overlays)
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
| `soft` (default) | Remove managed surface (constitution, tests, workflow, managed hooks, manifest, AGENTS.md block). | Pack-seeded `install-assets/` docs (`QUALITY.md`, others; a legacy pre-#201 install may also carry `COSTS.md`). Backup `.bak` files. |
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
```

The preview is informational. Ask for an explicit `yes` to execute — this is destructive, and the cost of a misclicked default is higher than the friction of an extra keystroke.

**Unmarked-collision resolution.** When Step 2 found hook collisions, resolve each one before the main confirmation:

| Choice | Action |
|---|---|
| `leave alone` (default) | Keep the hook as-is. `uninstall` does not touch it. Note in the report. |
| `delete with backup` | Move the hook to `<path>.pre-reset.bak`, then remove the reference from `core.hooksPath` if it becomes empty. |
| `restore wrap` (only if a `<name>.userhook` sibling exists) | Delete the managed hook (if any) and rename `<name>.userhook` back to `<name>`. |

### Step 5 — Execute (via `uninstall-apply`)

Run `packverb uninstall-apply <root> --mode <soft|hard|dry-run> [--allow-heuristic]`.
The engine deletes and restores in this fixed order (deliberate — the
`.governance/` pair is removed last, so its absence is the idempotency signal for
subsequent runs):

1. **Hooks first.** Delete `.githooks/<name>` that carry the line-2 marker; rename `<name>.userhook` siblings back to `<name>`. Unmarked hooks are never touched — they tripped the `unmarked-collision` refusal in the plan.
2. **Git config.** Unset `core.hooksPath` only if it still equals `.githooks` (Path A). A user-redirected value is left alone and reported.
3. **AGENTS.md surgery** (`docsurgery.strip_marker_block`). Paired markers → delete the inclusive span + the trailing blank line. Opening-marker-only → strip to the next `^## ` heading and record the heuristic in `Assumptions:`. Span removal is byte-safe by construction (every other line is preserved verbatim). A manifest `agents_md_created: true` stub is left in place (deleting a possibly-grown doc stays the operator's call).
4. **Tree deletes.** `CONSTITUTION.md`, the CI workflow, the enable-governance script.
5. **Path B.** Remove only the governance entries (`.governance/run.sh` invocations) from the husky / `pre-commit` config, using the manifest's `path_b.entries`.
6. **Seeded docs.** Soft: preserve + report as orphaned. Hard: delete every path the manifest lists under `install_assets_seeded`.
7. **Backups.** Soft: preserve `*.pre-governance.bak`. Hard: delete them.
8. **`.governance/` last.** Remove the directory recursively (manifest pair, runtime, packs, configs go with it).

All deletes are plain `rm` against tracked paths. The engine never runs `git clean`, `git reset --hard`, or stash, and never commits — same discipline as `init`. `--mode dry-run` reports the would-be actions and writes nothing.

**Leave changes unstaged.** The user reviews the diff and commits intentionally. The pre-commit hook is also gone now, so `git diff` is the only guard rail — the desired end state of an uninstall.

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
