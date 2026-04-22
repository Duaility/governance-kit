# Watch annotations

The `doc-gardener` skill decides whether a stale doc needs a content update by diffing the paths that doc "watches" against the doc's last-verified date. The most reliable way to tell it what to watch is an explicit annotation.

## Syntax

Anywhere in the doc — conventionally near the top, after the title — add:

```markdown
<!-- gardener-watches: <comma-separated paths> -->
```

Paths are relative to the repo root. They can be:

- Files: `src/auth/session.py`
- Directories (trailing slash required): `src/auth/`
- Globs (shell-style, passed to `git ls-files`): `src/auth/**/*.py`

Multiple annotations in one doc are allowed and concatenated. One per logical concern is clearest:

```markdown
<!-- gardener-watches: src/auth/ -->
<!-- gardener-watches: docs/security.md -->
```

## A worked example

**`docs/auth/session.md`** — a doc describing how sessions are created, stored, and expired.

```markdown
# Session lifecycle

<!-- last-verified: 2026-03-14 -->
<!-- gardener-watches: src/auth/session.py, src/auth/tokens.py, src/middleware/cookies.py -->

Sessions are created in `create_session()` (src/auth/session.py), signed using...
```

When the gardener runs:

1. Reads `last-verified: 2026-03-14`.
2. Reads the watches: three specific files.
3. Runs `git log --since="2026-03-14" -- src/auth/session.py src/auth/tokens.py src/middleware/cookies.py`.
4. If the log is empty → bump the stamp (code unchanged).
5. If the log has commits → draft a content update that summarizes those commits and adjusts the doc.

## Choosing the watch set

Some rules of thumb:

- **Prefer specific files over whole directories.** `src/auth/session.py` gives the gardener a narrow signal; `src/` gives it noise. A doc that "watches" too much will be flagged as drifted by every unrelated change.
- **Include the test file if the doc describes observable behavior.** Tests encode the contract the doc explains; a test change often means the doc's examples need updating.
- **Include siblings the doc cross-references.** If the session doc says "see the token doc for details," include `docs/auth/tokens.md` — a change to the token doc may imply a change here too.
- **Don't include generated files.** `db-schema.md` watching `src/generated/` is a false-positive machine — the generated code changes constantly. If the source of generation is meaningful, watch *that* instead.

## Inference fallback (no annotation)

If the doc has no `gardener-watches` annotation, the gardener will try in order:

1. **Fenced code blocks** with filename hints: ```` ```python:src/auth/session.py ````
2. **Inline path references** that look like tracked files: `src/auth/session.py`, `lib/tokens.js`.
3. **Directory sibling**: a doc at `docs/auth/README.md` without other evidence is assumed to watch `src/auth/` (if present).
4. **Well-known-file defaults**: for common repo-root docs (AGENTS.md, README.md, SECURITY.md, CONSTITUTION.md, etc.) the gardener falls back to a built-in watch set — e.g., AGENTS.md watches top-level source dirs; SECURITY.md watches `.github/workflows/` and auth/security folders; CONSTITUTION.md watches `tests/governance/rules/`. `CHANGELOG.md` and `adrs/**` are explicitly **skipped** — they're historical records, not drift-tracked docs. See the table in `SKILL.md` Step 3(e) for the full list.

Inference is best-effort. Docs that matter should have explicit annotations — it's one line, it's permanent, and it makes the gardener's PRs predictable.

## Opting out

A doc listed in `tests/governance/freshness.conf` but without a watch set (no annotation, no inferable evidence) will be reported as `unwatched-stale` — flagged, but no PR created. Either:

- Add a `gardener-watches` annotation.
- Remove the doc from `freshness.conf` (opt out of tracking entirely).

Do not leave a doc in `unwatched-stale` indefinitely — it's governance noise. Pick one.
