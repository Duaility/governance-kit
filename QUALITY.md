# Quality Log

Tracks bugs, issues, and quality observations discovered in this repo. An entry lives here whether it's fixed in the same PR or not — the log is the audit trail. When an issue is fixed, move it from **Open** to **Resolved** and link the commit or PR that closed it.

Entry format:

```
- YYYY-MM-DD — <short title>. <one-or-two-sentence description>. <optional: reproduction / link>.
```

## Open

- 2026-04-22 — `no-broken-internal-doc-links` linter doesn't skip markdown inline-code spans. A bracket-paren link example inside backticks is treated as a real link, forcing prose rewrites whenever docs want to show link syntax. Fix: teach `.governance/rules/no-broken-internal-doc-links.sh` (and the shipped asset copy in `governance-bootstrap/assets/dot-governance/rules/`) to strip inline-code spans before extracting links.

## Resolved

- 2026-04-22 — Local git hooks were not enforced by a rule. `CONSTITUTION.md` named the pre-commit and `commit-msg` hooks as part of the enforcement layering, but nothing verified they were installed on a contributor's clone — a fresh clone landed with zero local enforcement until someone re-ran bootstrap. Fixed: hook scripts moved to tracked `.githooks/` and the new `hooks-configured` rule asserts `core.hooksPath=.githooks` plus tracked + executable hook files. Bootstrap skill updated to ship hooks under `.githooks/` going forward.
- 2026-04-22 — `governance-bootstrap/assets/governance.yml` shipped without a `permissions:` block, so the workflow template the skill installs failed the `workflows-hardened` rule the same skill installs. Patched in PR [#2](https://github.com/Duaility/governance-kit/pull/2) — both the asset and the local copy now declare `permissions: contents: read`.
- 2026-04-22 — `governance-bootstrap/references/RULES_CATALOG.md:29` described `no-broken-internal-doc-links` using a bracket-paren link example inside inline code, which the linter read as a literal broken link. Reworded the prose in PR [#2](https://github.com/Duaility/governance-kit/pull/2) to avoid the parenthetical pattern. The underlying linter gap is logged above as an open issue.
