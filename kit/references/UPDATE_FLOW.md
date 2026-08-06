# `governance update` — activation flow

Re-syncs the kit-runtime files installed at `governance install` to a kit version
the repo's manifest pins — the **repo-pinned model** (issue #177). Dispatched
from the installed skill's `SKILL.md`. (Verb name: `governance update`; `kit update`
remains a recognized alias, and the engine subcommands keep their `kit-*` names.)

> **`<lib_dir>`** throughout is the `assets/packs/lib/` of the kit tree this
> document came from — normally the repo's pinned kit, resolved by the
> installed skill's `bootstrap.py` (issue #198); in the governance-kit source
> repo itself, `kit/assets/packs/lib/`.

## The repo-pinned model (read this first)

The repo's `install.yaml` is the authoritative statement of which kit it runs.
`kit update` is "**resolve a target → fetch its tree → delegate apply to the
target's own engine → record the pin**" — the gradle-wrapper / rustup-shim
model. The skill is a thin *bootstrapper*; the version-selection happens through
the manifest pin, not through which skill copy `npx skills` last installed.

- **Resolution default flips to the published tag.** By default the target is
  the **latest published `kit/vX.Y.Z` tag** (resolved over the network via
  `git ls-remote`), not "whatever skill is installed". `--to X.Y.Z` selects an
  exact version. Offline (or no remote), resolution falls back to the repo's
  cached pin (a full kit tree, network-free); with nothing cached it reports
  `installed-skill`, which `update` **refuses** — the published skill is a thin
  shim with no kit assets to apply from (issue #198).
- **Delegated apply.** Forward and same-version updates exec the **fetched
  target tree's own** `kitverb.py kit-plan` / `kit-apply` — the code that writes
  version X's files *is* version X's code, so markers never lie and a running
  flow never applies asset contracts it predates. A delegated apply happens
  inside `~/.governance/cache/kits/<owner>__<repo>@<sha>/`, the kit twin of the
  pack cache.
- **Real downgrades.** `--allow-downgrade` rolls the runtime backward,
  explicit-only. A downgrade is driven by the *newer* engine — the
  pinned kit this flow runs from — applying the *fetched older* assets + hook
  generator (an older engine cannot be trusted with a newer manifest, and
  refuses downgrades anyway).
- **Delegation floor.** Delegation needs the target to ship the engine
  (`kitverb.py kit-plan`/`kit-apply`), first present in `kit/v0.4.0`. A target
  below that floor is refused with the legacy skill-reinstall path.
- **The pin.** After a successful apply the resolved `kit_ref` + `kit_sha` are
  written to `install.yaml` (the `kit-pin` step). Absent fields on a repo
  bootstrapped before this change are **backfilled on the first `kit update`**.

**What does not change:** no network at hook/commit time — `run.sh`, `lib.sh`,
and the dispatchers stay vendored; network happens only inside `kit update` /
`pack update`, exactly as packs do. The plan/apply UX (diff-before-exec, per-file
decisions, one atomic commit) is unchanged — only the source tree the plan reads
from moves into the cache.

`kit update` is the answer to "a new governance-kit was published — how do I
pull it into this repo?". It is **disjoint** from `pack update`:

| Verb | Updates |
|---|---|
| `pack update` | Directive folders + `packs.lock` SHA pins (rules content). |
| `kit update` | The runtime artifacts `init` originally seeded (`run.sh`, `lib.sh`, `governance.yml`, hook dispatchers) and the `kit_version` recorded in `install.yaml`. |

A single user-facing run can chain both with `--with-packs`. The default
behavior is kit-runtime only — pack updates are reviewed separately because
their diffs land directive code that runs on commits.

## Why a separate verb

`init` is one-shot: it copies `dot-governance/run.sh`, `lib.sh`, and
`governance.yml` into the target repo and
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
| `install.yaml.kit_version` == resolved target | No-op for the kit-runtime; still record the pin (`kit-pin`) and, if `--with-packs`, fall through to pack update. Report `kit: up-to-date`. |
| Resolved target is **older** than `install.yaml.kit_version` | Refuse unless `--allow-downgrade`. The refusal names the flag. With it, the *newer pinned* engine applies the *fetched older* assets (see Step 5). |
| Resolved target is below the delegation floor (`< 0.4.0`) | Refuse — that target ships no `kitverb.py` engine to delegate to. Name the floor and the legacy `npx skills add …#kit/v<target>` reinstall path. |
| Offline / upstream unreachable | Do not error. Fall back to the cached pin (`kit_ref`/`kit_sha`), reporting the provenance; exit 0 when there is nothing to do. If the pin is uncached too (`provenance: installed-skill`), **refuse with guidance** — the thin shim carries no kit assets to apply from; connect once or re-run when the cache is populated (issue #198). |
| Offline / fetch failed **with `--to X.Y.Z`** | The fallback may satisfy the request only if it resolves *exactly* X.Y.Z; a fallback that resolves a different version refuses (never "asked for X, applied Y, exit 0"). Re-run with network access or drop `--to`. |
| Working tree has uncommitted changes | Refuse, unless `--force` is set. The user reviews `git status`, then commits / stashes / re-runs with `--force`. |
| A managed file was hand-edited (line-2 marker present, byte-diff non-empty) | Show the diff and ask per-file: `apply` / `skip` / `overwrite-with-backup` (writes `<path>.pre-update.bak` then overwrites). Default `apply`. |
| A managed file is missing the line-2 marker | Treat as user-owned. Skip silently and surface in the report under `Skipped (unmanaged):`. |
| `--with-packs` was passed | After the kit-runtime block, run `pack update` against every `source: gh` entry in the lockfile. Each pack still uses its own diff-before-exec confirmation. |
| `--check-upstream` was passed | Run the read-only upstream check (`kit-upstream` from `<lib_dir>`) and surface the result in the `Upstream:` report row — a signal only. The default (no `--to`) run already targets the latest published tag, so a pin behind upstream is resolved by this very verb. |
| Structured question tools are unavailable | Use short free-text prompts. If no answer to a destructive prompt, stop. |

---

## Activation flow

Run these steps in order. Do not skip steps unless noted.

### Step 1 — Verify the install and resolve the target

Run in parallel:
- `git rev-parse --show-toplevel` — confirm git repo; capture the root.
- Read `<root>/.governance/packs.lock` (only required when `--with-packs`).

Then resolve the target in one deterministic call (this is the network step):

```sh
python3 \
    <lib_dir>/kitverb.py kit-resolve "<root>" \
    [--to X.Y.Z] [--allow-downgrade] [--offline]
```

`kit-resolve` reads the repo's recorded pin, resolves the **target** version
(default: the latest published `kit/vX.Y.Z` tag; `--to` for an exact version;
offline falls back to the cached pin; with nothing cached it reports
`installed-skill`, which this flow refuses — see the matrix above), fetches that
tree into `~/.governance/cache/kits/`, and reports the delegation plan. It writes
nothing to the repo. Consume its JSON:

| Field | Use |
|---|---|
| `result` | `ok` / `refused`. On `refused`, surface `reason` + `recovery` and stop. |
| `current_version` | The repo's recorded pin (or `null`). |
| `target_version` | The resolved target. |
| `provenance` | `published-tag` / `explicit` / `cache` / `installed-skill` — name it in the `Resolved:` report row. |
| `direction` | `forward` / `same` / `downgrade` / `unknown` — drives Step 2. |
| `floor_ok` | `false` ⇒ already refused (target `< 0.4.0`). |
| `delegate` | `true` ⇒ run the fetched engine; `false` ⇒ offline fallback to the engine this flow runs from (the pinned kit). |
| `engine_path` | The `kitverb.py` to invoke for Steps 4–5 (the fetched target's own on forward/same; the hosting pinned kit's on a downgrade or offline fallback). |
| `assets_root` / `hooks_lib` | Passed to the **hosting** engine only on a downgrade (the fetched older tree's `assets/` + `lib/`). Omit them when delegating to the target's own engine. |
| `kit_ref` / `kit_sha` | The pin to record after a successful apply (`kit-pin`). |

If `result` is `refused` (floor or downgrade-without-flag), surface the reason
and stop — do not collect decisions for a run that will not happen.

Now resolve the file-level plan against the engine `kit-resolve` named:

```sh
python3 \
    <engine_path> kit-plan "<root>" --diff \
    [--assets-root <assets_root> --stamp-version <target_version>]   # downgrade only
```

The `--assets-root`/`--stamp-version` flags are passed **only** on a downgrade
(hosting engine, fetched older assets). For forward/same the fetched target's own
engine already reads its own tree and version — pass neither.

`kit-plan` is the side-effect-free core of Steps 2–3. It reads
`<root>/.governance/install.yaml`, or — when the manifest is absent —
reconstructs the pin from the `kit-version=` markers on the default managed
set (taking the semver-aware **min**, since an update only lands when *every*
managed file catches up). It resolves the version delta against the version the
engine stamps (the **target** version — the fetched engine's own
`KIT_VERSION`, or, on a downgrade, `--stamp-version`) and emits the managed-file
inventory with each destination's marker state and a plan-status hint. It writes
nothing. **Consume its JSON rather than re-deriving any of this by hand** — the
bash-array reconstruction and min-reduction that used to live inline here is
exactly the surface where a shell-portability quirk or a skipped phase silently
produced a wrong plan (issue #170, finding B).

| Field | Use |
|---|---|
| `kit_version` | The version this plan stamps — the target. |
| `installed_kit_version` | The recorded/reconstructed pin, or `null`. |
| `manifest_source` | `install.yaml` / `reconstructed` / `absent`. |
| `reconstructed_from` | Files that contributed to a reconstructed pin (name them in the `Assumptions:` line). |
| `delta` | `forward` / `up-to-date` / `downgrade` / `pre-tracking` / `no-recoverable-pin`. |
| `files[]` | `{key, src, dest, exists, marker, dest_version, status, diff}` per managed file — the Step 3 inventory. |

`status` is a per-file action hint — `skip` (versioned marker ==
target), `apply` (older or bare marker), `add` (destination missing),
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

### Step 2 — Act on the direction

`kit-resolve` already classified `direction` (target vs the repo's pin) and
refused the floor / downgrade-without-flag cases. `kit-plan`'s `delta` mirrors
it against the engine's stamp version. Act on the combined picture:

| Case | Action |
|---|---|
| `pre-tracking` | Manifest present but carries no `kit_version`. Offer to record the target version; on consent, pass `--record-pre-tracking` to `kit-apply` in Step 5 (render `<prev>` as `unknown` in the report). Without that flag `kit-apply` refuses — the flag *is* the recorded consent. |
| `forward` | Forward update. Continue to Step 3. |
| `same` / `up-to-date` | No file changes. Still record the pin (`kit-pin`, Step 5) so a repo first pinned now stops being treated as unpinned; if `--with-packs`, jump to Step 6. Report `kit: up-to-date` with the `Resolved:` provenance row. |
| `downgrade` (with `--allow-downgrade`) | Roll backward. `kit-resolve` named the **hosting (pinned, newer)** engine + the fetched older `assets_root`/`hooks_lib`; pass `--assets-root --stamp-version <target> --hooks-lib --allow-downgrade` to `kit-plan`/`kit-apply`. |
| `downgrade` (without the flag) / floor | Already refused by `kit-resolve` — surface its `reason`/`recovery` and stop. |
| `no-recoverable-pin` | Stop with the `uninstall` + `init` recovery path. |

**Resolution provenance (always reported).** Because the default target is the
latest published tag, "up-to-date" now means "current with the published kit",
not merely "current with some machine copy" — the issue-#170 footgun is
closed by construction. The `Resolved:` report row must still name *how* the
target was resolved, verbatim shape:

> `Resolved: <target> via <published-tag | explicit (--to) | cache | installed-skill>` — and, for the `cache` / `installed-skill` fallbacks, append the `Assumptions:` note `kit-resolve` already emitted (offline / upstream unreachable; refresh the skill to pick up a published release).

**Opt-in upstream check (`--check-upstream`).** The resolution default already
consults the published tags, so `--check-upstream` is now a lightweight extra
signal that surfaces the same comparison in the `Upstream:` row without
fetching a tree:

```sh
python3 \
    <lib_dir>/kitverb.py kit-upstream
```

`kit-upstream` is read-only — a single `git ls-remote`. It returns `status`
(`current`/`behind`/`ahead`/`unknown`), `latest_published`, and
`releases_behind`. Surface it in the `Upstream:` row:

- `behind` → `behind by <N> (latest <v>)` (a `kit update` with no `--to` will move to it).
- `current` → `current (latest <v>)`.
- `unknown` (offline / git unavailable) → `not reachable (offline?)` — never block the verb on it.

A downgrade is never automatic: `kit-resolve` refuses one unless
`--allow-downgrade` is set — silently rolling a runtime file backward under a
pin the user already trusts is the footgun this verb exists to prevent.

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
| `assets/governance.yml` | `<ci_workflow>` | `governance-kit:managed kit-version=<v>` in first 3 lines |

`enable-governance.sh` is no longer a managed kit asset (issue #267): the verb
neither re-syncs it nor lists it. A legacy install that still carries one keeps
its now-inert copy; enablement is kit-owned (the verb sets `core.hooksPath`).

The hook dispatchers are kit-owned too, but `kit-plan` does not list them as
file pairs — they are regenerated wholesale in Step 5 (`generate_hooks_for_strategy`)
rather than copied from a static asset, so the plan reports `hook_strategy`
instead.

Per-directive configuration is **not** kit-owned and never appears here: a
directive's pack-owned `defaults.conf` is refreshed by `governance pack update`
(it lives in the directive folder), and the user-owned overlay
`.governance/conf/<id>.conf` is touched by no lifecycle verb after it is seeded.
`kit update` leaves both alone.

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

Skip (unmanaged — hand-edited or pre-marker):
  .github/workflows/governance.yml   diff: 8 +/-0  (line-2 marker absent)

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

### Step 5 — Execute: delegated `kit-apply`, then `kit-pin`

The apply is a single deterministic call against the engine `kit-resolve`
named (issue #172 mechanics, issue #177 delegation):

```sh
python3 \
    <engine_path> kit-apply "<root>" \
    --decisions '{".github/workflows/governance.yml": "keep"}'   # only if Step 4 collected any
```

For forward / same-version this is the **fetched target tree's own**
`kitverb.py` (so it writes its own assets, stamps its own version). On a
**downgrade** it is the hosting (pinned, newer) engine with the resolved overrides:
`--assets-root <assets_root> --stamp-version <target> --hooks-lib <hooks_lib>
--allow-downgrade`. On an offline **installed-skill** fallback it is the hosting
engine with no overrides.

Flags, all optional: `--decisions <json|file>` (per-file overrides from
Step 4), `--dry-run` (resolve every action, write nothing), `--force`
(proceed over a dirty tree — mirror it in `Assumptions:`),
`--record-pre-tracking` (the consent from Step 2's pre-tracking branch),
`--owner <o> --repo <r>` (required only when `manifest_source` is
`reconstructed` — the fresh manifest needs the repo identity).

After a successful (non-`--dry-run`) apply, **record the pin** — the one repo
write `kit-apply` deliberately does not do, so the value-write is identical no
matter which (possibly older) target engine performed the file apply (the
byte-identity contract):

```sh
python3 \
    <lib_dir>/kitverb.py kit-pin "<root>" \
    --kit-ref "<kit_ref>" --kit-sha "<kit_sha>"     # from kit-resolve
```

Skip `kit-pin` only on the installed-skill fallback (no fetched `kit_sha` to
record) — there the repo simply stays on its existing pin.

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
lands in `git`'s argv. The `agent-session-identity` pre-commit hook infers the
issue anchor by walking
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
Resolved:         <target> via published-tag | explicit (--to) | cache | installed-skill
Updated:          <file list with byte-counts, or `none`>
Skipped:          <byte-equal files, or `none`>
Skipped (unmanaged): <files without the line-2 marker + per-file user
                  choice (keep / apply-anyway / overwrite-with-backup),
                  or `none`>
Hook dispatcher:  regenerated | unchanged
Smoke test:       pass | fail (exit <code>): <first failing directive>
Pin:              <kit_ref>@<kit_sha[:12]> recorded | unchanged (installed-skill fallback)
Packs:            up-to-date | <N> updated | not checked (use --with-packs)
Upstream:         not checked (use --check-upstream) | current (latest <v>) |
                  behind by <N> (latest <v>) | not reachable (offline?)
Committed:        <short-sha> <conventional-commit subject>
                  (or `would-commit:` under `--dry-run`, or `none` for a
                  no-op / refusal)
Assumptions:      <any, or `none`>
Next:             git push
```

For the documented short-circuit branches:

- **Up-to-date no-op** — every action row is `none` except `From → To:`
  (`<v> → <v> (up-to-date)`), `Resolved:` (the resolution provenance),
  `Smoke test:` (`pass`), `Pin:` (recorded if it changed, else `unchanged`),
  `Packs:` (the `--with-packs`-aware sentinel), `Upstream:` (the
  `--check-upstream`-aware sentinel), `Committed:` (`none` unless the pin write
  produced a commit), and `Next:`. When the resolution fell back to the cache
  (or the hosting tree itself), `Assumptions:` carries the offline note
  `kit-resolve` emitted.
- **Refusal** (`no recoverable pin`, downgrade without `--allow-downgrade`,
  below the delegation floor, dirty tree without `--force`) — emit
  `From → To:` / `Resolved:` with the detected values, set every action row to
  `none`, and put the refusal reason and recovery path under `Assumptions:`.

## Required final output

The full report block above. There is no shorter "summary" variant — the verb
either emits every row or it has not finished.

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
- **Delegated apply.** Forward / same-version updates run the *fetched
  target's own* `kitverb.py`, so the code that writes version X's files is
  version X's code — markers never lie and the running flow never applies
  asset contracts it predates. `kit-resolve` does the resolve + fetch; the
  skill is a thin bootstrapper.
- **Downgrades are explicit.** `--allow-downgrade` rolls a runtime file
  backward; without it the verb refuses (naming the flag). A downgrade is
  driven by the *newer* pinned engine applying the *fetched older* assets +
  hook generator — an older engine can't be trusted with a newer manifest.
- **Delegation floor.** A target below `kit/v0.4.0` ships no engine to
  delegate to and is refused with the legacy skill-reinstall path.
- **Refuse on a dirty tree.** `--force` exists for the rare case the
  user knows what they are doing.
- **Idempotent.** Running `kit update` against an already-current repo
  is a successful no-op. Every file is `skip`, no commit is made.
- **Atomic commit.** The whole update lands in one commit, like every
  other writer in this skill.
- **No network at hook/commit time.** `run.sh`, `lib.sh`, and the
  dispatchers stay vendored in the repo; commits never reach the network.
  Network happens only *inside* `kit update` (resolving + fetching the
  target tree) and the optional `pack update` chain — exactly as `pack add`
  / `pack update` do. `--offline` skips even that, resolving from the cached
  pin.

## References

- the installed skill's `SKILL.md` — verb dispatch.
- [VERBS.md](VERBS.md) — per-verb reference.
- [INSTALL_SCHEMA.md](INSTALL_SCHEMA.md) — `kit_version` field, where
  this verb writes through.
- [INIT_FLOW.md](INIT_FLOW.md) — the verb that originally seeded
  every file `kit update` re-syncs.
- [PACK_VERBS.md](PACK_VERBS.md) — `pack update` is the orthogonal
  verb for rules-content updates; `kit update --with-packs` chains it.
- [RESET_FLOW.md](RESET_FLOW.md) — the recovery verb for *directive*
  drift; `kit update` is for *runtime-file* drift.
