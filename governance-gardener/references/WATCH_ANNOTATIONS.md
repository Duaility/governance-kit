# Watch annotations

When the `governance-gardener` checks doc drift (signals A3 and A4), it needs to know *which code* each doc is describing. The most reliable way to tell it: an explicit annotation in the doc.

## Syntax

Anywhere in the doc — conventionally near the top, right after the title — add:

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
4. Empty log → **A4 · Bump-eligible** (stamp can be advanced with no content change).
5. Non-empty log → **A3 · Doc drift** (content update needed — a draft PR is offered as a follow-up).

## Choosing the watch set

- **Prefer specific files over whole directories.** `src/auth/session.py` gives a narrow signal; `src/` is noise. A doc that watches too much gets flagged by every unrelated change.
- **Include the test file if the doc describes observable behavior.** Tests encode the contract the doc explains; a test change often means the doc's examples need updating.
- **Include siblings the doc cross-references.** If the session doc says "see the token doc for details," include `docs/auth/tokens.md` — a change there may imply a change here.
- **Don't include generated files.** Watching `src/generated/` is a false-positive machine.

## The tracked-doc baseline

Even without a `freshness.conf` entry, the gardener considers these paths if they exist:

```
AGENTS.md
CLAUDE.md
README.md
SECURITY.md
CONTRIBUTING.md
CODE_OF_CONDUCT.md
CONSTITUTION.md
docs/**/*.md
doc/**/*.md
plans/**/*.md
plan/**/*.md
rfcs/**/*.md
.github/AGENTS.md
.github/SECURITY.md
```

Explicitly **skipped** (historical records — they shouldn't drift once written):

```
CHANGELOG.md
CHANGELOG/**
adrs/**/*.md
adr/**/*.md
docs/adrs/**/*.md
docs/adr/**/*.md
governance-health/**/*.md     # the gardener's own reports
```

## Inference fallback

If a doc has no `gardener-watches` annotation, the gardener tries in order:

1. **Fenced code blocks** with filename hints: ```` ```python:src/auth/session.py ````
2. **Inline path references** that look like tracked files: `src/auth/session.py`, `lib/tokens.js`.
3. **Directory sibling**: a doc at `docs/auth/README.md` without other evidence is assumed to watch `src/auth/` (if it exists).
4. **Well-known-file defaults:**

| Doc | Default watch set |
|---|---|
| `AGENTS.md`, `CLAUDE.md` | top-level source dirs that exist: `src/`, `lib/`, `app/`, `pkg/`, `cmd/`, `internal/` |
| `README.md` (root) | `src/` + manifests (`package.json`, `pyproject.toml`, `go.mod`, `Cargo.toml`, `pom.xml`) |
| `SECURITY.md` | `.github/workflows/`, `src/auth/`, `src/security/`, `auth/`, `security/` (whichever exist) |
| `CONSTITUTION.md` | `tests/governance/rules/`, `tests/governance/lib.sh` |
| `CONTRIBUTING.md` | `.github/`, `tests/` (if present) |

Inference is best-effort. Docs that matter should have explicit annotations — it's one line, it's permanent, it makes the gardener's findings predictable.

## Unwatched-stale

A doc whose stamp has expired but where no watch set can be resolved (no annotation, no inferable evidence, no well-known default) is flagged as `unwatched-stale` in the Alignment section of the report. The gardener will not propose a stamp bump or a content update for it — the right action is for the user to either:

- Add a `gardener-watches` annotation (preferred).
- Remove the doc from `freshness.conf` if it exists there.
- Delete the doc if it no longer belongs.

Leaving a doc in `unwatched-stale` run after run means the Trend section will keep flagging it. That's intentional.
