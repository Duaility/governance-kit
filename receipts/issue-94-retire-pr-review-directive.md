# Issue 94: Retire pr-review-required-when-pr-ready Directive

## Checklist

- [x] Delete the directive folder under extensions/packs/agent-governance/directives/.
- [x] Delete the dogfood install under .governance/packs/duaility/agent-governance/directives/.
- [x] Drop the directive id from the agent-governance pack standard preset.
- [x] Remove the directive row from README.md, the agent-governance README.md, and DIRECTIVES_CATALOG.md.
- [x] Remove the directive entry from .governance/installed-packs.yaml.
- [x] Add an evolution log entry to CONSTITUTION.md.

## What changed

The `pr-review-required-when-pr-ready` directive demanded that every non-draft PR carry a codex-authored review (body containing `<!-- codex-review -->`) and ran from `post-commit` as a local advisory skipped in CI. In practice it was too coupled to one external reviewer tool (codex) and one marker convention, fired on every commit while the PR remained non-draft (re-demanding fresh codex reviews on every iteration), and was too opinionated for a directive shipped in the `standard` preset of a community pack.

**Delete the directive folder under extensions/packs/agent-governance/directives/.** The pack-source folder `extensions/packs/agent-governance/directives/pr-review-required-when-pr-ready/` (containing `directive.yaml`, `check.sh`, `constitution.md`, and `evals/test.sh`) is removed entirely.

**Delete the dogfood install under .governance/packs/duaility/agent-governance/directives/.** The dogfood mirror at `.governance/packs/duaility/agent-governance/directives/pr-review-required-when-pr-ready/` is removed in lockstep.

**Drop the directive id from the agent-governance pack standard preset.** `extensions/packs/agent-governance/pack.yaml` no longer lists `pr-review-required-when-pr-ready` under `presets.standard.directives`. The `standard` preset is now `issue-templates`, `issues-tracked`, `agent-token-accounting` (5 directives cumulative when extending `minimal`).

**Remove the directive row from README.md, the agent-governance README.md, and DIRECTIVES_CATALOG.md.** `README.md` (top-level catalog table), `extensions/packs/agent-governance/README.md` (auxiliary directives section + preset table), and `governance/references/DIRECTIVES_CATALOG.md` (catalog row + `standard` preset row) all drop their references.

**Remove the directive entry from .governance/installed-packs.yaml.** The dogfood install manifest no longer lists the directive under the `duaility/agent-governance` pack.

**Add an evolution log entry to CONSTITUTION.md.** The retirement is recorded under `## Evolution Log` with the date, motivation, and an explicit note that historical receipts and prior evolution-log entries that reference the retired id are intentionally not rewritten — they describe what was true at the time. The kit's `post-commit` hook infrastructure (`packctl.py` `HOOKS` set, `hooks.sh` `_emit_post_commit`, the dispatcher generator) is kept since it is generally useful for future advisory directives.

## Out of scope

Receipts and prior evolution-log entries that reference the retired id are not rewritten — they are historical records of what was true at the time. No alias period or shim is provided. V0 stance applies.

## Verification

- `bash .governance/run.sh` — 14 directives pass (was 15 before retirement).
- `bash scripts/test.sh` — pack smoke now reports `2 pack(s), 14 directive(s), 14 eval(s) passed`.
- `find . -name "pr-review-required-when-pr-ready" -type d` returns nothing under `extensions/` or `.governance/`.
- `grep -rln "pr-review-required-when-pr-ready"` outside `receipts/` and the `## Evolution Log` section of `CONSTITUTION.md` returns nothing.
