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
| `--check-upstream` was passed | Run the read-only upstream check (`kitverb.py kit-upstream`) and surface the result in the `Upstream:` report row. **Never** auto-fetch-and-apply — if the installed skill is behind, route the user to the skill manager (`npx skills update governance --global`), then re-run. The verb still syncs the repo to the *installed* kit as usual. |
| Structured question tools are unavailable | Use short free-text prompts. If no answer to a destructive prompt, stop. |

---

## Activation flow

Run these steps in order. Do not skip steps unless noted.

### Step 1 — Verify the install

Run in parallel:
- `git rev-parse --show-toplevel` — confirm git repo; capture the root.
- Read `<root>/.governance/packs.lock` (only required when `--with-packs`).
- Resolve the full update plan in one deterministic call:
  ```sh
  uv run --quiet --isolated --with PyYAML python \
      governance/assets/packs/lib/kitverb.py kit-plan "<root>" --diff
  ```

`kit-plan` is the side-effect-free core of Steps 1–3. It reads
`<root>/.governance/install.yaml`, or — when the manifest is absent —
reconstructs the pin from the `kit-version=` markers on the default managed
set (taking the semver-aware **min**, since an update only lands when *every*
managed file catches up). It resolves the version delta against the kit on
PATH and emits the managed-file inventory with each destination's marker state
and a plan-status hint. It writes nothing. **Consume its JSON rather than
re-deriving any of this by hand** — the bash-array reconstruction and
min-reduction that used to live inline here is exactly the surface where a
shell-portability quirk or a skipped phase silently produced a wrong plan
(issue #170, finding B).

| Field | Use |
|---|---|
| `kit_version` | `KIT_VERSION` of the kit on PATH (the installed skill copy). |
| `installed_kit_version` | The recorded/reconstructed pin, or `null`. |
| `manifest_source` | `install.yaml` / `reconstructed` / `absent`. |
| `reconstructed_from` | Files that contributed to a reconstructed pin (name them in the `Assumptions:` line). |
| `delta` | `forward` / `up-to-date` / `downgrade` / `pre-tracking` / `no-recoverable-pin` — drives Step 2. |
| `files[]` | `{key, src, dest, exists, marker, dest_version, status, diff}` per managed file — the Step 3 inventory. |

`status` is a per-file action hint — `skip` (versioned marker ==
`KIT_VERSION`), `apply` (older or bare marker), `add` (destination missing),
`unmanaged` (no marker; user-owned). With `--diff`, each entry also carries
the unified diff from the current destination to the **stamped** source —
the kit template with the new `kit-version=` already applied, so the marker
line is never spurious noise. Show these diffs in Step 4; do not hand-stamp
temp copies to compute them.

The execution half is `kit-apply` (Step 5) — it **recomputes this same plan
at execution time** and re-enforces every gate in code, so a stale reading
of the plan cannot slip through.

If `delta` is `no-recoverable-pin` (`manifest_source: absent`), stop: the user
has no recoverable version pin (truly pre-marker install or all managed files
were hand-stripped). Recovery: `governance uninstall` + `governance init`.
When `manifest_source` is `reconstructed`, proceed — the manifest is rewritten
on success and an `Assumptions:` line records the reconstruction.

### Step 2 — Resolve the version delta

`kit-plan`'s `delta` field already classifies the update. Act on it:

| `delta` | Action |
|---|---|
| `pre-tracking` | Manifest present but carries no `kit_version`. Offer to record the current `KIT_VERSION`; on consent, pass `--record-pre-tracking` to `kit-apply` in Step 5 (render `<prev>` as `unknown` in the report). Without that flag `kit-apply` refuses — the flag *is* the recorded consent. |
| `forward` | Forward update. Continue to Step 3. |
| `up-to-date` | No-op for kit-runtime. If `--with-packs`, jump to Step 6. Else report `kit: up-to-date` and exit — but **always** emit the skill-provenance line (below). |
| `downgrade` | Stop. The repo was last touched by a newer kit; running an older `kit update` against it would silently downgrade. The user's recovery path is to upgrade the kit on PATH (e.g., `uvx --reinstall …`) and re-run. |
| `no-recoverable-pin` | Already handled in Step 1 — stop with the `uninstall` + `init` recovery path. |

**Skill-provenance line (up-to-date branch).** `KIT_VERSION` is resolved
*only* from the locally installed skill (`packctl.py kit-version` →
`governance/assets/kit.yaml`). The verb has **no awareness of the kit version
published upstream**: if the installed skill is itself stale, this branch
reports `up-to-date` while a newer kit exists — the single most confusing
failure mode of a routine "pull the latest kit" (issue #170). So whenever this
branch fires, the `Assumptions:` row must name the provenance and the refresh
path, verbatim shape:

> `Kit source: locally installed governance skill (kit <v>). "Up-to-date" is relative to the installed skill, not the published kit — to check for a newer release, refresh the skill (e.g. `npx skills update governance --global`) and re-run.`

This is a no-network reminder: it does not fetch anything, it just stops the
user from concluding "I'm current" when the real fix is one layer up, in the
skill install.

**Opt-in upstream check (`--check-upstream`).** When the user wants the hint
turned into a measurement, `--check-upstream` resolves the latest published
`kit/vX.Y.Z` tag and reports how far behind the installed skill is:

```sh
uv run --quiet --isolated --with PyYAML python \
    governance/assets/packs/lib/kitverb.py kit-upstream
```

`kit-upstream` is read-only — a single `git ls-remote` against the kit's
upstream (`duaility/governance-kit` by default; the skill records its real
origin in the `skills` lockfile). It returns `status`
(`current`/`behind`/`ahead`/`unknown`), `latest_published`, and
`releases_behind`. Surface it in the `Upstream:` report row:

- `behind` → `behind by <N> (latest <v>) — refresh the skill: npx skills update governance --global, then re-run`.
- `current` → `current (latest <v>)`.
- `unknown` (offline / git unavailable) → `not reachable (offline?)` — never block the verb on it.

It is **only** a signal. `kit update` never fetches-and-applies a newer kit
itself: that would make the *currently running* flow apply assets and a
manifest contract it predates (silent version skew — the exact failure this
verb exists to prevent), and it would bypass the skill manager's pinned,
lock-verified install path with a second unaudited code-ingestion route.
Pulling a newer kit onto the machine is the skill manager's job; this verb only
syncs the repo to whatever kit is installed. So when `behind`, the verb routes
to `npx skills update governance --global` and stops short of applying — it
does not download or run upstream code.

Do **not** attempt a downgrade automatically. Downgrades have to be
explicit (`--allow-downgrade`, future flag) — silently rolling a runtime
file backwards under a manifest stamp the user already trusts is the kind
of footgun this verb exists to prevent.

### Step 3 — Inventory the managed files

`kit-plan` already built this inventory — `files[]` pairs each kit asset
(`src`) with its install destination (`dest`), derived from the manifest
fields, and carries the destination's `marker` state, `dest_version`, and
plan-status `status`. Use it directly; the table below documents what those
pairs are:

| Source (in kit) | Destination (in repo) | Marker |
|---|---|---|
| `assets/dot-governance/run.sh` | `<tests_dir>/run.sh` | `governance-kit:managed kit-version=<v>` in first 3 lines |
| `assets/dot-governance/lib.sh` | `<tests_dir>/lib.sh` | `governance-kit:managed kit-version=<v>` in first 3 lines |
| `assets/enable-governance.sh` | `<enable_governance_script>` (Path A only — field absent under Path B) | `governance-kit:managed kit-version=<v>` in first 3 lines |
| `assets/governance.yml` | `<ci_workflow>` | `governance-kit:managed kit-version=<v>` in first 3 lines |
| `assets/freshness.conf` | `<tests_dir>/freshness.conf` (only if the file already exists — `kit update` does not seed it) | None — user-tunable config; skip on diff |
| `assets/integrity.conf` | `<tests_dir>/integrity.conf` (only if the file already exists — `kit update` does not seed it) | None — user-tunable config; skip on diff |

The hook dispatchers are kit-owned too, but `kit-plan` does not list them as
file pairs — they are regenerated wholesale in Step 5 (`generate_hooks_for_strategy`)
rather than copied from a static asset, so the plan reports `hook_strategy`
instead. The two `*.conf` files above are likewise outside `files[]` (no
marker, seed-only).

**Marker shape.** The ownership marker is a `# governance-kit:managed`
comment within the file's leading comment block: line 2 for shebang
scripts (right after `#!/usr/bin/env bash`), line 1 for YAML and other
files without a shebang. The full form carries the version pin:

```
# governance-kit:managed kit-version=<v>
```

Hook dispatchers carry the same form (kit-owned regenerable files all
share one marker shape). The `kit-version=<v>` token is the per-file
version pin — `kit update` reads it to compute drift; the manifest's
`kit_version` field is a cache that mirrors the markers. The marker
carries no wall-clock date, so re-stamping the same kit version is a
byte-identical no-op.

**Pre-marker installs.** Three sub-cases, distinguished by what the
marker scan finds in each managed file:

| Marker on dest | Treatment |
|---|---|
| Present and versioned (`kit-version=<v>`) | Compare `<v>` to new `KIT_VERSION`; equal → skip, older → re-stamp + diff. |
| Present but bare (`# governance-kit:managed` with no `kit-version=`) | Treat as version-unknown but kit-owned. Apply forward in this run; the new stamp brings it under per-file pin tracking. |
| Absent | Treat as user-owned. Surface as `Skipped (unmanaged)` and offer the per-file `keep` / `apply anyway` / `overwrite-with-backup` choice. |

Per-file action status and diff text both come from `kit-plan --diff`
(Step 1) — there is nothing to compute by hand in this step.

### Step 4 — Confirm and collect decisions

Show the user the plan (`kit-apply` re-checks the dirty-tree and delta
gates in code, but surface refusals *before* asking for confirmation —
don't collect decisions for a run that will be refused):

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

For every file in `Apply`, print the diff (from `kit-plan --diff`) under
the summary so the user sees what is changing in `run.sh` etc. before any
file is touched. Same diff-before-exec discipline `pack add` and `reset`
use.

Collect per-file decisions into a JSON object `{<dest>: <decision>}`:

- For files in `Skip (unmanaged)`, offer **per-file** the three options:
  - `keep` (default) — leave the file alone; report under `Skipped (unmanaged)`.
  - `apply` — overwrite, no backup.
  - `overwrite-with-backup` — write `<path>.pre-update.bak` then overwrite.
- For a *managed* file the user wants to hold back (hand-edited under the
  marker), the same `keep` / `overwrite-with-backup` overrides are
  accepted; managed files default to `apply` — the marker is the
  regeneration contract.

Ask for an explicit `yes` to execute the kit-runtime block. Silent
acceptance must not proceed — the verb is destructive.

### Step 5 — Execute: one `kit-apply` call

The entire apply is a single deterministic call (issue #172):

```sh
uv run --quiet --isolated --with PyYAML python \
    governance/assets/packs/lib/kitverb.py kit-apply "<root>" \
    --decisions '{"scripts/enable-governance.sh": "keep"}'   # only if Step 4 collected any
```

Flags, all optional: `--decisions <json|file>` (per-file overrides from
Step 4), `--dry-run` (resolve every action, write nothing), `--force`
(proceed over a dirty tree — mirror it in `Assumptions:`),
`--record-pre-tracking` (the consent from Step 2's pre-tracking branch),
`--owner <o> --repo <r>` (required only when `manifest_source` is
`reconstructed` — the fresh manifest needs the repo identity).

`kit-apply` executes, in order, everything this step used to spell out as
prose: re-enforces the delta and dirty-tree gates, writes each approved
file **pre-stamped** with the new `kit-version=` marker (mode preserved),
honors the per-file decisions (backups as `<path>.pre-update.bak`),
regenerates the hook dispatchers via hooks.sh `generate_hooks_for_strategy`
under the manifest's `hook_strategy`, writes `kit_version` through to
`install.yaml` (in-place edit that preserves every other field; on the
reconstructed path a fresh v3 manifest via install.sh
`write_installed_manifest`), smoke-tests `bash <tests_dir>/run.sh`, and
prints a JSON report. **Do not hand-execute `cp` / `stamp_managed_marker` /
hook regeneration / manifest edits** — that hand-assembly is the drift
surface this subcommand closed, exactly as `kit-plan` closed the plan side
(issue #170, finding B).

Report fields → exit codes: `result` is `applied` / `up-to-date` /
`dry-run` (exit 0), `refused` (exit 2 — `reason` + `recovery` name the
gate), or `error` (exit 1 — partial writes possible; the tree was clean,
so `git checkout -- .` restores it). `updated` / `added` / `skipped` /
`kept` / `unmanaged` / `backups` list per-file outcomes; `hook_dispatcher`
is `regenerated` or `unchanged` (byte-compared); `manifest` is `updated` /
`created`; `smoke_test` carries `{exit_code, summary}`; `assumptions`
collects the reconstruction / pre-tracking / `--force` notes for the
Step 8 report. A smoke-test failure does **not** abort the run — surface
it; it may reflect repo state the user needs to know about.

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

`git add` the staged set — read it from the `kit-apply` report:
- Every file in `updated` + `added`.
- The regenerated hook dispatchers (when `hook_dispatcher: regenerated`).
- `.governance/install.yaml`.
- (Under `--with-packs`) any directive folders + lockfile updates from
  the chained `pack update` runs.

Never stage the `backups` entries (`*.pre-update.bak`) — they are the
user's local safety copies, not part of the update.

Run `git status` to confirm the staged set is exactly the update surface.

Conventional Commits subject:

| Run | Subject |
|---|---|
| Kit-runtime only | `chore(governance): kit update <old> → <new>` |
| Kit + packs | `chore(governance): kit update <old> → <new> (+packs)` |

Append the issue anchor the repo's `commit-message-format` directive
requires (`(#N)`). If the user did not name an issue, ask for it as a
blocking input — same discipline as every other writer in this skill.

**Export `AGENT_ISSUE='#N'` for the commit.** This subject is delivered
via a HEREDOC (below), not a `-m "<subject>"` flag — so the subject never
lands in `git`'s argv. The `agent-steering-accounting` and
`agent-token-accounting` pre-commit hooks infer the issue anchor by walking
that argv for a `(#N)` token; with a HEREDOC there is nothing to walk, and
they block the commit asking for `AGENT_ISSUE`. (This is *not* a regex
mismatch with `commit-message-format` — that directive and the hooks accept
the identical `(#N)` shape, including subjects like `… (+packs) (#N)`; the
gap is purely that argv-based inference can't see a HEREDOC subject.) So
prefix the commit:

```sh
AGENT_ISSUE='#N' git commit -F - <<'EOF'
chore(governance): kit update <old> → <new> (#N)
…
EOF
```

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
Upstream:         not checked (use --check-upstream) | current (latest <v>) |
                  behind by <N> (latest <v>) — refresh: npx skills update
                  governance --global, then re-run | not reachable (offline?)
Committed:        <short-sha> <conventional-commit subject>
                  (or `would-commit:` under `--dry-run`, or `none` for a
                  no-op / refusal)
Assumptions:      <any, or `none`>
Next:             git push
```

For the documented short-circuit branches:

- **Up-to-date no-op** — every row is `none` except `From → To:` (which
  reads `<v> → <v> (up-to-date)`), `Smoke test:` (`pass`), `Packs:` (the
  `--with-packs`-aware sentinel), `Upstream:` (the `--check-upstream`-aware
  sentinel), `Committed:` (`none`), and `Next:` (`none` — the user has nothing
  to push). `Assumptions:` **must** carry the skill-provenance line (see above)
  — this is the one branch where "up-to-date" can be a false negative, so the
  report has to name what it actually compared against. With `--check-upstream`
  the `Upstream:` row turns that caveat into a measured `current` / `behind by
  <N>` instead.
- **Refusal** (`no recoverable pin`, `no-downgrade`, dirty tree without
  `--force`) — emit `From → To:` with the detected delta, set every
  action row to `none`, and put the refusal reason and recovery path
  under `Assumptions:`.

## Required final output

Same 11-field block as Step 8 above. There is no shorter "summary"
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
  `# governance-kit:managed kit-version=<v>` marker.
  The `kit-version=` token is the per-file pin `kit update` reads;
  `install.yaml.kit_version` mirrors it. If the manifest is missing,
  the verb reconstructs the pin by scanning markers (taking the min
  `kit-version=`) and rewrites the manifest on success. Only a repo
  with neither manifest nor versioned markers is unrecoverable.
- **Plan and apply are both deterministic.** `kit-plan` computes the plan;
  `kit-apply` executes it — gates, stamped writes, decisions, hook regen,
  manifest write-through, smoke test — in one tested call. The operator
  (agent or human) owns only what is genuinely theirs: eliciting
  decisions, showing diffs, and the commit. Prose is not an executor.
- **Diff-before-exec.** Step 4 prints the per-file diff (from
  `kit-plan --diff`) before any file is touched. Same discipline that
  protects `pack add` and `reset`. The diff is computed against the
  source template *after* the new `kit-version=` has been stamped, so the
  marker line itself is not spurious noise.
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
