# Receipt — issue #291

Documentation-only change: remove the in-progress sweep feature from public docs and restructure the docs site into a tabbed information architecture with a first-time-developer onboarding flow.

## Checklist

- [x] Remove all references to the in-progress sweep feature from the public README
- [x] Remove the sweep lane from the docs site (page, nav, and cross-links)
- [x] Restructure the docs navigation into horizontal tabs with vertical groups
- [x] Revamp the home and quickstart pages for first-time developers
- [x] Realign the cross-page navigation chain to the new reading order

## What changed

- **Remove all references to the in-progress sweep feature from the public README** — `README.md` drops the dedicated "The sweep lane" section (heading, the off-commit-path mermaid diagram, and the `SWEEP_FLOW.md` link), the `Git hook / CI / sweep` diagram label, the **Sweep** row of the invariant ladder, the sweep mentions in the "What developers get" and "Packs make rules portable" sections, the sweep-lane sentence in the sub-agent-attestations section, the sweep-lane clause in the Proof bullet, and repoints the Documentation table's `Sweep flow` cell to `Sub-agent attestations` (`kit/references/SUBAGENT_ATTESTATION.md`).
- **Remove the sweep lane from the docs site (page, nav, and cross-links)** — deleted `docs/concepts/sweep-lane.mdx`; removed its nav group from `docs/docs.json` and its card from `docs/index.mdx`; reworded the cross-links and removed the sweep subsection/rows in `docs/guide/mental-models.mdx`, `docs/guide/quickstart.mdx`, `docs/concepts/limitations.mdx`, `docs/concepts/audit-chain.mdx`, and `docs/reference/directive-catalog.mdx`. The only remaining "sweep" strings are the unrelated capability-check verb ("statically sweeps the directive's code").
- **Restructure the docs navigation into horizontal tabs with vertical groups** — `docs/docs.json` replaces the single "Documentation" tab with four horizontal tabs (Get started, Concepts, Guides, Reference), each carrying its own vertical sidebar groups.
- **Revamp the home and quickstart pages for first-time developers** — `docs/index.mdx` is rewritten as a lean landing (value prop, start-here cards, how-it-works diagram, an "Explore the docs" grid mapping to the four tabs) with the reconciliation table de-duplicated out to the introduction; `docs/guide/quickstart.mdx` is reshaped into the openclaw "What you need → numbered steps → What to do next" form.
- **Realign the cross-page navigation chain to the new reading order** — the `Next →` footers in `docs/concepts/constitution.mdx`, `docs/concepts/runtime.mdx`, `docs/concepts/packs.mdx`, and `docs/concepts/versioning.mdx` now follow the Concepts tab order (constitution → runtime → packs → versioning → audit-chain → limitations), and `docs/concepts/limitations.mdx` gains a bridge into the Reference tab.

## Out of scope

- Reference docs under `kit/references/` (including `SWEEP_FLOW.md`) and the live `surface: sweep` code contract — they are not public docs and the feature still exists in the kit.
- `CONSTITUTION.md`, `.governance/`, prior `receipts/`, and `CHANGELOG.md` — immutable, historical, or hand-edit-forbidden.
- No kit engine, pack directive, or `.governance/` runtime content was touched.

## Verification

`docs/docs.json` parses and every nav page resolves; no `.mdx` page is orphaned; every internal link resolves; and no sweep-feature string remains (only the "statically sweeps" verb):

```sh
python3 - <<'PY'
import json, re, pathlib
root = pathlib.Path("docs")
d = json.load(open(root/"docs.json"))
nav = [p for t in d["navigation"]["languages"][0]["tabs"] for g in t["groups"] for p in g["pages"]]
assert all((root/(p+".mdx")).exists() for p in nav), "missing nav page"
allp = sorted(str(p.relative_to(root)).removesuffix(".mdx") for p in root.rglob("*.mdx"))
assert [p for p in allp if p not in nav] == [], "orphan page"
lr = re.compile(r"\]\((/[^)\s#]+)(#[^)\s]*)?\)")
for m in root.rglob("*.mdx"):
    for x in lr.finditer(m.read_text()):
        assert (root/(x.group(1).lstrip('/')+".mdx")).exists(), f"broken link {x.group(1)}"
print("docs nav + links OK")
PY
grep -rni "sweep" README.md docs/   # expect only the "statically sweeps" capability-check verb
```

```sh
bash .governance/run.sh
```

## Decisions

- Kept the `native-tests` and `authoring-*` pages at their existing `/reference/` URLs even though they now appear under the **Guides** tab; moving the files would change URLs and risk broken links for no functional gain (Mintlify keys navigation by path, not folder).
- Did not rewrite the bodies of the already-accurate concept/reference pages — the first-time-developer simplification (#288) applies to the landing/onboarding surface, and churning correct technical prose would add risk without value.
- Used "sweep" in the issue/PR/commit metadata to describe the change accurately; the no-sweep-in-docs intent applies to user-facing documentation, not VCS change descriptions.

## Layer boundaries

PASS

- PASS — Every staged file is documentation outside the layer stack (`skill/` → `kit/` → `packs/`): `README.md`, ten `docs/**` files (including the deleted `docs/concepts/sweep-lane.mdx` and the `docs/docs.json` nav), and the new `receipts/issue-291-tabbed-docs-and-drop-sweep.md`. `git diff --cached --name-only` filtered against `skill/`, `kit/`, `packs/`, `.governance/` returns nothing — no engine, verb, flow, or directive logic landed in any layer.
- PASS — No dependency edges change. The diff only removes/rewords sweep-feature prose and re-points doc cross-links (e.g. README's `SWEEP_FLOW.md` cell → `SUBAGENT_ATTESTATION.md`, several `Next:` footers); every target remains an existing `kit/references/` or `docs/` page, and no doc asserts an upward (packs→kit or kit→skill) relationship. The `architecture-map-holds` model in `ARCHITECTURE.md` is untouched.
- PASS — No shared logic is introduced or duplicated. The change removes documentation of the sweep lane from public surfaces only; the receipt's `## Out of scope` notes the live `surface: sweep` contract and `kit/references/SWEEP_FLOW.md` are deliberately left in the kit, so the owning layer still solely holds that logic.

## Audit

PASS

- PASS — `## What changed` faithfully describes the diff with no material omission. Each diff hunk maps to a bullet: README drops the "The sweep lane" section + mermaid + `SWEEP_FLOW.md` link, the `Git hook / CI / sweep` → `Git hook / CI` label, the **Sweep** invariant-ladder row, the "What developers get"/"Packs make rules portable" sweep mentions, the sub-agent-attestation sweep sentence, the Proof-bullet sweep clause, and repoints the doc table's `Sweep flow` → `Sub-agent attestations`/`SUBAGENT_ATTESTATION.md`; `docs/concepts/sweep-lane.mdx` is deleted; `docs.json` is rebuilt into four tabs; `index.mdx`/`quickstart.mdx` are rewritten; the `Next →` footers are realigned. `grep -rni sweep README.md docs/` returns only the unrelated "statically sweeps" capability-check verb.
- PASS — every `- [x]` checklist item is realized in the diff: README sweep references removed (grep clean); sweep lane removed from the docs site (page deleted, nav group and index card gone, cross-links reworded in mental-models/quickstart/limitations/audit-chain/directive-catalog); `docs.json` now has four horizontal tabs each with vertical groups; `index.mdx` is a lean landing with an "Explore the docs" grid and `quickstart.mdx` follows "What you need → steps → What to do next"; the cross-page chain traces constitution → runtime → packs → versioning → audit-chain → limitations and bridges into Reference, with no orphan or missing nav pages.
- PASS — the receipt's `## Checklist` mirrors the issue's acceptance checklist verbatim: all five items match `gh issue view 291` word-for-word, in the same order.

## Accounting

<!-- Accounting rows are maintained by the agent-token-accounting and agent-steering-accounting pre-commit hooks. Keys are opaque — do not parse. -->

### Costs

| cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | cum-input | cum-cache-create | cum-cache-read | cum-output | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| claude-code-80c0621d-99b-1781618993-1 | claude-code | 80c0621d-99ba-4cd0-9894-9d2f7c36e175 | #291 | claude-opus-4-8 | 6642 | 34918 | 30540 | 2670 | 44230 | 0.3335 | 6642 | 34918 | 30540 | 2670 | docs: restructure docs into tabbed navigation and drop in-progress sweep referen |

### Steering

| steer-key | session | issue | type | tier | user-reason | commit |
| --- | --- | --- | --- | --- | --- | --- |
| steer-0aee2b7fdec-1781618992-1 | 0aee2b7f-dec7-4ba8-bb63-e957542b7d78 | #291 | interrupt | structural |  | docs: restructure docs into tabbed navigation and drop in-progress sweep refere… | 1 | 2026-06-16T11:41:29.434Z |
| steer-0aee2b7fdec-1781618992-2 | 0aee2b7f-dec7-4ba8-bb63-e957542b7d78 | #291 | correction | classifier | wanted the question re-asked before proceeding | docs: restructure docs into tabbed navigation and drop in-progress sweep refere… | 2 | 2026-06-16T11:41:36.061Z |
