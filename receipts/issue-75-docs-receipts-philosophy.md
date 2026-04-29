# Receipt: surface receipts + add PHILOSOPHY.md across docs

Issue: [#75](https://github.com/Duaility/governance-kit/issues/75)

## Checklist

- [x] PHILOSOPHY.md created with seven tenets and spec-kit contrast section
- [x] AGENTS.md Further reading links to PHILOSOPHY.md
- [x] root README Visibility section lists four artifacts and names the chain
- [x] root README mermaid diagram includes a receipts/ node
- [x] root README Community Packs section lists all 7 agent-governance directives
- [x] root README Anatomy of a directive flags optional sibling folders
- [x] agent-governance pack README rewritten as install-decision document
- [x] pack.yaml "matching plan" → "matching receipt" residue fixed

## What changed

The kit's docs treated three append-only ledgers (`CONSTITUTION.md`, `COSTS.md`, `STEERING.md`) as the canonical visibility surface and never named `receipts/` — but receipts are the actual unit a reviewer reads instead of the diff, and they are the most distinctive artifact GDD produces compared to spec-driven workflows. The agent-governance pack README also lagged: 5 of 7 directives shown, no preset mapping, monorepo authoring trivia in front of consumer-facing content, and a residual "matching plan" comment in `pack.yaml` left over from the plans→receipts rename in #63. This commit closes those gaps and adds a canonical philosophy doc.

- **PHILOSOPHY.md created with seven tenets and spec-kit contrast section.** New file at `governance/references/PHILOSOPHY.md` that articulates the GDD stance — *steer at the rule layer not the turn layer; rules must be executable; receipts beat plans; ledgers outlive sessions; verify don't trust; capture corrections; rules accumulate with rationale*. Closes with a "What this commits us to / What this rejects" section and a final subsection contrasting GDD with spec-driven development ("spec-kit steers at runtime, GDD at compile time"). Pairs the tenets with the existing artifacts so a reader can map each principle to a file in the repo.
- **AGENTS.md Further reading links to PHILOSOPHY.md.** Added a new top entry in `AGENTS.md`'s Further reading section pointing at the new file with a one-line hook ("the stance behind GDD: rules over prompts, receipts over plans, ledgers over transcripts"). Placed first because it is the foundational read for anyone trying to understand why the rest of the kit is shaped the way it is.
- **Root README Visibility section lists four artifacts and names the chain.** Rewrote the section to enumerate four append-only artifacts — `CONSTITUTION.md`, `receipts/issue-<N>-*.md`, `COSTS.md`, `STEERING.md` — instead of three. Receipts are described with their four required sections and the `- [x]` crosswalk trust boundary. Closing line names the **issue → receipt → commit → cost** chain explicitly and flags that breaking any link fails the next push. Also corrected the closing claim about which pack ships what (steering is opt-in, not symmetric with token cost).
- **Root README mermaid diagram includes a receipts/ node.** Added a `receipts/` node between Agent and Human with an inbound `writes` edge from Agent and an outbound `read, not diffs` edge to Human, mirroring the dotted-edge style of the existing `COSTS.md` and `STEERING.md` nodes. Visual now matches the four-artifact prose.
- **Root README Community Packs section lists all 7 agent-governance directives.** Replaced the single-row table-with-comma-list with a tagline row plus a dedicated `### duaility/agent-governance` subsection containing a 7-row directive table. Each row names what the directive enforces and which preset it lands in (minimal/standard/—). `pr-required-when-checklist-complete` is now visible (it was missing); `agent-steering-accounting` is flagged as opt-in with the privacy reason inline.
- **Root README Anatomy of a directive flags optional sibling folders.** Added a paragraph after the minimal directive layout naming the optional siblings every full-shape directive can carry: `lib/` (shared bash/Python), `hooks/<pre-commit|commit-msg|prepare-commit-msg|post-commit|pre-push>.sh`, `runtimes/<name>.sh`, `install-assets/`. `agent-token-accounting` is named as the directive that uses every one of these.
- **Agent-governance pack README rewritten as install-decision document.** Replaced the previous structure (scoped id + monorepo trivia + 5-row directive table + agent-token-accounting installation deep-dive) with: opener naming the chain and audience, *When to install / Skip when* bullets, *What it costs you* (concrete operational cost per commit), *The chain* (5-row table with each directive tagged by its link in the chain and crosswalk trust boundary called out on receipt-per-issue), *Auxiliary directives* (`pr-required-when-checklist-complete` post-commit-vs-CI distinction; `agent-steering-accounting` privacy-driven opt-in), *Presets* table with cumulative count + explicit "steering is never bundled" note, *Install* command, and *Further reading*. Dropped the agent-token-accounting installation deep-dive (it duplicates `governance/references/AGENT_TOKEN_ACCOUNTING.md`) and the monorepo authoring note (consumer-irrelevant; the contributor view lives in `extensions/README.md`).
- **pack.yaml "matching plan" → "matching receipt" residue fixed.** Updated line 6 of `extensions/packs/agent-governance/pack.yaml` from "every commit has an issue template, an issue anchor, a matching plan, and full cost accounting" to "...a matching receipt..." — closing residue from the #63 rename. The chain comment block lower in the file already used "receipt" correctly; only the higher-level summary line was stale.

## Out of scope

- **Directive-level changes.** No `check.sh`, `directive.yaml`, `constitution.md`, or eval edits in this commit. The work is documentation and one stale-comment fix; no enforcement logic moves.
- **New directives or new packs.** This commit adjusts how existing directives are described, not which directives exist.
- **Test or eval changes.** `.governance/run.sh` and per-directive `evals/test.sh` are untouched.
- **AGENT_TOKEN_ACCOUNTING.md / AGENT_STEERING_ACCOUNTING.md edits.** The pack README now points readers at these references for trailer schemas and runtime wiring, but the references themselves are correct as-is and out of scope here.
- **Refreshing the dogfood `.governance/local/directives/` copies of any directive.** Not applicable — no directive content changed, so the dual-edit rule does not apply.
- **Adding receipts as their own ledger directive (e.g., a `receipts-tracked` directive).** The `receipt-per-issue` directive already enforces the receipt shape; promoting receipts in the docs is sufficient. A separate index/ledger directive would be a follow-up if the pattern proves useful.

## Verification

A reviewer can confirm completion by running these checks:

1. **PHILOSOPHY.md exists with the right shape.** `test -f governance/references/PHILOSOPHY.md && grep -E '^## (Tenets|Relationship to spec-driven development|What this commits us to|What this rejects)' governance/references/PHILOSOPHY.md | wc -l` returns at least 4 — the tenets list and the spec-kit contrast section are both present.
2. **AGENTS.md links to PHILOSOPHY.md.** `grep -n 'governance/references/PHILOSOPHY.md' AGENTS.md` returns one hit inside the `## Further reading` section, positioned before the `CONSTITUTION.md` entry.
3. **Root README Visibility section enumerates four artifacts.** `sed -n '/^## Visibility/,/^## /p' README.md | grep -cE '^- \*\*'` returns 4. The same range contains the literal chain string `issue → receipt → commit → cost`.
4. **Root README mermaid diagram has a receipts node.** `grep -n 'Re\[receipts/' README.md` returns one hit inside the mermaid block; `grep -n 'A -.->|"writes"| Re' README.md` returns one hit.
5. **Root README Community Packs lists all 7 directives.** The `### duaility/agent-governance` section's directive table contains rows for `issue-templates`, `issues-tracked`, `receipt-per-issue`, `commit-issue-receipt-match`, `pr-required-when-checklist-complete`, `agent-token-accounting`, and `agent-steering-accounting` (verifiable with `grep -cE '^\| \`(issue-templates\|issues-tracked\|receipt-per-issue\|commit-issue-receipt-match\|pr-required-when-checklist-complete\|agent-token-accounting\|agent-steering-accounting)\`' README.md` returning 7).
6. **Root README Anatomy of a directive flags optional sibling folders.** `grep -nE 'lib/.*hooks/.*runtimes/.*install-assets/' README.md` returns one hit immediately after the minimal directive code block.
7. **Pack README is the install-decision shape.** `grep -nE '^## (When to install|What it costs you|The chain|Auxiliary directives|Presets|Install|Further reading)' extensions/packs/agent-governance/README.md` returns 7 hits.
8. **pack.yaml stale "matching plan" residue is fixed.** `grep -n 'matching plan' extensions/packs/agent-governance/pack.yaml` returns no hits; `grep -n 'matching receipt' extensions/packs/agent-governance/pack.yaml` returns one hit on line 6.
9. **All relative links resolve.** `bash .governance/local/directives/no-broken-internal-doc-links/check.sh` exits 0.
10. **Dogfood suite stays green except the expected post-commit advisory.** `bash .governance/run.sh` reports failures only on `pr-required-when-checklist-complete` (because no PR exists yet for this branch) — every other directive passes.
