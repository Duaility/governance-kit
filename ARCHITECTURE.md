# Architecture

How `governance-kit` is organised, and how the pieces fit together.

## Surfaces

`governance-kit` ships two agent-runtime skills plus the pack tree.
Each skill is a self-contained directory with frontmatter
(`SKILL.md`), optional `assets/`, `references/`, and `evals/`.

- `governance/` — the unified lifecycle skill. Exposes four verb
  families (`init`, `uninstall`, `pack *`, `rule *`) that together
  own every mutation to the governance surface:
  `CONSTITUTION.md`, `tests/governance/`, hooks, the install manifest,
  and the AGENTS.md directive block. The per-verb flows are documented
  under `governance/references/`: `INIT_FLOW.md` (8 steps),
  `UNINSTALL_FLOW.md` (6 steps), `RULE_AMEND_FLOW.md` (atomic-triple),
  and `PACK_VERBS.md` (community-pack lifecycle).
- `governance-gardener/` — walks the installed governance surface and
  emits a Governance Health Report.

## Rule packs

Each pack is a directory. Two packs ship in-tree:

- `core` at `governance/assets/packs/core/` — kit-bundled general-purpose
  rules, always selected. Also houses the shared pack `lib/`
  (`packs.sh`, `install.sh`, `hooks.sh`, `packctl.py`, `packverb.py`,
  `eval-lib.sh`).
- `duaility/agent-governance` at `extensions/packs/agent-governance/` —
  community-shaped, authored as if hosted in its own repo. Opt-in per-repo.

Every pack has:

- `pack.yaml` — pack identity and presets (`minimal`, `standard`, `strict`).
- `rules/<rule-id>/` — self-contained rule folder:
  - `rule.yaml` — `category`, `recommended`, `summary`, `surface`, `hook`.
  - `check.sh` — the executable test, sourcing `lib.sh`.
  - `constitution.md` — the Invariant subsection copied into
    the target repo's `CONSTITUTION.md`.
  - `evals/test.sh` — pass/fail fixtures exercised by
    `scripts/test-packs.sh`.
  - Optional siblings: `install-assets/` (seed files), `hooks/*.sh`
    (rule-owned hook helpers), `runtimes/*.sh` (per-runtime logic).

## Rule lifecycle

1. Author writes `rules/<id>/` folder and registers it in the pack's
   `pack.yaml` preset.
2. `scripts/test-packs.sh` validates the pack structure, exercises
   every eval, and installs `core.standard` into a disposable repo to
   confirm the bootstrap contract still holds.
3. `governance init` copies the rule folder into
   `tests/governance/rules/<id>/` in the target repo and records the
   selection in `.governance-kit/installed-packs.yaml`.
4. Hook generator builds `.githooks/pre-commit`, `.githooks/commit-msg`,
   `.githooks/prepare-commit-msg` from the installed manifest. Each
   dispatcher carries an ownership marker so `governance uninstall` can
   identify and remove it safely.
5. On commit, `tests/governance/run.sh` discovers every installed rule
   and runs `check.sh` against the repo state.

## Invariants

- Rule folders are self-contained. Relocating a rule is one `git mv`.
- The hook generator reads `rule.yaml` at install time — it does not
  import any pack-wide registry.
- `always_install: true` is reserved to the `core` pack.
- Generated files carry ownership markers; `governance uninstall` is
  allowed to remove only files it can identify as its own.
- The fresh-repo contract in `scripts/test-packs.sh` proves that a
  new repo bootstrapped with `core.standard` runs green end-to-end.
