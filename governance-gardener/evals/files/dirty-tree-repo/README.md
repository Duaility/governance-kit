# dirty-tree-repo

Bootstrapped repo. Gardener eval case 2 — the skill must refuse to run on a dirty tree.

**Seed steps for the grader:**
1. Copy this fixture to a fresh directory.
2. `git init && git add -A && git commit -m "seed"`
3. Create the dirty state: `echo 'wip' >> UNCOMMITTED.md`
4. Do NOT commit — the skill is supposed to see uncommitted work.
