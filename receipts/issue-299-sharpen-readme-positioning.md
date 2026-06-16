# Issue 299: Sharpen README positioning for agent-heavy developers

Closes [#299](https://github.com/Duaility/governance-kit/issues/299).

## Checklist

- [x] Reframe the top tagline around shared repo memory for coding agents.
- [x] Rewrite the core idea around common agent workflow pain: drift, broad rewrites, cross-agent context loss, and hidden cost.
- [x] Keep the example rules crisp enough to orient developers without overwhelming them.
- [x] Verify the governance suite still passes.

## What changed

**Reframe the top tagline around shared repo memory for coding agents.** `README.md` now opens with "Give every coding agent the same repo memory" and a tighter value line focused on repeated steering, unwanted rewrites, token spend, and durable rules in git.

**Rewrite the core idea around common agent workflow pain: drift, broad rewrites, cross-agent context loss, and hidden cost.** The `README.md` core idea now starts from the developer experience of delegating work across Claude Code, Codex, and similar agents: narrow requests become broader diffs, stable modules get rewritten, corrections disappear between sessions, and cost hides in transcripts.

**Keep the example rules crisp enough to orient developers without overwhelming them.** The examples in `README.md` are now short signals: define the slice, keep the diff inside it, block rewrites and duplicate abstractions, require useful receipts, audit boundary drift, and record cost.

**Verify the governance suite still passes.** The full governance suite was run after the README edits.

## Out of scope

- Changing the governance-kit implementation, packs, or directive behavior.
- Updating generated assets, release metadata, or the consumed `.governance/` tree.
- Adding new README sections beyond the positioning copy already requested.

## Decisions

None.

## Verification

```sh
bash .governance/run.sh
```

Result: all 17 directives passed.

## Audit

PASS - `README.md` is the only product-facing file changed. The receipt describes the README positioning diff, mirrors the issue checklist, names the changed file, and records the governance verification command.

## Layer boundaries

PASS - The diff changes `README.md` copy and adds this issue receipt under `receipts/`. Both files sit in the documentation/audit layer they belong to. No kit engine logic, pack directive code, runtime files, or cross-layer dependencies were added or moved. No shared logic was introduced or duplicated.

## Accounting

<!-- Accounting rows are maintained by the agent-token-accounting and agent-steering-accounting pre-commit hooks. Keys are opaque — do not parse. -->

### Costs

| cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | cum-input | cum-cache-create | cum-cache-read | cum-output | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| codex-019ed17e-dc5-1781632772-1 | codex | 019ed17e-dc5b-75f1-a035-b8e65b713377 | #299 | gpt-5.5 | 394222 | 0 | 6845952 | 19131 | 413353 | 2.9840 | 394222 | 0 | 6845952 | 19131 | docs(readme): sharpen agent positioning (#299) |
| codex-019ed17e-dc5-1781632911-1 | codex | 019ed17e-dc5b-75f1-a035-b8e65b713377 | #299 | gpt-5.5 | 19620 | 0 | 1212288 | 1326 | 20946 | 0.3720 | 413842 | 0 | 8058240 | 20457 | docs(readme): sharpen agent positioning (#299) |
| codex-019ed17e-dc5-1781633039-1 | codex | 019ed17e-dc5b-75f1-a035-b8e65b713377 | #299 | gpt-5.5 | 9265 | 0 | 888064 | 1330 | 10595 | 0.2651 | 423107 | 0 | 8946304 | 21787 | docs(readme): sharpen agent positioning (#299) |
