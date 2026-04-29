# `governance directive {add,modify,remove}` — activation flow

The atomic-triple recipe the `directive *` verbs run. Dispatched from
[`../SKILL.md`](../SKILL.md) via [DIRECTIVE_VERBS.md](DIRECTIVE_VERBS.md).

Governance-driven development's cardinal directive: *the constitution and the enforcing tests evolve together, in one commit.* These verbs make obeying that directive cheap and make breaking it harder than following it.

> The recovery hatch when an amendment causes problems is `governance reset` — it restores a pack-sourced directive (or all of them) to the pinned pack version in one commit. See [RESET_FLOW.md](RESET_FLOW.md). Reset is **only** available for pack-sourced directives; hand-authored directives have no pristine source and must be removed with `directive remove` instead.

Every amendment produced here is three logical changes, committed atomically:

1. A new (or updated) directive folder at `.governance/local/directives/<directive-name>/` with `directive.yaml`, `check.sh`, and `constitution.md`.
2. A new **Directives** subsection in `CONSTITUTION.md`.
3. A new entry in the `CONSTITUTION.md` **Evolution Log**.

The flow stages and **commits** the amendment in one conventional commit. Review happens on the PR — the flow does not run inline approval loops, because the workflow this is built for relies on PR review as the gate. The flow still refuses to finish with a partial amendment on disk.

## Interaction policy

| Situation | Action |
|---|---|
| Governance kit is missing | Stop and tell the user to run `governance init` first. |
| User asks for a general review or health check | Do not amend. Answer directly rather than mutating files. |
| Request has enough info to draft the directive | Draft, smoke-test, commit. No approval loop — PR review is the review layer. |
| Request is missing rationale or check logic | Ask only the blocking question(s). Do not ask for approval of drafts that are already unambiguous. |
| Request updates an existing directive | Preserve the existing rationale unless the user explicitly changes the policy intent. Note the update in the summary. |
| Request removes a directive | Remove the test and directive together, add an evolution-log entry, and surface dangling references. |
| Smoke test fails on pre-existing violators | Ask one blocking question — **loosen** (which threshold), **grandfather** (add waivers to the specific violators), or **block** (commit as-is, user fixes tree separately). Act on the answer, then commit. Do not punt a red-CI PR to the reviewer. |
| Structured question tools are unavailable | Use short free-text questions instead of stopping. |
| Directive is owned by a community pack (appears in `.governance/packs.lock`) | Refuse. Route the user to `governance pack update` / `governance pack remove` so the lockfile stays consistent. |

---

## Activation flow

### Step 1 — Verify the kit is installed

Run in parallel:
- `git rev-parse --show-toplevel` — confirm we're inside a git repo; capture the root.
- Check for `<root>/CONSTITUTION.md`.
- Check for `<root>/.governance/local/directives/` (directory).
- Check for `<root>/.governance/run.sh` (executable).

If any is missing, stop. The user needs `governance init` first — don't pretend to amend something that isn't there. Tell them that explicitly.

If `CONSTITUTION.md` lacks a **Directives** or **Evolution Log** heading, still stop and tell the user which is missing — adding those sections is a kit-structure change, not an amendment, and belongs to `init`.

### Step 2 — Collect the directive specification

Most requests will already give you most of this — extract what you can from the user's prompt before asking. What you need:

| Field | Constraint |
|---|---|
| **Directive name** | `[a-z][a-z0-9-]*[a-z0-9]`, ≤ 50 chars, matches the filename. No spaces, no uppercase. |
| **Directive statement** | One sentence, present tense, naming what the code **must** or **must not** do. |
| **Rationale** | Why this matters. Ideally references a concrete incident, policy, or constraint. |
| **Check logic** | What the script actually inspects — files, patterns, paths, size thresholds, git state, etc. |
| **Exceptions** | How approved deviations are documented. Default: no exceptions. Otherwise: waiver comment `governance: allow-<directive-name> <ticket>` or a named config file the directive reads. |

Before you draft anything, write down an explicit **intent map** for yourself:

| Field | What to capture |
|---|---|
| **Bad merge to block** | The concrete merge or omission this directive is meant to stop. |
| **Policy surface** | `repo-state` or `change-set obligation`. |
| **Enforcement surface** | Repo-at-rest scan, staged diff, or branch diff in CI. |
| **Why this surface fits** | One sentence tying the check shape back to the bad merge. |

If a **blocking** field is missing (no rationale, or check logic so vague the bash cannot be deterministic), **ask only that blocking question** via `AskUserQuestion` or free text. Never ask for approval of a draft that is already implementable — the PR is the review surface, not the skill's transcript. One question at a time; do not dump a multi-field form.

If the user's rationale says "every substantive change must...", "this kind of change must also...", "reviewers keep missing intent/approval/metadata", or anything else that describes a missing companion artifact in a change set, classify it as a **change-set obligation** unless the user explicitly says otherwise.

Default operating mode is **fast path**: draft → syntax-check → smoke-test → edit constitution → stage → commit. Ask a clarifying question only when the intent map cannot be filled in from the user's request. If structured question tools are unavailable, use short free-text questions instead of stopping.

**Handle collisions without asking for confirmation:**
- If `.governance/local/directives/<name>/check.sh` already exists → this is an **update**, not a new directive. Proceed with the update (preserving rationale unless policy intent changes) and note it in the summary. Treat the matching `CONSTITUTION.md` subsection as an update too.
- If `CONSTITUTION.md` already has a subsection whose header closely matches the proposed name → same: proceed with update, note it.
- If the user asked to **remove** a directive, verify the matching script and directive exist before deleting, and grep for dangling references in docs or CI notes. If references exist, surface them in the summary — do not silently delete around them.

**Refuse to amend packaged directives.** Before editing, check whether the directive id appears in `.governance/packs.lock`. If it does, stop and tell the user to use `governance pack update` (to re-pin to a version of the pack that has the change) or `governance pack remove` (to stop tracking the pack). The lockfile is the source of truth for pack-owned directives; hand-editing them silently would create drift that the next `pack update` would overwrite.

Do not proceed until the intent map is coherent. A valid amendment needs a concrete bad merge, a policy surface, and a check shape that would actually fail that bad merge.

### Step 3 — Draft the test script

Create or update `.governance/local/directives/<name>/`. Start `check.sh` from [`../assets/amend/directive.template.sh`](../assets/amend/directive.template.sh). Substitute:
- `<directive-name>` → the chosen name.
- The commented block → the actual check.

The script must:
- Source `../../lib.sh` (the helpers from `governance init`).
- Call `directive_start "<name>"` at the top and `directive_end` at the bottom.
- Call `require_git` if it touches `git ls-files` / `git grep`.
- On every violation: call `violation "<file>:<line> — <specific-message>"`. A directive without a location in the message is less useful — always include one if the check is per-file or per-line.
- Honor in-source waivers via `has_waiver "$file" "$line_no" "<directive-name>"` wherever violations are line-level, *unless* the user explicitly said no exceptions.

Choose the inspection surface to match the intent map:
- `repo-state` directives inspect the tracked tree at rest (`git ls-files`, `git grep`, known paths).
- `change-set obligation` directives inspect the staged diff locally and the branch diff in CI. Do not collapse these into existence checks just because existence checks are easier to write.
- If you cannot enforce the intended surface mechanically, stop and tell the user the directive is not ready yet. Do not ship a knowingly weak proxy without calling it out and getting explicit buy-in.

Create or update `.governance/local/directives/<name>/directive.yaml` with at least `category`, `recommended`, `summary`, `surface`, and `hook` fields. Use `hook: pre-commit` for ordinary repo-state directives, `hook: commit-msg` only for directives that validate the pending commit message, and `hook: none` for CI-only checks.

Create or update `.governance/local/directives/<name>/constitution.md` with the same Directives subsection you add to `CONSTITUTION.md`; this keeps the installed directive folder self-describing for future `init` work.

Syntax-check it: `bash -n .governance/local/directives/<name>/check.sh`. If it fails, fix and re-check. Never ship syntactically broken bash.

Write the script once it passes syntax check. Do not pause for user approval of the draft — PR review is the review layer. The only reason to stop mid-draft is a missing *blocking* input (rationale, or check shape so vague the bash cannot be deterministic); ask that one question and continue.

### Step 4 — Smoke-test the script

Run `bash .governance/local/directives/<name>/check.sh` against the current repo and capture the result.

- **Exits 0 (passes)** — fine. The directive isn't flagging the current tree. Proceed.
- **Exits 1 (fails)** — real directive output, pre-existing violators. This is the one case where a **single blocking question** is required before commit, because the resolution branches on user intent in a way the flow cannot decide mechanically. Show the verbatim violator list and ask the user to pick exactly one:
  1. **Loosen** — the directive is too strict; adjust the threshold / pattern / scope before committing. (Ask which threshold or scope to relax if the change isn't obvious from their answer.)
  2. **Grandfather** — the violators are pre-existing tech debt the user is willing to carry. Add waiver comments to the specific files/lines so CI stays green, then commit. The grandfathering is a reviewable diff.
  3. **Block** — the violators are real bugs. Commit the amendment as-is (CI will go red), and the user fixes the tree in a follow-up before merging.
  Then act on the chosen resolution and commit. Do **not** punt a red-CI PR to the reviewer by default — PR review is the review layer for the *directive*, not for triaging its collateral damage. "Block" is a valid choice when the user means it, but it's a choice, not a fallback.
- **Any other exit code / crashes** — the directive has a bug. Back to Step 3. Never ship an amendment that crashes.

For `change-set obligation` directives, also smoke-test the failure mode itself whenever feasible. The minimum bar is to create or identify a representative changed-path scenario and verify the directive fails when the required companion artifact is missing, not just that it passes on the current tree. If you cannot exercise the missing-companion case safely in the repo, say so explicitly in the final summary.

### Step 5 — Edit CONSTITUTION.md

Two edits, both in the same file:

**(a) Insert a Directives subsection**, alphabetical by directive name (or append at the end if no natural alphabetical spot). Use [`../assets/amend/directive-section.template.md`](../assets/amend/directive-section.template.md) as the shape:

```markdown
### <directive-name>

- **Directive**: <one-sentence statement>.
- **Rationale**: <why this matters, link incident if applicable>.
- **Enforced by**: `.governance/local/directives/<directive-name>/check.sh`
- **Exceptions**: <none | waiver comment format | config file reference>
```

Preserve everything else in the file verbatim. Use `Edit`, not `Write`.

If this is an **update** to an existing directive, preserve the original rationale unless the user explicitly changes the underlying policy intent. Threshold changes and mechanical refinements normally keep the existing rationale and only update the directive text, exceptions, or enforcement details.

**(b) Append an Evolution Log entry** in the format the file already uses (check the existing entries — the format is per-project). Default template:

```markdown
- YYYY-MM-DD — @<git-config-user> — Add `<directive-name>`: <one-line summary>.
```

Use today's date from the session environment (not a placeholder).

### Step 6 — Stage and commit the three artifacts

Use `git add -A .governance/local/directives/<directive-name> CONSTITUTION.md` so removals are staged correctly too.

Then run `git status` to confirm the three changes are staged and nothing else unrelated is picked up. If other unstaged changes exist, leave them unstaged — they're not part of this amendment.

**Commit** using a Conventional Commits subject matching the action:

- Added directive: `feat(governance): add <directive-name> — <one-line summary>`
- Updated directive: `refactor(governance): <one-line summary of what tightened/loosened> (<directive-name>)` (or `feat` if the update materially changes policy intent)
- Removed directive: `chore(governance): remove <directive-name> — <one-line reason>`

Append the issue anchor the repo requires (`commit-message-format` enforces `(#N)` in this kit by default). If the user did not name an issue, ask for it as a blocking input — it's a repo directive, not a style preference.

The commit body should include:
- A two-line summary of what the amendment does and why.
- If smoke-test exited 1: the verbatim violator list so the PR reviewer can act on it.
- Any material assumptions.

Pass the message via a HEREDOC so the formatting survives the shell. Do **not** push; the user (or the outer agent step) handles push. The flow's job ends at the local commit — PR review is the review layer, but opening the PR is not this flow's scope.

### Step 7 — Report to the user

Print:
- The directive name.
- The action type: added, updated, or removed.
- The three files changed (with paths).
- The intent map: bad merge to block, policy surface, and chosen enforcement surface.
- Smoke-test result: pass, fail-with-violators (list them), or crashed-then-fixed.
- Commit status: the SHA and subject of the commit just made.
- How to test locally: `bash .governance/run.sh <directive-name>`
- Assumptions made. If none, say `Assumptions: none`.
- A reminder that the pre-commit hook and CI workflow discover installed directive folders — no hook reinstall is needed for `pre-commit`, `commit-msg`, or `prepare-commit-msg` directives that declare the right `hook:` in `directive.yaml`.
- Next step for the user: `git push` to open the PR-review cycle (the real review gate).

## Required final output

Every successful `directive *` run should include:

- `Directive:` name
- `Action:` added, updated, or removed
- `Files changed:` list
- `Smoke test:` result (with violator list if exit-1)
- `Committed:` `<short-sha> <conventional-commit subject>`
- `Assumptions:` any material assumptions, or `none`
- `Next:` `git push` to open the PR-review cycle

---

## Key design principles

- **Three artifacts or nothing.** If you can only produce two of the three (e.g., the script is ambiguous and can't be written yet), stop and report. Do not edit `CONSTITUTION.md` for a directive whose test doesn't exist yet, and do not write a test whose directive isn't in the constitution. That is exactly the drift this flow is built to prevent.
- **PR review is the review layer.** Don't ask the user to sign off on a draft before you write it, and don't ask them to resolve smoke-test violators inline. Commit the amendment, surface the information they need to review on the PR, and let that be the gate.
- **Block only on genuinely missing inputs.** Rationale and a deterministic check shape are not optional — if either is missing from the user's request, ask a single targeted question. Everything else (threshold exact value, wording choices, alphabetical ordering) is decided here and the reviewer adjusts.
- **Never invent rationale.** "Because it's best practice" is not a rationale — governance derives authority from *named* incidents and *real* constraints. A directive without one is a speed bump nobody respects.
- **Preserve policy intent on updates.** Threshold tweaks and mechanical refinements should not silently rewrite the rationale.
- **Strengthen weak proxies, do not preserve them by default.** If an existing directive claims to enforce per-change behavior but only checks repo-level existence or file shape, treat that mismatch as drift worth fixing, not a quirk to copy forward.
- **Choose the check shape by failure mode.** Ask what bad merge this directive is meant to block. If the answer is "a future change that forgot to do X", the test should inspect the staged diff or branch diff rather than only the repo at rest.
- **Name the policy surface explicitly.** Every amendment must classify the directive as `repo-state` or `change-set obligation` before any bash is written. If you cannot make that classification, you do not understand the directive yet.
- **A passing smoke test is not enough for change-set directives.** If the directive is supposed to fail a missing companion artifact, prove that scenario fails or say why you could not exercise it. "It passes on the current repo" is not evidence that the right merge would be blocked.
- **Respect existing formatting.** The constitution is a living document. Match the indent style, list marker, and heading level conventions already in the file. Don't rewrite prose the user has been tending to.
- **State material assumptions explicitly.** Surface them in the commit body and the summary; the reviewer sees them on the PR.
- **Commit, don't push.** The flow creates a local commit; pushing is a separate decision the user makes. The flow's boundary is one atomic commit.

## References

- [`../assets/amend/directive.template.sh`](../assets/amend/directive.template.sh) — the starter shape for a new directive script.
- [`../assets/amend/directive-section.template.md`](../assets/amend/directive-section.template.md) — the shape for the Directives subsection.
- [DIRECTIVE_AUTHORING.md](DIRECTIVE_AUTHORING.md) — patterns and anti-patterns for writing good governance checks.
