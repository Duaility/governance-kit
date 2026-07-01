# issue-343: fix(audit): raise min_governance_kit floor to 0.12.0 for the subagent conf overlay

Closes [#343](https://github.com/Duaility/governance-kit/issues/343).

## Checklist

- [x] Raise `min_governance_kit` in `packs/audit/pack.yaml` from `0.10.0` to `0.12.0`
- [x] Update the floor rationale comment to cite the #333 conf-overlay dependency first shipped in kit/v0.12.0

## What changed

- **Raise `min_governance_kit` in `packs/audit/pack.yaml` from `0.10.0` to `0.12.0`.**
  The audit pack's `subagent:` tiers/isolation conf overlay (added in #333,
  shipping in audit v0.8.0) is resolved by kit-owned `lib.sh`/`sweep.py` —
  `subagent_attest` reads `SUBAGENT_ISOLATION` and the attest/sweep tiers via
  `conf_get`. Those helpers first ship to consumers in kit/v0.12.0, so a
  consumer on an older kit would silently ignore the overlay rows.
- **Update the floor rationale comment to cite the #333 conf-overlay dependency first shipped in kit/v0.12.0.**
  The comment block above the field in `packs/audit/pack.yaml` now cites that
  dependency, superseding the prior 0.10.0 rationale (#272/#319), and restates
  the first-shipped-tag convention.

## Out of scope

- Updating the consumed `.governance/` tree. This repo treats `.governance/` as
  a released consumer materialization; it catches up via the real `pack update`
  verb in a post-release dogfood-sync PR, never by hand.
- Any behavioral change to the conf-overlay resolution itself — that shipped in
  #333 (pack) and kit/v0.12.0 (runtime). This change only tightens the declared
  dependency floor so the overlay is guaranteed to work where the pack installs.

## Decisions

- **Floor = first-shipped kit tag, not source line.** Consistent with the
  established convention (#272/#319/#320): the helpers exist on an earlier
  source line but the floor is the first kit release that ships them to
  consumers — kit/v0.12.0.

## Verification

```sh
bash scripts/test-packs.sh
bash .governance/run.sh
```

Both passed locally. `kit-version-consistency` confirms kit.yaml (0.12.0) is
>= every pack `min_governance_kit` (audit now 0.12.0).

## Audit

Fresh-context sub-agent audit of the staged diff against issue #343 and this
receipt:

- PASS - Both "What changed" bullets describe exactly the two diff hunks in packs/audit/pack.yaml (floor 0.10.0→0.12.0; rationale comment rewritten to cite #333/kit v0.12.0 superseding #272/#319); no omission.
- PASS - Both [x] items are realized in the diff: line `min_governance_kit: "0.12.0"` and the replaced #343 comment block.
- PASS - Receipt Checklist matches issue #343's two items verbatim (only checkbox state differs).

## Layer boundaries

Fresh-context sub-agent layer audit against `ARCHITECTURE.md`:

- PASS - Both changed files sit in correct layers: `packs/audit/pack.yaml` is packs-layer metadata; `receipts/issue-343-*.md` is an audit record, not a source layer.
- PASS - `min_governance_kit: 0.12.0` is a downward version floor (packs declaring a minimum kit), not a new source edge; no upward packs→kit import added and `.governance/` untouched.
- PASS - No shared logic copied into a consumer layer; the diff only changes a version scalar and rationale prose plus a new Markdown receipt.

## Steering

Fresh-context review of the session transcript:

- PASS - No operator corrections in this session. The only operator input was the request to cut a release and a scope decision made via a clarifying question (cut both axes and raise the audit floor); neither is a correction of delivered work, so there are no `### Steering` rows to record.

## Accounting

<!-- Accounting rows are maintained by the agent-token-accounting and agent-steering-accounting pre-commit hooks. Keys are opaque — do not parse. -->

### Costs

| cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | cum-input | cum-cache-create | cum-cache-read | cum-output | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| claude-code-be37c0c7-060-1782902207-1 | claude-code | be37c0c7-0600-4af4-ad14-41e65c0017ef | #343 | claude-opus-4-8 | 44185 | 214972 | 4720815 | 79234 | 338391 | 5.9058 | 44185 | 214972 | 4720815 | 79234 | fix(audit): raise min_governance_kit floor to 0.12.0 for the subagent conf overl |
| claude-code-be37c0c7-060-1782902329-1 | claude-code | be37c0c7-0600-4af4-ad14-41e65c0017ef | #343 | claude-opus-4-8 | 2274 | 14868 | 578937 | 6771 | 23913 | 0.5630 | 46459 | 229840 | 5299752 | 86005 | fix(audit): raise min_governance_kit floor to 0.12.0 for the subagent conf overl |
