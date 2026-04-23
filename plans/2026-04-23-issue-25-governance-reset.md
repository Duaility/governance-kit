<!-- last-verified: 2026-04-23 -->

# 2026-04-23 — Add `governance-reset` skill

## Goal

Ship a fourth skill alongside `governance-bootstrap` / `governance-amend`
/ `governance-gardener` that cleanly uninstalls a previously bootstrapped
governance surface from a repo. Today, backing out of the kit is a
manual hunt-and-peck exercise — the kit installs ~10 classes of artifact
and mutates `git config core.hooksPath`, but nothing in the kit knows how
to reverse that mechanically. `governance-reset` closes the symmetry gap
so **every side-effect `governance-bootstrap` can produce,
`governance-reset` can reverse**, with an ownership-marker discipline
that refuses to delete anything it did not install.

Closes [#25](https://github.com/Duaility/governance-kit/issues/25).

## Why a separate skill, not a flag on bootstrap

`bootstrap --uninstall` would grow a second activation flow inside the
largest skill in the kit. The three existing skills are each anchored
on one verb (seed / edit / tend); reset fits the same shape
(*untend*). Keeping it a sibling:

- Preserves the "each skill is single-purpose" rule established by the
  rename to `governance-gardener`.
- Gives the uninstall logic its own `SKILL.md` activation flow, which
  will be distinct (survey → classify → mode select → confirm →
  execute → report) even where steps look superficially similar.
- Lets `governance-reset` keep a *narrower* permission surface — it
  does not ask stack / preset questions and never installs anything.

## Scope — what reset must undo

Three source-of-truth categories, deliberately in priority order:

1. **Manifest-driven (authoritative).** If
   `.governance-kit/installed-packs.yaml` is present, it records every
   pack, rule, and installed path. Drive reset from the manifest; it
   is the only reliable record of what the kit owns in this repo.

2. **Marker-driven (trust, but verify).** Hooks under `.githooks/` and
   (rarely) `.git/hooks/` carry the line-2 ownership marker
   `governance-kit:managed`. Files with the marker are safe to
   delete; files without the marker on paths the kit *would* write
   are not ours to touch — surface a collision and ask.

3. **Heuristic fallback.** When neither manifest nor marker exists
   but artifacts are detected (a `CONSTITUTION.md` whose header
   sentinel matches bootstrap's template, `tests/governance/run.sh`
   identical to ours, etc.), default to **dry-run** and require opt-in
   before deleting anything.

The full inventory the skill must know about:

| Category | Artifact | Reset action |
|---|---|---|
| Files | `CONSTITUTION.md` | delete (soft + hard) |
| Files | `tests/governance/**` including `run.sh`, `lib.sh`, every `rules/<id>/` | delete (soft + hard) |
| Files | `tests/governance/freshness.conf` | delete with the rest |
| Files | `.github/workflows/governance.yml` | delete (soft + hard) |
| Files | `.governance-kit/installed-packs.yaml` (+ empty parent dir) | delete last, after reading it |
| Hooks | `.githooks/pre-commit`, `commit-msg`, `prepare-commit-msg` | delete **only if** line-2 marker present |
| Hooks | `.githooks/<name>.userhook` (from Path A wrap resolution) | rename back to `<name>` |
| Hooks | `<path>.pre-governance.bak` (from Path A overwrite resolution) | offer restore or delete |
| Docs | `AGENTS.md` — the `<!-- governance: rules-to-follow -->` block | surgical strip of the marker-bounded block |
| Docs | `AGENTS.md` — full file | delete **only if** manifest says we created it as a stub |
| Git config | `core.hooksPath=.githooks` | unset **only if** value still `.githooks` |
| Seeded docs | `QUALITY.md`, `COSTS.md`, any future `install-assets/` | soft: preserve + report; hard: delete |
| Path B | husky entry, `.pre-commit-config.yaml` governance block | remove governance entries only; do not touch others |

## Modes

Three modes, selected via `AskUserQuestion` after the survey. Default
is **soft**; **dry-run** is forced when manifest is missing AND
artifacts are detected (ambiguous state).

- `dry-run` — print the plan, write nothing.
- `soft` — remove managed surface; preserve seeded `install-assets/`
  docs (they are user-owned post-seed).
- `hard` — remove everything governance-kit touched, including seeded
  docs and overwrite-collision backups.

## Safety rules (non-negotiable)

- **Ownership marker respect.** No hook deleted without the
  `governance-kit:managed` line-2 marker. An unmarked hook at a path
  the kit would manage triggers a collision prompt, symmetrical with
  bootstrap.
- **Dry-run by default in ambiguous states.** Manifest missing +
  artifacts present ⇒ force dry-run, explicit opt-in required to
  delete.
- **No destructive git ops.** No `git clean`, no `git reset --hard`,
  no touching of uncommitted work. Delete tracked governance artifacts
  and unset one git config — that is all.
- **Idempotent.** Running on a repo with nothing installed is a no-op
  that reports "nothing to remove".
- **Surgical AGENTS.md edit.** Strip only the marker-bounded block;
  byte-diff the rest and abort if anything else changed.
- **Leave changes unstaged.** Never auto-commit. The user reviews the
  diff and commits intentionally, same discipline as bootstrap.

## Steps — each is its own commit in the umbrella PR

Every commit closes `(#25)` and touches this plan file to satisfy
`commit-issue-plan-match`.

1. **Commit 1 — Plan.** This file. Records the design so subsequent
   commits have a pointer, and establishes the `issue-25` plan required
   by `plan-per-issue` and `commit-issue-plan-match`.

2. **Commit 2 — Skill files.** `governance-reset/SKILL.md` (the entry
   point — frontmatter, negative triggers, interaction policy,
   six-step activation flow, key design rules) plus both references:
   - `references/UNINSTALL_MATRIX.md` — canonical table of every
     artifact the kit can produce and its soft / hard / dry-run reset
     action. The skill consults this at execute time.
   - `references/MANIFEST_SCHEMA.md` — schema of
     `.governance-kit/installed-packs.yaml` that reset reads, plus the
     fallback heuristic when the manifest is absent.

   SKILL.md and references ship in one commit because the SKILL links
   to both references via relative paths — splitting them would break
   `no-broken-internal-doc-links` in the intermediate state.

3. **Commit 3 — Baseline evals.** Three eval cases under
   `governance-reset/evals/`:
   - Case 1 — full-install hard-reset round-trip against a
     `bootstrapped-repo/` fixture carrying the manifest, marked
     hooks, constitution, tests tree, CI workflow, seeded docs, and
     an `AGENTS.md` with the directive block.
   - Case 2 — idempotent no-op against a `clean-repo/` fixture with
     no governance footprint.
   - Case 3 — explicit `dry-run` mode against the same bootstrapped
     fixture, asserting the tree is byte-identical afterwards.

   The three remaining eval scenarios from the issue's acceptance
   criteria (partial install, unmarked-hook collision, Path B /
   husky) are deliberately out of scope for this PR — they land as a
   follow-up purely test-only PR so the design surface of PR-a can
   be reviewed without eval-harness noise.

4. **Commit 4 — AGENTS.md + README.md.** Add `governance-reset` to
   the skills table in `AGENTS.md` (now "four skills"), add the reset
   use case to the `README.md` skill list, update the repo-layout
   tree to show the new directory, and update the "Linking the skills
   into a runtime" snippet to mention the fourth symlink.

## Out of scope

- **Partial reset of individual rules.** That is
  `governance-amend`'s job (remove a rule atomically). Reset is all
  or nothing for the kit-owned surface.
- **Migrating state to a different governance tool.**
- **Restoring a specific historical commit.** Git does that.
- **Removing `~/.claude/skills/` and `~/.codex/skills/` symlinks.**
  Those are user-machine state, not repo state.
- **Auto-commit of the reset.** Matches bootstrap's discipline — the
  user commits intentionally after reviewing the diff.
- **A new `governance-kit:managed` marker on every generated file
  (not just hooks).** Raised as an open question in the issue; worth
  its own amendment discussion, but not a blocker for shipping reset
  — the manifest + hook marker combination is sufficient for v1.

## Open questions resolved for this PR

1. *Should reset remove runtime symlinks?* No — out of scope (repo
   state only).
2. *"Reset to preset X" mode?* No — two-step (`reset` then
   `bootstrap`) keeps each skill single-purpose.
3. *Tombstone commit?* Not in v1. Users compose their own commit
   message; no value in prescribing one.
4. *Archive evolution-log entries?* No — `CONSTITUTION.md` is being
   deleted in full; git history preserves the log. Archiving would
   duplicate state.
