# `governance reset` — activation flow

The recovery flow for a repo whose installed directives have drifted
from their pinned source. Dispatched from [`../SKILL.md`](../SKILL.md).

`reset` is the inverse of `directive {add,modify,remove}` and
hand-edits to installed directive folders. For every directive that
was installed from a pack, `reset` restores the directive folder and
its `CONSTITUTION.md` subsection to the **pack version pinned in the
manifest** — *not* the latest upstream version (that is what `pack
update` is for). The pinned SHA is the trust unit.

`reset` is **not** `uninstall`. `uninstall` removes governance from
the repo entirely; `reset` keeps the install in place and restores
the rules to their pristine pinned state. Three scopes are supported:

| Scope flag | What gets restored |
|---|---|
| `--directive <id>` | One directive folder + its CONSTITUTION subsection. |
| `--pack <id>` | Every directive sourced from `<id>` (per the install manifest). |
| `--all` | Every pack-sourced directive in the install manifest. |

Exactly one scope flag is required. Reset will not run with no scope —
the cost of a misclicked default is too high.

Hand-authored directives (added via `governance directive add`, not
sourced from any pack) have no pristine version. By default `reset`
leaves them alone. Pass `--drop-handauthored` to also delete them in
the same commit.

## Interaction policy

| Situation | Action |
|---|---|
| Repo is not a git repo | Stop. `reset` operates on a tracked governance surface, which requires git. |
| Governance kit is missing (`CONSTITUTION.md` or `.governance/` absent) | Stop and tell the user to run `governance init` first — there is nothing to reset. |
| Pack lockfile (`.governance/packs.lock`) is missing | Stop and tell the user. Reset depends on the lockfile to know which directive came from which pack. The user's recovery path is `governance uninstall` then `governance init`. |
| `--directive <id>` names a directive not in the lockfile | Stop. List the directives that *are* in the lockfile. Suggest `--pack` or `--all` if the user meant something broader. |
| `--directive <id>` names a hand-authored directive in a `source: local` pack | The directive folder *is* its own pristine source. Reset preserves it untouched (it is not pack-sourced — there is no upstream to restore from). Use `governance directive remove <id>` to delete, or `--all --drop-handauthored` to drop all repo-local directives. |
| `--pack <id>` names a pack not in the lockfile | Stop. List the installed packs. |
| Pinned SHA's pack content is missing from the cache | Re-fetch via `packverb fetch` using the original `ref@<sha>`. If the upstream pack is unreachable, abort — reset cannot work without the pristine source. |
| Working tree has uncommitted changes | Refuse, unless `--force` is set. The user reviews `git status` and either commits, stashes, or re-runs with `--force`. |
| The directive folder on disk is byte-identical to the pinned version | Skip it — there is nothing to restore. Note in the report. |
| Smoke test (`.governance/run.sh`) fails on the post-reset tree | Commit anyway. The amendment was destructive intent; failures on the *current* tree are pre-existing repo state, not reset bugs. Surface them in the report so the PR reviewer sees them. |
| Structured question tools are unavailable | Use short free-text questions. If no answer to a destructive prompt, stop — reset is destructive enough that assumed defaults are unsafe. |

---

## Deterministic plan/apply

`reset` follows the same terraform-style split as `kit update` and the `pack`
verbs (issue #172): a pure **plan** and a tested **apply** engine. The skill
never hand-executes `rm` / `cp` / CONSTITUTION edits / hook regen.

- **Plan.** `packverb reset-plan {directive|pack|all} <root> [<target>]
  [--drop-handauthored] [--diff]` resolves the in-scope directive set, locates
  each one's **pinned** pristine source (re-fetching the lockfile SHA into the
  cache if missing), classifies it `restore` / `skip` (byte-identical) / `drop`,
  and with `--diff` emits the per-directive `installed → pristine` folder diff.
  It writes nothing. Engine: `resetplan.py`.
- **Diff-before-exec.** The skill shows the diffs and asks for an explicit `yes`.
- **Apply.** `packverb reset-apply {directive|pack|all} <root> [<target>]
  [--drop-handauthored] [--dry-run] [--force] [--date YYYY-MM-DD] [--author <u>]`
  recomputes the plan and executes: restore folders via `copy_tree_without_evals`,
  replace/insert CONSTITUTION subsections via `docsurgery`, drop hand-authored
  directives (under `--drop-handauthored`), regenerate the hook dispatcher, append
  one Evolution Log entry per pack, and smoke-test. Engine: `resetapply.py`.
- **One atomic commit.** The apply writes and reports; the commit stays with the
  operator (who supplies `--date`/`--author` for the log entry, and the `(#N)`
  anchor on the commit).

The apply enforces in code every gate that was prose: refuse when the lockfile is
missing (reset is lockfile-driven), when the scope resolves to nothing, on a
dirty tree without `--force`. It leaves `.governance/conf/` untouched
(user-owned per-directive configuration, not pinned per-directive state). Exit 0
applied/no-op/dry-run, 2 refused, 1 error.

---

## Activation flow

Run these steps in order. Do not skip steps unless noted.

### Step 1 — Verify the kit is installed

Run in parallel:
- `git rev-parse --show-toplevel` — confirm we're inside a git repo; capture the root.
- Read `<root>/.governance/packs.lock`. Schema in [LOCK_SCHEMA.md](LOCK_SCHEMA.md). Source of truth for pack provenance.
- Read `<root>/.governance/install.yaml` for `hook_strategy` and `tests_dir`. Schema in [INSTALL_SCHEMA.md](INSTALL_SCHEMA.md).
- Check for `<root>/CONSTITUTION.md`.
- Check for `<root>/.governance/packs/<owner>/<repo>/directives/`.

If the lockfile is missing, stop. Reset is **lockfile-driven** — the
lockfile is the ledger of what came from where, and there is no safe
heuristic fallback that can reconstruct pack provenance after the
fact. Tell the user to use `governance uninstall` + `governance init`
if they want a clean slate.

If the lockfile is present but `version` ≠ `"2"`, fall back per
[LOCK_SCHEMA.md](LOCK_SCHEMA.md#forward-compatibility) (or
[INSTALL_SCHEMA.md](INSTALL_SCHEMA.md#legacy-fallback--v01--v2-manifests) when
the legacy v2 single-file manifest is present) and proceed. Log every
assumption in the Step 7 report.

### Step 2 — Resolve scope

Parse exactly one of `--directive <id>`, `--pack <id>`, `--all`. If
none or more than one is supplied, stop and explain. If `--dry-run`
is also supplied, run every step except Step 6 (no commit) and
prefix the report's `Files changed:` lines with `would-`.

Build the in-scope directive set:

| Scope | In-scope set |
|---|---|
| `--directive <id>` | Just `<id>`. Refuse if `<id>` is not in the lockfile or belongs to a `source: local` pack. |
| `--pack <id>` | Every directive in `lock.packs[<id>].directives`. Refuse if `<id>` is not in the lockfile or has `source: local` (no upstream to restore from). |
| `--all` | Every directive in `lock.packs[*].directives` across every pack with `source: gh`. |

Build the **hand-authored set** as the union of every directive id under packs
with `source: local`. These are the directives a user added via
`governance directive add` into a repo-local pack.

If `--drop-handauthored` is set, the hand-authored set is added to
the in-scope set with a `kind: drop` marker. Without `--drop-handauthored`,
the hand-authored set is preserved untouched and listed under
"Preserved" in the Step 7 report.

`--drop-handauthored` is only meaningful with `--all`. Reject it with
`--directive` or `--pack` (those scopes have no notion of "all
hand-authored directives in scope").

### Step 3 — Plan

Run `packverb reset-plan <scope> <root> [<target>] [--drop-handauthored] --diff`.
The plan locates each in-scope directive's **pinned** pristine source — the cache
at `${GOVERNANCE_KIT_HOME:-$HOME/.governance/cache}/packs/<pack-id-slug>@<sha>/<subpath>/directives/<id>/`
(re-fetched from the lockfile `ref@<sha>` if the cache entry is missing; a fetch
failure aborts the plan, never a partial reset), classifies each one `restore` /
`skip` (byte-identical to pinned) / `drop` (hand-authored, only under
`--drop-handauthored`), and emits the per-directive `installed → pristine` folder
diff. The plan writes nothing.

### Step 4 — Confirm (diff-before-exec)

Show the user the plan: the scope, the pinned-source resolution, the
restore/skip/drop classification, and — for each restored directive — the diff
that will be applied so they see the exact code that will start running on their
commits. This is the same diff-before-exec discipline `pack add`/`pack update`
use. Ask for an explicit `yes`. Silent acceptance must not proceed — reset is
destructive and is the verb a user reaches for while *recovering* from a state
they did not understand.

### Step 5 — Apply

Run `packverb reset-apply <scope> <root> [<target>] [--drop-handauthored]
[--force] --date <YYYY-MM-DD> --author <git-user>`. The engine recomputes the
plan and, in one call: replaces each restored directive folder from the pinned
source (minus `evals/`), replaces/inserts its CONSTITUTION.md subsection from the
pinned `constitution.md`, drops hand-authored directories + strips their
subsections (under `--drop-handauthored`), regenerates the hook dispatcher (a
restore can change which hooks are needed), appends one Evolution Log entry per
pack (`- <date> — @<author> — Reset directives from \`<pack-id>\` to pinned
\`<sha>\` (...)`), and smoke-tests without aborting on failure. It refuses a dirty
tree without `--force` and leaves `.governance/conf/` untouched (a dropped
directive's overlay is removed under `--drop-handauthored`, mirroring `pack remove`).
`--dry-run` resolves everything and writes nothing.

### Step 6 — Stage and commit

Stage the reset surface from the report (`.governance/packs/<pack-id>/directives`,
`CONSTITUTION.md`, the regenerated hook files). Run `git status` to confirm the
staged set is exactly the reset surface. Leave any unrelated changes unstaged.

Conventional Commits subject, matching the scope:

| Scope | Subject |
|---|---|
| `--directive <id>` | `chore(governance): reset <id> to <pack>@<short-sha>` |
| `--pack <id>` | `chore(governance): reset pack <id> to pinned <short-sha>` |
| `--all` | `chore(governance): reset all directives to pinned manifest state` |
| `--all --drop-handauthored` | `chore(governance): reset all directives + drop hand-authored` |

Append the issue anchor the repo's `commit-message-format` directive
requires (`(#N)`). If the user did not name an issue, ask for it as
a blocking input — same discipline as `directive *`.

The commit body should include:
- The scope (verbatim CLI args).
- The pack/SHA pairs that drove each restore.
- A bullet list of restored directives + dropped directives + skipped directives.
- The smoke-test result (exit code + first failure if any).
- Any material assumptions (e.g., legacy-manifest fallback, cache miss + re-fetch).

Pass the message via a HEREDOC. Do **not** push; pushing is the
user's decision, same as every other writer in this skill.

If `--dry-run` was set, skip Step 6 entirely. The report says what
*would* have been committed.

### Step 7 — Report

Print:
- `Scope:` `--directive <id>` | `--pack <id>` | `--all` | `--all --drop-handauthored`
- `Source of truth:` `manifest v1` (or `manifest v0.1 — heuristic fallback`)
- `Restored:` list of `<id>` with their `<pack>@<sha>` source
- `Dropped:` list of hand-authored `<id>` (only under `--drop-handauthored`)
- `Preserved:` list of hand-authored `<id>` (default behavior)
- `Skipped:` list of `<id>` already byte-identical to pinned
- `Cleared:` a dropped directive's `.governance/conf/<id>.conf` overlay removed (under `--drop-handauthored`)
- `Hook dispatcher:` `regenerated` | `unchanged`
- `Smoke test:` `pass` | `fail (exit <code>): <first failing directive>`
- `Committed:` `<short-sha> <conventional-commit subject>` (or `would-commit:` under `--dry-run`)
- `Assumptions:` any material assumptions, or `none`
- `Next:` `git push` to open the PR-review cycle

## Required final output

Every successful `reset` run should include:

- `Scope:` the scope acted on
- `Restored:` directive list
- `Smoke test:` result
- `Committed:` short-sha + subject (or `would-commit:` under `--dry-run`)
- `Assumptions:` any, or `none`
- `Next:` `git push`

---

## Key design principles

- **Pinned, not latest.** Reset restores to the SHA in the lockfile,
  not the upstream HEAD. Picking up upstream changes is `pack update`'s
  job — keeping these orthogonal means a user who reaches for `reset`
  during an incident does not silently land newer pack code in the
  same commit.
- **Manifest-driven.** Pack provenance comes from the install manifest
  and the lockfile. Reset refuses to run without them — there is no
  safe heuristic for "which pack did this directive come from" after
  the fact.
- **One commit, one diff.** Like every other writer in this skill,
  reset stages the full restore surface and commits it atomically.
  PR review is the review layer; the commit body carries the diff
  context the reviewer needs.
- **Hand-authored is preserved by default.** A user who runs `reset
  --all` to recover from a botched amend is not asking to lose the
  rules they wrote themselves. `--drop-handauthored` is opt-in and
  scoped to `--all`.
- **Diff-before-exec.** Step 4 prints the per-directive diff before
  any file is touched. The same discipline that protects `pack add`
  protects `reset` — the user sees the code about to start running
  on their commits.
- **Refuse on a dirty tree.** Reset is destructive enough that
  surprising the user by overwriting their in-progress work is a
  worse failure mode than asking them to commit or stash first.
  `--force` exists for the rare case the user knows what they are
  doing.
- **No partial state.** A reset either lands fully or rolls back. If
  the cache fetch for one pack fails, abort before any file is
  written.
- **Idempotent.** Running `reset --all` on a repo that is already
  pristine is a successful no-op — every directive is `kind: skip`,
  the report is empty, no commit is made.

## References

- [`../SKILL.md`](../SKILL.md) — verb dispatch.
- [VERBS.md](VERBS.md) — per-verb reference.
- [LOCK_SCHEMA.md](LOCK_SCHEMA.md) — pack lockfile (the pin record reset reads first).
- [INSTALL_SCHEMA.md](INSTALL_SCHEMA.md) — install receipt (hook strategy + identity reset reads).
- [PACK_VERBS.md](PACK_VERBS.md) — `pack update` is the verb to use when the user wants newer rules, not pristine ones.
- [DIRECTIVE_AMEND_FLOW.md](DIRECTIVE_AMEND_FLOW.md) — the verb reset is the inverse of for hand-authored amendments to pack-sourced directives.
- [UNINSTALL_FLOW.md](UNINSTALL_FLOW.md) — the verb to use when the user wants the install gone entirely, not just restored.
