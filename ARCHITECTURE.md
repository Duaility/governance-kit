# Architecture

How `governance-kit` is organised, and how the pieces fit together.

## Surfaces

`governance-kit` ships four agent-runtime skills plus a shared ruleset.
Each skill is a self-contained directory with frontmatter
(`SKILL.md`), optional `assets/`, `references/`, and `evals/`.

- `governance-bootstrap/` — scaffolds `CONSTITUTION.md`,
  `tests/governance/`, hook dispatchers, and CI workflow into a target
  repo. Reads rule packs from `assets/packs/<pack>/`.
- `governance-amend/` — atomically adds or modifies a rule: edits
  `constitution.md`, writes the check, and appends an Evolution Log
  entry in a single commit.
- `governance-gardener/` — walks the installed governance surface and
  emits a Governance Health Report.
- `governance-reset/` — reverses every bootstrap side-effect, using
  ownership markers so we only remove what we wrote.

## Rule packs

Each pack is a directory under `governance-bootstrap/assets/packs/`:

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

Two packs ship in-tree: `core` (general-purpose) and `agent-governance`
(issue/plan/commit/cost chain for agent-driven repos).

## Rule lifecycle

1. Author writes `rules/<id>/` folder and registers it in the pack's
   `pack.yaml` preset.
2. `scripts/test-packs.sh` validates the pack structure, exercises
   every eval, and installs `core.standard` into a disposable repo to
   confirm the bootstrap contract still holds.
3. Bootstrap copies the rule folder into `tests/governance/rules/<id>/`
   in the target repo and records the selection in
   `.governance-kit/installed-packs.yaml`.
4. Hook generator builds `.githooks/pre-commit`, `.githooks/commit-msg`,
   `.githooks/prepare-commit-msg` from the installed manifest. Each
   dispatcher carries an ownership marker so governance-reset can
   identify and remove it safely.
5. On commit, `tests/governance/run.sh` discovers every installed rule
   and runs `check.sh` against the repo state.

## Invariants

- Rule folders are self-contained. Relocating a rule is one `git mv`.
- The hook generator reads `rule.yaml` at install time — it does not
  import any pack-wide registry.
- `always_install: true` is reserved to the `core` pack.
- Generated files carry ownership markers; governance-reset is allowed
  to remove only files it can identify as its own.
- The fresh-repo contract in `scripts/test-packs.sh` proves that a
  new repo bootstrapped with `core.standard` runs green end-to-end.
