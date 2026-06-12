# `governance install` — activation flow

The recipe `governance install` runs (alias: `governance init`). Dispatched from
the installed skill's `SKILL.md`.

**Installs from the released kit, not the machine copy (issue #194).** `install`
is a lifecycle verb the *thin skill* owns, but its first act is to resolve and
fetch the kit it will install from — the latest published `kit/vX.Y.Z` tag — and
run every assembly engine from *that* tree (Step 0). This is the same
resolve-and-delegate model `update` uses: the released artifact, not whatever
`npx skills` last put on the machine, is what reaches repo state. Offline, it
falls back to the installed skill and records that provenance.

`install` sets up governance-driven development in the current repository:

1. A `CONSTITUTION.md` at the repo root — the evolving source of truth for directives, guidelines, and directives.
2. Machine-enforced tests under `.governance/` — every directive in the constitution has a corresponding test.
3. A pre-commit hook (and commit-msg / prepare-commit-msg / post-commit / pre-push dispatchers when the selected directives need them) — runs `.governance/` before commits and pushes, with `SKIP_GOVERNANCE=1` and `git commit --no-verify` / `git push --no-verify` as escape hatches.
4. A GitHub Actions workflow at `.github/workflows/governance.yml` — same tests, enforced in CI on every PR.

Directives are grouped into **packs** — self-contained directories that bundle directives, their constitution snippets, and hook declarations. Five concern-scoped packs ship in-tree today, under `packs/<concern>/` (source-of-truth in this monorepo; consumers fetch via `gh:duaility/governance-kit/packs/<concern>@<rev>`):

- **`governance-kit/foundation`** — `required-docs`, `kit-version-sync`, `repo-hygiene`.
- **`governance-kit/security`** — `secrets-hygiene`, `token-permissions`, `pinned-dependencies`.
- **`governance-kit/docs`** — `internal-doc-links`, `doc-freshness`.
- **`governance-kit/commits`** — `commit-message-format`, `no-orphan-todos`, `no-unjustified-suppressions`.
- **`governance-kit/audit`** — a trustworthy record of agent work: issue → receipt → commit traceability (`issue-templates` → `issues-tracked` → `receipt-per-issue` → `commit-issue-receipt-match`), cost + steering accounting (`agent-token-accounting`, `agent-steering-accounting`), and the tamper protection that keeps those records honest (`doc-integrity`, `toolchain-config-protection`).

`governance init` unions each pack's chosen preset across all bundled packs (see Step 3).

Governance evolves: new directives get added to `CONSTITUTION.md` *and* to `.governance/` together. The constitution without the tests is just a wishlist.

## Interaction policy

| Situation | Action |
|---|---|
| Repo is not a git repo | Stop and tell the user `governance init` requires git. |
| Repo already has governance artifacts and the user asked for setup | Continue in augment/overwrite mode; default to augment. |
| Repo already has governance artifacts and the user asked for review, explanation, or one targeted change | Do not run `init`. Answer directly or route to `governance directive *`. |
| Hook framework is unclear | Infer from tracked files. If still unclear, assume `.githooks/` and label that as an assumption. |
| Structured question tools are unavailable | Ask concise free-text questions, then proceed with defaults if the user does not provide more detail. |

---

## Deterministic plan/apply

`init` is the most interactive verb, but its **mechanical** half follows the same
plan/apply split as the other lifecycle verbs (issue #172). The operator owns the
elicitation — pack/preset/directive selection (Step 3), principle inference (Step
4), hook-collision choices (Step 6), the Step-8 finding loop, and the commit
(Step 9). Everything mechanical is one tested call.

- **Plan.** `packverb init-plan --decisions <json>` validates the resolved
  install set (refuses a cross-pack directive-id collision — a flat-namespace
  overwrite) and emits the directive inventory for the diff-before-exec preview.
  Engine: `initplan.py` (also owns the pure CONSTITUTION assembly).
- **Apply.** `packverb init-apply <root> --decisions <json> [--dry-run] [--force]`
  consumes the operator's serialized decisions and assembles the whole install in
  one call: install each directive folder + its `install-assets/`, seed each
  directive's user-config overlay from its `config.conf`, assemble + write CONSTITUTION.md (template +
  operator principles + each directive's `constitution.md` subsection, the example
  replaced), create the AGENTS.md stub when asked, stamp the runtime
  (`run.sh`/`lib.sh`) and CI workflow, generate the hook dispatchers (+ for
  `githooks`: `core.hooksPath` and `enable-governance.sh`), write the
  `install.yaml` receipt + `packs.lock` pin, and smoke-test. Engine: `initapply.py`.

The `decisions` object the operator serializes carries: `owner`/`repo`,
`hook_strategy`, `principles[]`, `seed_agents_stub`, and `packs[]` (each with `id`,
`version`, `source`, `ref`/`sha`/`subpath`, the resolved local `pack_dir`, and the
final `directives[]` install list). The apply refuses outside a git repo, refuses
to clobber an existing install without `--force`, and refuses a collision. It does
**not** make the commit (Step 9) — that stays the operator's, so the accounting
populators read the live session transcript. `--dry-run` reports the would-be
writes and changes nothing.

Steps 3–7 below describe the elicitation and the resolved inputs; the file writes
they used to spell out are now the `init-apply` call. Step 8 (validate + resolve
findings) and Step 9 (commit) remain the operator's.

---

## Activation flow

Run these steps in order. Do not skip steps unless noted.

### Step 0 — Resolve and fetch the kit to install from

Before assembling anything, resolve which kit this install runs from. `install`
is the one place unreleased content used to reach repo state — it ran wholesale
from whatever skill `npx skills` last installed (main HEAD). This step closes
that skew by fetching the released tag and running every later engine from it
(issue #194, milestone 1).

The installed skill is a fetch-only shim (`SKILL.md` + `bootstrap.py`); it
already ran this step to reach this document (`<skill_dir>` is the directory
holding the installed `SKILL.md`):

```sh
python3 <skill_dir>/bootstrap.py resolve [--to X.Y.Z]
```

`resolve` picks the target (default: the latest published `kit/vX.Y.Z` tag;
`--to X.Y.Z` pins an exact version), fetches that tree into
`~/.governance/cache/kits/<owner>__<repo>@<sha>/`, validates it is delegable
(it must ship its own engine lib and flow docs — pre-0.4.0 kits refuse here),
and reports the tree to run from. A fresh repo has no recorded pin, so no
direction gate applies. Consume its JSON:

| Field | Use in `install` |
|---|---|
| `result` | `ok` / `refused`. On `refused`, surface `reason` + `recovery` and stop. |
| `provenance` | `published-tag` / `explicit` (`--to`) / `cache` (offline `--to` served from the local cache). Thread into `decisions.kit_provenance` (Step 3) and name it in the summary. |
| `kit_ref` / `kit_sha` | The pin to thread into `decisions` (Step 3) and record in `install.yaml`. |
| `lib_dir` | The fetched kit's `assets/packs/lib` — call this `<lib_dir>`. **Every engine invocation in Steps 2–7 runs from `<lib_dir>`**, not from `kit/assets/packs/lib/`. |
| `assets_dir` | The fetched kit's `assets/` — call this `<assets_dir>`. The source for `CONSTITUTION.template.md`, `dot-governance/`, `governance.yml`, the bundled `packs/`, etc. |

**Offline / upstream unreachable → refuse with guidance (issue #198).** When
`resolve` reports `result: refused`, there is no released kit tree to
assemble from — the published skill is a thin shim that carries no templates,
packs, or engines. **Stop without writing anything** and surface its
`recovery`: connect once so `install` can fetch the released `kit/vX.Y.Z` (it
lands in `~/.governance/cache/kits/` and later installs of the same version
are network-free), or pass `--to X.Y.Z` for a version already in that cache.
Do not assemble a partial or skill-sourced tree. (`kit_provenance:
installed-skill` remains in the manifest schema only for repos installed by
pre-#198 kits.)

For the rest of this flow, **`<lib_dir>` is the resolved kit's lib** and
`<assets_dir>` is its `assets/`. Where older revisions of this doc wrote
`kit/assets/packs/lib/…` or `../assets/…`, read `<lib_dir>/…` and
`<assets_dir>/…`.

### Step 1 — Survey the repository

Before touching anything, run these in parallel:

- `git rev-parse --show-toplevel` to confirm this is a git repo and find the root.
- `ls -la` at the root.
- Check for existing `CONSTITUTION.md`, `.governance/`, `.github/workflows/governance.yml`, `.githooks/`, and `.git/hooks/pre-commit` (legacy location — flag if present).

If this is not a git repo, stop and tell the user — `governance init` requires git.

If artifacts already exist, report what's there and ask whether to **augment** (add missing pieces, preserve existing) or **overwrite** (fresh start). Default to augment.

Also detect hook strategy before you offer or install hook-related directives:
- If `.husky/` exists, `package.json` references husky, or `.pre-commit-config.yaml` exists, treat the repo as using an existing hook framework.
- Otherwise, use the repo-local `.githooks/` strategy described below.

This choice is recorded as `hook_strategy:` in `.governance/install.yaml` (`githooks` | `husky` | `pre-commit`). The `required-docs` directive's `hooks` sub-check inspects that value and only enforces the `.githooks/` scaffolding when `hook_strategy` is `githooks`. Do not present `.githooks/` as universal if the repo already has a tracked hook framework.

**Hook-collision survey.** As part of the survey, inspect existing hook files at:

| Location | What to look for |
|---|---|
| `.githooks/pre-commit`, `.githooks/commit-msg`, `.githooks/prepare-commit-msg`, `.githooks/post-commit`, `.githooks/pre-push` | grep for the ownership marker `governance-kit:managed` |
| `.git/hooks/*` | same marker (legacy path — flag even if marker is found) |
| `.husky/*`, `.pre-commit-config.yaml` | signals Path B below, not a collision |

Record findings for use at Step 6.

### Step 2 — Discover directive packs

Source the loader **from the resolved kit's lib** (`<lib_dir>`, Step 0) and
enumerate packs from that kit's bundled pack root (`<assets_dir>/packs`, which
holds the five bundled `governance-kit/*` concern packs):

```sh
source "<lib_dir>/packs.sh"
list_packs "<assets_dir>/packs"
```

The loader is a bash wrapper around
`uv run --isolated --with PyYAML`, so pack manifests are parsed as real
YAML. If `uv` is unavailable, stop and tell the user pack discovery
requires `uv` (or install it before continuing).

Every `<root>/<pack-dir>/pack.yaml` is a pack. Pack ids are scoped (`<author>/<slug>` — e.g. `governance-kit/security`, `acme/widgets`); the directory name is the slug half. Directive metadata lives inside each directive's folder (`<pack-dir>/directives/<directive-id>/directive.yaml`) — the loader surfaces it via `directives_for` and `directive_field`. For each pack, build an in-memory catalog of:

- pack id, name, description, version (from `pack.yaml`)
- declared presets (`minimal`, `standard`, `strict`, plus any pack-specific ones — from `pack.yaml`)
- directive list; for each directive read `category`, `recommended`, `summary`, `surface`, `hook`, `always_install` from `directives/<directive-id>/directive.yaml`. The check script is at `directives/<directive-id>/check.sh` and the Directive snippet at `directives/<directive-id>/constitution.md` — paths are implied by the folder shape, not declared.

Pack manifests are validated against the built-in `KIT_VERSION` constant in the resolved kit's `<lib_dir>/packctl.py`. Packs whose `min_governance_kit` is newer than `KIT_VERSION` are rejected during discovery with a clear error.

No env var or CLI flag controls pack selection in v1 — discovery is in-tree only.

### Step 3 — Choose packs, preset, and customize

Three nested questions. Each subsequent question's option list is computed from the prior answer.

**Q0 — "Which directive packs do you want?"** — multiselect.

- The bundled `governance-kit/*` concern packs (always included, non-deselectable — present them as pre-checked with a note).
- Every other pack discovered in Step 2, with its description from the manifest.

**Q1 — "Which preset?"** — single-select.

| Preset | Intent |
|---|---|
| `minimal` | Smallest credible governance baseline. |
| `standard` | Recommended default for most repos. |
| `strict` | Broad governance coverage for teams that want more structure. |
| `custom` | Start from a blank slate — no preselected directives beyond the always-installed set. |

**Semantics across packs: union.** The preset resolves as the union of the preset's directive ids across the selected packs:

```
preset_rules = ⋃ { union_preset(<preset>, <pack-dir>) : pack-dir in selected-packs }
```

A pack that does not declare the chosen preset contributes nothing for that preset — **no fallback to `recommended`**. This is deliberate: "my pack has no strict" means "strict adds nothing beyond what I already offer", not "give me everything".

Use `standard` as the recommended preset. If the user does not answer and you must proceed, assume `standard` and label it in the final summary as a material assumption.

**Q2..Qn — Category menus.** For each category present across the union of selected packs' directives (canonical: `Foundation`, `Security`, `SystemOfRecord`, `CommitHygiene`, `Quality`, `AgentDiscipline`; third-party packs may add more), present one `AskUserQuestion` with:

- Header: the category name.
- Options: every directive in that category from any selected pack. Pre-check based on the preset union from Q1. Each option's description is the directive's `summary` field from its manifest.
- `multiSelect: true`.

Split into multiple `AskUserQuestion` calls — the tool caps at four questions per call. Follow the same pattern today's flow does: first call for Foundation / Security / SystemOfRecord / CommitHygiene; second call for Quality / AgentDiscipline / any additional categories. Category menus with only a single directive are fine — do not pad with filler.

If the user picks "Other" and describes a new directive, generate a new directive folder under `.governance/packs/<owner>/<repo>/directives/<id>/` with `directive.yaml`, `check.sh`, and `constitution.md`, following the template in [DIRECTIVES_CATALOG.md](DIRECTIVES_CATALOG.md), and add a matching Directives subsection to `CONSTITUTION.md`. The directive joins the target repo directly; it is not retrofitted into a pack (that is a pack-authoring activity, covered in [PACK_AUTHORING.md](PACK_AUTHORING.md)).

**Always installed — bypass the menu.** Walk every selected pack's `always_install: true` directives and queue them for install regardless of user picks. This flag is **reserved to the bundled `governance-kit/*` packs**; third-party packs declaring it are rejected at install.

**Install resolution.** The final install list is:

```
install = always_install_bundled
       ∪ preset_rules (from Q1)
       ∪ user_selected_rules (from Q2..Qn, which may add or remove items)
```

If two selected packs list the same directive `id`, reject with a clear error before touching the filesystem. The target repo.s directive id namespace is still flat even though pack-installed files live under `.governance/packs/<pack-id>/directives/<id>/`, so collisions there would be silent overwrites.

Before installing, classify any user-described custom directive by surface:

| Policy surface | Use when the intent is | Preferred enforcement shape |
|---|---|---|
| `repo-state` | "the repo must contain / must not contain X" | Existence, content, pattern, metric, or structural check over tracked files |
| `change-set obligation` | "every substantive change must also do X" | Staged-diff check locally plus branch-diff check in CI |

Ask this explicitly whenever the user requests a custom directive or a directive whose rationale sounds per-change:

> What bad merge are we trying to block: a repo missing something at rest, or a substantive change landing without its required companion update?

Do not accept a repo-exists proxy for a change-set obligation unless you explicitly tell the user it is only a weak approximation and they approve that tradeoff.

This is where the elicitation ends and the mechanical assembly begins. Resolve
the GitHub `<owner>/<repo>` identity (Step 1), locate each selected pack's source
dir (the resolved kit's bundled `<assets_dir>/packs/<concern>/` or a fetched cache
dir for community packs — resolve its pinned SHA with `<lib_dir>/packverb.py fetch
<ref>` so the lock entry records a real pin), and serialize the `decisions`
object: `owner`/`repo`, `hook_strategy`, the inferred `principles[]`,
`seed_agents_stub`, the kit pin from Step 0 (`kit_ref`, `kit_sha`,
`kit_provenance`), and `packs[]` (each with `id`, `version`, `source`,
`ref`/`sha`/`subpath`, the resolved `pack_dir`, and the final `directives[]`
install list). Then hand the whole assembly to the **resolved kit's**
`init-apply`:

```sh
"<lib_dir>/packverb.py" init-apply "$repo_root" --decisions decisions.json
```

`init-apply` runs from `<lib_dir>` so the engine that writes version X's files
*is* version X's code — the same delegation contract `update` uses, now extended
to install. The `kit_ref` / `kit_sha` / `kit_provenance` threaded through
`decisions` are written into `install.yaml`, recording which kit this repo runs
and how the install resolved it (issue #194).

`init-apply` installs each directive folder (minus `evals/`) + its
`install-assets/`, and for any directive shipping a `config.conf` seeds the
user-config overlay `.governance/conf/<owner>/<pack>/<id>.conf` from it (augment-only — an
existing file is preserved). For `doc-integrity` (`always_install`, on by
default) the standard rules ship active in its `defaults.conf`, each a no-op
until its document exists. It then assembles + writes CONSTITUTION.md,
stamps the runtime + CI workflow, generates the hooks (+ `core.hooksPath` /
`enable-governance.sh` for `githooks`), and writes the `install.yaml` v3 receipt +
`packs.lock` v2 pin. The receipt's `--install-asset`/`--agents-md-*` ledger and the
lock's per-pack directive list are derived from the decisions and the installed
tree — no hand-assembled `write_installed_manifest`/`lock-add` invocations. The
install pair is the authoritative record `governance uninstall` and `reset` trust;
installed directive folders are user-owned copies, not an auto-upgrade contract.
See [INSTALL_SCHEMA.md](INSTALL_SCHEMA.md) and [LOCK_SCHEMA.md](LOCK_SCHEMA.md).

### Step 4 — Infer the principles

The only operator judgment in the constitution is the **Principles** section.
Infer 3-5 high-level principles from the directives the user picked (plus a
generic starter like "Changes to the constitution require changes to the
enforcing tests") and put them in the decisions object's `principles[]`.
`init-apply` assembles the rest: it copies `CONSTITUTION.template.md`, splices the
operator principles into the **Principles** section, and splices each directive's
`constitution.md` subsection verbatim into the **Directives** section (replacing
the template example), leaving Compliance / Amendment process / Evolution Log
intact.

Do not invent principles the user did not pick. It is better to ship a short
constitution than a bloated one. If you had to infer anything material — preset or
hook strategy — record it under `Assumptions:` in the final summary. If you
install any custom or change-set-aware directive, make sure the directive text
says what merge it blocks, not just what file shape it checks.

### Step 4b — Inject the Compliance directive into AGENTS.md

The constitution's **Compliance** section is the directive; the AGENTS.md snippet is the routing pointer that tells agents to *read* the directive. Without it, agents may never reach the constitution. Inject `../assets/AGENTS.snippet.md` into the target repo's `AGENTS.md`.

The snippet is bounded by a pair of HTML marker comments — opening `<!-- governance: directives-to-follow -->` on its first line and closing `<!-- /governance: directives-to-follow -->` on its last. Both markers ship together in the template and **both** must be preserved on insert. Idempotency: grep for the opening marker before inserting; if it is already present, skip silently. Do not insert the opening without the closing or vice versa — `governance uninstall` relies on the pair to locate the exact block to strip.

Three cases:

1. **`AGENTS.md` exists and lacks the marker.** Insert the snippet near the top of the file. The right insertion point is **after the H1 heading and the first intro paragraph (or any frontmatter), and before the first `##` heading**. Use `Edit` — preserve everything else verbatim.

2. **`AGENTS.md` is missing AND the `required-docs` directive is installed.** Create a stub at `<repo-root>/AGENTS.md` containing: `# AGENTS.md`, a one-line intro, the directive snippet, and a `## What this repo is` placeholder. Tell the user the stub is intentionally minimal — they need to flesh it out (`required-docs` enforces 30–250 lines and ≥ 3 internal doc links for AGENTS.md).

3. **`AGENTS.md` is missing AND `required-docs` was not installed.** Skip silently. Do not nag — the user opted out, and creating a file they didn't ask for is presumptuous.

After injecting, run `bash .governance/run.sh` once so the user sees whether the newly-seeded AGENTS.md still needs more content.

### Step 5 — The test runner (installed by `init-apply`)

`init-apply` copies `../assets/dot-governance/run.sh` → `.governance/run.sh`
(the entrypoint — discovers and runs every `directives/<id>/check.sh`) and
`lib.sh` → `.governance/lib.sh` (shared pass/fail/skip + `tracked_files`
helpers), makes them executable, and stamps each with the per-file version pin
(`# governance-kit:managed kit-version=<v>`, byte-stable, no wall-clock date) —
the pin `governance kit update` reads to detect drift, mirrored by
`install.yaml.kit_version`.

`init-apply` also records the **content-addressed kit pin** in the manifest
(issue #177): `kit_ref` and `kit_sha` come straight from Step 0's `resolve`
(the fetched `kit/vX.Y.Z` tag and the commit it resolved to), threaded through
`--decisions`. Alongside the pin, `kit_provenance`
(`published-tag` / `explicit` / `cache`, also from Step 0) records *how*
the install resolved its kit (issue #194). Together these make the repo's
manifest the authoritative statement of which kit it runs and how it got there —
`update` fetches that ref and delegates apply to its engine. See
[INSTALL_SCHEMA.md](INSTALL_SCHEMA.md) and [UPDATE_FLOW.md](UPDATE_FLOW.md).

`init` only installs the bash runner. Governance is a meta-layer that sits on top of the project's code — coupling the directive suite to the project's own test runner (pytest / jest / go test) inverts the dependency. Bash works in any repo, in any CI, without install steps. Users who want governance failures to surface alongside their normal test report can add native test wrappers post-init by following [NATIVE_TESTS.md](NATIVE_TESTS.md) — that is an opt-in enhancement, not part of bootstrap.

### Step 6 — The git hooks (generated by `init-apply`)

Hooks are **generated**, not copied. `init-apply` builds a hook spec from the
installed directive folders and calls `hooks.sh generate_hooks_for_strategy`
(via the shared `applylib.regenerate_hooks`) under the decisions'
`hook_strategy`. The wrapper emits all five dispatchers — `pre-commit`,
`commit-msg`, `prepare-commit-msg`, `post-commit`, `pre-push` — into the right
dir per strategy (`.githooks/` / `.husky/` / `.governance/hooks/`) with identical
bodies, each carrying the line-2 ownership marker. Every dispatcher scans
installed `directive.yaml` files at runtime, runs directive-owned
`hooks/<kind>.sh` populators first, then `check.sh` for matching `hook:`
declarations, and honors `SKIP_GOVERNANCE=1`. **Never** hand-roll a `bash
.governance/run.sh` shim into a host framework — that flat runner skips `hook:`
filtering and populators, the exact gap the generator closes.

For **`githooks`** (default when no other framework is present), `init-apply`
also runs `git config core.hooksPath .githooks` and lays down + stamps
`scripts/enable-governance.sh` — the one-command onboarding every other
contributor runs once per fresh clone. In the final report, point new
contributors at it (in `README.md` or `AGENTS.md`); until they run it,
`required-docs` nags with the exact command. `init-apply` does **not** create
files under `.git/hooks/`; if `.git/hooks/pre-commit` already exists from another
tool, surface it before proceeding (it could be a husky / pre-commit.com hook).

The `hook_strategy` and any **collision resolution** stay the operator's call (the
plan/apply mechanics don't pick a framework or resolve an unmarked-hook
conflict):

**Pre-existing hook collision (unmarked).** If the survey in Step 1 found a target hook that exists and lacks the ownership marker, STOP before running `init-apply`. Show the user the existing hook and offer three options:

1. **Wrap** (default) — write the generated hook, rename the existing one to `<name>.userhook`, and exec it at the end of the generated hook. Keeps both behaviors.
2. **Merge by hand** — print both scripts, skip hook install, rely on CI.
3. **Overwrite + backup** — back up the existing hook to `<path>.pre-governance.bak`, then write ours. Warn in the final summary.

If the existing hook **has** the marker, overwrite silently — `governance directive *` relies on this. (The marker is a contract: "this file is regeneratable.")

**Path B — existing hook framework.** If the project uses `husky` or the `pre-commit` framework, *do not* set `core.hooksPath` and do not copy into `.githooks/` — those frameworks already have their own tracked hook-config mechanism. Generate dispatchers via the same strategy-aware entry point used in Path A — only the strategy and the resulting install dir change.

In this path:
- For husky: call `generate_hooks_for_strategy <repo-root> husky <version> <spec>`. The wrapper writes all five dispatchers into `.husky/` so directive-owned populator hooks (`directives/<id>/hooks/<kind>.sh`) are wired uniformly. Each generated file carries the line-2 ownership marker; existing unmarked hooks trigger the same collision flow as Path A.
- For pre-commit.com: call `generate_hooks_for_strategy <repo-root> pre-commit <version> <spec>` to materialize dispatchers under `.governance/hooks/`, then add a `.pre-commit-config.yaml` hook block per stage that shells out to `bash .governance/hooks/<kind>`. See [NATIVE_TESTS.md](NATIVE_TESTS.md) for the per-framework snippets.
- Record `hook_strategy: husky` or `hook_strategy: pre-commit` in `.governance/install.yaml` so `required-docs`' `hooks` sub-check transparently skips (it only enforces `.githooks/` scaffolding when `hook_strategy` is `githooks`).
- Record each materialized hook file under `path_b.entries` with its fingerprint so `governance uninstall` and `governance reset` can recognize the kit's output.
- Tell the user explicitly that the repo is using its existing tracked hook framework instead of `.githooks/`, and that populator coverage (token-accounting, steering-accounting) now matches Path A.

### Step 7 — The CI workflow (installed by `init-apply`)

`init-apply` copies `../assets/governance.yml` → `.github/workflows/governance.yml`
and stamps it. The workflow runs `bash .governance/run.sh` on `push` to `main`
and on every `pull_request`, and never skips — CI is the backstop the pre-commit
hook can be bypassed around. If the user later opts into native tests via
[NATIVE_TESTS.md](NATIVE_TESTS.md), they extend the workflow at that point.

### Step 8 — Validate the working tree and resolve findings

Goal: make the install commit pass every installed directive on the first try, with **no `SKIP_GOVERNANCE` and no bootstrap-only waivers**. This is the step that makes "no audit gap at bootstrap" possible.

1. **Stage the install output.** `git add` everything Steps 4–7 wrote: `CONSTITUTION.md`, `AGENTS.md` (if seeded/edited), `.governance/`, `.githooks/` (or the Path-B equivalent), `.github/workflows/governance.yml`, `scripts/enable-governance.sh`, and any install-assets (`COSTS.md`, `STEERING.md`, `QUALITY.md`, …).

2. **Seed the bootstrap receipt.** If `commit-issue-receipt-match` is installed, create `receipts/issue-<N>-bootstrap-governance.md` from [`../assets/receipt.bootstrap.template.md`](../assets/receipt.bootstrap.template.md), substituting the bootstrap issue number `<N>` and the actual install choices. Stage it. (`<N>` is the GitHub issue the operator filed to track the adoption — surface that anchor up front in the survey if it isn't already known.)

3. **Dry-run all validators against the staged tree.** Run `bash .governance/run.sh`. Mode-B walkers (`agent-token-accounting`, `agent-steering-accounting`, `commit-issue-receipt-match`) are no-ops here (no new commit yet) — they fire when Step 9's commit lands. Every other directive sees the staged tree via `git ls-files`, so file-shape findings surface now.

4. **Resolve each finding, prefering inline fix over bypass.** For each failing directive, take the most surgical fix:

   | Directive | Resolve via |
   |---|---|
   | `repo-hygiene` (merge markers, build artefacts, large files) | Remove the offending file if safe; otherwise add `governance: allow-repo-hygiene file-size-limit <ticket-or-reason>` to the file's head. Re-stage. |
   | `secrets-hygiene` (tracked `.env`, AWS key pattern, etc.) | **Rotate first, then remove.** Add the file to `.gitignore`. The line-level waiver `governance: allow-secrets-hygiene <ticket>` is only for legacy already-leaked credentials that are queued for rotation. |
   | `pinned-dependencies` (tag-pinned actions) | SHA-pin every third-party action; re-stage the workflow file. |
   | `token-permissions` (missing `permissions:`) | Add an explicit least-privilege `permissions:` block; re-stage the workflow file. |
   | `required-docs` (missing `LICENSE`, `SECURITY.md`, etc.) | Stub the missing file with a one-line placeholder the operator will flesh out. If they explicitly opted out of `required-docs`, this won't fire. |
   | `issue-templates` (missing `.github/ISSUE_TEMPLATE/*.md`) | Generate the templates the directive expects; the directive's `install-assets/` carries the canonical shape. |
   | `internal-doc-links` (`resolve` sub-check) | Fix the broken link; do not waive. The `reachable` sub-check stays off unless the repo opts in via `.governance/conf/governance-kit/docs/internal-doc-links.conf`. |
   | `commit-message-format`, `commit-issue-receipt-match`, `receipt-per-issue` | The bootstrap receipt + Step 9's commit subject together satisfy these. |

   If a finding can't be inline-fixed (rotating a credential, removing a load-bearing legacy artefact), **pause init and surface it to the operator** — do not paper over it with a broader waiver.

5. **Re-run `bash .governance/run.sh` until it exits green.** Then proceed to Step 9. The pre-commit hook will see the same tree and pass on the first try.

### Step 9 — Make the install commit and report to the user

Run a normal `git commit` — no `SKIP_GOVERNANCE`, no `--no-verify`, no waiver in the body:

```sh
git commit -m "feat(governance): bootstrap governance-driven development (#<N>)"
```

What happens on this commit:

- **`hooks/pre-commit.sh` populators** fire normally. `agent-token-accounting` reads the active session transcript via `runtimes/<runtime>.sh`, appends the matching row to `COSTS.md`, writes the handoff env file. `agent-steering-accounting` does the same for `STEERING.md`.
- **`hooks/prepare-commit-msg.sh` stampers** consume the handoff and stamp the eight token trailers + the three steering trailers onto the install commit's message.
- **`commit-msg` validators** all pass — the tree is clean (Step 8), the trailers are stamped (populators ran), and the receipt is in place (Step 8.2).

The install commit lands with **real token trailers and a real `COSTS.md` row** — the directives are satisfied with data, not with exemptions.

**Runtime-not-detected fallback.** If `init` was invoked from a shell with no `CLAUDECODE` / `CODEX_THREAD_ID` (etc.), the token-accounting populator can't read a transcript and stamps nothing. Add `governance: allow-agent-token-accounting unsupported-runtime: bootstrapped from non-agent shell` to the commit body before running `git commit`. The validator then bypasses the trailer requirement for this commit only — and `git log --grep='allow-agent-token-accounting'` keeps the gap visible forever. The steering side needs no equivalent (its populator always stamps a zero-default triple via `prepare-commit-msg.sh`).

Print a concise summary:

- Packs selected.
- Preset chosen and whether it was explicit or assumed.
- Hook strategy chosen (`.githooks/`, husky, or `pre-commit`).
- Directives installed (with file paths, grouped by pack if multiple packs were selected).
- Directives deliberately skipped (with reasons) when that matters.
- Any pre-existing hook collisions encountered and how they were resolved.
- **Findings resolved in Step 8** — every inline fix and every per-file/per-line waiver added, with the reason recorded against it.
- **Findings escalated** — anything Step 8 could not inline-fix and surfaced to the operator (with the action they need to take).
- **Resolved kit** (Step 0): the target version and how it resolved (`published-tag` / `explicit` / `cache`).
- **Detected runtime** at commit time: `claude-code`, `codex`, or `none`. If `none`, mention the body waiver that was applied.
- **Install commit SHA** that just landed.
- How to run locally: `bash .governance/run.sh`.
- How to skip in an emergency: `SKIP_GOVERNANCE=1 git commit ...` or `git commit --no-verify`. (Not for the install commit — that's what Step 8 is for. Emergencies only.)
- Assumptions made. If none, say `Assumptions: none`.
- Reminder: **constitution amendments must land with their test.** Point to [DIRECTIVES_CATALOG.md](DIRECTIVES_CATALOG.md) and (if multiple packs were selected) [PACK_AUTHORING.md](PACK_AUTHORING.md) for the templates.

## Required final output

Every successful `install` run should leave the user with a summary that includes:

- `Resolved kit:` `<version> via published-tag | explicit (--to) | cache` (Step 0). On the `cache` provenance, note upstream was not consulted.
- `Packs:` the list of selected packs.
- `Preset:` chosen preset and whether it was explicit or assumed.
- `Hook strategy:` `.githooks/`, husky, or `pre-commit`.
- `Directives installed:` file-backed list or grouped summary.
- `Directives skipped:` only when the omission is meaningful.
- `Hook collisions:` the resolution chosen for each pre-existing unmarked hook, or `none`.
- `Findings resolved:` every inline fix or waiver added in Step 8, with reason.
- `Findings escalated:` anything Step 8 could not inline-fix, with the action the operator needs to take, or `none`.
- `Detected runtime:` `claude-code` / `codex` / `none`. If `none` and audit-chain directives were installed, mention the unsupported-runtime waiver applied to the install commit.
- `Install commit:` SHA of the commit Step 9 just landed.
- `Assumptions:` any material assumptions, or `none`.
- `Next command:` `bash .governance/run.sh`

---

## Key design principles

- **The constitution and the tests evolve together.** Never add a directive to the constitution without a test. Never add a test without a directive. If the user asks to add one in isolation, push back and do both.
- **Packs are the extension point.** Adding a directive to a pack is a two-file edit (the `.sh` + the manifest entry); every menu, hook dispatcher, and constitution snippet flows from the manifest. Do not shadow the manifest with hand-written lists in SKILL.md.
- **The bundled `governance-kit/*` packs are non-optional.** Users can select additional packs but cannot deselect the bundled concern packs. The `always_install: true` flag is reserved to the bundled `governance-kit/*` packs — third-party packs cannot force-install directives.
- **Preset semantics are union, not fallback.** If a pack lacks the selected preset, it contributes nothing for that preset.
- **Escape hatches are a feature, not a bug.** `SKIP_GOVERNANCE=1` exists because governance that blocks emergency hotfixes will get ripped out. CI enforces the directive even when the hook is skipped, which is the right layering.
- **The install commit passes validators on the first try.** Step 8 dry-runs every directive against the staged tree and inline-fixes findings (or escalates them); Step 9 commits through normal hooks. `SKIP_GOVERNANCE` is not a bootstrap tool — using it on the install commit skips the populators too, which leaves the audit chain unsatisfiable for that commit forever. Inline-fix is the contract; bypass is the emergency exit.
- **No bootstrap exemption in directive `check.sh` files.** If a directive needs an install-commit accommodation, that's a flow gap in Step 8 — fix the flow, not the directive. The one body-level waiver this PR keeps (`allow-agent-token-accounting unsupported-runtime: <reason>`) is for subsequent commits with no `runtimes/<name>.sh` adapter, not a bootstrap workaround.
- **Bash-only at bootstrap; native is post-init.** Governance is a meta-layer over the project's code, so the directive suite must not depend on the project's own toolchain. `init` only installs the bash runner. Native test wrappers (pytest / jest / go test) are an opt-in users add later via [NATIVE_TESTS.md](NATIVE_TESTS.md) — never asked at bootstrap.
- **Respect the repo's existing hook framework.** `.githooks/` is the default only when no tracked hook framework already exists. Do not force repos off husky or `pre-commit`.
- **Hook ownership is explicit.** Every generated hook carries a `governance-kit:managed kit-version=<v>` marker on line 2 — the same shape runtime templates use. An unmarked hook at a target path is somebody else's file — prompt before touching it.
- **Match the enforcement surface to the real intent.** If a directive is meant to govern each substantive change, do not implement it as a repo-exists or file-count check.
- **Reject weak proxies when they create false confidence.** A directive that says "every change must do X" but only checks "the repo contains one X somewhere" is a bad bootstrap output, not a partial success.
- **State material assumptions explicitly.** If you had to infer the preset or hook strategy, surface that in the summary.
- **No invented directives.** When writing the constitution, only include directives the user selected. Governance loses authority the moment it contains directives nobody signed off on.

## References

- [DIRECTIVES_CATALOG.md](DIRECTIVES_CATALOG.md) — full list of ready-made directives with descriptions, and the template for adding new ones. Notes pack membership per directive.
- [PACK_AUTHORING.md](PACK_AUTHORING.md) — how to write a third-party pack.
- [NATIVE_TESTS.md](NATIVE_TESTS.md) — how to port bash directives to pytest / jest / go test, and husky / pre-commit-framework snippets.
- [AGENT_TOKEN_ACCOUNTING.md](AGENT_TOKEN_ACCOUNTING.md) — wiring instructions for the `agent-token-accounting` directive shipped by the `governance-kit/audit` pack.
