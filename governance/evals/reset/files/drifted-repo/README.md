# drifted-repo

Post-init repo with three packs in `.governance/packs.lock`:

- `governance-kit/core` — `source: builtin`, owns `secrets-hygiene`. Drifted: `check.sh` has a local edit.
- `acme/widgets` — `source: gh`, pinned at SHA `5f3c0a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f`, owns `widget-naming`. Drifted: `check.sh` has a local edit.
- `acme/drifted-repo` — `source: local` (hand-authored), owns `team-policy`. No upstream — preserved by default, dropped under `--drop-handauthored`.

The drift is intentional and visible — every drifted file has a `# DRIFT:` comment so the eval grader can detect whether reset replaced the file.
