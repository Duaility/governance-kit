---
name: governance-gardener
description: Walks the repo's governance surface and produces a Governance Health Report — a dated markdown file that flags misalignment between CONSTITUTION.md, the code, and git history. Three axes — Alignment (rules vs. code — blind spots, invisible norms, doc drift), Friction (rules vs. history — dead rules, escape-hatch usage, recurring fixes), Consistency (governance vs. governance — three-legged drift, orphans, hedge language). The report is the product; follow-up actions (doc stamp bumps, drafted doc updates) are opt-in after review. Never auto-amends the constitution. Pairs with governance-bootstrap (which seeds rules) and governance-amend (which edits them). Use when the user says "garden the governance", "governance health check", "run the gardener", "check for blind spots", "find dead rules", or when debugging why the governance tooling feels noisy or out of date. Also designed for /loop or a scheduled task.
license: MIT
metadata:
  author: governance-kit
  version: "0.1"
  companion-of: governance-bootstrap, governance-amend
---

# governance-gardener

`governance-bootstrap` seeds the rules. `governance-amend` edits them. This skill **tends them** — periodically walking the governance surface, comparing the artifacts against reality, and producing a report of what a human should act on.

## The one artifact

Every run produces a single markdown file: `governance-health/YYYY-MM-DD.md`. That is the product. PRs and amendments are optional follow-ups the user triggers *after* reading the report.

This matters. Anchoring on "open PRs" narrows the skill to doc-drift-shaped problems. Anchoring on "produce a health report" lets blind spots, dead rules, escape-hatch friction, and doc drift sit on equal footing, with equal accountability to evidence.

## What the report covers

Three axes. Each axis compares governance artifacts against a different source of truth.

| Axis | Compared against | What it catches |
|---|---|---|
| **Alignment** | the code itself | Rules the code doesn't actually follow (aspirational), norms the code follows that aren't named (invisible), docs that describe an older version of the code (drift). |
| **Friction** | git history | Rules the team works around (escape-hatch clusters), rules nothing ever trips (dead), the same class of mistake fixed repeatedly (missing rule), reverts on one path (missing guardrail). |
| **Consistency** | governance itself | Three-legged drift (rule↔test↔log), orphans in `freshness.conf`, hedge language in Invariants, redundant rules. |

Full signal catalog with thresholds and evidence requirements: [references/SIGNAL_CATALOG.md](references/SIGNAL_CATALOG.md).

## Activation flow

### Step 1 — Preflight

From the repo root:

1. Confirm this is a git repo (`git rev-parse --show-toplevel`). If not, stop.
2. Confirm the working tree is clean. If dirty, stop and tell the user to commit or stash — the gardener writes a report file and optionally opens branches, and must not entangle its output with unrelated work.
3. Confirm `CONSTITUTION.md` and `tests/governance/` exist. If not, suggest running `governance-bootstrap` first and exit.
4. Note prior runs: `ls governance-health/*.md 2>/dev/null`. The most recent one, if any, feeds the **Trend** section.

Tunables (env vars, all optional):
- `GARDENER_WINDOW_DAYS` — history window for Friction signals. Default 180.
- `GARDENER_FRESHNESS_DAYS` — doc staleness window. Default 90 (matches the `doc-freshness` rule).
- `GARDENER_MIN_EVIDENCE` — minimum evidence count for a Friction finding to surface. Default 3.

### Step 2 — Load the governance model

Parse these once; every axis reuses them:

- **Invariants** — scrape `CONSTITUTION.md` for `### <rule-name>` subsections under `## Invariants`. For each, capture: rule text, rationale, "Enforced by" path, exceptions.
- **Tests** — list `tests/governance/rules/*.sh`.
- **Evolution Log** — parse `## Evolution Log` entries (date, author, summary, linked PR if present).
- **Freshness config** — `tests/governance/freshness.conf` if present.
- **Tracked doc set** — the baseline globs + freshness.conf (see [references/WATCH_ANNOTATIONS.md](references/WATCH_ANNOTATIONS.md) for the baseline).

### Step 3 — Walk the three axes

Run each signal. Collect findings as structured records: `{axis, signal, severity, title, evidence, suggested_action}`. Severity is `info | watch | action`.

**Alignment signals** — see SIGNAL_CATALOG.md §Alignment:
- `A1` Aspirational rule — Invariants row with no matching test script on disk.
- `A2` Invisible norm — pattern present in ≥80% of applicable files with no rule naming it. Opt-in only; runs when `GARDENER_NORM_SCAN=1` (noisy otherwise).
- `A3` Doc drift — tracked doc whose `last-verified` has expired AND watched paths have changed since the stamp.
- `A4` Bump-eligible — tracked doc whose `last-verified` has expired but watched paths are unchanged (low-risk follow-up available).

**Friction signals** — SIGNAL_CATALOG.md §Friction:
- `F1` Escape-hatch cluster — commits using `--no-verify` or `SKIP_GOVERNANCE=1` in the window. Groups by affected rule when inferable.
- `F2` Dead rule — rule test whose watched paths haven't changed in ≥2× the window AND whose test script hasn't been edited since the rule was added.
- `F3` Recurring-fix cluster — commit-subject clusters (`fix style`, `fix typo`, `fix lint`) with ≥ `MIN_EVIDENCE` occurrences not covered by an existing rule.
- `F4` Revert cluster — `git log --grep=^Revert` with ≥2 hits on the same path.

**Consistency signals** — SIGNAL_CATALOG.md §Consistency:
- `C1` Rule without test — an Invariants entry names a test that doesn't exist.
- `C2` Test without rule — a `rules/*.sh` script not mentioned in any Invariants entry.
- `C3` Evolution-log drift — a log entry whose commit touched neither `CONSTITUTION.md` nor `tests/governance/`.
- `C4` Orphaned freshness entry — a path in `freshness.conf` that doesn't exist on disk.
- `C5` Hedge language — an Invariants **Rule** line containing `should`, `generally`, `usually`, `typically`, `try to`. Invariants are hard rules; hedges belong in Principles.
- `C6` Redundant rule — two rule scripts whose `grep`/`awk` patterns overlap by ≥80%. Flag for dedup.

### Step 4 — Render the report

Write to `governance-health/YYYY-MM-DD.md` using [assets/health-report.template.md](assets/health-report.template.md). Sections:

1. **Summary** — traffic-light table per axis with the worst signal called out.
2. **Alignment / Friction / Consistency** — one section per axis, findings grouped by severity. Every finding names: signal ID, title, evidence (commit SHAs, file paths with line numbers, counts), suggested action, confidence.
3. **Actionable queue** — the short list of things the user can do right now. Each item is a shell command or a pointer to another skill:
   - `governance-gardener --bump-stamps` (low-risk, batched PR).
   - `governance-gardener --draft-doc-updates` (draft PRs per doc).
   - `governance-amend <rule-name>` (for each rule-shaped candidate).
4. **Trend** — diff against the previous report (counts only: +2 Friction findings, -1 Consistency, etc.). Skip if no prior run exists.

The report file carries `<!-- governance: allow-plan-captured -->` at the top so it doesn't trip the `plan-captured` rule — it's a report, not a plan.

If the same finding shows up run after run and nobody acts on it, the Trend section will make that visible. That's the whole reason for writing a file instead of streaming to stdout.

### Step 5 — Offer follow-up actions

After writing the report, use `AskUserQuestion` to ask:

```
Report written to governance-health/<date>.md. What next?
  (1) Open the bump-stamps PR (low risk, batched)
  (2) Draft doc-update PRs (one per drifted doc, opened as draft)
  (3) Both (1) and (2)
  (4) Nothing — I'll review the report first (default)
```

Default is **(4)** on the first run in a session: the user should see the report before the skill starts opening PRs. Autonomous invocations (`/loop`, scheduled tasks) also default to (4) — they produce the report and exit.

If the user picks an action, delegate to the follow-up flows in [references/FOLLOWUP_ACTIONS.md](references/FOLLOWUP_ACTIONS.md). The gardener never auto-amends `CONSTITUTION.md` or `tests/governance/rules/` — rule-shaped candidates always hand off to `governance-amend`.

### Step 6 — Exit cleanly

Print a one-screen summary:
- Path to the report.
- Count of findings by axis and severity.
- The follow-up the user chose (if any) and the PR URLs it produced.
- What to run next: `governance-amend <name>` for each action-severity rule candidate.

Do not loop or recurse.

## Key design rules

- **The report is the product.** Every side effect (PR, branch, issue) is optional and opt-in. A successful run that opens zero PRs is still a successful run.
- **Every finding carries evidence.** Commit SHAs, file paths with line numbers, occurrence counts. A finding without evidence is a guess — drop it or mark its confidence as `low`.
- **Never auto-amend.** The gardener does not edit `CONSTITUTION.md` or write new rule scripts. Candidates are proposed; `governance-amend` does the editing.
- **Never auto-merge.** Even the low-risk bump-stamps PR requires a human click.
- **Refuse to run on a dirty tree.** The skill writes a report file and (if the user opts in) creates branches. Mixing with unrelated user work is never right.
- **Confidence is mandatory.** Every finding is tagged `high | medium | low`. Readers calibrate their attention by it; hiding uncertainty wastes the reviewer's time.
- **Diffable across runs.** Report files stay in `governance-health/`. Run N+1 can compare against run N. If you move or rewrite old reports, you lose the trend signal.

## When NOT to use this skill

- **Initial scaffolding.** Use `governance-bootstrap` first; the gardener has nothing to garden on an ungoverned repo.
- **Adding a specific rule you already know you want.** Use `governance-amend` directly. The gardener is for *discovering* candidates, not executing them.
- **Enforcement.** The governance suite (`tests/governance/run.sh`) enforces rules; the gardener reports on their health. They're complementary, not overlapping.

## References

- [references/SIGNAL_CATALOG.md](references/SIGNAL_CATALOG.md) — every signal, its threshold, and what evidence it requires.
- [references/WATCH_ANNOTATIONS.md](references/WATCH_ANNOTATIONS.md) — the `<!-- gardener-watches: ... -->` annotation format for doc-drift detection.
- [references/FOLLOWUP_ACTIONS.md](references/FOLLOWUP_ACTIONS.md) — how `--bump-stamps` and `--draft-doc-updates` are executed after the user opts in.
- [assets/health-report.template.md](assets/health-report.template.md) — the report skeleton.
- [assets/stamp-bump-pr.template.md](assets/stamp-bump-pr.template.md) — PR body for the batched bump-stamps follow-up.
- [assets/doc-update-pr.template.md](assets/doc-update-pr.template.md) — PR body for a single drafted doc-update follow-up.
