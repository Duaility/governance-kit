---
name: doc-gardener
description: Scans docs opted into freshness tracking, detects staleness (either by elapsed time or by drift against the code they describe), and produces a remediation PR. Two-tier handling — docs whose watched code has not changed since the last-verified stamp get a simple stamp bump; docs whose watched code has changed get a drafted content update for human review. Pairs with the governance-bootstrap skill's doc-freshness rule. Use when the user says "run doc gardener", "check doc freshness", "garden the docs", "update stale docs", or when governance reports doc-freshness violations. Also designed to be invoked by /loop or a scheduled task for autonomous gardening.
license: MIT
metadata:
  author: governance-kit
  version: "0.1"
  companion-of: governance-bootstrap
---

# doc-gardener

The `doc-freshness` rule in `governance-bootstrap` makes staleness *visible*. This skill makes it *actionable*. It is the harness-engineering pattern: a recurring agent that scans for docs that no longer reflect the code, and opens fix-up PRs so a human can approve the remediation.

Two classes of staleness, handled differently:

| Case | Evidence | Action |
|---|---|---|
| **Stamp expired, code unchanged** | `last-verified` is older than the window, but none of the watched code has changed since that date. | Low-risk auto-bump. Update the stamp, open a minimal PR explaining "verified still accurate". |
| **Stamp expired, code changed** | `last-verified` is older than the window *and* watched code has been modified since then. | Draft a content update. Summarize what changed in the code, propose a doc edit, open the PR as **Draft** for human review. |

The skill never auto-merges. Every change lands through a PR and a human approval — that's the whole point.

---

## Activation flow

### Step 1 — Build the tracked-doc set

Run from the repo root (`git rev-parse --show-toplevel` confirms git). The tracked-doc set is the **union** of two sources:

**(a) Baseline — well-known docs that almost any repo should keep fresh.** The gardener always considers these if they exist on disk, even without any config. Glob each pattern relative to the repo root and keep the hits:

```
AGENTS.md
CLAUDE.md
README.md
CHANGELOG.md
CHANGELOG/**/*.md
SECURITY.md
CONTRIBUTING.md
CODE_OF_CONDUCT.md
CONSTITUTION.md
docs/**/*.md
doc/**/*.md
plans/**/*.md
plan/**/*.md
adrs/**/*.md
adr/**/*.md
docs/adrs/**/*.md
docs/adr/**/*.md
rfcs/**/*.md
.github/AGENTS.md
.github/SECURITY.md
```

Skip obvious machine-generated paths (`node_modules/`, `vendor/`, `dist/`, `build/`, `target/`, `.venv/`, `__pycache__/`). If a file appears in both the baseline and the explicit config, dedupe.

**(b) Explicit opt-in — `tests/governance/freshness.conf`.** One path per line; `#` comments and blank lines ignored. This is where the user adds docs the baseline misses (a README inside a subpackage, a runbook with a non-standard name, anything outside `docs/`). If the file is absent, treat it as empty — the baseline alone is still a valid tracked set.

If the union is empty (no baseline hits, no config), stop and tell the user: this repo has no markdown docs in the conventional locations and no explicit config — there's nothing for the gardener to do.

### Step 2 — Enumerate stale docs

For each path in the tracked set:

1. Read the file. Extract the `<!-- last-verified: YYYY-MM-DD -->` stamp.
2. If the stamp is missing → classify as **`no-stamp`** (treat as stale).
3. If the stamp is within the window (default 90 days; env `GOVERNANCE_FRESHNESS_DAYS` overrides) → **skip**.
4. Otherwise → classify as **`stale`** and proceed to Step 3.

Also surface **orphans**: files listed in `freshness.conf` that no longer exist on disk. Report them; do not attempt to fix. The user decides whether to remove them from the config or restore the file. (Baseline-sourced paths can't be orphaned — they're discovered by globbing, so a missing file simply isn't in the set.)

### Step 3 — Determine what each stale doc watches

For each stale doc, build a **watch set** — the list of paths whose changes matter. Look for evidence in this order (use the first that yields results):

**(a) Explicit annotation** (preferred):
```markdown
<!-- gardener-watches: src/auth/, src/session/session.py, docs/security.md -->
```
Parse the comma-separated list. Paths are relative to the repo root.

**(b) Fenced code blocks** with filenames: ```` ```python:src/auth/tokens.py ```` style, or a filename on the line preceding the fence.

**(c) Inline path references** — grep the doc for strings that look like tracked file paths (`[a-z_][a-z0-9_/.-]+\.(py|js|ts|go|rs|md|yml|yaml|sh)`) and keep only those that actually exist under the repo root.

**(d) Fallback — directory sibling**: if the doc lives at `docs/auth/README.md`, watch `src/auth/` (if it exists). If the doc lives at the repo root, no directory sibling.

**(e) Well-known-file fallback**: for common repo-root docs, use these defaults if (a)–(d) haven't produced a watch set. The aim is low-friction coverage — explicit `gardener-watches` annotations should still be preferred.

| Doc | Default watch set |
|---|---|
| `AGENTS.md`, `CLAUDE.md` | top-level source dirs that exist: `src/`, `lib/`, `app/`, `pkg/`, `cmd/`, `internal/` |
| `README.md` (repo root) | `src/` (if present) + `package.json` / `pyproject.toml` / `go.mod` / `Cargo.toml` / `pom.xml` (whichever exist) |
| `SECURITY.md` | `.github/workflows/`, and any of `src/auth/`, `src/security/`, `auth/`, `security/` that exist |
| `CONSTITUTION.md` | `tests/governance/rules/`, `tests/governance/lib.sh` |
| `CONTRIBUTING.md` | `.github/`, hooks under `.git/hooks/` are not tracked, so watch `tests/` instead if present |
| `CHANGELOG.md`, `CHANGELOG/**` | skip the gardener — changelogs are written by humans at release time, not drift-driven. Classify as `skip-changelog` (don't bump, don't draft, don't warn). |
| `docs/adrs/**`, `adrs/**`, `docs/adr/**`, `adr/**` | ADRs are historical records; once written they shouldn't drift. Classify as `skip-adr` (same handling as changelog). |

If none of (a)–(e) yields anything, classify the doc as **`unwatched-stale`**: the stamp has expired but we don't know what to check it against. Report it; suggest adding an explicit `<!-- gardener-watches: ... -->` annotation. Do not bump the stamp.

See `references/WATCH_ANNOTATIONS.md` for the annotation format.

### Step 4 — Classify each doc

For each stale-with-watches doc:

- `stamp_date = <last-verified stamp>`
- `changes = git log --since="$stamp_date" --pretty=oneline -- <watch-paths...>`

| `changes` | Classification |
|---|---|
| empty | **`bump-only`** — watched code unchanged since stamp; auto-bump is safe. |
| non-empty | **`needs-update`** — watched code has drifted; draft a content update. |

### Step 5 — Present the findings

Before acting, show the user a summary:

```
Freshness report (<N> docs tracked, <M> stale):

  bump-only        (<count>):  docs where watched code is unchanged
    - docs/security.md          (stamp: 2025-11-01, 172 days old)
    - docs/deploy.md            (stamp: 2025-10-15, 189 days old)

  needs-update     (<count>):  docs where watched code drifted
    - docs/auth/session.md      (stamp: 2025-09-10, 5 commits since)

  unwatched-stale  (<count>):  stale, but no watch set inferable
    - docs/misc/notes.md        (add a gardener-watches annotation)

  no-stamp         (<count>):  no last-verified marker found
    - docs/new-thing.md         (add a stamp to opt in)

  orphaned         (<count>):  listed in freshness.conf but missing
    - docs/removed.md

  skipped          (<count>):  intentionally excluded (changelogs, ADRs)
    - CHANGELOG.md, docs/adrs/0003-auth.md

Proceed with:
  (1) bump-only PR    — <count> stamp updates, low risk
  (2) needs-update PRs — <count> draft PRs for review
  (3) both
  (4) dry-run only — no PRs
```

Use `AskUserQuestion` to get the decision. Default (and the right choice for autonomous loops) is **dry-run only** the first time the user invokes the skill in a session — they should see the report before the skill starts opening PRs.

### Step 6 — Create the PRs

Do this from a clean working tree. If the tree is dirty, stop and tell the user to commit or stash first — the skill must not mix its output with unrelated user changes.

**Bump-only PR** (one PR for the batch):

1. `git checkout -b doc-gardener/stamp-bumps-<YYYY-MM-DD>`
2. For each `bump-only` doc: replace the `<!-- last-verified: OLD -->` with today's date. Use `Edit`, not `Write`.
3. `git add <files>` and commit with message: `docs(gardener): bump last-verified stamps — <count> docs, code unchanged`
4. `git push -u origin <branch>` (if `origin` exists and push is allowed).
5. `gh pr create` with title `docs(gardener): bump stamps for <count> unchanged docs` and a body from `assets/gardener-pr-bump.template.md`. Mark **ready for review** (not draft) — these are low-risk and batch-reviewable.

**Needs-update PRs** (one PR per doc — they need individual review):

For each `needs-update` doc:
1. `git checkout -b doc-gardener/update-<slug>-<YYYY-MM-DD>`
2. Read the doc. Read the commit messages + diffs of the changed watch-set files since `stamp_date`. Produce:
   - A **Summary of changes** section for the PR body (one bullet per relevant commit, paraphrased — not a raw log dump).
   - A **proposed diff** against the doc that reflects the drift. Be conservative: change what the drift actually implies, don't refactor the whole doc.
3. Apply the diff via `Edit`. Update the stamp to today.
4. Commit: `docs(gardener): draft update for <doc path> — code drift since <stamp_date>`
5. `git push -u origin <branch>`
6. `gh pr create --draft` (draft — human must review the content). Body from `assets/gardener-pr-update.template.md`, including the Summary of changes and a "What I inferred" section listing the watch-set commits.

**Never force-push.** If a branch with the same name already exists, use a suffix (`-v2`, `-v3`) rather than overwriting — previous gardener runs may be mid-review.

### Step 7 — Report back

Print a compact summary:
- Branches created.
- PR URLs (from `gh pr create` output).
- What the user should do next (review the drafts, merge the bump-PR quickly).
- Remaining issues: `unwatched-stale`, `no-stamp`, `orphaned` — list them as a "needs your attention" section.

If invoked via `/loop`, the skill should exit cleanly after this report. Do not recurse or re-run without an explicit user trigger.

---

## Key design rules

- **Two tiers, sharply separated.** A stamp bump is a near-trivial PR; a content update is a significant draft. Never collapse them into one PR — reviewers will either under-scrutinize the update or over-scrutinize the bumps.

- **Drafts for content changes, always.** The gardener writes a first pass; humans decide whether it's right. Opening a non-draft PR for inferred content changes would invite rubber-stamping.

- **Never auto-merge.** Even bump-only PRs need a human to click the button. The cost of a mistaken bump is a doc that falsely claims accuracy.

- **Refuse to work on a dirty tree.** This skill touches many files across many branches. Mixing its output with unrelated user changes creates unfixable confusion.

- **Honor the watch set, nothing else.** Do not update a doc based on evidence outside its declared watches. If a user wants broader tracking, they add paths to the annotation.

- **Be honest in the PR body.** The `What I inferred` section should be specific about which commits were consulted and what was extrapolated. If the skill had to guess, it should say so — reviewers need to know the confidence level.

## References

- `assets/gardener-pr-bump.template.md` — PR body for the batched stamp-bump PR.
- `assets/gardener-pr-update.template.md` — PR body for individual content-update drafts.
- `references/WATCH_ANNOTATIONS.md` — the `<!-- gardener-watches: ... -->` annotation format and worked examples.
