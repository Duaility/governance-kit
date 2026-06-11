# Eval fixtures — `governance uninstall`

Each subdirectory is a seed repo state for one eval case. Before running an eval, copy the fixture into a fresh temp directory, run `git init && git add -A && git commit -m "seed"` inside it, and point the skill at that directory.

- `bootstrapped-repo/` — a minimal but complete post-init state, driving eval cases 1 (hard mode), 3 (dry-run), and 4 (soft mode).
  - `.governance/install.yaml` (init receipt, v3) and `.governance/packs.lock` (pack pin record, v2) are the two manifests `uninstall` reads as the authoritative source of truth.
  - `.githooks/*` hooks all carry the line-2 `governance-kit:managed` marker — `uninstall` must respect the marker before deleting.
  - `AGENTS.md` contains a directive block bounded by paired `<!-- governance: directives-to-follow -->` markers (with closing marker), plus user content above and below it. `uninstall` must surgically strip only the block; every other line must survive byte-identical.
  - `QUALITY.md` and `COSTS.md` are pack-seeded user-owned docs; soft mode preserves them (eval 4), hard mode deletes them (eval 1).
- `clean-repo/` — a repo with no governance footprint, driving eval case 2 (idempotent no-op).

Fixtures are intentionally small. The eval checks the skill's *behavior* (source-of-truth choice, mode selection, ownership-marker respect, surgical AGENTS.md edit, no destructive git ops), not completeness of the post-init surface.

After a successful run of eval case 1, the `bootstrapped-repo/` fixture should be byte-identical to `clean-repo/` modulo whatever non-governance files it originally contained. Since this fixture carries no non-governance content, the post-uninstall tree collapses to just the `README.md`.
