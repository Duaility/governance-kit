---
name: governance-amend
description: Amends an existing governance-kit setup by adding, modifying, or removing a specific governance rule atomically across the enforcing test and the constitution's invariant/log entries. Use when the repo already has governance-kit installed and the user wants a concrete rule change such as "add a governance rule", "add a new invariant", "amend the constitution", "modify rule X", or "remove rule Y". Do not use for initial setup; use governance-bootstrap for that. Do not use for general health reviews; use governance-gardener for that.
license: MIT
metadata:
  author: governance-kit
  version: "0.1"
  companion-of: governance-bootstrap
---

# governance-amend

The `governance-bootstrap` skill sets up the system of record. **This skill evolves it.**

Governance-driven development's cardinal rule: *the constitution and the enforcing tests evolve together, in one commit.* This skill makes obeying that rule cheap and makes breaking it harder than following it.

Every amendment this skill produces is three logical changes, committed atomically:

1. A new (or updated) rule folder at `tests/governance/rules/<rule-name>/` with `rule.yaml`, `check.sh`, and `constitution.md`.
2. A new **Invariants** subsection in `CONSTITUTION.md`.
3. A new entry in the `CONSTITUTION.md` **Evolution Log**.

The skill stages and **commits** the amendment in one conventional-commit. Review happens on the PR — the skill does not run inline approval loops, because the workflow this skill is built for relies on PR review as the gate. The skill still refuses to finish with a partial amendment on disk.

## Negative triggers

Do **not** use this skill for these requests:

- "Set up governance for this repo" — use `governance-bootstrap`.
- "Run a governance health check" or "find dead rules" — use `governance-gardener`.
- "Explain what this constitution means" — answer directly; do not amend anything.
- "Review whether these rules are good" — answer directly or use `governance-gardener`.

## Interaction policy

| Situation | Action |
|---|---|
| Governance kit is missing | Stop and tell the user to run `governance-bootstrap` first. |
| User asks for a general review or health check | Do not amend. Redirect to `governance-gardener`. |
| Request has enough info to draft the rule | Draft, smoke-test, commit. No approval loop — PR review is the review layer. |
| Request is missing rationale or check logic | Ask only the blocking question(s). Do not ask for approval of drafts that are already unambiguous. |
| Request updates an existing rule | Preserve the existing rationale unless the user explicitly changes the policy intent. Note the update in the summary. |
| Request removes a rule | Remove the test and invariant together, add an evolution-log entry, and surface dangling references. |
| Smoke test fails on pre-existing violators | Ask one blocking question — **loosen** (which threshold), **grandfather** (add waivers to the specific violators), or **block** (commit as-is, user fixes tree separately). Act on the answer, then commit. Do not punt a red-CI PR to the reviewer. |
| Structured question tools are unavailable | Use short free-text questions instead of stopping. |

---

## Activation flow

### Step 1 — Verify the kit is installed

Run in parallel:
- `git rev-parse --show-toplevel` — confirm we're inside a git repo; capture the root.
- Check for `<root>/CONSTITUTION.md`.
- Check for `<root>/tests/governance/rules/` (directory).
- Check for `<root>/tests/governance/run.sh` (executable).

If any is missing, stop. The user needs `governance-bootstrap` first — don't pretend to amend something that isn't there. Tell them that explicitly.

If `CONSTITUTION.md` lacks an **Invariants** or **Evolution Log** heading, still stop and tell the user which is missing — adding those sections is a kit-structure change, not an amendment, and belongs to bootstrap.

### Step 2 — Collect the rule specification

Most requests will already give you most of this — extract what you can from the user's prompt before asking. What you need:

| Field | Constraint |
|---|---|
| **Rule name** | `[a-z][a-z0-9-]*[a-z0-9]`, ≤ 50 chars, matches the filename. No spaces, no uppercase. |
| **Rule statement** | One sentence, present tense, naming what the code **must** or **must not** do. |
| **Rationale** | Why this matters. Ideally references a concrete incident, policy, or constraint. |
| **Check logic** | What the script actually inspects — files, patterns, paths, size thresholds, git state, etc. |
| **Exceptions** | How approved deviations are documented. Default: no exceptions. Otherwise: waiver comment `governance: allow-<rule-name> <ticket>` or a named config file the rule reads. |

Before you draft anything, write down an explicit **intent map** for yourself:

| Field | What to capture |
|---|---|
| **Bad merge to block** | The concrete merge or omission this rule is meant to stop. |
| **Policy surface** | `repo-state` or `change-set obligation`. |
| **Enforcement surface** | Repo-at-rest scan, staged diff, or branch diff in CI. |
| **Why this surface fits** | One sentence tying the check shape back to the bad merge. |

If a **blocking** field is missing (no rationale, or check logic so vague the bash cannot be deterministic), **ask only that blocking question** via `AskUserQuestion` or free text. Never ask for approval of a draft that is already implementable — the PR is the review surface, not the skill's transcript. One question at a time; do not dump a multi-field form.

If the user's rationale says "every substantive change must...", "this kind of change must also...", "reviewers keep missing intent/approval/metadata", or anything else that describes a missing companion artifact in a change set, classify it as a **change-set obligation** unless the user explicitly says otherwise.

Default operating mode is **fast path**: draft → syntax-check → smoke-test → edit constitution → stage → commit. Ask a clarifying question only when the intent map cannot be filled in from the user's request. If structured question tools are unavailable, use short free-text questions instead of stopping.

**Handle collisions without asking for confirmation:**
- If `tests/governance/rules/<name>/check.sh` already exists → this is an **update**, not a new rule. Proceed with the update (preserving rationale unless policy intent changes) and note it in the summary. Treat the matching `CONSTITUTION.md` subsection as an update too.
- If `CONSTITUTION.md` already has a subsection whose header closely matches the proposed name → same: proceed with update, note it.
- If the user asked to **remove** a rule, verify the matching script and invariant exist before deleting, and grep for dangling references in docs or CI notes. If references exist, surface them in the summary — do not silently delete around them.

Do not proceed until the intent map is coherent. A valid amendment needs a concrete bad merge, a policy surface, and a check shape that would actually fail that bad merge.

### Step 3 — Draft the test script

Create or update `tests/governance/rules/<name>/`. Start `check.sh` from `assets/rule.template.sh`. Substitute:
- `<rule-name>` → the chosen name.
- The commented block → the actual check.

The script must:
- Source `../../lib.sh` (the helpers from governance-bootstrap).
- Call `rule_start "<name>"` at the top and `rule_end` at the bottom.
- Call `require_git` if it touches `git ls-files` / `git grep`.
- On every violation: call `violation "<file>:<line> — <specific-message>"`. A rule without a location in the message is less useful — always include one if the check is per-file or per-line.
- Honor in-source waivers via `has_waiver "$file" "$line_no" "<rule-name>"` wherever violations are line-level, *unless* the user explicitly said no exceptions.

Choose the inspection surface to match the intent map:
- `repo-state` rules inspect the tracked tree at rest (`git ls-files`, `git grep`, known paths).
- `change-set obligation` rules inspect the staged diff locally and the branch diff in CI. Do not collapse these into existence checks just because existence checks are easier to write.
- If you cannot enforce the intended surface mechanically, stop and tell the user the rule is not ready yet. Do not ship a knowingly weak proxy without calling it out and getting explicit buy-in.

Create or update `tests/governance/rules/<name>/rule.yaml` with at least `category`, `recommended`, `summary`, `surface`, and `hook` fields. Use `hook: pre-commit` for ordinary repo-state rules, `hook: commit-msg` only for rules that validate the pending commit message, and `hook: none` for CI-only checks.

Create or update `tests/governance/rules/<name>/constitution.md` with the same Invariants subsection you add to `CONSTITUTION.md`; this keeps the installed rule folder self-describing for future bootstrap/gardener work.

Syntax-check it: `bash -n tests/governance/rules/<name>/check.sh`. If it fails, fix and re-check. Never ship syntactically broken bash.

Write the script once it passes syntax check. Do not pause for user approval of the draft — PR review is the review layer. The only reason to stop mid-draft is a missing *blocking* input (rationale, or check shape so vague the bash cannot be deterministic); ask that one question and continue.

### Step 4 — Smoke-test the script

Run `bash tests/governance/rules/<name>/check.sh` against the current repo and capture the result.

- **Exits 0 (passes)** — fine. The rule isn't flagging the current tree. Proceed.
- **Exits 1 (fails)** — real rule output, pre-existing violators. This is the one case where a **single blocking question** is required before commit, because the resolution branches on user intent in a way the skill cannot decide mechanically. Show the verbatim violator list and ask the user to pick exactly one:
  1. **Loosen** — the rule is too strict; adjust the threshold / pattern / scope before committing. (Ask which threshold or scope to relax if the change isn't obvious from their answer.)
  2. **Grandfather** — the violators are pre-existing tech debt the user is willing to carry. Add waiver comments to the specific files/lines so CI stays green, then commit. The grandfathering is a reviewable diff.
  3. **Block** — the violators are real bugs. Commit the amendment as-is (CI will go red), and the user fixes the tree in a follow-up before merging.
  Then act on the chosen resolution and commit. Do **not** punt a red-CI PR to the reviewer by default — PR review is the review layer for the *rule*, not for triaging its collateral damage. "Block" is a valid choice when the user means it, but it's a choice, not a fallback.
- **Any other exit code / crashes** — the rule has a bug. Back to Step 3. Never ship an amendment that crashes.

For `change-set obligation` rules, also smoke-test the failure mode itself whenever feasible. The minimum bar is to create or identify a representative changed-path scenario and verify the rule fails when the required companion artifact is missing, not just that it passes on the current tree. If you cannot exercise the missing-companion case safely in the repo, say so explicitly in the final summary.

### Step 5 — Edit CONSTITUTION.md

Two edits, both in the same file:

**(a) Insert an Invariants subsection**, alphabetical by rule name (or append at the end if no natural alphabetical spot). Use `assets/invariant-section.template.md` as the shape:

```markdown
### <rule-name>

- **Rule**: <one-sentence statement>.
- **Rationale**: <why this matters, link incident if applicable>.
- **Enforced by**: `tests/governance/rules/<rule-name>/check.sh`
- **Exceptions**: <none | waiver comment format | config file reference>
```

Preserve everything else in the file verbatim. Use `Edit`, not `Write`.

If this is an **update** to an existing rule, preserve the original rationale unless the user explicitly changes the underlying policy intent. Threshold changes and mechanical refinements normally keep the existing rationale and only update the rule text, exceptions, or enforcement details.

**(b) Append an Evolution Log entry** in the format the file already uses (check the existing entries — the format is per-project). Default template:

```markdown
- YYYY-MM-DD — @<git-config-user> — Add `<rule-name>`: <one-line summary>.
```

Use today's date from the session environment (not a placeholder).

### Step 6 — Stage and commit the three artifacts

Use `git add -A tests/governance/rules/<rule-name> CONSTITUTION.md` so removals are staged correctly too.

Then run `git status` to confirm the three changes are staged and nothing else unrelated is picked up. If other unstaged changes exist, leave them unstaged — they're not part of this amendment.

**Commit** using a Conventional Commits subject matching the action:

- Added rule: `feat(governance): add <rule-name> — <one-line summary>`
- Updated rule: `refactor(governance): <one-line summary of what tightened/loosened> (<rule-name>)` (or `feat` if the update materially changes policy intent)
- Removed rule: `chore(governance): remove <rule-name> — <one-line reason>`

Append the issue anchor the repo requires (`conventional-commits` enforces `(#N)` in this kit by default). If the user did not name an issue, ask for it as a blocking input — it's a repo invariant, not a style preference.

The commit body should include:
- A two-line summary of what the amendment does and why.
- If smoke-test exited 1: the verbatim violator list so the PR reviewer can act on it.
- Any material assumptions.

Pass the message via a HEREDOC so the formatting survives the shell. Do **not** push; the user (or the outer agent step) handles push. The skill's job ends at the local commit — PR review is the review layer, but opening the PR is not this skill's scope.

### Step 7 — Report to the user

Print:
- The rule name.
- The action type: added, updated, or removed.
- The three files changed (with paths).
- The intent map: bad merge to block, policy surface, and chosen enforcement surface.
- Smoke-test result: pass, fail-with-violators (list them), or crashed-then-fixed.
- Commit status: the SHA and subject of the commit the skill just made.
- How to test locally: `bash tests/governance/run.sh <rule-name>`
- Assumptions made. If none, say `Assumptions: none`.
- A reminder that the pre-commit hook and CI workflow discover installed rule folders — no hook reinstall is needed for `pre-commit`, `commit-msg`, or `prepare-commit-msg` rules that declare the right `hook:` in `rule.yaml`.
- Next step for the user: `git push` to open the PR-review cycle (the real review gate).

## Required final output

Every successful run should include:

- `Rule:` name
- `Action:` added, updated, or removed
- `Files changed:` list
- `Smoke test:` result (with violator list if exit-1)
- `Committed:` `<short-sha> <conventional-commit subject>`
- `Assumptions:` any material assumptions, or `none`
- `Next:` `git push` to open the PR-review cycle

---

## Key design rules

- **Three artifacts or nothing.** If you can only produce two of the three (e.g., the script is ambiguous and can't be written yet), stop and report. Do not edit `CONSTITUTION.md` for a rule whose test doesn't exist yet, and do not write a test whose invariant isn't in the constitution. That is exactly the drift this skill is built to prevent.
- **PR review is the review layer, not the skill.** Don't ask the user to sign off on a draft before you write it, and don't ask them to resolve smoke-test violators inline. Commit the amendment, surface the information they need to review on the PR, and let that be the gate.
- **Block only on genuinely missing inputs.** Rationale and a deterministic check shape are not optional — if either is missing from the user's request, ask a single targeted question. Everything else (threshold exact value, wording choices, alphabetical ordering) the skill decides and the reviewer adjusts.
- **Never invent rationale.** "Because it's best practice" is not a rationale — governance derives authority from *named* incidents and *real* constraints. A rule without one is a speed bump nobody respects.
- **Preserve policy intent on updates.** Threshold tweaks and mechanical refinements should not silently rewrite the rationale.
- **Strengthen weak proxies, do not preserve them by default.** If an existing rule claims to enforce per-change behavior but only checks repo-level existence or file shape, treat that mismatch as drift worth fixing, not a quirk to copy forward.
- **Choose the check shape by failure mode.** Ask what bad merge this rule is meant to block. If the answer is "a future change that forgot to do X", the test should inspect the staged diff or branch diff rather than only the repo at rest.
- **Name the policy surface explicitly.** Every amendment must classify the rule as `repo-state` or `change-set obligation` before any bash is written. If you cannot make that classification, you do not understand the rule yet.
- **A passing smoke test is not enough for change-set rules.** If the rule is supposed to fail a missing companion artifact, prove that scenario fails or say why you could not exercise it. "It passes on the current repo" is not evidence that the right merge would be blocked.
- **Respect existing formatting.** The constitution is a living document. Match the indent style, list marker, and heading level conventions already in the file. Don't rewrite prose the user has been tending to.
- **State material assumptions explicitly.** Surface them in the commit body and the summary; the reviewer sees them on the PR.
- **Commit, don't push.** The skill creates a local commit; pushing is a separate decision the user makes. The skill's boundary is one atomic commit.

## References

- `../GOVERNANCE_VOCABULARY.md` — shared terms used across the three governance skills.
- `assets/rule.template.sh` — the starter shape for a new rule script.
- `assets/invariant-section.template.md` — the shape for the Invariants subsection.
- `references/RULE_AUTHORING.md` — patterns and anti-patterns for writing good governance checks.
