<!-- governance: allow-plan-validation legacy -->
<!-- governance: allow-plan-per-issue predates-rule -->

# 2026-04-22 — Replace `doc-gardener` with `governance-gardener`

## Goal

Remove the `doc-gardener` skill entirely and introduce a new `governance-gardener` skill built from the ground up around a single product: a **Governance Health Report**.

`doc-gardener` anchored on a narrow failure mode (stale docs) and a narrow output (remediation PRs). That framing made it hard to extend. Re-anchoring on "walk the governance surface and report what you find" lets blind spots, dead rules, escape-hatch friction, three-legged drift, and doc drift all sit as equal-footed findings in one report. The kit then reads as three verbs on one metaphor: **bootstrap** (seed), **amend** (edit), **gardener** (tend).

This is a clean-slate replacement, not a rename. The old skill's code for doc drift survives only where the concept survives — in the `A3` and `A4` signals and in the two follow-up actions (`--bump-stamps`, `--draft-doc-updates`).

## Why a report, not PRs

Anchoring the skill on "open PRs" narrows it to problems that fit that shape. Anchoring on "produce a dated report file" lets:

- Every failure mode sit on equal footing (blind spots can't be a PR; they need human judgment first).
- Trend analysis across runs ("this finding hasn't been acted on in 60 days" — the diff makes it visible).
- Autonomous invocations (`/loop`, scheduled tasks) do something useful without the risk of autonomous PR-opening.
- Follow-up actions (PR-opening) become explicit, opt-in, evidence-checked steps rather than the default.

The report is the product. PRs are optional.

## Scope of this change

**In:**

1. Delete the `doc-gardener/` directory.
2. Delete the obsolete rename plan (`plans/2026-04-22-rename-doc-gardener-to-governance-gardener.md`), which is superseded by this one.
3. Create `governance-gardener/` with: `SKILL.md`, three references (`SIGNAL_CATALOG.md`, `WATCH_ANNOTATIONS.md`, `FOLLOWUP_ACTIONS.md`), and three assets (`health-report.template.md`, `stamp-bump-pr.template.md`, `doc-update-pr.template.md`).
4. Update references in `AGENTS.md`, `README.md`, `governance-bootstrap/SKILL.md`, `governance-bootstrap/assets/freshness.conf`, and the existing compliance plan.
5. Re-run the governance suite to confirm nothing broke.

**Out:**

- Implementing the signals themselves (this PR ships the design and the skill files; the flow inside the skill is activation-time logic, not code to commit).
- Evals for the new skill (follow-up — the old doc-gardener evals don't transfer cleanly, and we want to see how the three-axis report feels in practice before writing eval assertions).
- Changing `governance-bootstrap` or `governance-amend`.
- `CONSTITUTION.md` changes — no rule is being added, modified, or removed, so the cardinal rule doesn't apply.

## The three axes

| Axis | Source of truth | Signals (see SIGNAL_CATALOG.md) |
|---|---|---|
| **Alignment** | the code | A1 aspirational rule · A2 invisible norm · A3 doc drift · A4 bump-eligible |
| **Friction**  | git history | F1 escape-hatch cluster · F2 dead rule · F3 recurring-fix cluster · F4 revert cluster |
| **Consistency** | governance itself | C1 rule without test · C2 test without rule · C3 evolution-log drift · C4 orphaned freshness entry · C5 hedge language · C6 redundant rule |

Every signal carries its own threshold, evidence requirement, and confidence level. Signals that can't produce evidence are dropped; signals below threshold are dropped. This is the discipline that keeps the report trustworthy.

## Steps

1. **Delete `doc-gardener/`** — `git rm -r doc-gardener/`.
2. **Delete the obsolete rename plan** — `rm plans/2026-04-22-rename-doc-gardener-to-governance-gardener.md`.
3. **Create `governance-gardener/SKILL.md`** — activation flow built around Preflight → Load model → Walk three axes → Render report → Offer follow-up actions → Exit.
4. **Create `governance-gardener/references/SIGNAL_CATALOG.md`** — every signal, its check, evidence, threshold, severity, confidence.
5. **Create `governance-gardener/references/WATCH_ANNOTATIONS.md`** — ported from the old `doc-gardener` reference, updated to speak about A3/A4 rather than "bump-only / needs-update".
6. **Create `governance-gardener/references/FOLLOWUP_ACTIONS.md`** — documents `--bump-stamps` and `--draft-doc-updates` as opt-in follow-ups that read the most recent report.
7. **Create the three assets** — `health-report.template.md` (the report skeleton), `stamp-bump-pr.template.md`, `doc-update-pr.template.md`.
8. **Update `AGENTS.md`** — skill table, directory layout, symlink instructions.
9. **Update `README.md`** — skill list.
10. **Update `governance-bootstrap/SKILL.md` and `governance-bootstrap/assets/freshness.conf`** — the `doc-freshness` rule's companion skill reference, plus the config header comment.
11. **Update `plans/2026-04-22-add-compliance-directive.md`** — drop the old skill name from two incidental references.
12. **Run `bash tests/governance/run.sh`** — all 12 rules should still pass. The health report file under `governance-health/` (once the gardener writes one) carries `<!-- governance: allow-plan-captured -->` so it doesn't trip `plan-captured`.
13. **Commit as a single `refactor(skills): replace doc-gardener with governance-gardener`.**

## Design rules the new skill must honor

- The **report is the product**. Every side effect is optional and opt-in.
- Every finding carries evidence: commit SHAs, file paths with line numbers, counts.
- **Never auto-amend** — rule-shaped candidates hand off to `governance-amend`.
- **Never auto-merge** — even bump-stamp PRs need a human click.
- **Refuse to run on a dirty tree.**
- **Confidence is mandatory** on every finding (`high | medium | low`).
- Reports stay in `governance-health/` so consecutive runs are diffable — the Trend section depends on this.

## Open questions (non-blocking)

1. **Should `governance-health/` be `.gitignored`?** Arguments for committing: trend analysis works across collaborators; a maintainer can see the last N reports in the repo. Arguments against: report churn inflates the history and may tempt people to edit old reports. Leaning toward committing — the value of a shared trend artifact outweighs the noise, and the `governance: allow-plan-captured` waiver keeps the file from fighting the rule set.
2. **Should the gardener also emit a machine-readable sidecar (`governance-health/YYYY-MM-DD.json`)?** A JSON companion makes trend comparison trivial for scripts; for now, the markdown diff is enough. Defer until a user asks.
3. **Should C1 and A1 be one signal?** They have identical evidence (rule in CONSTITUTION.md, test not on disk). Kept separate because the *reader* of the Alignment section and the reader of the Consistency section are doing different jobs. Same evidence, different frame.
4. **Evals.** The old doc-gardener evals tested bump-only vs. needs-update PR shape. The new skill's primary artifact is a markdown report — eval assertions are string-patterns on the report contents. Defer until we've run the skill against a real repo and calibrated thresholds.

## Notes

- The "self-reflection" framing that prompted this lives in Axis 1 (A1, A2) and Axis 2 (F1–F4). Naming it "self-reflection" invites a vibes-y, LLM-heavy implementation; the three-axis catalog keeps every candidate grounded in evidence.
- Keeping docs, rules, and consistency in one skill (rather than three skills) matters because the gardener metaphor binds them: each axis is *tending the governance surface*, just on a different substrate.
- Nothing here expands mechanical enforcement. Every new signal is advisory. Mechanical rules still come from `governance-bootstrap` at seed time and from `governance-amend` thereafter. The gardener's job is to surface the *candidates* for those two skills to act on.
