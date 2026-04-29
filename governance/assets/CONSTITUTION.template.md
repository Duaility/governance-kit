# Constitution

This document is the source of truth for the principles, guidelines, and directives that govern development in this repository. Every directive here is enforced by an executable test under `.governance/`. A directive with no enforcing test is not a directive — it is a wish.

> **The cardinal rule:** Amendments to this constitution must land in the same commit as the change to its enforcing test. No exceptions.

## Compliance

Anyone working in this repo — humans, agents, scripted automation — must satisfy every principle, guideline, and directive in this document.

- **Mechanical directives** (the **Directives** section below) are enforced by `.governance/` via the pre-commit hook and CI. A violating commit is blocked locally and re-blocked in CI if the hook is bypassed.
- **Principles and guidelines** (the **Principles** section above the Directives) cannot be checked mechanically. They depend on judgment and reviewer discipline. A change that defies a principle without explanation is grounds to block the PR.

If a specific change cannot satisfy a directive, document the deviation in the PR description and use the directive's stated waiver mechanism if one exists. Drive-by violations without explanation will block the merge.

## Principles

<!-- High-level philosophy. 3-5 statements max. These are not enforced automatically — they frame the directives below and guide what belongs here. -->

- Changes to this constitution must land with a corresponding change to the enforcing tests.
- Escape hatches exist (`SKIP_GOVERNANCE=1`, `git commit --no-verify`) — but every skipped commit is still checked in CI.
- Governance directives should fail loudly and cheaply. If a directive cannot be mechanically checked, it does not belong here.

<!-- Replace / extend with project-specific principles. -->

## Directives

<!--
For each directive, use this structure:

### <short name>

- **Directive**: one-sentence statement, in the present tense.
- **Rationale**: why this matters — ideally linked to a past incident or concrete cost.
- **Enforced by**: relative path to the test file.
- **Exceptions**: how approved deviations are documented (e.g., `# governance: allow-secret <ticket-id>`).
-->

### Example — constitution-exists (meta-directive)

- **Directive**: A `CONSTITUTION.md` exists at the repo root and is non-empty.
- **Rationale**: Governance without a discoverable source of truth is tribal knowledge.
- **Enforced by**: `.governance/packs/<owner>/<repo>/directives/constitution-exists/check.sh`
- **Exceptions**: none.

<!-- governance-bootstrap will inject one subsection per directive the user selected. -->

## Amendment process

1. Open a PR that modifies this file **and** the directive folder under `.governance/packs/<owner>/<repo>/directives/` in the same commit.
2. The PR description states *what* changed and *why* — link the incident, RFC, or discussion that motivated it.
3. Add an entry to the **Evolution Log** below.
4. At least one reviewer with governance authority approves.

## Evolution Log

<!-- Append, do not rewrite history. Format: YYYY-MM-DD — <author> — <one-line summary>. Link the PR. -->

- YYYY-MM-DD — @you — Initial constitution bootstrapped via governance-bootstrap.

## Escape hatches

Governance is enforced at two layers:

1. **Pre-commit hook** — runs `.governance/run.sh` before each commit. Skip with `SKIP_GOVERNANCE=1 git commit ...` or `git commit --no-verify` when a hotfix cannot wait.
2. **CI workflow** — `.github/workflows/governance.yml` runs the same tests on every PR and push to the default branch. CI cannot be skipped from a developer machine.

The hook is for speed; CI is for enforcement. If a commit lands with the hook skipped, CI will catch it.
