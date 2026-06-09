# `governance kit update` — activation flow

Re-syncs the kit-runtime files installed at `governance init` against the kit
version currently loaded as the skill. Dispatched from
[`../SKILL.md`](../SKILL.md).

`kit update` is the answer to "a new governance-kit was published — how do I
pull it into this repo?". It is **disjoint** from `pack update`:

| Verb | Updates |
|---|---|
| `pack update` | Directive folders + `packs.lock` SHA pins (rules content). |
| `kit update` | The runtime artifacts `init` originally seeded (`run.sh`, `lib.sh`, `enable-governance.sh`, `governance.yml`, hook dispatchers) and the `kit_version` recorded in `install.yaml`. |

A single user-facing run can chain both with `--with-packs`. The default
behavior is kit-runtime only — pack updates are reviewed separately because
their diffs land directive code that runs on commits.

## Why a separate verb

`init` is one-shot: it copies `dot-governance/run.sh`, `lib.sh`, the
`enable-governance.sh` template, and `governance.yml` into the target repo and
never tracks them again. If a later kit version ships a smarter runner or a
fixed dispatcher generator, the consumer's repo silently keeps the old
copies. This verb closes the loop:

1. Records `kit_version` in `install.yaml` so future runs know what version
   did the install (or last update).
2. Diffs each kit-owned runtime file against the current kit assets and
   prompts per-file before writing.
3. Regenerates the hook dispatcher so directive `hook:` declarations and
   populator wiring catch up to the new generator.

## Interaction policy

| Situation | Action |
|---|---|
| Repo is not a git repo | Stop. The verb operates on a tracked governance surface. |
| Governance kit is missing (`CONSTITUTION.md` or `.governance/` absent) | Stop and tell the user to run `governance init` first. |
| `install.yaml` is missing **but** runtime files carry versioned `kit-version=` markers | Reconstruct the version pin by scanning runtime markers (take the min `kit-version=`); proceed. The verb rewrites `install.yaml` from the reconstructed version on success — the manifest is a cache, not the source of truth. Surface this in `Assumptions:`. |
| `install.yaml` is missing **and** no runtime file carries a versioned marker | Stop and route the user to `governance uninstall` + `governance init` — there is no recoverable version pin. |
| `install.yaml.kit_version` is absent | Treat the install as pre-tracking; offer to record the current `KIT_VERSION` and proceed (this is the upgrade path for repos bootstrapped before the field existed). |
| `install.yaml.kit_version` ≥ kit's `KIT_VERSION` | No-op for the kit-runtime; if `--with-packs`, fall through to pack update. Report `kit: up-to-date`. |
| Working tree has uncommitted changes | Refuse, unless `--force` is set. The user reviews `git status`, then commits / stashes / re-runs with `--force`. |
| A managed file was hand-edited (line-2 marker present, byte-diff non-empty) | Show the diff and ask per-file: `apply` / `skip` / `overwrite-with-backup` (writes `<path>.pre-update.bak` then overwrites). Default `apply`. |
| A managed file is missing the line-2 marker | Treat as user-owned. Skip silently and surface in the report under `Skipped (unmanaged):`. |
| `--with-packs` was passed | After the kit-runtime block, run `pack update` against every `source: gh` entry in the lockfile. Each pack still uses its own diff-before-exec confirmation. |
| Structured question tools are unavailable | Use short free-text prompts. If no answer to a destructive prompt, stop. |

---

## Activation flow

Run these steps in order. Do not skip steps unless noted.

### Step 1 — Verify the install

Run in parallel:
- `git rev-parse --show-toplevel` — confirm git repo; capture the root.
- Read `<root>/.governance/install.yaml`. Schema in [INSTALL_SCHEMA.md](INSTALL_SCHEMA.md).
- Read `<root>/.governance/packs.lock` (only required when `--with-packs`).
- Resolve `KIT_VERSION` from the kit currently loaded:
  ```sh
  uv run --quiet --isolated --with PyYAML python \
      governance/assets/packs/lib/packctl.py kit-version
  ```

If `install.yaml` is missing, attempt **manifest reconstruction from
markers** before giving up:

```sh
source governance/assets/packs/lib/install.sh
versions=()
for f in "$root"/.governance/run.sh \
         "$root"/.governance/lib.sh \
         "$root"/.github/workflows/governance.yml \
         "$root"/scripts/enable-governance.sh \
         "$root"/.githooks/pre-commit; do
    v=$(read_marker_kit_version "$f" 2>/dev/null) || continue
    [[ -n "$v" ]] && versions+=("$v")
done
```

Take the minimum (semver-aware) of `versions[]` as the reconstructed
`installed_kit_version`. The marker is the per-file version pin; taking
the min reflects that an update only lands when *every* managed file
catches up. If any versioned marker is found, proceed — the manifest
will be rewritten on success and a `Assumptions:` line records the
reconstruction.

If `install.yaml` is missing **and** no runtime file carries a
versioned `kit-version=` marker, stop. The user has no recoverable
version pin (truly pre-marker install or all managed files were
hand-stripped). Recovery: `governance uninstall` + `governance init`.

### Step 2 — Resolve the version delta

Read `installed_kit_version` from `install.yaml.kit_version`. Three cases:

| Case | Action |
|---|---|
| Field is absent (`null`) | Pre-tracking install. Treat `installed_kit_version` as `"0"` for the purpose of reporting; proceed. |
| `installed_kit_version` < `KIT_VERSION` | Forward update. Continue to Step 3. |
| `installed_kit_version` == `KIT_VERSION` | No-op for kit-runtime. If `--with-packs`, jump to Step 6. Else report `kit: up-to-date` and exit. |
| `installed_kit_version` > `KIT_VERSION` | Stop. The repo was last touched by a newer kit; running an older `kit update` against it would silently downgrade. The user's recovery path is to upgrade the kit on PATH (e.g., `uvx --reinstall …`) and re-run. |

Do **not** attempt a downgrade automatically. Downgrades have to be
explicit (`--allow-downgrade`, future flag) — silently rolling a runtime
file backwards under a manifest stamp the user already trusts is the kind
of footgun this verb exists to prevent.

### Step 3 — Inventory the managed files

Build the list of files this verb owns. Each entry pairs the kit asset
with the install destination, derived from `install.yaml`:

| Source (in kit) | Destination (in repo) | Marker |
|---|---|---|
| `assets/dot-governance/run.sh` | `<tests_dir>/run.sh` | `governance-kit:managed kit-version=<v>` in first 3 lines |
| `assets/dot-governance/lib.sh` | `<tests_dir>/lib.sh` | `governance-kit:managed kit-version=<v>` in first 3 lines |
| `assets/enable-governance.sh` | `<enable_governance_script>` (Path A only — field absent under Path B) | `governance-kit:managed kit-version=<v>` in first 3 lines |
| `assets/governance.yml` | `<ci_workflow>` | `governance-kit:managed kit-version=<v>` in first 3 lines |
| `assets/freshness.conf` | `<tests_dir>/freshness.conf` (only if the file already exists — `kit update` does not seed it) | None — user-tunable config; skip on diff |
| `assets/integrity.conf` | `<tests_dir>/integrity.conf` (only if the file already exists — `kit update` does not seed it) | None — user-tunable config; skip on diff |

**Marker shape.** The ownership marker is a `# governance-kit:managed`
comment within the file's leading comment block: line 2 for shebang
scripts (right after `#!/usr/bin/env bash`), line 1 for YAML and other
files without a shebang. The full form carries the version pin:

```
# governance-kit:managed kit-version=<v> generated=<YYYY-MM-DD>
```

Hook dispatchers carry the same form (kit-owned regenerable files all
share one marker shape). The `kit-version=<v>` token is the per-file
version pin — `kit update` reads it to compute drift; the manifest's
`kit_version` field is a cache that mirrors the markers. `generated=`
is informational and tracks the most recent stamp; do not treat it as
load-bearing.

**Pre-marker installs.** Three sub-cases, distinguished by what the
marker scan finds in each managed file:

| Marker on dest | Treatment |
|---|---|
| Present and versioned (`kit-version=<v>`) | Compare `<v>` to new `KIT_VERSION`; equal → skip, older → re-stamp + diff. |
| Present but bare (`# governance-kit:managed` with no `kit-version=`) | Treat as version-unknown but kit-owned. Apply forward in this run; the new stamp brings it under per-file pin tracking. |
| Absent | Treat as user-owned. Surface as `Skipped (unmanaged)` and offer the per-file `keep` / `apply anyway` / `overwrite-with-backup` choice. |

For each pair, compute:
- **Diff status:** byte-equal (`skip`), byte-different + versioned marker
  (`apply`), byte-different + bare marker (`apply` — re-stamp brings it
  under tracking), byte-different + marker absent (`unmanaged`),
  destination missing (`add`).
- **Diff text:** `diff -u <dest> <src-stamped>` for the user-visible
  plan, where `<src-stamped>` is the source template after
  `stamp_managed_marker` has applied the new `kit-version=` and today's
  date. This avoids spurious diff noise from the marker line.

### Step 4 — Confirm

Refuse to proceed if `git status --porcelain` shows uncommitted changes,
unless `--force` was passed.

Show the user the plan:

```
kit update: 0.2 → 0.3

Apply (diff to existing managed file):
  .governance/run.sh                 12 +/-3
  .githooks/pre-commit               <regenerated by hooks.sh — diff below>

Skip (already up-to-date):
  .governance/lib.sh
  .github/workflows/governance.yml

Skip (unmanaged — hand-edited or pre-marker):
  scripts/enable-governance.sh       diff: 8 +/-0  (line-2 marker absent)

Add (missing — will create):
  (none)

Hook dispatcher: regenerate (.githooks/{pre-commit,commit-msg,...})

[--with-packs not set; pack updates will not run this turn]

Working tree: clean
```

For every file in `Apply`, print the diff under the summary so the user
sees what is changing in `run.sh` etc. before any file is touched. Same
diff-before-exec discipline `pack add` and `reset` use.

For files in `Skip (unmanaged)`, offer **per-file** the three options:
- `keep` (default) — leave the file alone; report under `Skipped`.
- `apply anyway` — overwrite, no backup.
- `overwrite-with-backup` — write `<path>.pre-update.bak` then overwrite.

Ask for an explicit `yes` to execute the kit-runtime block. Silent
acceptance must not proceed — the verb is destructive.

### Step 5 — Execute the kit-runtime sync

For each pair in `Apply` or chosen `apply` / `overwrite-with-backup` from
Step 4, in order:

1. If `overwrite-with-backup`, rename `<dest>` to `<dest>.pre-update.bak`.
2. `cp <kit>/<src> <dest>`. Preserve mode (`chmod +x` for `run.sh`,
   `enable-governance.sh`).
3. Stamp the marker with the new kit version:
   ```sh
   stamp_managed_marker "<dest>" "<KIT_VERSION>"
   ```
   This rewrites the bare `# governance-kit:managed` line in the source
   template to the versioned form `# governance-kit:managed
   kit-version=<v> generated=<YYYY-MM-DD>` in place. `stamp_managed_marker`
   is idempotent and lives in `governance/assets/packs/lib/install.sh`.

For each pair in `Add` (destination missing): `cp <kit>/<src> <dest>`.

After all file pairs:

4. **Regenerate the hook dispatcher.** Reuse `generate_hooks_for_strategy`
   from `governance/assets/packs/lib/hooks.sh`, passing the manifest's
   `hook_strategy`. The new generator may emit different dispatcher
   bodies (that is the whole point of `kit update`); the existing
   ownership marker discipline picks up regenerated files silently and
   prompts for unmanaged ones (Step 6 collision flow in
   [INIT_FLOW.md](INIT_FLOW.md)).

5. **Update `install.yaml`.** Re-emit the manifest with
   `kit_version: "<new>"`. Use `write_installed_manifest`'s
   `--kit-version` flag (see [INSTALL_SCHEMA.md](INSTALL_SCHEMA.md)).

6. **Smoke-test.** Run `bash .governance/run.sh` against the post-update
   tree. Capture exit code and output for the report. Do **not** abort
   on failure — failures may reflect repo state the user needs to know
   about. Surface them in the report.

### Step 6 — (Optional) Chain `pack update`

If `--with-packs` was passed:

1. Read `.governance/packs.lock`.
2. For every entry with `source: gh`, invoke the `pack update <id>` flow
   (see [PACK_VERBS.md](PACK_VERBS.md#pack-update-pack-id)). Each pack
   still uses its own per-pack diff-before-exec confirmation — `kit
   update --with-packs` does **not** auto-approve pack updates.
3. Aggregate per-pack results into the Step 7 report.

If `--with-packs` was not passed and any pack's lock entry would resolve
to a newer SHA at its current `ref`, mention it in the report:

```
Packs: 2 packs may have newer SHAs at their pinned refs (run with --with-packs to update):
  governance-kit/core    v0.2  → checks for newer SHA on rerun
  acme/soc2              main  → checks for newer SHA on rerun
```

This is a hint, not a fetch — a hint that costs nothing because the
lockfile already records the floating `ref`.

### Step 7 — Stage and commit

`git add` the staged set:
- Every kit-runtime file that was rewritten.
- The regenerated hook dispatchers.
- `.governance/install.yaml`.
- (Under `--with-packs`) any directive folders + lockfile updates from
  the chained `pack update` runs.

Run `git status` to confirm the staged set is exactly the update surface.

Conventional Commits subject:

| Run | Subject |
|---|---|
| Kit-runtime only | `chore(governance): kit update <old> → <new>` |
| Kit + packs | `chore(governance): kit update <old> → <new> (+packs)` |

Append the issue anchor the repo's `commit-message-format` directive
requires (`(#N)`). If the user did not name an issue, ask for it as a
blocking input — same discipline as every other writer in this skill.

The commit body should include:
- The kit version delta.
- A bullet list of files updated, skipped, and unmanaged-skip.
- The smoke-test result.
- (Under `--with-packs`) a per-pack summary: ids that drifted, ids
  already pristine.
- Any material assumptions (e.g., pre-tracking install, force on dirty
  tree).

Pass the message via a HEREDOC. Do **not** push.

If `--dry-run` was set, skip Step 7 entirely. The report says what
*would* have been committed.

### Step 8 — Report

Every successful run — including no-ops and refusals — must emit the full
report block below. Every field is required; render `none` (or the
documented sentinel) when a row has nothing to say. Skipping a row is a
flow violation, not a stylistic choice — the eval grader treats a missing
`Packs:` or `Hook dispatcher:` line as a failed run even when the
underlying behavior was correct.

```
From → To:        <old-kit-version> → <new-kit-version>
Updated:          <file list with byte-counts, or `none`>
Skipped:          <byte-equal files, or `none`>
Skipped (unmanaged): <files without the line-2 marker + per-file user
                  choice (keep / apply-anyway / overwrite-with-backup),
                  or `none`>
Hook dispatcher:  regenerated | unchanged
Smoke test:       pass | fail (exit <code>): <first failing directive>
Packs:            up-to-date | <N> updated | not checked (use --with-packs)
Committed:        <short-sha> <conventional-commit subject>
                  (or `would-commit:` under `--dry-run`, or `none` for a
                  no-op / refusal)
Assumptions:      <any, or `none`>
Next:             git push
```

For the documented short-circuit branches:

- **Up-to-date no-op** — every row is `none` except `From → To:` (which
  reads `<v> → <v> (up-to-date)`), `Smoke test:` (`pass`), `Packs:` (the
  `--with-packs`-aware sentinel), `Committed:` (`none`), and `Next:`
  (`none` — the user has nothing to push).
- **Refusal** (`no recoverable pin`, `no-downgrade`, dirty tree without
  `--force`) — emit `From → To:` with the detected delta, set every
  action row to `none`, and put the refusal reason and recovery path
  under `Assumptions:`.

## Required final output

Same 10-field block as Step 8 above. There is no shorter "summary"
variant — the verb either emits the full block or it has not finished.

---

## Key design principles

- **Disjoint from `pack update`.** Kit-runtime updates and pack-content
  updates are two different concerns: one is "the framework code got
  smarter", the other is "the rules content got tighter". Conflating
  them lands a bigger diff under one PR than reviewers can sensibly
  audit. `--with-packs` is the explicit opt-in for the combined flow.
- **Marker is the version pin; manifest is a cache.** Every kit-owned
  file (runtime templates and hook dispatchers alike) carries a
  `# governance-kit:managed kit-version=<v> generated=<date>` marker.
  The `kit-version=` token is the per-file pin `kit update` reads;
  `install.yaml.kit_version` mirrors it. If the manifest is missing,
  the verb reconstructs the pin by scanning markers (taking the min
  `kit-version=`) and rewrites the manifest on success. Only a repo
  with neither manifest nor versioned markers is unrecoverable.
- **Diff-before-exec.** Step 4 prints the per-file diff before any file
  is touched. Same discipline that protects `pack add` and `reset`.
  The diff is computed against the source template *after* the new
  `kit-version=` and today's date have been stamped, so the marker line
  itself is not spurious noise.
- **Marker is the contract.** Line-2 `governance-kit:managed` is the
  ownership marker. Files without it are user-owned and surface as
  `Skipped (unmanaged)` — never silently overwritten. This is the
  same rule the hook generator already follows.
- **No downgrades.** A newer manifest stamp in front of an older kit on
  PATH stops the verb. Silently rolling a runtime file backwards is the
  exact failure mode this verb exists to prevent.
- **Refuse on a dirty tree.** `--force` exists for the rare case the
  user knows what they are doing.
- **Idempotent.** Running `kit update` against an already-current repo
  is a successful no-op. Every file is `skip`, no commit is made.
- **Atomic commit.** The whole update lands in one commit, like every
  other writer in this skill.
- **No network outside `--with-packs`.** Kit-runtime sync is a pure
  local file-copy plus `install.yaml` rewrite. Network calls are
  scoped to the optional `pack update` chain.

## References

- [`../SKILL.md`](../SKILL.md) — verb dispatch.
- [VERBS.md](VERBS.md) — per-verb reference.
- [INSTALL_SCHEMA.md](INSTALL_SCHEMA.md) — `kit_version` field, where
  this verb writes through.
- [INIT_FLOW.md](INIT_FLOW.md) — the verb that originally seeded
  every file `kit update` re-syncs.
- [PACK_VERBS.md](PACK_VERBS.md) — `pack update` is the orthogonal
  verb for rules-content updates; `kit update --with-packs` chains it.
- [RESET_FLOW.md](RESET_FLOW.md) — the recovery verb for *directive*
  drift; `kit update` is for *runtime-file* drift.
