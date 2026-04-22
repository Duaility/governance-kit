# Signal catalog

Every signal the `governance-gardener` emits. Each one specifies *what it checks*, *what evidence it must produce*, and *what threshold gates it*. Findings without evidence are dropped; findings below threshold are dropped. The point of the thresholds is to keep the report trustworthy — if the gardener cries wolf once, the next report gets ignored.

Severity levels:

- **`info`** — worth knowing, probably no action.
- **`watch`** — looks like a pattern; revisit if it recurs.
- **`action`** — evidence is strong enough to act on now.

Confidence levels (independent of severity):

- **`high`** — the signal is structural (file exists / doesn't, path changed / didn't).
- **`medium`** — the signal is statistical (cluster size crossed threshold).
- **`low`** — the signal is heuristic (pattern-match on naming or commit subjects).

Stability levels:

- **`stable`** — deterministic enough to trust as a default report signal.
- **`experimental`** — useful, but more inference-heavy; include only with clear evidence.
- **`opt-in`** — noisy enough that it should run only when explicitly enabled.

---

## §Alignment — governance vs. code

### A1 · Aspirational rule

**Checks:** every `### <rule-name>` under `## Invariants` in `CONSTITUTION.md` names an "Enforced by:" path. For each, confirm the path exists.

**Evidence:** rule name, line number in `CONSTITUTION.md`, missing path.

**Threshold:** none — one missing test is enough.

**Severity:** `action`. **Confidence:** `high`. **Stability:** `stable`.

---

### A2 · Invisible norm

**Checks:** patterns consistently present in the codebase but not named by any rule. Opt-in — only runs when `GARDENER_NORM_SCAN=1`, because the false-positive cost is high.

Built-in patterns scanned (extend in `references/NORM_PATTERNS.md` if you add more):

- Every bash script under `tests/` starts with `set -euo pipefail`.
- Every `rules/*.sh` sources `lib.sh` on the second non-comment line.
- Every markdown file under `docs/` ends with a single trailing newline.
- Every Python file opens with `from __future__ import annotations`.

**Evidence:** pattern name, match rate (e.g., "12/12 = 100%"), example file paths (up to 3).

**Threshold:** ≥80% match rate AND ≥5 files in the sample AND no existing Invariants rule mentions the pattern.

**Severity:** `watch`. **Confidence:** `medium`. **Stability:** `opt-in`.

---

### A3 · Doc drift

**Checks:** for each tracked doc with a `<!-- last-verified: YYYY-MM-DD -->` stamp older than `GARDENER_FRESHNESS_DAYS` (default 90), run `git log --since=<stamp> -- <watch-paths>`. If the log has commits, the watched code drifted since the stamp.

Watch-set resolution order is canonicalized in [WATCH_SCOPES.md](WATCH_SCOPES.md). Use explicit annotations when possible.

**Evidence:** doc path, stamp date, list of commit SHAs on watched paths.

**Threshold:** ≥1 commit on a watched path since the stamp.

**Severity:** `action`. **Confidence:** `high` if explicit annotation, `medium` if inferred. **Stability:** `stable`.

---

### A4 · Bump-eligible

**Checks:** same as A3, but the `git log` returned empty — the stamp is stale in time but the watched code hasn't moved, so the doc is still accurate.

**Evidence:** doc path, stamp date, days old.

**Threshold:** stamp age > `GARDENER_FRESHNESS_DAYS` AND watched-path log is empty.

**Severity:** `info` (follow-up available). **Confidence:** `high`. **Stability:** `stable`.

---

## §Friction — governance vs. history

### F1 · Escape-hatch cluster

**Checks:** commits in the last `GARDENER_WINDOW_DAYS` days that bypassed governance. Two sources:

- Commits with `SKIP_GOVERNANCE=1` in the reflog / author note / commit trailer (if surfaced by the user's workflow).
- Commits that `--no-verify` is inferable from: CI run for that commit's PR ran governance and failed, but the commit was merged anyway. (Requires `gh` + CI logs; otherwise skip.)

Group by the rule that would have fired only when the evidence is direct. If grouping isn't inferable, emit one repo-level cluster titled "unknown rule" and lower confidence.

**Evidence:** list of commit SHAs, grouped by rule. Count per group.

**Threshold:** ≥ `GARDENER_MIN_EVIDENCE` (default 3) per cluster.

**Severity:** `watch` at 3–5, `action` at >5 in a single cluster.

**Confidence:** `high` when grouping is known, `medium` when it's unknown. **Stability:** `experimental`.

**Interpretation:** a loud F1 cluster usually means a rule is wrong, not that the team is undisciplined. Investigate the rule before investigating the people.

---

### F2 · Dead rule

**Checks:** for each `tests/governance/rules/*.sh`:

1. Determine its watched scope using [WATCH_SCOPES.md](WATCH_SCOPES.md).
2. Run `git log --since=<2× window>` on those paths.
3. Run `git log -- <test-script-path>` to see when the test was last edited.

A rule is *dead* if its watched scope has had no activity in 2× the window AND the test script itself hasn't been edited since the rule was added (i.e., it's frozen). If no credible watched scope can be resolved, skip this signal for that rule.

**Evidence:** rule name, last activity date on watched paths, last edit date of the test script.

**Threshold:** watched-path quiet period ≥ 2× `GARDENER_WINDOW_DAYS`.

**Severity:** `watch`. **Confidence:** `low` — dead rules might be dormant, not dead; surface them for human judgment, don't recommend deletion automatically. **Stability:** `experimental`.

---

### F3 · Recurring-fix cluster

**Checks:** parse commit subjects in the window. Cluster by stemmed tokens after the conventional-commit prefix:

- `fix: style <thing>` → cluster "fix style"
- `fix(typo): <x>` → cluster "fix typo"
- `fix: lint warnings in <x>` → cluster "fix lint"
- `chore: formatting pass` → cluster "formatting"

Drop clusters that match an existing Invariants rule (e.g., "fix conventional-commit subject" wouldn't surface because `conventional-commits` already enforces it).

**Evidence:** cluster label, list of commit SHAs, count.

**Threshold:** ≥ `GARDENER_MIN_EVIDENCE` commits per cluster.

**Severity:** `watch`. **Confidence:** `medium`. **Stability:** `experimental`.

**Interpretation:** a recurring-fix cluster usually means either (a) a rule is missing or (b) automation is missing. Both are valid amendments — either a new `tests/governance/rules/<name>.sh` or a pre-commit formatter/linter.

---

### F4 · Revert cluster

**Checks:** `git log --grep=^Revert --since=<window>` and group by the paths touched in each revert.

**Evidence:** path, list of reverted commit SHAs.

**Threshold:** ≥2 reverts on the same path.

**Severity:** `watch`. **Confidence:** `high`. **Stability:** `stable`.

**Interpretation:** the path is unstable. Could be a missing test, a missing rule, or a deeper design issue. Not necessarily a governance amendment — sometimes the right fix is in the code, not the rules.

---

## §Consistency — governance vs. governance

These are mechanical lints. They have no thresholds — any violation is surfaced.

### C1 · Rule without test

**Checks:** every `### <rule-name>` under `## Invariants` names an "Enforced by:" path. Confirm the path is in `tests/governance/rules/` and exists.

**Evidence:** rule name, line number, expected path.

**Severity:** `action`. **Confidence:** `high`. **Stability:** `stable`.

Overlaps with A1 — A1 is the symptom ("your rule is aspirational"), C1 is the lint ("the three-legged invariant broke"). Same evidence, surfaced under both axes because the reader looking for alignment issues and the reader looking for consistency issues are different.

---

### C2 · Test without rule

**Checks:** for each `tests/governance/rules/*.sh`, grep `CONSTITUTION.md` for a mention of the script name or the rule name derived from the script filename.

**Evidence:** script path, derived rule name.

**Severity:** `action`. **Confidence:** `high`. **Stability:** `stable`.

---

### C3 · Evolution-log drift

**Checks:** parse `## Evolution Log` entries. For each entry that references a PR (`#<n>`) or commit SHA:

- Look up the commit(s) that introduced the change.
- Confirm the commit touched **both** `CONSTITUTION.md` and at least one file under `tests/governance/`.

Entries that don't reference a PR or SHA are skipped (can't verify).

**Evidence:** log line, referenced commit SHA, files touched.

**Severity:** `watch`. **Confidence:** `high`. **Stability:** `stable`.

---

### C4 · Orphaned freshness entry

**Checks:** every path in `tests/governance/freshness.conf` exists on disk.

**Evidence:** missing path, line number in the config.

**Severity:** `action`. **Confidence:** `high`. **Stability:** `stable`.

---

### C5 · Hedge language in Invariants

**Checks:** for every `### <rule-name>` under `## Invariants`, scan the `- **Rule**:` line for hedge tokens: `should`, `generally`, `usually`, `typically`, `try to`, `mostly`, `when possible`.

Exception: the word "should" is allowed when followed directly by "not" or "never" (hard prohibitions, not hedges).

**Evidence:** rule name, line number, matched token.

**Severity:** `watch`. **Confidence:** `high`. **Stability:** `stable`.

---

### C6 · Redundant rule

**Checks:** pairwise comparison of rule scripts. For each pair, count the overlap of grep patterns, file globs, and path literals. If ≥80% of one script's distinctive tokens appear in the other, flag the pair.

**Evidence:** both rule names, overlap ratio, shared tokens (top 5).

**Severity:** `watch`. **Confidence:** `low` — pattern overlap is not the same as semantic overlap; this is a starting point for human review. **Stability:** `experimental`.

---

## Adding a new signal

1. Pick an axis (or argue for a new one in a plan file first).
2. Define the check, the evidence it must produce, and the threshold.
3. Add a section to this catalog using the same shape.
4. Add a section to `assets/health-report.template.md`.
5. Implement the check in the skill's activation flow.
6. If the signal needs tunables, add an env var prefixed `GARDENER_`.

Every signal must answer *what would make me drop this finding from the report?* If the answer is "nothing, I always want to see it," the signal has no threshold and produces noise. Tighten it or move it to `info` severity.
