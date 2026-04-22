# Quality Log

Tracks bugs, issues, and quality observations discovered in this repo. An entry lives here whether it's fixed in the same PR or not — the log is the audit trail. When an issue is fixed, move it from **Open** to **Resolved** and link the commit or PR that closed it.

Entry format:

```
- YYYY-MM-DD — <short title>. <one-or-two-sentence description>. <optional: reproduction / link>.
```

## Open

- 2026-04-22 — Local git hooks are not enforced by a rule. `CONSTITUTION.md` claims pre-commit and `commit-msg` hooks are part of the enforcement layering (lines 63 and 112), but nothing verifies they're installed on a contributor's clone. Fix planned via a `hooks-configured` rule that moves hooks to `.githooks/` and checks `core.hooksPath` is set — see the active discussion in PR [#2](https://github.com/Duaility/governance-kit/pull/2).
- 2026-04-22 — `no-broken-internal-doc-links` linter doesn't skip markdown inline-code spans. A bracket-paren link example inside backticks is treated as a real link, forcing prose rewrites whenever docs want to show link syntax. Fix: teach `tests/governance/rules/no-broken-internal-doc-links.sh` (and the shipped asset copy in `governance-bootstrap/assets/tests-bash/rules/`) to strip inline-code spans before extracting links.

## Resolved

- 2026-04-22 — `governance-bootstrap/assets/governance.yml` shipped without a `permissions:` block, so the workflow template the skill installs failed the `workflows-hardened` rule the same skill installs. Patched in PR [#2](https://github.com/Duaility/governance-kit/pull/2) — both the asset and the local copy now declare `permissions: contents: read`.
- 2026-04-22 — `governance-bootstrap/references/RULES_CATALOG.md:29` described `no-broken-internal-doc-links` using a bracket-paren link example inside inline code, which the linter read as a literal broken link. Reworded the prose in PR [#2](https://github.com/Duaility/governance-kit/pull/2) to avoid the parenthetical pattern. The underlying linter gap is logged above as an open issue.
