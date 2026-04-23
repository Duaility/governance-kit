### plan-per-issue

- **Rule**: Every tracked `plans/*.md` filename includes an `issue-<N>` token identifying the GitHub issue it plans for, and no two plan files share the same issue number.
- **Rationale**: Plans are the durable record of intent behind a change set. A one-to-one binding between plan and issue keeps the system of record unambiguous — reviewers jump from an issue to its single plan, and agents can detect whether an issue already has a plan before drafting a duplicate.
- **Enforced by**: `tests/governance/rules/plan-per-issue/check.sh`
- **Exceptions**: Per-file waiver — a line matching `governance: allow-plan-per-issue` (bare or inside an HTML comment) anywhere in the file exempts that plan. Used to grandfather plans that predate this rule.
