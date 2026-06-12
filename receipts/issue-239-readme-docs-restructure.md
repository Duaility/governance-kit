# Issue 239: Restructure README and docs site around the Governance Kit framing

Closes [#239](https://github.com/Duaility/governance-kit/issues/239).

## Checklist

- [x] Rework the README hero, tagline, and badges
- [x] Add a Why section mapping harness-engineering failure modes to design answers
- [x] Add mental-model visuals to the README
- [x] Refactor the docs site nav and pages to the new structure
- [x] Add the missing docs pages
- [x] Fix stale pack, ledger, and path references across the docs
- [x] Rebrand prose to "Governance Kit"
- [x] Verify the directive suite is green

## What changed

- **Rework the README hero, tagline, and badges.** Replaced the Kubernetes-style "Declare the repo state you want" tagline with a plain-language one, **"The governance layer for AI coding agents."** Added a block ASCII-art hero (GOVERNANCE / KIT), a bold value-prop line, a badge row (governance CI, dogfood-smoke CI, latest `kit/v*` tag, Agent Skills, MIT), an in-page nav row, and an "AI agents: start at AGENTS.md / CONSTITUTION.md" pointer — modeled on the chopratejas/headroom README structure.
- **Add a Why section mapping harness-engineering failure modes to design answers.** New `## Why` section credits OpenAI's [harness engineering](https://openai.com/index/harness-engineering/) article as the stated inspiration and presents a five-row table mapping each named agent-first failure mode (instruction files that rot, agents replicating uneven patterns, knowledge trapped off-system, human-QA bottleneck, context scarcity) to the corresponding design answer, quoting the article's phrasing.
- **Add mental-model visuals to the README.** Added two Mermaid diagrams with explicit `classDef` colors: the installer/product/content layering with the rustup / toolchain / lockfile analogy in the Lifecycle section, and the issue → receipt → commit → cost chain in The audit chain section.
- **Refactor the docs site nav and pages to the new structure.** Rewrote `docs/docs.json` into a single Documentation tab grouped Get started → The constitution → Packs → The audit chain → The sweep lane → Integrations → Configuration → Reference → Architecture → Help, renamed `getting-started.mdx` to `quickstart.mdx` (with a redirect), and updated the landing, introduction, mental-models, audit-chain, and reference pages to the new framing and tagline.
- **Add the missing docs pages.** Created `installation.mdx`, `configuration.mdx`, `troubleshooting.mdx`, `concepts/sweep-lane.mdx`, and `concepts/limitations.mdx`, grounded in the kit's reference docs (SWEEP_FLOW, VERSIONING, NATIVE_TESTS) and the live directive set.
- **Fix stale pack, ledger, and path references across the docs.** Replaced the dissolved `governance-kit/core` with the six bundled concern packs throughout; reorganized the directive catalog per pack (splitting `workflows-hardened` into `token-permissions` + `pinned-dependencies`, renaming `version-consistency` to `kit-version-sync`); replaced the retired `COSTS.md`/`STEERING.md` ledgers with the receipt-homed `## Accounting` rows; pointed the manual-install symlink at `skill/` instead of the old `governance/`; and pack-qualified the `.governance/conf/` overlay paths.
- **Rebrand prose to "Governance Kit".** Changed running-text mentions to "Governance Kit" in the README and every docs page, leaving literal identifiers (repo slug `Duaility/governance-kit`, pack ids `governance-kit/*`, the `# governance-kit:managed` marker, file paths, commands) untouched.

## Decisions

- **Address the product as "Governance Kit" in prose, hyphenated lowercase only for identifiers.** A single user-facing name reads better than the package slug in running text; identifiers must stay verbatim because they are matched mechanically (pack ids, markers, paths).
- **Model both README and docs on the headroom structure rather than inventing one.** It is a proven shape for an agent-facing OSS project: plain hero, Why, Proof, honest fit, progressive disclosure. The Proof section is reframed as the dogfood ("this repo governs itself") since the kit has no benchmark numbers to show.
- **Diagrams as Mermaid with explicit colors, not images.** Mermaid renders on GitHub and in Mintlify, stays diffable, and needs no binary asset in the tree; the user's reference graphic was reproduced as a colored node graph.
- **Lean on the kit's own reference docs for the new pages' claims.** Installation, Configuration, Sweep lane, and Limitations restate what SWEEP_FLOW / VERSIONING / NATIVE_TESTS and the directive set already establish, rather than introducing new product behavior.

## Out of scope

- A demo GIF/asciinema recording for the README hero (headroom's strongest asset) — no recording exists yet; the textual gate-fire demo carries it for now.
- A star-history chart and any third-party badges (Trendshift, codecov) — premature for the repo's current state.
- Any change to directive behavior, pack contents, the skill, or the kit runtime — this change is documentation only.
- Rewriting historical receipts or evolution-log entries that reference the former `governance-kit/core` pack or the old ledgers — they describe what was true at the time.

## Verification

```sh
bash .governance/run.sh                 # full directive suite — all 21 pass
python3 - <<'PY'                         # docs nav references every page on disk, no orphans
import json, os
d = json.load(open('docs/docs.json')); pages=[]
def walk(o):
    if isinstance(o, dict):
        for k,v in o.items(): pages.extend(v) if k=='pages' else walk(v)
    elif isinstance(o, list):
        [walk(i) for i in o]
walk(d['navigation'])
assert not [p for p in pages if not os.path.exists(f'docs/{p}.mdx')]
print('nav ok:', len(pages), 'pages')
PY
```

- **Verify the directive suite is green** — `bash .governance/run.sh` reports all 21 directives passing (the run shown in the code block above).
- Brand sweep: `grep -n "governance-kit" README.md docs/**/*.mdx` returns only literal identifiers (pack ids, the managed marker, repo slug, file paths, commands) — no prose mentions.
- Link integrity is covered by the `internal-doc-links` directive in the suite run above.

## Accounting

<!-- Accounting rows are maintained by the agent-token-accounting and agent-steering-accounting pre-commit hooks. Keys are opaque — do not parse. -->

### Costs

| cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| claude-code-13c6bcbc-bf3-1781288814-1 | claude-code | 13c6bcbc-bf3f-4081-b64e-be9881134245 | #239 | claude-opus-4-8 | 53080 | 1580317 | 37952689 | 420516 | 2053913 | 39.6316 | docs: restructure README and docs site around the Governance Kit framing (#239) |

### Steering

| steer-key | session | issue | type | tier | user-reason | commit |
| --- | --- | --- | --- | --- | --- | --- |
| steer-13c6bcbcbf3-1781288813-1 | 13c6bcbc-bf3f-4081-b64e-be9881134245 | #239 | interrupt | structural |  | docs: restructure README and docs site around the Governance Kit framing (#239) |
| steer-13c6bcbcbf3-1781288813-2 | 13c6bcbc-bf3f-4081-b64e-be9881134245 | #239 | correction | classifier | Deprioritize hero art; demand concise, intent-focused readme reframe | docs: restructure README and docs site around the Governance Kit framing (#239) |
| steer-13c6bcbcbf3-1781288813-3 | 13c6bcbc-bf3f-4081-b64e-be9881134245 | #239 | correction | classifier | Rejected proposed declarative-state tagline as nonsensical | docs: restructure README and docs site around the Governance Kit framing (#239) |
| steer-13c6bcbcbf3-1781288813-4 | 13c6bcbc-bf3f-4081-b64e-be9881134245 | #239 | correction | classifier | Challenged whether full headroom doc structure was actually replicated | docs: restructure README and docs site around the Governance Kit framing (#239) |
| steer-13c6bcbcbf3-1781288813-5 | 13c6bcbc-bf3f-4081-b64e-be9881134245 | #239 | interrupt | structural |  | docs: restructure README and docs site around the Governance Kit framing (#239) |
