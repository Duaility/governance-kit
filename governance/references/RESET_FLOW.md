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
| Governance kit is missing (`CONSTITUTION.md` or `tests/governance/` absent) | Stop and tell the user to run `governance init` first — there is nothing to reset. |
| Install manifest (`.governance-kit/installed-packs.yaml`) is missing | Stop and tell the user. Reset depends on the manifest to know which directive came from which pack. The user's recovery path is `governance uninstall` then `governance init`. |
| `--directive <id>` names a directive not in the manifest | Stop. List the directives that *are* in the manifest. Suggest `--pack` or `--all` if the user meant something broader. |
| `--directive <id>` names a hand-authored directive | Stop. Hand-authored directives have no pristine source. Tell the user to use `governance directive remove <id>` to delete it, or `--all --drop-handauthored` to drop all hand-authored directives. |
| `--pack <id>` names a pack not in the manifest | Stop. List the installed packs. |
| Pinned SHA's pack content is missing from the cache | Re-fetch via `packverb fetch` using the original `ref@<sha>`. If the upstream pack is unreachable, abort — reset cannot work without the pristine source. |
| Working tree has uncommitted changes | Refuse, unless `--force` is set. The user reviews `git status` and either commits, stashes, or re-runs with `--force`. |
| The directive folder on disk is byte-identical to the pinned version | Skip it — there is nothing to restore. Note in the report. |
| Smoke test (`tests/governance/run.sh`) fails on the post-reset tree | Commit anyway. The amendment was destructive intent; failures on the *current* tree are pre-existing repo state, not reset bugs. Surface them in the report so the PR reviewer sees them. |
| Structured question tools are unavailable | Use short free-text questions. If no answer to a destructive prompt, stop — reset is destructive enough that assumed defaults are unsafe. |

---

## Activation flow

Run these steps in order. Do not skip steps unless noted.

### Step 1 — Verify the kit is installed

Run in parallel:
- `git rev-parse --show-toplevel` — confirm we're inside a git repo; capture the root.
- Read `<root>/.governance-kit/installed-packs.yaml`. Schema in [MANIFEST_SCHEMA.md](MANIFEST_SCHEMA.md).
- Check for `<root>/CONSTITUTION.md`.
- Check for `<root>/tests/governance/directives/`.
- Read `<root>/.governance/packs.lock` if present. Schema in [PACK_VERBS.md](PACK_VERBS.md).

If the manifest is missing, stop. Reset is **manifest-driven** — the
manifest is the ledger of what came from where, and there is no safe
heuristic fallback that can reconstruct pack provenance after the
fact. Tell the user to use `governance uninstall` + `governance init`
if they want a clean slate.

If the manifest is present but `version` ≠ `"1"`, fall back per
[MANIFEST_SCHEMA.md](MANIFEST_SCHEMA.md#legacy-fallback--v01--pre-pr-26-manifests)
and proceed. Log every assumption in the Step 7 report.

### Step 2 — Resolve scope

Parse exactly one of `--directive <id>`, `--pack <id>`, `--all`. If
none or more than one is supplied, stop and explain. If `--dry-run`
is also supplied, run every step except Step 6 (no commit) and
prefix the report's `Files changed:` lines with `would-`.

Build the in-scope directive set:

| Scope | In-scope set |
|---|---|
| `--directive <id>` | Just `<id>`. Refuse if `<id>` is hand-authored or not in the manifest. |
| `--pack <id>` | Every directive in `manifest.packs[<id>].directives[*].id`. Refuse if `<id>` is not in the manifest. |
| `--all` | Every directive in `manifest.packs[*].directives[*].id` across every pack. |

Build the **hand-authored set** by scanning
`tests/governance/directives/<id>/` for any folder whose `<id>` does
**not** appear under any `manifest.packs[*].directives[*].id`. These
are the directives a user added via `governance directive add`.

If `--drop-handauthored` is set, the hand-authored set is added to
the in-scope set with a `kind: drop` marker. Without `--drop-handauthored`,
the hand-authored set is preserved untouched and listed under
"Preserved" in the Step 7 report.

`--drop-handauthored` is only meaningful with `--all`. Reject it with
`--directive` or `--pack` (those scopes have no notion of "all
hand-authored directives in scope").

### Step 3 — Locate the pristine source for each in-scope directive

For each pack-sourced directive in scope:

1. Look up the pack id and the directive id in the manifest.
2. **`core` pack** — pristine source is the kit-bundled tree at
   `${KIT_ROOT}/governance/assets/packs/core/directives/<directive-id>/`.
   `KIT_ROOT` is the governance-kit checkout that is supplying the
   skill (resolve from the symlink target, not the consumer repo).
3. **Community pack** — read `.governance/packs.lock` to find the
   pinned SHA + ref. Pristine source is the cache at
   `${GOVERNANCE_KIT_HOME:-$HOME/.governance-kit}/packs/<pack-id-slug>@<sha>/directives/<directive-id>/`
   (where `/` in pack id is encoded as `__`).
4. If the cache entry is missing, re-fetch with
   `packverb fetch <ref>@<sha>` to repopulate. If the fetch fails,
   abort the entire reset — partial reset is not a supported state.

For hand-authored directives in the `--drop-handauthored` set, there
is no pristine source — they are deletions, not restorations. Mark
them `kind: drop`.

For each pack-sourced directive, also compute:

- The byte-diff between the installed `tests/governance/directives/<id>/`
  and the pristine source (excluding `evals/`, which is not
  installed). If empty, mark the directive `kind: skip` and
  surface that in the report.
- The current `CONSTITUTION.md` subsection for `<id>` (best-effort
  match by heading) and the pristine subsection from the pack's
  `directives/<id>/constitution.md`. Compute the byte-diff.
- Any per-directive loosen/grandfather state in
  `tests/governance/freshness.conf` or in-source waivers added during
  amend Step 4 (best-effort scan: comments matching
  `governance: allow-<id>`). Reset clears the freshness.conf
  thresholds for in-scope directives; in-source waivers are left
  alone (those are repo content, not directive state).

### Step 4 — Confirm

Refuse to proceed if `git status --porcelain` shows uncommitted
changes, unless `--force` was passed. Tell the user to commit, stash,
or re-run with `--force`.

Show the user the exact plan:

```
Reset scope: --all  (or: --directive <id>  /  --pack <id>)
Pinned-source resolution:
  core                     → kit-bundled tree
  duaility/agent-governance@5f3c... → cache: ~/.governance-kit/packs/duaility__agent-governance@5f3c.../

Directives to restore (kind: restore):
  constitution-exists    no diff — skipped
  no-secrets             check.sh: 12 +/-3, constitution.md: 4 +/-2
  agent-token-accounting check.sh: 0 +/-0, constitution.md: 1 +/-0

Directives to drop (kind: drop)         [--drop-handauthored]:
  custom-org-rule        hand-authored, no pristine source

Directives preserved (hand-authored, no flag):
  custom-org-rule

Other state to clear:
  tests/governance/freshness.conf entries for: no-secrets

Hook dispatcher: regenerate (a directive may declare a different `hook:` after restore)

Working tree: clean
```

For every restored directive, also print the diff that will be
applied (`diff -ruN <installed> <pristine>`) so the user sees the
exact code that will start running on their commits. This is the same
diff-before-exec discipline `pack add` and `pack update` use.

Ask for an explicit `yes` to execute. Silent acceptance must not
proceed — this is destructive, and reset is the kind of verb a user
runs when they are *recovering* from a state they did not understand,
so confirmation is part of the help.

### Step 5 — Execute the restore

For each directive marked `kind: restore`, in order:

1. **Replace the directive folder.** Remove
   `tests/governance/directives/<id>/` and copy the pristine
   `directives/<id>/` from the source resolved in Step 3, minus the
   `evals/` directory. This mirrors `install_directive_folder` from
   `governance/assets/packs/lib/install.sh` — same contract, same
   exclusions.
2. **Restore the CONSTITUTION subsection.** Read the pack's
   `directives/<id>/constitution.md`. If `CONSTITUTION.md` already
   has a subsection whose heading matches `<id>`, replace it
   in-place. If not, insert it alphabetically under the **Directives**
   section. Preserve everything else in the file verbatim — same
   discipline as amend Step 5(a).
3. **Clear loosen/grandfather state.** If the directive id appears in
   `tests/governance/freshness.conf`, remove its line. (In-source
   waiver comments are left alone; they are repo content.)

For each directive marked `kind: drop` (only present under
`--all --drop-handauthored`), in order:

1. `rm -rf tests/governance/directives/<id>/`.
2. Strip the matching subsection from `CONSTITUTION.md`. If no
   subsection is found, note it in the report.

For directives marked `kind: skip`, do nothing — they are already
identical to the pinned version.

After all directive-level changes:

4. **Regenerate the hook dispatcher.** Reuse the hook-generation
   path from `governance/assets/packs/lib/hooks.sh`. A reset can
   change which hooks are needed (e.g., a directive's `hook:` field
   may differ between the installed-and-amended version and the
   pinned version).
5. **Append an Evolution Log entry.** Use today's date from the
   session environment and the format the file already uses. Default
   shape per restored or dropped directive (group restores into one
   log entry per pack to keep the log readable):

   ```markdown
   - YYYY-MM-DD — @<git-config-user> — Reset directives from `<pack-id>` to pinned `<sha>` (`<id-1>`, `<id-2>`, ...).
   ```

   For dropped hand-authored directives:

   ```markdown
   - YYYY-MM-DD — @<git-config-user> — Drop hand-authored directives via `reset --drop-handauthored` (`<id-1>`, `<id-2>`, ...).
   ```

6. **Smoke-test.** Run `bash tests/governance/run.sh` against the
   restored tree. Capture exit code and output for the report. Do
   **not** abort on failure — the directive set is now pristine, and
   any failures are repo state the user needs to know about.

### Step 6 — Stage and commit

Use `git add -A tests/governance/directives CONSTITUTION.md` plus any
hook files the dispatcher regenerated and `tests/governance/freshness.conf`
if it changed. Run `git status` to confirm the staged set is exactly
the reset surface. Leave any unrelated changes unstaged.

Conventional Commits subject, matching the scope:

| Scope | Subject |
|---|---|
| `--directive <id>` | `chore(governance): reset <id> to <pack>@<short-sha>` |
| `--pack <id>` | `chore(governance): reset pack <id> to pinned <short-sha>` |
| `--all` | `chore(governance): reset all directives to pinned manifest state` |
| `--all --drop-handauthored` | `chore(governance): reset all directives + drop hand-authored` |

Append the issue anchor the repo's `conventional-commits` directive
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
- `Cleared:` `freshness.conf` entries removed
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
- [MANIFEST_SCHEMA.md](MANIFEST_SCHEMA.md) — install manifest reset reads.
- [PACK_VERBS.md](PACK_VERBS.md) — `pack update` is the verb to use when the user wants newer rules, not pristine ones.
- [DIRECTIVE_AMEND_FLOW.md](DIRECTIVE_AMEND_FLOW.md) — the verb reset is the inverse of for hand-authored amendments to pack-sourced directives.
- [UNINSTALL_FLOW.md](UNINSTALL_FLOW.md) — the verb to use when the user wants the install gone entirely, not just restored.
