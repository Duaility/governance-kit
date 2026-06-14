# issue-267 — stop digesting local-only hook plumbing; de-vendor enable-governance.sh

Closes [#267](https://github.com/Duaility/governance-kit/issues/267).

## Checklist

- [x] Hook dispatchers are no longer digested
- [x] `enable-governance.sh` is de-vendored
- [x] Enablement stays kit-owned
- [x] Closed the dogfood gap with an eval

## What changed

- **Hook dispatchers are no longer digested (the bug).** `digestlib.managed_runtime_files`
  dropped the `.githooks/*` / `.husky/*` / `.governance/hooks/*` globbing block (and the
  `enable_governance_script` candidate). The digest set is now the **trust-chain** artifacts
  CI actually executes — `run.sh`, `lib.sh`, the CI workflow, and the sweep pair — nothing
  else. This removes both Wrap failure modes at the root: the agent can append
  `exec <kind>.userhook` to the generated dispatcher (Failure 1) and the `<kind>.userhook`
  itself can sit in the hook dir (Failure 2) without diverging any recorded digest. No
  runtime `.userhook` discovery machinery was needed.
- **`enable-governance.sh` is de-vendored.** Deleted `kit/assets/enable-governance.sh`;
  removed its stamping from `initapply.py`, its reconstructed-manifest pairing from
  `kitapply.py`, its update inventory + marker-reconstruction candidate from `kitverb.py`,
  and the `--enable-governance-script` flag + manifest write from `install.sh`. New installs
  never write `enable_governance_script` to `install.yaml`.
- **Enablement stays kit-owned.** `init-apply` still runs `git config core.hooksPath .githooks`
  for the `githooks` strategy. A fresh clone without the kit re-enables local hooks with the
  documented one-liner `git config core.hooksPath .githooks` (now in the root README's
  Contributing block); skipping it costs only local fast-feedback — CI still enforces.
- **Closed the dogfood gap with an eval.** `scripts/test-init.py` gains
  `test_init_apply_wrap_collision_then_commit_is_clean`: it stashes a pre-existing hook as
  `pre-commit.userhook`, runs `init-apply`, appends the `exec` wrap line to the generated
  dispatcher, and asserts `managed-tree-integrity` reports zero violations — the exact path
  this repo never exercises because it has no hook collision.
- **Docs + tests updated.** The `managed-tree-integrity` directive `constitution.md` and
  `DIRECTIVES_CATALOG.md` now state the dispatchers are out of scope; `INSTALL_SCHEMA.md`,
  `UPDATE_FLOW.md`, `UNINSTALL_FLOW.md`, `UNINSTALL_MATRIX.md`, `INIT_FLOW.md`, and `VERBS.md`
  drop `enable-governance.sh` from the managed/re-synced sets (marking it legacy where
  uninstall still cleans it up). `test-kitverb.py` / `test-kitresolve.py` / `test-install-sh.sh`
  drop the file as a fixture, repointing the unmanaged-decision tests at an unmarked CI workflow.

## Out of scope

- **Legacy uninstall cleanup is kept.** `uninstallplan.py` still deletes
  `scripts/enable-governance.sh` when a pre-#267 manifest records the field — graceful
  cleanup for repos that were installed before this change. New installs never set the field,
  so the branch is a no-op for them.
- **The dogfood's own vendored `scripts/enable-governance.sh`** (a legacy install artifact)
  is left in place; it is part of the consumed `.governance/` tree, which moves only via the
  post-release `governance update`, never by hand.
- The four `kit/evals/kit-update/files/*` fixtures retain `enable_governance_script:` as
  legacy-install representations; the update verb now correctly ignores the field.

## Decisions

- **Exclude vs. discover-at-runtime.** The issue's Reframe is decisive: the dispatchers sit
  outside the CI trust chain (`bash .governance/run.sh` never reads `core.hooksPath`), are
  intentionally bypassable (`SKIP_GOVERNANCE=1` / `--no-verify`), and are regenerated from
  `(kit, install set, strategy)`. Digesting them bought near-zero protection, so the fix is
  to not record them — not to add `.userhook` discovery to the generator.
- **Delete the kit asset rather than keep it dead.** With nothing in install/update reading
  `kit/assets/enable-governance.sh`, keeping it would be dead code in a trust tool (kit is V0;
  no backcompat constraint). The one-liner fully replaces its only unique role.
- **Eval as a deterministic test, not prose.** The collision-then-commit path is asserted in
  `test-init.py` (run by CI) rather than only described in an LLM-judged eval, so the
  regression is caught mechanically.

## Verification

```sh
uv run --with PyYAML python scripts/test-digestlib.py        # parity + determinism green
uv run --with PyYAML python scripts/test-init.py             # incl. new Wrap collision test
uv run --with PyYAML python scripts/test-kitverb.py          # unmanaged-decision tests repointed
uv run --with PyYAML python scripts/test-kitresolve.py
uv run --with PyYAML python scripts/test-reset-uninstall.py  # legacy uninstall still cleans up
bash scripts/test-install-sh.sh                              # 77 assertions
bash scripts/test-packs.sh                                   # 6 packs, 21 directives
bash packs/foundation/directives/managed-tree-integrity/evals/test.sh
bash .governance/run.sh                                      # dogfood suite green (18 directives)
```

## Accounting

<!-- Accounting rows are maintained by the agent-token-accounting and agent-steering-accounting pre-commit hooks. Keys are opaque — do not parse. -->

### Steering

| steer-key | session | issue | type | tier | user-reason | commit |
| --- | --- | --- | --- | --- | --- | --- |

### Costs

| cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| claude-code-8b4319bb-810-1781431768-1 | claude-code | 8b4319bb-8108-4781-858b-a01b356f4277 | #267 | claude-opus-4-8 | 40933 | 456537 | 37028169 | 185134 | 682604 | 26.2005 | 40933 | 456537 | 37028169 | 185134 |  |
