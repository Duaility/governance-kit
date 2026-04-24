### plan-per-issue

- **Rule**: Every tracked `plans/*.md` file satisfies two shape requirements:
    1. The filename includes an `issue-<N>` token identifying the GitHub issue it plans for, and no two plans share the same issue number.
    2. The body contains at least one `## Validation`, `## Verification`, or `## Acceptance` section describing how completion will be judged.
- **Rationale**: Plans are the durable record of intent behind a change set. A one-to-one binding between plan and issue keeps the system of record unambiguous — reviewers jump from an issue to its single plan, and agents can detect whether an issue already has a plan before drafting a duplicate. A validation-intent section forces the author to name the exit criterion before code is written, which is what distinguishes a plan from a running commentary.
- **Enforced by**: `tests/governance/rules/plan-per-issue/check.sh`
- **Exceptions**: Two per-file waivers, each matched as a bare line or inside an HTML comment anywhere in the file:
    - `governance: allow-plan-per-issue` — exempts the plan from the filename-token and duplicate-issue checks. Used to grandfather plans that predate this rule.
    - `governance: allow-plan-validation` — exempts the plan from the validation-section check only. Used to grandfather legacy plans imported before the validation requirement existed; new plans should carry the section instead.
