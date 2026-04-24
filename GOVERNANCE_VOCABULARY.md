<!-- last-verified: 2026-04-22 -->

# Governance Vocabulary

Shared terms used by the `governance` skill's verbs (`init`, `uninstall`, `pack *`, `rule *`).

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

## Execution terms

### bootstrap

Initial installation of the governance kit into a repo that does not yet have it, or an explicit augment/overwrite operation requested by the user.

### amend

A targeted change to an existing governance installation: add, modify, or remove a specific rule while keeping the constitution and enforcing test in sync.

### material assumption

An inference that changes behavior in a way the user may care about. Examples: choosing a stack in a polyglot repo, choosing `.githooks/` over another hook framework, selecting the `standard` preset without explicit user confirmation, or inferring watched scope from sibling directories. Skills should label these explicitly as assumptions in their summaries.
