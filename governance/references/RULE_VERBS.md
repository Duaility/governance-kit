<!-- last-verified: 2026-04-24 -->

# governance rule * — verb flows

Authoritative flow for the hand-authored rule verbs: `governance rule add`, `governance rule modify`, `governance rule remove`. These verbs replace the `governance-amend` skill; until that skill is retired, `rule *` delegates to its flow verbatim.

## The atomic triple

Every rule amendment is **three logical changes, committed atomically**:

1. A rule folder at `tests/governance/rules/<rule-id>/` — `rule.yaml`, `check.sh`, `constitution.md` (+ optional `hooks/`, `lib/`, `runtimes/`, `install-assets/`).
2. An **Invariants** subsection in `CONSTITUTION.md` — the human-readable rule + rationale + enforcement pointer.
3. A new entry in the `CONSTITUTION.md` **Evolution Log** — dated, one line per amendment.

A commit that touches the rule folder without the matching constitution edits (or vice versa) is a broken amendment. The `governance-amend` flow refuses to finish with partial state on disk; `rule *` inherits that discipline.

## `rule add <rule-id>`

- **Aliases a user might type:** "add a governance rule", "new invariant", "amend the constitution", "add rule X".
- **Authoritative flow:** [../../governance-amend/SKILL.md](../../governance-amend/SKILL.md) Steps 1–6.
- **Assets used:**
  - `../../governance-amend/assets/rule.template.sh` — `check.sh` skeleton.
  - `../../governance-amend/assets/invariant-section.template.md` — constitution subsection skeleton.
  - `../../governance-amend/references/RULE_AUTHORING.md` — rule-name rules, check patterns, smoke-test guidance.
- **Preconditions:** governance-kit must already be installed (`CONSTITUTION.md` present with `Invariants` + `Evolution Log` headings, `tests/governance/rules/` exists). If the kit is missing, stop and route to `governance init`.
- **Smoke test before commit:** the drafted `check.sh` must pass against the current tree. If it fails on pre-existing violators, ask the single blocking question — **loosen** (which threshold), **grandfather** (add waivers to specific violators), or **block** (commit as-is, user fixes tree separately) — then act. Never ship a rule that red-lights HEAD.

## `rule modify <rule-id>`

- **Aliases a user might type:** "modify rule X", "tighten rule X", "loosen rule X", "update the check logic for X".
- **Authoritative flow:** same as `rule add`, but the existing rule folder and invariant subsection are edited in place (preserving rationale unless the policy intent itself is changing).
- **Evolution Log requirement:** a modification is still an amendment — append a new log entry describing what changed and why. A rule whose check logic changes without a log entry is opaque to future maintainers.

## `rule remove <rule-id>`

- **Aliases a user might type:** "remove rule X", "retire rule X", "drop the invariant about X".
- **Authoritative flow:** [../../governance-amend/SKILL.md](../../governance-amend/SKILL.md) — the removal branch at the end of Step 5.
- **Mechanics:**
  1. Delete `tests/governance/rules/<rule-id>/`.
  2. Remove the rule's **Invariants** subsection from `CONSTITUTION.md`.
  3. Append an **Evolution Log** entry recording the removal date and reason.
  4. Surface any dangling references (mentions in `README.md`, `AGENTS.md`, CI config) so the user can clean them up.
  5. If the rule belonged to a community pack tracked in `.governance/packs.lock`, this verb is the wrong tool — use `governance pack remove <pack-id>` instead so the lockfile stays consistent.

## Boundaries

- `rule *` mutates **hand-authored** rules: things the user wrote for their own repo or that came from `core`. Rules installed via `governance pack add <community-pack>` are owned by the lockfile; edit them with `governance pack update` or by forking the upstream pack.
- `rule *` does **not** run CI. The governance-amend flow commits the atomic triple; CI runs on the PR.
- When the user asks to "review" or "audit" rules rather than change one, route to `governance-gardener`.
