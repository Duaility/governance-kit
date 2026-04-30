# Eval fixtures — `governance pack {search,create,add,update,remove,list}`

Each subdirectory is a seed repo state for one or more eval cases. Before running an eval, copy the fixture into a fresh temp directory, run `git init && git add -A && git commit -m "seed"` inside it, and point the skill at that directory.

- `seeded-repo/` — post-init repo with only `governance-kit/core` installed; `.governance/install.yaml` (v3) and `.governance/packs.lock` (v2) are present. Backs eval cases 1 (`pack search`), 2 (`pack create`), and 3 (`pack add`).
- `repo-with-installed-pack/` — post-init repo with `governance-kit/core` AND `acme/widgets@5f3c0a1b…` (`source: gh`) AND `acme/repo-with-installed-pack` (`source: local`, with **two** directives — `team-policy` and `naming-convention`) present in the lockfile. Backs eval cases 4 (`pack update`), 5 (`pack remove` of a `gh` pack), 6 (`pack list`), 7 (`pack remove` of a multi-directive `local` pack), and 8 (`pack create` refusal — target name `widgets` already exists).

Fixtures are intentionally minimal and rely on the eval harness to seed any cache state needed (e.g. populated `${GOVERNANCE_KIT_HOME:-~/.governance/cache}/packs/...`) when an eval requires offline cache hits. The eval checks the skill's *behavior* (SHA pinning, diff-before-exec, capability enforcement, lockfile upsert, dispatcher regeneration), not real-world network access.
