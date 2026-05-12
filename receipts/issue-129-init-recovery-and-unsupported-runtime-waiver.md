# issue-129 — init bootstrap-recovery flow + unsupported-runtime waiver

Closes [#129](https://github.com/Duaility/governance-kit/issues/129).

## Checklist

- [x] Redesign `governance init` so the install commit passes validators on the first try
- [x] Split Step 8 into dry-run + inline-fix; add Step 9 as the install commit
- [x] Drop the recommendation to use `SKIP_GOVERNANCE=1` on the install commit
- [x] Drop the implicit `directive_active_for` self-bootstrap exemption from `agent-steering-accounting/check.sh`
- [x] Add an `unsupported-runtime` body waiver to `agent-token-accounting/check.sh`
- [x] Add a bootstrap-receipt template under `governance/assets/`
- [x] Update both directive constitution snippets to declare the new behaviour
- [x] Update `AGENT_TOKEN_ACCOUNTING.md` and `AGENT_STEERING_ACCOUNTING.md` to drop bootstrap-waiver mentions

## What changed

- **Redesign `governance init` so the install commit passes validators on the first try.** The previous flow recommended `SKIP_GOVERNANCE=1` for the install commit and recovered via amend-through-hooks or bootstrap waivers; both papered over the underlying problem rather than fixing it. The new flow runs validators in a pre-commit dry-run, fixes findings inline (per-file waivers, generated receipt, hardened workflow) or escalates them to the operator, and only then runs `git commit` through normal hooks. No `SKIP_GOVERNANCE`, no bootstrap waiver, no audit gap.
- **Split Step 8 into dry-run + inline-fix; add Step 9 as the install commit.** `INIT_FLOW.md` now describes Step 8 as "Validate the working tree and resolve findings" — stage everything, seed the bootstrap receipt from the new template, run `bash .governance/run.sh` against the staged tree, resolve each failure with the most surgical fix in a directive→remediation table, and loop until green. Step 9 makes the normal install commit; the populators stamp real trailers and the validators pass.
- **Drop the recommendation to use `SKIP_GOVERNANCE=1` on the install commit.** The "Bootstrap commit and first-PR recovery" section is removed entirely from `INIT_FLOW.md`. The escape hatch still exists for emergencies but is no longer a bootstrap tool — the new design makes it unnecessary.
- **Drop the implicit `directive_active_for` self-bootstrap exemption from `agent-steering-accounting/check.sh`.** The implicit Mode B exemption silently skipped commits whose parent didn't yet carry the directive's `check.sh`. That asymmetry with `agent-token-accounting` is what tripped #129's agent into misdiagnosing the kit. Now there is no exemption in either directive: `prepare-commit-msg.sh` already stamps the zero-default summary triple when no runtime is detected, so a normal `git commit` from the init flow satisfies steering without any per-commit accommodation.
- **Add an `unsupported-runtime` body waiver to `agent-token-accounting/check.sh`.** `governance: allow-agent-token-accounting unsupported-runtime: <reason>` accepted on any commit, non-empty reason required, bypasses the trailer + ledger requirement. No `COSTS.md` row is written for waivered commits; the audit trail is the body line, discoverable via `git log --grep='allow-agent-token-accounting'`. This is the only body-level waiver this directive carries — it covers runtimes that have no `runtimes/<name>.sh` adapter and the init flow's "runtime not detected at install time" fallback.
- **Add a bootstrap-receipt template under `governance/assets/`.** `governance/assets/receipt.bootstrap.template.md` is what Step 8 instantiates as `receipts/issue-<N>-bootstrap-governance.md`. It follows the four-section receipt schema (`Checklist`, `What changed`, `Out of scope`, `Verification`) with placeholders for the install choices, the per-finding fixes, and the install commit's SHA.
- **Update both directive constitution snippets to declare the new behaviour.** `agent-token-accounting`'s Exceptions clause now lists only `unsupported-runtime` and explicitly notes "no bootstrap accommodation lives in this directive — `governance init` is responsible for making the install commit pass on the first try." `agent-steering-accounting`'s Exceptions clause notes the same and points at the always-on zero-default triple as the mechanism.
- **Update `AGENT_TOKEN_ACCOUNTING.md` and `AGENT_STEERING_ACCOUNTING.md` to drop bootstrap-waiver mentions.** Token doc's "What gets enforced where" table reflects the single remaining waiver; steering doc's "Escape hatches" section no longer mentions a bootstrap waiver and points at the populator's zero-default triple as the no-runtime fallback.

## Out of scope

- **`POPULATORS.md` top-level concept page.** The populator architecture is linked from `INIT_FLOW.md` and `AGENT_TOKEN_ACCOUNTING.md` but not yet hoisted to a SKILL.md-level top-level concept. Worth its own issue.
- **Auto-applying inline fixes for every finding category.** Step 8's directive→remediation table is the agent's playbook today; some categories (rotating a credential, removing a load-bearing legacy artefact) require human judgement and are explicitly escalated. A future iteration could codify more of the inline fixes into helpers.
- **Split `SKIP_GOVERNANCE` into validator-skip vs populator-skip.** Discussed during design; not needed under the new flow because the install commit no longer uses `SKIP_GOVERNANCE`. If a later emergency-hotfix scenario reintroduces the same gap, the split is the clean fix.
- **Migration shim for repos already bootstrapped under the prior implicit steering exemption.** The kit is V0; the directive is now strict and pre-existing repos may need to add a one-time fix to their first post-install commit.

## Verification

- `bash scripts/test.sh` → all kit-internal layers pass: packctl/packverb Python suites, install.sh, hooks.sh, runtime, schema-split, the 14-directive fresh-install contract, and 14 directive eval suites including the three new token-accounting cases.
- `bash .governance/run.sh` → dogfood `pre-commit-test-gate` passes.
- The new token-accounting eval cases exercise both the pass path (unsupported-runtime with a non-empty reason) and the fail paths (unsupported-runtime with empty reason rejected; no waiver + no trailers still fires the missing-Agent: violation).
- `INIT_FLOW.md` Step 8 is self-contained: an agent reading it cold has the staging order, the directive→remediation table, and the loop-until-green instruction. No outbound references to a "recovery" section are left dangling — that section is removed.
- `governance/assets/receipt.bootstrap.template.md` follows the `receipt-per-issue` four-section schema and uses substitution placeholders consistent with how `INIT_FLOW.md` Step 8 references them.
