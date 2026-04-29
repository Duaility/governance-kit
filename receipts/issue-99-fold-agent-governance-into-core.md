# issue-99 — fold agent-governance into core

Closes [#99](https://github.com/Duaility/governance-kit/issues/99).

## Checklist

- [x] Pack restructure
- [x] Catalog relocation
- [x] Extensions tree deleted
- [x] Dogfood update
- [x] Code updates
- [x] Doc updates
- [x] Evolution log entry

## What changed

- **Pack restructure.** Moved 6 directive folders (`receipt-per-issue`, `commit-issue-receipt-match`, `issue-templates`, `issues-tracked`, `agent-token-accounting`, `agent-steering-accounting`) from `extensions/packs/agent-governance/directives/` into `governance/assets/packs/core/directives/` via `git mv` so the rename history is preserved. The 5 chain directives joined core's `standard` preset; `agent-steering-accounting` remains opt-in (out of every preset) because it captures human correction text verbatim. Bumped `governance/assets/packs/core/pack.yaml` to `0.2` / `min_governance_kit: "0.2"`.
- **Catalog relocation.** Moved `catalog.community.json` + `catalog.schema.json` into `governance/assets/`. The catalog is now empty (the only entry was `duaility/agent-governance`, which is gone). The schema is preserved for future community packs and `governance pack search` continues to read it (returning no rows for now).
- **Extensions tree deleted.** Removed `extensions/README.md`, `extensions/packs/agent-governance/{README.md,pack.yaml}`, and the now-empty subdirectories. The monorepo-of-community-shaped-packs framing is gone — community packs live in their own repos and install via `governance pack add gh:<owner>/<repo>`.
- **Dogfood update.** `.governance/installed-packs.yaml` collapses two pack entries into one `governance-kit/core` block listing all 13 directives (7 prior core + 6 from agent-governance). `.governance/packs/duaility/agent-governance/` removed; its directive folders moved into `.governance/packs/governance-kit/core/directives/`. The hand-authored `duaility/governance-kit` pack (housing `pre-commit-test-gate`) is unaffected.
- **Code updates.** `secrets-hygiene/check.sh` drops the `extensions/packs/*` exclusion; `scripts/test-packs.sh` drops the `extensions/packs` discovery root and relaxes its synthetic commit-msg test (the standard preset now bundles `agent-token-accounting`, which demands real runtime trailers + a matching `COSTS.md` row, so a synthetic "good" message is no longer testable in isolation — only the bad-message rejection ping survives); `scripts/test-packverb.py` rebases its catalog/validate-pack tests onto temp-built catalogs and the in-tree core pack; `scripts/test-packctl.py` + `scripts/test-packctl-validate.py` drop the AGENT_PACK fixture and use a synthetic in-tmpdir pack for the `union-preset` test. The 6 moved eval `test.sh` files were updated for `PACK_DIR`, the relative `..`-depth to ROOT (now 7 levels, was 6), and the `CHECK` path. The `agent-steering-accounting/check.sh` self-bootstrap `DIRECTIVE_PATH` literal was updated in both the asset and the dogfood mirror so the move commit itself is treated as the install commit at the new path.
- **Doc updates.** Root `AGENTS.md`, `README.md`, `ARCHITECTURE.md`; `governance/SKILL.md`; all 6 directive `constitution.md` snippets (asset + dogfood mirrors, all `Enforced by:` paths repointed to the new `core` location); `governance/assets/COSTS.template.md`; the reference set under `governance/references/`. README's "Community packs" table was replaced with a "What's in core" section that lists every shipped directive and its preset.
- **Evolution log entry** added to `CONSTITUTION.md` describing the change, motivation, and removed surfaces. Historical evolution-log entries and prior receipts that reference the `agent-governance` pack id or the `extensions/` tree are intentionally not rewritten — they describe what was true at the time. Historical ledger rows in `COSTS.md`/`STEERING.md` (which reference `agent-governance` in commit subjects) are likewise preserved.

## Out of scope

- Renaming the `agent-token-accounting` and `agent-steering-accounting` directive ids — they keep their names even though the `agent-` prefix no longer disambiguates a pack boundary. A rename would churn every `COSTS.md` / `STEERING.md` row that quotes a directive id in its `note` column for no real win.
- Adding new community packs to the now-empty catalog.
- Changing the `agent-steering-accounting` privacy contract — it stays opt-in, out of every preset.
- Touching the `duaility/governance-kit` repo-local pack (`pre-commit-test-gate`).

## Verification

- `bash .governance/run.sh` → ✓ all 14 directives passed (`pre-commit-test-gate`, `agent-steering-accounting`, `agent-token-accounting`, `commit-issue-receipt-match`, `commit-message-format`, `doc-freshness`, `issue-templates`, `issues-tracked`, `no-broken-internal-doc-links`, `receipt-per-issue`, `repo-hygiene`, `required-docs`, `secrets-hygiene`, `workflows-hardened`).
- `bash scripts/test.sh` → ✓ all kit-internal test layers passed (`test-packs`: 1 pack, 14 directives, 14 evals; `test-packctl`, `test-packctl-validate`, `test-packverb`, `test-install-sh`, `test-hooks-sh`, `test-runtime` all green).
- `grep -rn "extensions/packs\|duaility/agent-governance" --include='*.md' --include='*.sh' --include='*.py' --include='*.yaml' --include='*.json'` → returns only historical content (receipts/, plans/, evolution log entries, historical `COSTS.md`/`STEERING.md` ledger rows).
