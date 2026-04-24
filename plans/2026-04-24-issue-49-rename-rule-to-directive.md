<!-- last-verified: 2026-04-24 -->

# 2026-04-24 — Rename rule/invariant vocabulary to directive

## Goal

The governance-kit vocabulary was split between two overclaiming words —
`rule` (for the pack atom) and `invariant` (for the constitution subsection).
Both misrepresent what a hook actually guarantees. A `check.sh` that runs at
commit time is a *directive* — an authoritative instruction that binds the
change to a named outcome while leaving the implementation local — not a
mathematical invariant and not a "rule" in the disciplinary sense.

Normalize the public vocabulary before 1.0 while a breaking rename is still
cheap. Pre-1.0 means no alias period: the old names go away in one commit.

Closes [#49](https://github.com/Duaility/governance-kit/issues/49).

## Scope

### Renamed surfaces

- **Pack layout.** `rules/<id>/` → `directives/<id>/`, `rule.yaml` →
  `directive.yaml`.
- **Constitution.** `## Invariants` → `## Directives`, `**Rule**:` →
  `**Directive**:`.
- **Skill verbs.** `governance rule {add,modify,remove}` →
  `governance directive {add,modify,remove}`.
- **Bash API.** `rule_start` / `rule_end` / `rule_field` /
  `install_rule_folder` / `rules_for` / `install_rule_assets` /
  `rule_supports_hook_strategy` / `build_hook_spec_from_installed_rules`
  → the `directive_*` equivalents.
- **Install manifest.** `.governance-kit/installed-packs.yaml` v1 schema:
  `rules:` key → `directives:` key; `installed_path` values move from
  `tests/governance/rules/<id>` to `tests/governance/directives/<id>`.
- **Reference docs.** `RULES_CATALOG.md` → `DIRECTIVES_CATALOG.md`;
  `RULE_AMEND_FLOW.md` → `DIRECTIVE_AMEND_FLOW.md`; `RULE_VERBS.md` →
  `DIRECTIVE_VERBS.md`; `RULE_AUTHORING.md` → `DIRECTIVE_AUTHORING.md`.
- **Generated hook dispatchers.** Discover `directive.yaml` at runtime
  (`.githooks/pre-commit`, `.githooks/commit-msg`,
  `.githooks/prepare-commit-msg` all updated).

### Intentionally unchanged

- `check.sh` — the executable artefact keeps its name.
- Waiver tokens (`governance: allow-<id> <reason>`) — the `<id>` is
  user-chosen, so flipping the label would force every downstream waiver
  to rewrite.
- Append-only records: Evolution Log entries in `CONSTITUTION.md`,
  `plans/**`, `QUALITY.md`, `COSTS.md`. History is preserved verbatim
  — future entries use the new vocabulary.
- Idiomatic English where "rule" is figurative: the "cardinal rule"
  callout, the "Rules to follow" section heading (paired with its stable
  `<!-- governance: rules-to-follow -->` slug so future refactors can
  still anchor on it).
- Narrow engineering uses of `invariant` where it is the right word —
  e.g. ARCHITECTURE.md's `## Invariants` section about architectural
  invariants, agent-token-accounting's "new-work invariant" math.

## Approach

Single atomic commit that touches the live vocabulary surfaces across:

- `governance/assets/packs/core/directives/**` (7 directives) and
  `extensions/packs/agent-governance/directives/**` (5 directives).
- The in-tree dogfood at `tests/governance/directives/**`.
- The Python + bash pack loader (`packctl.py`, `packverb.py`,
  `scripts/test-packs.sh`, `scripts/test-packverb.py`).
- Every `SKILL.md` / reference doc under `governance/references/**`.
- Top-level docs: `README.md`, `AGENTS.md` (+ `CLAUDE.md` symlink),
  `ARCHITECTURE.md`, `GOVERNANCE_VOCABULARY.md`.
- Eval fixtures under `governance/evals/{bootstrap,amend,reset}/**`
  (including the fixture `CONSTITUTION.md`, `run.sh`,
  `installed-packs.yaml`, and `README.md` files that simulate user-state
  repos).
- GitHub Actions workflow labels in `.github/workflows/governance.yml`
  and the template `governance/assets/governance.yml`.

Historical append-only content (Evolution Log, plans/**, QUALITY.md,
COSTS.md row history) is deliberately left untouched — the repo's
own `plan-per-issue` + append-only policy treats those as record, not
current-state, so rewriting them would be a history edit.

## Validation

- `bash tests/governance/run.sh` exits 0 with `13 directive(s) passed`.
- `bash scripts/test-packs.sh` exits 0 with
  `2 pack(s), 13 directive(s), 13 eval(s) passed`, including the renamed
  `test_init_flow_does_not_reference_deleted_required_docs_directives`
  check in `scripts/test-packverb.py`.
- `grep -rn 'rule_start\|rule_end\|rule_field\|install_rule\|RULES_CATALOG\|RULE_AMEND\|RULE_VERBS\|RULE_AUTHORING\|always_install_rules'`
  returns matches only in append-only historical files (`plans/**`,
  `CONSTITUTION.md` Evolution Log, `QUALITY.md`, `COSTS.md`) — every
  live-code and live-doc match is gone.
- The PR's CI `governance` job and `pack-tests` job both pass.

## Evolution Log entry

The accompanying entry in `CONSTITUTION.md` cites this plan and
`#49`, and states the breaking-change contract so future readers can
see why the alias period was skipped.
