# duaility/agent-governance

Pack id: `duaility/agent-governance` · Category: `AgentDiscipline`

The audit chain for repos under **agent-driven development** — where every commit is produced by an agent runtime (Claude Code, Codex, Cursor, ...) and the human's job is to read the trail, not the diff. Promoted from this kit's own dogfood suite so any repo can opt into the same discipline.

## When to install

Install when:

- Every (or nearly every) commit in the repo is agent-authored.
- You need a reviewer-readable trail **per issue**, not just per diff.
- You want token cost to survive squash merges.

Skip when:

- Most commits are human-authored — the chain assumes the agent is the author.
- Your workflow doesn't anchor work to GitHub issues (the chain pivots on `(#N)`).

## What it costs you

Once installed at the `standard` preset, every non-merge, non-revert commit must:

- Reference an issue: `(#N)` in the subject line or an `Issue: #N` trailer.
- Touch a `receipts/issue-<N>-*.md` file whose `## Checklist` `- [x]` items crosswalk into `## What changed` or `## Verification`.
- Carry token trailers (`Token-Input` / `Token-Output` / `Cost-Key` / `Cost-USD`, …) and append a row to `COSTS.md`.

When the receipt's checklist is fully checked on a non-default branch, an open PR must exist on the GitHub remote — advisory in the local `post-commit` hook, hard-gated in CI.

Opt into `agent-steering-accounting` separately if you also want each agent-authored commit to stamp `Steer-Count` / `Steer-Types` / `Steer-Tiers` and append rows to `STEERING.md` for each detected human steering event.

## The chain

```
issue → receipt → commit → cost
```

Each link is enforced by a separate directive; breaking any link fails the next push.

| # | Directive | Link in the chain |
|---|---|---|
| 1 | `issue-templates` | Issue creation uses durable forms (`proposal.yml`, `bug.yml`); blank issues are disabled. |
| 2 | `issues-tracked` | `QUALITY.md` is the system of record, with `## Open` and `## Resolved` sections. |
| 3 | `receipt-per-issue` | One receipt per issue, with `## Checklist`, `## What changed`, `## Out of scope`, `## Verification`. The **`- [x]` crosswalk** is the trust boundary: each checked item must appear (case-insensitive substring) in `## What changed` or `## Verification`. No silent box-flipping. |
| 4 | `commit-issue-receipt-match` | Every commit's issue anchor matches an `issue-<N>` token on a receipt the commit actually touches. |
| 5 | `agent-token-accounting` | Every commit stamps cost trailers and appends to `COSTS.md`; `Token-Total = Token-Input + Token-Output`; `Cost-Key` is unique and stable across squash merges. |

Receipts are the **post-implementation** audit artifact — distinct from the pre-implementation plans agent runtimes produce in plan-mode (an agent-runtime concept, out of governance scope).

## Auxiliary directives

One directive in the pack tightens the loop without sitting on the chain itself:

- **`agent-steering-accounting`** (opt-in, **not in any preset**) — every non-merge, non-revert commit stamps steering trailers and appends rows to `STEERING.md`. Opt-in only because the rows record human correction text verbatim. Install when you want a per-commit measure of where the agent ran on autopilot vs. needed your hand on the wheel.

## Presets

| Preset | Adds | Cumulative |
|---|---|---|
| `minimal` | `receipt-per-issue`, `commit-issue-receipt-match` | 2 |
| `standard` (extends minimal) | `issue-templates`, `issues-tracked`, `agent-token-accounting` | 5 |
| `strict` (extends standard) | (none) | 5 |

`agent-steering-accounting` is never bundled in a preset — install explicitly with `governance directive add agent-steering-accounting` after the pack is in.

## Install

```sh
governance pack add gh:Duaility/governance-kit/extensions/packs/agent-governance
# pick a preset when prompted; the pack lock pins the resolved SHA
```

## Further reading

- [AGENT_TOKEN_ACCOUNTING.md](../../../governance/references/AGENT_TOKEN_ACCOUNTING.md) — trailer schema, ledger schema (v1/v2/v3), per-runtime transcript readers, install layout.
- [AGENT_STEERING_ACCOUNTING.md](../../../governance/references/AGENT_STEERING_ACCOUNTING.md) — interrupt/correction classification, tier mapping, privacy stance.
- [PHILOSOPHY.md](../../../governance/references/PHILOSOPHY.md) — the GDD stance: receipts beat plans, ledgers outlive sessions, verify don't trust.
