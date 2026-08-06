# Philosophy

Governance-driven development (GDD) is the layer governance-kit operates at. This doc explains the stance behind the directives, ledgers, and verb surface — what the kit is trying to do, and what it explicitly rejects.

## The shift

Agent-driven development changes who authors code, but not who is accountable for it. The premise of GDD is that **as agents become the primary authors of changes, human oversight has to move up a layer** — from reviewing each diff to authoring the rules every diff must satisfy, and from trusting transcripts to reading receipts.

A few tenets fall out of that.

## Tenets

**1. Steer at the rule layer, not the turn layer.** Per-turn prompting does not compose. The next agent on the next branch cannot read your last conversation. A directive in `CONSTITUTION.md` reaches every future agent without you being in the room — once-authored, infinitely-enforced.

**2. If a rule is not executable, it is not a rule — it is a wish.** Every directive ships with a test that runs in pre-commit and CI, and the directive and its test land in the same commit (the [cardinal rule](../../CONSTITUTION.md)). There is no drift between "what we said the rule is" and "what the repo actually enforces," because they are the same artifact.

**3. Receipts beat plans.** Pre-implementation plans are the model's promise; post-implementation receipts are the model's attestation. Plans are private to the runtime and get thrown away. Receipts are durable, reviewable, and crosswalk every claim ("I did X") to evidence ("here is where X is verifiable in the diff or the verification steps").

**4. Receipts outlive sessions.** Durable files in the repo — `CONSTITUTION.md`, `QUALITY.md`, and the per-issue `receipts/` (which carry the session identity under each receipt's `## Session` section) — are the system of record. Historical `COSTS.md`/`STEERING.md` files are inert legacy artifacts; new commits record no usage, cost, or steering data. Not chat history, not harness-private state. Receipts survive the squash merge, the runtime swap, and team turnover.

**5. Verify, do not trust — and make verification cheap.** The agent is treated as a moderately untrusted author whose work crosswalks back to an issue, evidence, and session provenance. This is not pessimism about agents; it is the same posture mature teams already take with humans (CI, review, audit trails). GDD's job is to make that posture *cheap enough to apply at agent throughput*, because human review bandwidth does not scale with agent commit volume.

**6. Keep provenance minimal.** A session identifier is enough to connect an agent-authored change to the run that produced it. The kit does not retain conversation contents or infer operator intent from private runtime state.

**7. Rules accumulate with rationale.** Every directive amendment lands with its reason in the evolution log, blameable to the commit that introduced it. Six months from now, you should be able to answer *why* a rule exists, not just *that* it does. Institutional memory beats tribal knowledge.

## What this commits us to

Every change flows through an issue, produces a receipt, anchors to that receipt, and records session provenance when an agent runtime provides it. The chain is mechanically enforced — break any link and the next push fails.

## What this rejects

Vibes-based review. Ephemeral conventions ("be careful about X"). Unenforceable "best practices" that live in onboarding docs no agent reads. Audit trails that live only in chat. Per-task specs as the primary steering surface — those are useful, but they do not compose across agents and do not survive merge.

## Relationship to spec-driven development

Spec-kit-style workflows answer *"what should this feature do?"* — per-task, pre-implementation, often disposable once shipped. GDD answers *"what must every commit in this repo satisfy?"* — persistent, post-implementation, mechanical. The two are complementary: a spec describes the work to be done; GDD ensures the resulting commit carries its trailers, has a receipt, and matches its issue, regardless of how the work was specified.

Spec-kit steers the agent at runtime. GDD steers it at "compile time."
