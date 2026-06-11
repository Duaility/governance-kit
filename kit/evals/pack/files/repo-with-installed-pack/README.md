# repo-with-installed-pack

Post-init repo with three packs in `.governance/packs.lock`:

- `governance-kit/core` (`source: gh` (post-#117 the kit's core pack is fetched the same way community packs are)).
- `acme/widgets` (`source: gh`, pinned at SHA `5f3c0a1b…`) — the community pack the `pack update` and `pack remove` evals act on.
- `acme/repo-with-installed-pack` (`source: local`) — the auto-created repo-local pack.

Used by the `pack update`, `pack remove`, and `pack list` evals.
