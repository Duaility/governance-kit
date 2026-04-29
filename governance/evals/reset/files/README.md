# Eval fixtures

Each subdirectory is a seed repo state for one eval case. Before running an eval, copy the fixture into a fresh temp directory, run `git init && git add -A && git commit -m "seed"` inside it, and point the skill at that directory.

- `bootstrapped-repo/` — a minimal but complete post-bootstrap state, driving eval cases 1 (hard reset round-trip) and 3 (dry-run mode).
  - `.governance/installed-packs.yaml` is the manifest reset reads first.
  - `.githooks/*` hooks all carry the line-2 `governance-kit:managed` marker — reset must respect the marker before deleting.
  - `AGENTS.md` contains the `<!-- governance: rules-to-follow -->` block plus user content above and below it. Reset must surgically strip only the block; every other line must survive byte-identical.
  - `QUALITY.md` and `COSTS.md` are pack-seeded user-owned docs; soft mode preserves them, hard mode deletes them.
- `clean-repo/` — a repo with no governance footprint, driving eval case 2 (idempotent no-op).

Fixtures are intentionally small. The eval checks the skill's *behavior* (source-of-truth choice, mode selection, ownership-marker respect, surgical AGENTS.md edit, no destructive git ops), not completeness of the bootstrapped surface.

After a successful run of eval case 1, the fixture should be byte-identical to `clean-repo/` modulo whatever non-governance files it originally contained. Since this fixture carries no non-governance content, the post-reset tree collapses to just the `README.md` (the eval harness's own marker) — which is also why case 2 uses a sibling fixture instead of asserting the post-reset state of case 1.
