#!/usr/bin/env bash
# Rule: No obvious secrets (keys, tokens, private keys) in tracked files.
# This is a heuristic net — it will not catch everything. Pair it with a real
# scanner (gitleaks, trufflehog) in CI for defense in depth.
set -u
source "$(dirname "$0")/../lib.sh"
rule_start "no-secrets"
require_git

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT" || exit 1

# Patterns intentionally conservative to limit false positives.
# Each pattern: "<label>|<regex>"
patterns=(
    "AWS access key|AKIA[0-9A-Z]{16}"
    "AWS secret key|aws_secret_access_key[[:space:]]*=[[:space:]]*['\"]?[A-Za-z0-9/+=]{40}"
    "GCP service account|-----BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----"
    "GitHub token|gh[pousr]_[A-Za-z0-9]{36,}"
    "Slack token|xox[baprs]-[A-Za-z0-9-]{10,}"
    "Generic API key|api[_-]?key[[:space:]]*[:=][[:space:]]*['\"][A-Za-z0-9]{32,}['\"]"
    "Stripe live key|sk_live_[A-Za-z0-9]{24,}"
)

# Exclude binaries, the rule file itself (contains regexes), the constitution,
# and common lock files which sometimes contain base64 blobs.
excludes=(
    ":!tests/governance/rules/no-secrets.sh"
    ":!CONSTITUTION.md"
    ":!governance-bootstrap/assets/packs/*/evals/**"
    ":!*.lock"
    ":!*.lockfile"
    ":!package-lock.json"
    ":!yarn.lock"
    ":!pnpm-lock.yaml"
    ":!Cargo.lock"
    ":!poetry.lock"
    ":!Pipfile.lock"
    ":!go.sum"
)

for entry in "${patterns[@]}"; do
    label="${entry%%|*}"
    pattern="${entry#*|}"
    while IFS=: read -r file line_no _; do
        [[ -z "$file" ]] && continue
        has_waiver "$file" "$line_no" "no-secrets" && continue
        violation "$file:$line_no — possible $label"
    done < <(git grep -InE "$pattern" -- "${excludes[@]}" 2>/dev/null || true)
done

rule_end
