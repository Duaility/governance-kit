# Writing good governance rules

The constitution is only as strong as the rules inside it. A bad rule — one that fires noisily, catches nothing real, or can't be reasoned about — gets waived, disabled, or quietly removed. Here are the patterns to aim for and the anti-patterns to avoid.

## Aim for

**Deterministic.** Given the same repo state, the rule produces the same verdict every time. No network calls, no clock-dependent logic (except freshness rules that are *intentionally* clock-dependent), no parallelism races.

**Fast.** Every rule runs on every commit. A slow rule will be the reason someone adds `SKIP_GOVERNANCE=1` to their muscle memory. Target under a second. If a rule is unavoidably slow (dependency scan, type check), run it in CI only — not the pre-commit hook.

**Specific.** When a rule fires, the message must tell the developer *what* failed, *where*, and *why*. `"✗ bad code"` is worthless. `"src/auth/session.py:47 — pdb import left in source"` tells the developer exactly what to do.

**Minimal scope.** One rule, one concern. `no-secrets` scans for secrets. `dotenv-gitignored` checks `.env` handling. Do not combine them. A fused rule's failure is ambiguous.

**Waivable when warranted.** If legitimate exceptions exist, support the `governance: allow-<rule>` comment waiver. If the rule is genuinely absolute (no secrets, ever), say so explicitly in the rationale and skip the waiver logic.

## Avoid

**Stylistic opinions dressed as governance.** Indent style, quote style, import ordering — these belong in a formatter (prettier, black, gofmt), not a governance rule. Mixing format preferences into the constitution erodes the authority of the real invariants.

**Rules without rationale.** "We just always do it this way" is not a reason. Any rule added without a named incident, policy, or constraint gets deleted the first time it's inconvenient.

**Rules that lie.** A check that claims to enforce X but actually enforces a weak proxy for X is worse than no check — it creates false confidence. If you can only enforce an approximation, say so in the rationale, and name the gap.

**Checks that double as documentation.** If a rule's failure message is "see docs/SECURITY.md for why this matters", fine — but the message must *first* say what's wrong and where. Never make the developer read documentation to understand which line failed.

**Non-idempotent logic.** A rule that modifies the repo while checking is a bug. Governance reads; remediation writes. Keep them separate. (If the rule needs writable scratch space, use `mktemp -d`.)

**Reaching across the network.** Network calls from a pre-commit hook mean a flaky hook, which means developers skip it, which means governance runs only in CI, which means it doesn't block broken code locally. If you need a remote check (e.g., CVE database), run it in CI only.

## Patterns by rule class

### Existence / content checks (`*-exists`)

- Check at the repo root, or in a small known set of locations (`X.md`, `docs/X.md`, `.github/X.md`).
- Validate a minimum size or a minimum content signal (e.g., "contains an email address").
- Fail fast on the first missing condition — no reason to keep checking if the file is absent.

### Pattern-scan checks (`no-*`)

- Use `git grep` (not raw `grep`) so `.gitignore` is respected.
- Exclude the rule file itself from its own scan (common foot-gun).
- Support `has_waiver` per-line for false-positive escape.
- Anchor patterns carefully — `\beval\b` catches `eval(`, `my_eval(`, and `evaluate(`. Make sure that's what you want.

### Metric checks (`*-limit`)

- Expose the limit as an env var override (`GOVERNANCE_<RULE>_LIMIT`). Projects need to tune without forking the script.
- Report the actual value vs. the limit in the violation message. "file X has 612 lines (limit: 500)" is actionable; "file X is too large" isn't.

### Structural checks (`*-hardened`, `*-current`)

- These often have sub-checks. Name each sub-check in the violation message so the developer knows *which* part failed.
- If any sub-check fails, report all of them before exiting — don't bail on the first one. Developers want the full list.

## A concrete anti-pattern

Bad:

```bash
# Rule: code quality is good
while read f; do
    # if file is ugly, fail
    grep -q "bad" "$f" && violation "bad code"
done < <(ls)
```

Wrong on five axes: no rationale, non-specific rule statement, uses `ls` (includes gitignored files and directories), violation message has no location, pattern is meaningless.

Good:

```bash
#!/usr/bin/env bash
# Rule: no `pdb.set_trace()` left in tracked Python source.
# Rationale: pdb breakpoints committed to prod caused INC-2041 — the service
# stalled on every request waiting for a stdin that didn't exist.
set -u
source "$(dirname "$0")/../lib.sh"
rule_start "no-pdb-breakpoints"
require_git

while IFS=: read -r file line_no match; do
    [[ -z "$file" ]] && continue
    [[ "$file" == tests/* ]] && continue
    has_waiver "$file" "$line_no" "no-pdb-breakpoints" && continue
    violation "$file:$line_no — pdb breakpoint: ${match:0:80}"
done < <(git grep -nE 'pdb\.set_trace\(\)|breakpoint\(\)' -- '*.py' 2>/dev/null || true)

rule_end
```

Named, justified with a specific incident, scoped to the relevant language, excludes tests (where breakpoints during development are fine), supports waivers, shows the developer the exact line.
