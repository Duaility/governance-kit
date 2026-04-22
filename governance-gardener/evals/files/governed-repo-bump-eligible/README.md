# governed-repo-bump-eligible

A bootstrapped repo with one doc whose `last-verified` stamp has expired but whose watched paths have not changed since the stamp — the gardener should classify it as **bump-only** (signal A4), and when the user opts in to the bump-stamps follow-up, open a single batched stamp-only PR.

**Seed steps for the grader:**
1. Copy fixture; `git init && git add -A && git commit -m "seed"`.
2. Do NOT edit `src/api.ts` — the watched path must stay untouched relative to the stamp date, so the drift check returns "unchanged".
