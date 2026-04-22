<!-- last-verified: 2026-04-22 -->

# Governance Vocabulary

Shared terms used by `governance-bootstrap`, `governance-amend`, and `governance-gardener`.

## Core terms

### rule

A concrete requirement or prohibition that can be checked mechanically. In this repo, a rule belongs in `CONSTITUTION.md` only if there is an executable check for it.

### invariant

A rule as recorded in the `## Invariants` section of `CONSTITUTION.md`. Each invariant names the rule, rationale, enforcing test, and exceptions.

### principle

A non-mechanical guideline that still governs the repo, but depends on judgment rather than a pass/fail script.

### waiver

An explicitly documented exception to a rule. Waivers are local and intentional; they are not silent escapes. Typical forms are inline comments such as `governance: allow-<rule-name> <reason>` or named config files the rule reads.

### evolution log

The append-only history in `CONSTITUTION.md` recording governance changes. It explains when a rule changed and why.

### system of record

The tracked files that define how the repo works now. In this project that usually means `CONSTITUTION.md`, `AGENTS.md`, docs, rule scripts, and any tracked config the governance suite relies on.

### drift

Misalignment between two things that should agree. Common examples:

- constitution drift: the invariant and the enforcing test no longer match
- doc drift: a doc's `last-verified` stamp is older than the code it describes
- evolution-log drift: a logged amendment was not made atomically with its test change

### signal

A gardener finding pattern such as `A3`, `F2`, or `C5`. Signals are evidence-backed observations, not automatic amendments.

### watched scope

The file set a doc or rule is considered responsible for. The gardener uses watched scopes to decide whether a doc has drifted or whether a rule is dormant. Canonical resolution lives in [governance-gardener/references/WATCH_SCOPES.md](governance-gardener/references/WATCH_SCOPES.md).

## Execution terms

### bootstrap

Initial installation of the governance kit into a repo that does not yet have it, or an explicit augment/overwrite operation requested by the user.

### amend

A targeted change to an existing governance installation: add, modify, or remove a specific rule while keeping the constitution and enforcing test in sync.

### gardener

A periodic health check over an existing governance installation. The gardener writes a report and may optionally open follow-up PRs after user review.

### report-only mode

Gardener mode that writes the health report but does not create branches or PRs. Dirty working trees are acceptable here.

### follow-up mode

Gardener mode that may create branches or PRs after the report is written. Requires a clean working tree.

### material assumption

An inference that changes behavior in a way the user may care about. Examples: choosing a stack in a polyglot repo, choosing `.githooks/` over another hook framework, selecting the `standard` preset without explicit user confirmation, or inferring watched scope from sibling directories. Skills should label these explicitly as assumptions in their summaries.
