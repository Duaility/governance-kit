# Receipt: repo-local directive that verifies the architecture layer map (#274)

## Checklist

- [x] Carry the layer map as a Mermaid flowchart in ARCHITECTURE.md
- [x] Add the repo-local architecture-map-holds directive
- [x] Gate that named paths resolve and appear in the block
- [x] Gate the thin-skill boundary and the kit + pack pins
- [x] Gate that the diagram edges stay one-way
- [x] Sync the lock and mirror the constitution

## What changed

Implemented the full scope of #274: this repo's layer / responsibility model is
now carried as committed code (a Mermaid block) and a repo-local directive fails
the build when the picture drifts from the real tree. In short: Carry the layer
map as a Mermaid flowchart in ARCHITECTURE.md; Add the repo-local
architecture-map-holds directive; Gate that named paths resolve and appear in the
block; Gate the thin-skill boundary and the kit + pack pins; Gate that the
diagram edges stay one-way; and Sync the lock and mirror the constitution.

- **`ARCHITECTURE.md`** gains a `## Layer map` section: the `flowchart` Mermaid
  block from the issue (skill → kit → packs, downward only, with the rustup
  toolchain-manager analogy alongside), the `install.yaml`/`packs.lock` pin note,
  a `### What the gate checks` table, and three `arch-map-path:` HTML-comment tags
  (`skill/`, `kit/`, `packs/`) that are the check's explicit, machine-readable
  contract.
- **`.governance/packs/duaility/governance-kit/directives/architecture-map-holds/`**
  — the new repo-local directive, beside `consumed-tree-integrity` in the
  no-`source:` dogfood pack so it never ships in a bundled `packs/*` concern pack:
  `directive.yaml` (`category: Architecture`, `surface: repo-state`,
  `hook: pre-commit`), `check.sh` (the mechanical, offline gate), and
  `constitution.md` (the Directive subsection).
- **`check.sh`** asserts three groups: (1) exactly one non-empty `mermaid` block
  declaring a `flowchart`; (2) every tagged `arch-map-path:` token resolves on
  disk and appears verbatim in the block — the rename-drift catch; (3) the
  boundary edges — `skill/` carries no kit version string and nothing but
  `SKILL.md` + `bootstrap.py`, the repo pins both axes
  (`.governance/install.yaml` `kit_version`, ≥1 pack in `.governance/packs.lock`),
  and the block carries both downward edges with no upward edge.
- **`.governance/packs.lock`** — added `architecture-map-holds` to the local
  `duaility/governance-kit` pack's `directives:` list so `consumed-tree-integrity`
  (which asserts the vendored local directive set equals the lock list) stays
  green.
- **`CONSTITUTION.md`** — added the `### architecture-map-holds` subsection under
  `## duaility/governance-kit` and appended the Evolution Log entry, so test +
  constitution + log land in one commit.

## Out of scope

- Promoting this to the bundled `packs/architecture` concern pack — the map
  describes governance-kit's own installer/product/content layering and is
  meaningless in any consumer repo, so it is deliberately repo-local (issue
  decision).
- Mechanically gating the rustup analogy text and "the kit hardcodes no pack
  version" — these stay audit-only per #271's bucket ladder; their mechanical
  form false-positives on docs/examples that legitimately mention pinned pack
  tags.
- `mmdc`-based Mermaid validation — the check is structural so it runs identically
  and offline in the hook and in CI; a parser pass would add a flaky external
  dependency.

## Verification

```sh
# new directive passes in isolation, then the whole dogfood suite is green
bash .governance/run.sh duaility/governance-kit/architecture-map-holds
bash .governance/run.sh

# drift is actually caught (each mutation flips the check to exit 1):
#  - a tagged path that no longer resolves
#  - a tagged path missing from the mermaid block (diagram/tag drift)
#  - an upward edge (packs --> kit) added to the diagram
```

`bash .governance/run.sh` reports all 19 directives passing (including the new
`architecture-map-holds` and `consumed-tree-integrity`, confirming the lock
sync). The four hand-run drift mutations each correctly fail the directive and
restore clean.

## Decisions

- **Explicit `arch-map-path:` tags over naive token extraction.** Scanning the
  block for any `word/`-looking token false-positives on label text like
  `governance-kit/<concern>` (open question #2 in the issue). Tagging the
  checkable tokens in HTML comments beside the block makes the contract explicit
  and keeps diagram-vs-tag drift itself a gated failure.
- **`install.yaml` / `packs.lock` checked directly, not via path tags.** Those
  pins appear in the prose note, not the diagram nodes, and their real paths
  (`.governance/...`) differ from the diagram labels, so they are verified as
  boundary edges (group 3) rather than as `arch-map-path:` tokens (group 2).
- **One-way layering gated on the diagram's own arrows.** The "no upward edge"
  claim is enforced structurally on the Mermaid edge lines (no `kit --> skill`,
  no `packs --> kit`); a real dir-level dependency check is left partial per the
  issue, since `kit/` legitimately mentions `skill/` in prose docs.
- **Repo-local, hand-authored.** Like `consumed-tree-integrity`, this directive
  lives in the `source: local` dogfood pack authored directly under
  `.governance/`, so CONSTITUTION.md and the lock are synced by hand in the same
  commit rather than through a `packs/` source tree.

## Accounting

<!-- Accounting rows are maintained by the agent-token-accounting and agent-steering-accounting pre-commit hooks. Keys are opaque — do not parse. -->

### Costs

| cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | cum-input | cum-cache-create | cum-cache-read | cum-output | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| claude-code-77965fe1-dab-1781518971-1 | claude-code | 77965fe1-dab8-4cfb-8bb2-3396e8b13caa | #274 | claude-opus-4-8 | 29265 | 307538 | 8559753 | 109309 | 446112 | 9.0810 | 29265 | 307538 | 8559753 | 109309 | feat(governance): repo-local directive that verifies the architecture layer map  |
