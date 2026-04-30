# Eval fixtures — `governance reset`

Each subdirectory is a seed repo state for one eval case. Before running an eval, copy the fixture into a fresh temp directory, run `git init && git add -A && git commit -m "seed"` inside it, and point the skill at that directory.

`reset` restores drifted directives back to their **pinned pack version** — distinct from `pack update` (which re-pins to a newer SHA) and from `uninstall` (which removes governance entirely). Both fixtures here exercise reset-specific contracts: lockfile-driven provenance, diff-before-exec, hand-authored preservation, and refuse-without-lockfile.

- `drifted-repo/` — post-init repo with three packs in the lockfile and on-disk drift in two of them. Backs eval cases 1 (`--directive`), 2 (`--pack`), 3 (`--all --dry-run`), and 5 (`--all --drop-handauthored`).
  - `governance-kit/core` (`source: builtin`) owns `secrets-hygiene`. The installed `check.sh` has been edited to add a local rule (the drift). Reset must restore from the kit-bundled pristine source.
  - `acme/widgets` (`source: gh`, pinned at SHA `5f3c0a1b…`) owns `widget-naming`. The installed `check.sh` has been edited (the drift). Reset must restore from the cache at `${GOVERNANCE_KIT_HOME:-~/.governance/cache}/packs/acme__widgets@5f3c0a1b.../` (re-fetching if absent).
  - `acme/drifted-repo` (`source: local`) owns `team-policy` — a hand-authored directive. Reset preserves it by default; `--drop-handauthored` deletes it.
- `lockfile-missing/` — post-init repo with `CONSTITUTION.md` and `.governance/` artifacts but `.governance/packs.lock` deleted. Backs eval case 4 (refuse-to-run, point at `uninstall` + `init` recovery path).

Fixtures are intentionally minimal. The eval checks the skill's *behavior* (lockfile-first ownership resolution, diff-before-exec, hand-authored preservation by default, idempotent `kind: skip` for byte-identical directives, refuse-without-lockfile) — not completeness of a real-world post-init surface.
