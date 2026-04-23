<!-- last-verified: 2026-04-23 -->

# 2026-04-23 — Model governance rules as extensible rule packs

## Goal

Refactor `governance-bootstrap` from a monolithic rule menu into a
pack-driven loader. Two packs ship in-tree — `core` (today's built-in rules)
and `agent-governance` (this repo's agent-driven-development rules, promoted
from `tests/governance/rules/`). Bootstrap reads `pack.yaml` manifests to
drive its menu, preset resolution, constitution-snippet insertion, hook
generation, and CI. Adding a rule drops from a 4-file edit (`.sh` +
`RULES_CATALOG.md` + `SKILL.md` menu + hook logic) to a 2-file edit (`.sh` +
manifest entry).

Closes [#23](https://github.com/Duaility/governance-kit/issues/23).

## Steps

Each step is a separate commit. The whole sequence lands as one PR.

1. **Manifest schema + loader + `core` pack.yaml.** Write
   `governance-bootstrap/assets/packs/core/pack.yaml` that covers every
   currently-shipped rule (21 rules today). Write a bash loader at
   `governance-bootstrap/assets/packs/lib/packs.sh` with helpers
   `list_packs`, `rules_for`, `preset_resolve`, `pack_rule_field`. Uses
   `yq` when available, falls back to a minimal pure-bash YAML parser
   (manifests are shallow and regular — a full YAML parser is overkill).
   Add a `scripts/test-packs.sh` skeleton that at least asserts the
   manifest is loadable.

2. **Directory migration.** Move
   `governance-bootstrap/assets/tests-bash/rules/*.sh` →
   `governance-bootstrap/assets/packs/core/rules/`. Extract per-rule
   Invariant subsections from `assets/CONSTITUTION.template.md` into
   `assets/packs/core/constitution-snippets/<rule>.md`. The template
   becomes a minimal shell — principles + compliance block + an empty
   Invariants section that the bootstrap skill fills by copying snippets.
   Delete `assets/tests-bash/rules/` (big-bang migration per the issue's
   resolved decisions).

3. **Create `agent-governance` pack.** Author
   `governance-bootstrap/assets/packs/agent-governance/pack.yaml`
   covering `agent-token-accounting`, `plan-per-issue`,
   `commit-issue-plan-match`, `issues-tracked`. Copy (do not move — they
   stay live in this repo under `tests/governance/rules/` too) the rule
   scripts into `assets/packs/agent-governance/rules/`. Extract their
   Invariant subsections from this repo's `CONSTITUTION.md` into
   matching `constitution-snippets/`. Introduce the new category
   `AgentDiscipline` that the bootstrap menu will surface.

4. **Rewrite `SKILL.md` activation flow.** Replace the hand-written Step 3
   menu with: Step 2.5 pack discovery, Q0 pack multiselect (core always
   selected), Q1 preset choice (`minimal` / `standard` / `strict` /
   `custom`), dynamic Q2..Qn category screens built from the union of
   selected packs' rules. Preset semantics: union across packs; packs
   without the preset name contribute nothing.
   Installation step copies `rules/*.sh` into `tests/governance/rules/`
   (flat layout, reject ID collisions) and
   `constitution-snippets/<rule>.md` into the appropriate Invariant
   subsection of `CONSTITUTION.md`.

5. **Hook generation.** Replace the hardcoded copy of
   `assets/githooks/{pre-commit,commit-msg}` with a generator that emits
   dispatchers from the selected rules' `hook:` declarations:
   - `.githooks/pre-commit` — iterates every `rules/*.sh` with
     `hook: pre-commit` (today's run.sh behavior, but the set is
     manifest-driven).
   - `.githooks/commit-msg` — installed only if ≥1 selected rule
     declares `hook: commit-msg`; iterates just those rules.
   - `.githooks/prepare-commit-msg` — same pattern.
   - Each generated hook carries an ownership marker on line 2:
     `# governance-kit:managed pack-version=<v> generated=<YYYY-MM-DD>`.
   - Collision detection (in Step 1 survey): if target hook exists and
     lacks the marker, prompt: (1) wrap (default), (2) merge by hand,
     (3) overwrite + backup to `<path>.pre-governance.bak`.

6. **Evals infrastructure + CI job.** Add `scripts/test-packs.sh` that
   iterates `governance-bootstrap/assets/packs/*/evals/*/test.sh`. Add at
   least one eval per rule in `core` and `agent-governance` — each eval
   creates a temp-repo fixture, runs the rule against it, asserts
   pass/fail matches expectation. Wire into
   `.github/workflows/governance.yml` as an additional job.

7. **Docs updates.** Update `README.md`, `AGENTS.md`,
   `governance-bootstrap/references/RULES_CATALOG.md` (note pack
   membership per rule). Add new
   `governance-bootstrap/references/AUTHORING_PACKS.md` explaining how
   to write a third-party pack. Update the skill evals at
   `governance-bootstrap/evals/evals.json` if their assertions mention
   paths that moved.

8. **Evolution-log entry.** Append an entry to this repo's
   `CONSTITUTION.md` Evolution Log describing the migration.

## Resolved design decisions

Captured from the issue; noted here for future reviewers:

- Manifest format: **YAML**.
- Backwards compatibility: **big-bang** (skill is v0.1).
- Target-repo rule layout: **flat** `tests/governance/rules/`; collisions
  rejected at install.
- Pack discovery scope: **in-tree only** (`assets/packs/*`) for v1.
- Preset semantics across packs: **union**.
- Constitution snippet shape: **full Invariant subsection** (Rule /
  Rationale / Enforced by / Exceptions).
- Eval runner: **bash-only** for v1.
- Rule drift detection: **gardener concern**, not bootstrap.
- `always_install: true`: **reserved to `core`**; third-party packs
  cannot set it.
- Pack versioning: add `version:` and `min_governance_kit:` now, enforce
  loosely.

## Out of scope

- Remote pack fetching / registry / `GOVERNANCE_PACKS` env var.
- Auto-generated `RULES_CATALOG.md` from manifests.
- `governance-gardener` pack-drift detection.
- `governance-amend` pack awareness.
- Native-test generation from manifests (NATIVE_TESTS.md stays on-demand).
- Non-bash eval runners.

## Rationale for bundling

The issue explicitly asks for a big-bang migration. Splitting it into
multiple PRs would leave the repo in an intermediate state where the
skill references paths that no longer exist or where `agent-governance`
rules are duplicated between the pack and `tests/governance/rules/`
without a loader that can reconcile them. The 8 commits within one PR
keep each reviewable diff small while the working tree stays green at
every step.

## Progress

- [x] Step 1 — manifest schema + loader + core pack.yaml
- [x] Step 2 — directory migration into packs/core/
- [x] Step 3 — agent-governance pack
- [x] Step 4 — SKILL.md activation-flow rewrite
- [x] Step 5 — hook generation + collision detection
- [x] Step 6 — evals infrastructure + CI job
- [x] Step 7 — docs updates
- [x] Step 8 — evolution-log entry

## Test plan

- [ ] `scripts/test-packs.sh` passes locally and in CI against `core`
      and `agent-governance`.
- [ ] Bootstrap into a fresh test repo with `core` only + `standard`
      preset → installs same rules as today's `standard` preset.
- [ ] Bootstrap with `core` + `agent-governance` + `standard` preset →
      installs union of both standards.
- [ ] Bootstrap with `custom` preset → no preselected rules; dynamic
      menu populates from union of selected packs.
- [ ] Bootstrap twice into same repo (augment) → marker-bearing hooks
      overwrite silently; no duplicate rules.
- [ ] Bootstrap into repo with pre-existing unmarked `.githooks/pre-commit`
      → prompt; `wrap` produces working combined hook.
- [ ] Bootstrap into husky repo → Path B still works; `.githooks/`
      untouched.
- [ ] Two rules with same `id` across selected packs → install fails
      with clear error.
- [ ] Third-party pack declaring `always_install: true` → rejected.
- [ ] Pack with no `strict` preset + user picks `strict` → contributes
      nothing from that pack (union, not fallback).
- [ ] Dogfood: `agent-governance` pack produces an identical governance
      surface to what exists today when re-bootstrapped into this repo.
- [ ] No dangling references to `assets/tests-bash/rules/` in tracked
      files after migration.
- [ ] `bash tests/governance/run.sh` green on this branch.
- [x] `scripts/test-packs.sh` green in CI (mikefarah yq): loader must
      fall back to awk when yq's expression dialect rejects the
      jq-style `.id // ""` form.
- [x] Rules modelled as **atoms**: each rule is a self-contained folder
      `rules/<id>/` with `rule.yaml` + `check.sh` + `constitution.md` +
      `evals/test.sh`. `pack.yaml` carries only pack identity and the
      preset graph — no flat `rules:` block, no sibling
      `constitution-snippets/` or `evals/` directories. Adding /
      removing / reshuffling a rule is one `git mv` of its folder.
