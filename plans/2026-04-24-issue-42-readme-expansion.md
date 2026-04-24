<!-- last-verified: 2026-04-24 -->
# Plan — issue-42: Expand README with hook, quickstart, and concrete examples

Closes [#42](https://github.com/Duaility/governance-kit/issues/42).

## Goal

The prior `README.md` opened with a verb list and jumped to "After
cloning" — useful for contributors, opaque for first-time readers. It
surfaced neither the governance-driven-development pitch, nor a
30-second quickstart, nor a concrete rule example. Compared to landing
pages like [github/spec-kit](https://github.com/github/spec-kit), it
read like internal reference docs.

Rewrite the README to work as a landing page: lead with the problem
and the pitch, show one rule end-to-end so the "rule + test +
rationale as one unit" framing is concrete, and keep the contributor
setup out of the critical path.

## Scope

Apply the issue's priority order:

1. **Philosophy hook + tagline.** Lead with *"Rules your agents can't
   ignore"* and three sentences naming the pain (unenforceable prose
   rules, pre-commit configs stripped of rationale, amendments that
   drift across PRs). Follow with four Core-Philosophy bullets:
   rules carry rationale; amendments are atomic; packs are SHA-pinned
   and capability-scoped; agents author via verbs.
2. **30-second quickstart.** `claude` → `governance init` → show the
   `conventional-commits` failure output from a bad commit.
3. **Concrete rule example.** Render the `conventional-commits`
   folder layout (rule.yaml / check.sh / constitution.md / evals),
   then quote the `constitution.md` subsection so the *why* is
   visible on the landing page.
4. **Install section.** Promote the `~/.claude/skills/` and
   `~/.codex/skills/` symlink snippet out of `AGENTS.md` so readers
   can go from clone to working skill without a second hop.
5. **Core pack rules table.** Eight rows so the kit doesn't read as
   vaporware. Link to `RULES_CATALOG.md` for the full catalog.
6. **Community packs table.** Render
   `extensions/catalog.community.json` as a table (today:
   `duaility/agent-governance`) with an install command.
7. **Positioning vs. alternatives.** Short paragraph answering the
   obvious "why not just pre-commit / husky / lefthook?" question.
8. **GitHub callouts.** `> [!NOTE]` on the skill-link prerequisite;
   `> [!IMPORTANT]` on "don't edit CONSTITUTION.md by hand".
9. **Contributor setup moves down.** `./scripts/setup-clone.sh` and
   the worktree-inheritance note go into a Contributing section at
   the bottom — pointing to `AGENTS.md` for repo layout.
10. **Supported-agents line.** "Works with Claude Code and Codex"
    stated up top.

## Non-goals

- **GIF / asciinema.** The issue lists a `governance init` demo as an
  idea to borrow from spec-kit, but recording one is out of scope for
  this PR. Leave a slot to drop one in later without another README
  rewrite.
- **Badge row.** Release / license / CI badges assume metadata
  (published version, CI status URL) that isn't wired up yet.
- **Top-level table of contents.** The revised README stays under
  ~150 lines — a TOC would add noise at this size. Reconsider once
  it grows past three major sections.
- **Editing `extensions/catalog.community.json` or skill frontmatter.**
  This PR touches `README.md` only.

## Validation

- `bash tests/governance/run.sh` passes — in particular
  `no-broken-internal-doc-links` confirms every markdown link
  resolves.
- Visual pass that the quickstart code block, rule-folder tree, and
  tables render cleanly on GitHub.
