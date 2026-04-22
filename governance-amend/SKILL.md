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

Every amendment this skill produces is three logical changes, staged atomically:

1. A new (or updated) test script at `tests/governance/rules/<rule-name>.sh`.
2. A new **Invariants** subsection in `CONSTITUTION.md`.
3. A new entry in the `CONSTITUTION.md` **Evolution Log**.

The skill does **not** commit. The user reviews and commits. But the amendment is staged together and the skill refuses to finish with a partial amendment on disk.

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
| Request names a concrete rule, rationale, and check shape | Use the fast path. |
| Request is missing rationale or check logic | Ask one concise question at a time until it is implementable. |
| Request updates an existing rule | Preserve the existing rationale unless the user explicitly changes the policy intent. |
| Request removes a rule | Remove the test and invariant together, add an evolution-log entry, and surface dangling references. |
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

If any field is ambiguous, **ask one question at a time** via `AskUserQuestion` or free text — don't dump a four-question form on the user. The most common blocker is "check logic" being too vague; iterate until you have something concrete enough to write bash that either passes or fails deterministically.

If the user's rationale says "every substantive change must...", "this kind of change must also...", "reviewers keep missing intent/approval/metadata", or anything else that describes a missing companion artifact in a change set, classify it as a **change-set obligation** unless the user explicitly says otherwise.

Use two operating modes:
- **Fast path** — if the user's request already names a concrete rule, rationale, and check shape, draft the amendment directly, smoke-test it, and then show the result.
- **Interactive path** — if rule scope, rationale, or check logic is ambiguous, ask one concise question at a time until the rule is concrete enough to implement safely.

If structured question tools are unavailable, use short free-text questions instead of stopping.

**Check for collisions before you proceed:**
- If `tests/governance/rules/<name>.sh` already exists → this is an **update**, not a new rule. Confirm with the user before overwriting, and treat the matching `CONSTITUTION.md` subsection as an update too (not a new insertion).
- If `CONSTITUTION.md` already has a subsection whose header closely matches the proposed name → same thing, confirm.
- If the user asked to **remove** a rule, confirm the matching script and invariant exist before you start deleting. Also grep for dangling references in docs or CI notes before finishing.

Do not proceed until the intent map is coherent. A valid amendment needs a concrete bad merge, a policy surface, and a check shape that would actually fail that bad merge.

### Step 3 — Draft the test script

Start from `assets/rule.template.sh`. Substitute:
- `<rule-name>` → the chosen name.
- The commented block → the actual check.

The script must:
- Source `../lib.sh` (the helpers from governance-bootstrap).
- Call `rule_start "<name>"` at the top and `rule_end` at the bottom.
- Call `require_git` if it touches `git ls-files` / `git grep`.
- On every violation: call `violation "<file>:<line> — <specific-message>"`. A rule without a location in the message is less useful — always include one if the check is per-file or per-line.
- Honor in-source waivers via `has_waiver "$file" "$line_no" "<rule-name>"` wherever violations are line-level, *unless* the user explicitly said no exceptions.

Choose the inspection surface to match the intent map:
- `repo-state` rules inspect the tracked tree at rest (`git ls-files`, `git grep`, known paths).
- `change-set obligation` rules inspect the staged diff locally and the branch diff in CI. Do not collapse these into existence checks just because existence checks are easier to write.
- If you cannot enforce the intended surface mechanically, stop and tell the user the rule is not ready yet. Do not ship a knowingly weak proxy without calling it out and getting explicit buy-in.

Syntax-check it: `bash -n tests/governance/rules/<name>.sh`. If it fails, fix and re-check. Do not put syntactically broken bash in front of the user.

On the **interactive path**, show the draft and ask whether it's the check they want. Iterate. When the user signs off, write it to disk.

On the **fast path**, write the script once it passes syntax check, then show the user the resulting rule and any smoke-test output. Do not stop for approval unless the smoke test reveals ambiguity or the rule would require waivers or repo fixes the user did not ask for.

### Step 4 — Smoke-test the script

Run `bash tests/governance/rules/<name>.sh` against the current repo and capture the result.

- **Exits 0 (passes)** — fine. The rule isn't flagging the current tree. Proceed.
- **Exits 1 (fails)** — show the user the output and ask: is this a real violation that needs fixing now, or is the rule overly strict? They choose: (a) fix the code so the rule passes, or (b) loosen the rule, or (c) add a waiver comment for the specific existing cases.
- **Any other exit code / crashes** — the rule has a bug. Back to Step 3.

Never ship an amendment that crashes. Exit-1 is legitimate (that's a rule detecting a violation); exit-2+ or a stack trace is a broken rule.

For `change-set obligation` rules, also smoke-test the failure mode itself whenever feasible. The minimum bar is to create or identify a representative changed-path scenario and verify the rule fails when the required companion artifact is missing, not just that it passes on the current tree. If you cannot exercise the missing-companion case safely in the repo, say so explicitly in the final summary.

### Step 5 — Edit CONSTITUTION.md

Two edits, both in the same file:

**(a) Insert an Invariants subsection**, alphabetical by rule name (or append at the end if no natural alphabetical spot). Use `assets/invariant-section.template.md` as the shape:

```markdown
### <rule-name>

- **Rule**: <one-sentence statement>.
- **Rationale**: <why this matters, link incident if applicable>.
- **Enforced by**: `tests/governance/rules/<rule-name>.sh`
- **Exceptions**: <none | waiver comment format | config file reference>
```

Preserve everything else in the file verbatim. Use `Edit`, not `Write`.

If this is an **update** to an existing rule, preserve the original rationale unless the user explicitly changes the underlying policy intent. Threshold changes and mechanical refinements normally keep the existing rationale and only update the rule text, exceptions, or enforcement details.

**(b) Append an Evolution Log entry** in the format the file already uses (check the existing entries — the format is per-project). Default template:

```markdown
- YYYY-MM-DD — @<git-config-user> — Add `<rule-name>`: <one-line summary>.
```

Use today's date from the session environment (not a placeholder).

### Step 6 — Stage the three artifacts

Use `git add -A tests/governance/rules/<rule-name>.sh CONSTITUTION.md` so removals are staged correctly too.

Then run `git status` to confirm the three changes are staged and nothing else unrelated is picked up. If other unstaged changes exist, leave them unstaged — they're not part of this amendment.

**Do not commit.** The user commits, with a message they write. Suggest a commit message in the summary (Step 7) but don't run `git commit`.

### Step 7 — Report to the user

Print:
- The rule name.
- The action type: added, updated, or removed.
- The three files changed (with paths).
- The intent map: bad merge to block, policy surface, and chosen enforcement surface.
- Smoke-test result: pass, fail-with-real-violation, or crashed-then-fixed.
- Staged status: confirm the intended amendment files are staged and unrelated files are not.
- A suggested commit message in Conventional Commits format: `feat(governance): add <rule-name> — <one-line summary>`
- How to test locally: `bash tests/governance/run.sh <rule-name>`
- Assumptions made. If none, say `Assumptions: none`.
- A reminder that the pre-commit hook and CI workflow already pick up the new rule — no hook reinstall needed.

## Required final output

Every successful run should include:

- `Rule:` name
- `Action:` added, updated, or removed
- `Files changed:` list
- `Smoke test:` result
- `Staged:` yes/no summary
- `Assumptions:` any material assumptions, or `none`
- `Suggested commit:` conventional-commit subject

---

## Key design rules

- **Three artifacts or nothing.** If you can only produce two of the three (e.g., the script is ambiguous and can't be written yet), stop and report. Do not edit `CONSTITUTION.md` for a rule whose test doesn't exist yet, and do not write a test whose invariant isn't in the constitution. That is exactly the drift this skill is built to prevent.
- **Fast path when the request is concrete.** Do not force an approval loop for an obvious, well-specified amendment.
- **Iterate on the check when it is ambiguous.** A staged half-baked rule is worse than no rule — if the rule shape is unclear, slow down and clarify before staging.
- **Never invent rationale.** If the user didn't give a reason, ask. "Because it's best practice" is not a rationale — governance derives authority from *named* incidents and *real* constraints. A rule without one is a speed bump nobody respects.
- **Preserve policy intent on updates.** Threshold tweaks and mechanical refinements should not silently rewrite the rationale.
- **Strengthen weak proxies, do not preserve them by default.** If an existing rule claims to enforce per-change behavior but only checks repo-level existence or file shape, treat that mismatch as drift worth fixing, not a quirk to copy forward.
- **Choose the check shape by failure mode.** Ask what bad merge this rule is meant to block. If the answer is "a future change that forgot to do X", the test should inspect the staged diff or branch diff rather than only the repo at rest.
- **Name the policy surface explicitly.** Every amendment must classify the rule as `repo-state` or `change-set obligation` before any bash is written. If you cannot make that classification, you do not understand the rule yet.
- **A passing smoke test is not enough for change-set rules.** If the rule is supposed to fail a missing companion artifact, prove that scenario fails or say why you could not exercise it. "It passes on the current repo" is not evidence that the right merge would be blocked.
- **Respect existing formatting.** The constitution is a living document. Match the indent style, list marker, and heading level conventions already in the file. Don't rewrite prose the user has been tending to.
- **State material assumptions explicitly.** If you inferred the rule name, summary line, or author handle, surface that in the summary.
- **Don't commit.** The skill ends at `git add`, not `git commit`. The user's review is the final gate.

## References

- `../GOVERNANCE_VOCABULARY.md` — shared terms used across the three governance skills.
- `assets/rule.template.sh` — the starter shape for a new rule script.
- `assets/invariant-section.template.md` — the shape for the Invariants subsection.
- `references/RULE_AUTHORING.md` — patterns and anti-patterns for writing good governance checks.
