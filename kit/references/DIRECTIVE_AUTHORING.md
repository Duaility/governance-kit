# Writing good governance directives

The constitution is only as strong as the directives inside it. A bad directive — one that fires noisily, catches nothing real, or can't be reasoned about — gets waived, disabled, or quietly removed. Here are the patterns to aim for and the anti-patterns to avoid.

## Aim for

**Deterministic.** Given the same repo state, the directive produces the same verdict every time. No network calls, no clock-dependent logic (except freshness directives that are *intentionally* clock-dependent), no parallelism races.

**Fast.** Every directive runs on every commit. A slow directive will be the reason someone adds `SKIP_GOVERNANCE=1` to their muscle memory. Target under a second. If a directive is unavoidably slow (dependency scan, type check), run it in CI only — not the pre-commit hook.

**Specific.** When a directive fires, the message must tell the developer *what* failed, *where*, and *why*. `"✗ bad code"` is worthless. `"src/auth/session.py:47 — pdb import left in source"` tells the developer exactly what to do.

**Minimal scope.** One directive, one concern. `no-secrets` scans for secrets. `dotenv-gitignored` checks `.env` handling. Do not combine them. A fused directive's failure is ambiguous.

**Waivable when warranted.** If legitimate exceptions exist, support the `governance: allow-<directive>` comment waiver. If the directive is genuinely absolute (no secrets, ever), say so explicitly in the rationale and skip the waiver logic.

## Avoid

**Stylistic opinions dressed as governance.** Indent style, quote style, import ordering — these belong in a formatter (prettier, black, gofmt), not a governance directive. Mixing format preferences into the constitution erodes the authority of the real directives.

**Directives without rationale.** "We just always do it this way" is not a reason. Any directive added without a named incident, policy, or constraint gets deleted the first time it's inconvenient.

**Directives that lie.** A check that claims to enforce X but actually enforces a weak proxy for X is worse than no check — it creates false confidence. If you can only enforce an approximation, say so in the rationale, and name the gap.

**Repo-state checks for change-set obligations.** If the real intent is "every substantive change must do X", a check that only proves "the repo has one X file somewhere" is not governance, it's theater. Prefer inspecting the staged diff in hooks and the branch diff in CI.

**Checks that double as documentation.** If a directive's failure message is "see docs/SECURITY.md for why this matters", fine — but the message must *first* say what's wrong and where. Never make the developer read documentation to understand which line failed.

**Non-idempotent logic.** A directive that modifies the repo while checking is a bug. Governance reads; remediation writes. Keep them separate. (If the directive needs writable scratch space, use `mktemp -d`.)

**Reaching across the network.** Network calls from a pre-commit hook mean a flaky hook, which means developers skip it, which means governance runs only in CI, which means it doesn't block broken code locally. If you need a remote check (e.g., CVE database), run it in CI only.

## Patterns by directive class

### Change-set-aware checks

Use these when the directive is about what must accompany a given substantive change, not just what must exist in the repo.

Good fits:

- every substantive change must update a plan
- code changes affecting auth must update a specific doc or test suite
- changes under a sensitive path must touch an approval or metadata file

Implementation guidance:

- In pre-commit or local runs, inspect `git diff --cached --name-only`.
- In CI or branch validation, inspect the merge-base diff against the default branch.
- Exempt non-substantive paths explicitly, rather than pretending they never happen.
- Report the missing companion artifact and a few example changed files so the failure is obvious.

Bad fit:

- "repo contains at least one plan file" when the real intent is "this change must add or update a plan"
- "QUALITY.md exists" when the real intent is "newly discovered issues must be recorded before merge"

### Existence / content checks (`*-exists`)

- Check at the repo root, or in a small known set of locations (`X.md`, `docs/X.md`, `.github/X.md`).
- Validate a minimum size or a minimum content signal (e.g., "contains an email address").
- Fail fast on the first missing condition — no reason to keep checking if the file is absent.
- Use this class only when repo-level presence is the true policy intent. If the real intent is per-change compliance, do not hide behind an existence check.

### Pattern-scan checks (`no-*`)

- Use `git grep` (not raw `grep`) so `.gitignore` is respected.
- Exclude the directive file itself from its own scan (common foot-gun).
- Support `has_waiver` per-line for false-positive escape.
- Anchor patterns carefully — `\beval\b` catches `eval(`, `my_eval(`, and `evaluate(`. Make sure that's what you want.

### Metric checks (`*-limit`)

- Expose the limit through the per-directive config: read it with `conf_get <id> <KEY> <default>`, which resolves env `GOVERNANCE_<KEY>` first, then a `KEY=value` line in the user overlay `.governance/conf/<id>.conf`, then the default. Ship a commented `KEY=` example in the directive's `config.conf`. Projects need to tune without forking the script.
- Report the actual value vs. the limit in the violation message. "file X has 612 lines (limit: 500)" is actionable; "file X is too large" isn't.

### Configurable list checks

- When a directive enforces a **list** (allowed types, protected paths, integrity rules), ship the defaults in a pack-owned `defaults.conf` and read the effective list with `conf_list <id> "$(dirname "$0")/defaults.conf"`. The user overlay `.governance/conf/<id>.conf` layers on top: a bare line adds, `!<item>` removes a default, so consumers keep receiving improved defaults on `pack update` while still being able to add or drop items. See [PACK_AUTHORING.md](PACK_AUTHORING.md) for the file layout.

### Structural checks (`*-hardened`, `*-current`)

- These often have sub-checks. Name each sub-check in the violation message so the developer knows *which* part failed.
- If any sub-check fails, report all of them before exiting — don't bail on the first one. Developers want the full list.

## A concrete anti-pattern

Bad:

```bash
# Directive: code quality is good
while read f; do
    # if file is ugly, fail
    grep -q "bad" "$f" && violation "bad code"
done < <(ls)
```

Wrong on five axes: no rationale, non-specific directive statement, uses `ls` (includes gitignored files and directories), violation message has no location, pattern is meaningless.

Another common anti-pattern:

Bad directive statement:

> Every substantive change must update `plans/`.

Bad implementation:

```bash
[[ -d plans ]] || violation "plans/ missing"
git ls-files -- 'plans/*.md' | grep -q . || violation "no plan files"
```

Why it's bad: it proves only that the repo once had a plan file. It does not fail the exact thing the directive claims to prevent: a new substantive change landing without a plan update.

Better implementation shape:

```bash
changed_files=()
while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    changed_files+=("$f")
done < <(git diff --cached --name-only --diff-filter=ACMRD -- 2>/dev/null || true)

plan_touched=0
substantive=0
for f in "${changed_files[@]}"; do
    case "$f" in
        plans/*.md) plan_touched=1 ;;
        governance-health/*) ;;
        *) substantive=1 ;;
    esac
done

if [[ $substantive -eq 1 && $plan_touched -eq 0 ]]; then
    violation "substantive change set has no accompanying plan update"
fi
```

Now the check matches the policy claim.

Good:

```bash
#!/usr/bin/env bash
# Directive: no `pdb.set_trace()` left in tracked Python source.
# Rationale: pdb breakpoints committed to prod caused INC-2041 — the service
# stalled on every request waiting for a stdin that didn't exist.
set -u
source "$(dirname "$0")/../lib.sh"
directive_start "no-pdb-breakpoints"
require_git

while IFS=: read -r file line_no match; do
    [[ -z "$file" ]] && continue
    [[ "$file" == tests/* ]] && continue
    has_waiver "$file" "$line_no" "no-pdb-breakpoints" && continue
    violation "$file:$line_no — pdb breakpoint: ${match:0:80}"
done < <(git grep -nE 'pdb\.set_trace\(\)|breakpoint\(\)' -- '*.py' 2>/dev/null || true)

directive_end
```

Named, justified with a specific incident, scoped to the relevant language, excludes tests (where breakpoints during development are fine), supports waivers, shows the developer the exact line.
