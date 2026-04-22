# Eval fixtures

Each subdirectory is a seed repo state for one eval case. Before running, copy the fixture into a fresh temp directory and `git init && git add -A && git commit -m "seed"`. For cases that need a history (to make `git log --since` return results), apply follow-up commits after the seed commit — see per-case notes below.

- `mixed-staleness-repo/` — used by evals 1 and 2. Contains:
  - `tests/governance/freshness.conf` listing 4 docs.
  - `docs/security.md` with a stamp of ~200 days ago and a `gardener-watches` annotation pointing at a file that has NOT been touched since the stamp → expected **bump-only**.
  - `docs/auth/session.md` with a stamp of ~200 days ago and watches pointing at `src/auth/*.py` → apply a follow-up commit editing one of those files so the gardener sees drift → expected **needs-update**.
  - `docs/misc/notes.md` with a stale stamp, no annotation, no inferable paths → expected **unwatched-stale**.
  - `docs/new-thing.md` with no stamp at all → expected **no-stamp**.
  - `freshness.conf` also lists `docs/removed.md`, which does not exist → expected **orphaned**.

- `dirty-tree-repo/` — used by eval 3. Same scaffolding as `mixed-staleness-repo`, but the fixture setup script leaves an untracked file (`scratch.md`) and an unstaged edit to a tracked file before the gardener is invoked.

- `annotation-vs-inference-repo/` — used by eval 4. Contains exactly two docs: one with an explicit `<!-- gardener-watches: ... -->` annotation and one without. The unannotated doc has no fenced code blocks, no inline path references, and sits at the repo root (no directory sibling) — so inference should fail and it should be flagged as unwatched-stale.
