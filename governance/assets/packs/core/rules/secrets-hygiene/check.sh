#!/usr/bin/env bash
# Rule: secrets-hygiene — no plaintext secret patterns in tracked files and
# `.env` is gitignored / untracked. Rolls up: no-secrets, dotenv-gitignored.
#
# Each sub-check can be opted out of individually:
#     GOVERNANCE_SECRETS_HYGIENE_DISABLE="no-secrets"
# Sub-check keys: no-secrets, dotenv.
set -u
source "$(dirname "$0")/../../lib.sh"
rule_start "secrets-hygiene"
require_git

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT" || exit 1

_DISABLED=",${GOVERNANCE_SECRETS_HYGIENE_DISABLE:-},"
is_enabled() { [[ "$_DISABLED" != *",$1,"* ]]; }

# ── no-secrets ──────────────────────────────────────────────────
if is_enabled no-secrets; then
    _patterns=(
        "AWS access key|AKIA[0-9A-Z]{16}"
        "AWS secret key|aws_secret_access_key[[:space:]]*=[[:space:]]*['\"]?[A-Za-z0-9/+=]{40}"
        "GCP service account|-----BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----"
        "GitHub token|gh[pousr]_[A-Za-z0-9]{36,}"
        "Slack token|xox[baprs]-[A-Za-z0-9-]{10,}"
        "Generic API key|api[_-]?key[[:space:]]*[:=][[:space:]]*['\"][A-Za-z0-9]{32,}['\"]"
        "Stripe live key|sk_live_[A-Za-z0-9]{24,}"
    )
    _excludes=(
        ":!tests/governance/rules/secrets-hygiene/**"
        ":!CONSTITUTION.md"
        ":!governance/assets/packs/*/rules/*/evals/**"
        ":!extensions/packs/*/rules/*/evals/**"
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
    for entry in "${_patterns[@]}"; do
        label="${entry%%|*}"
        pattern="${entry#*|}"
        while IFS=: read -r file line_no _; do
            [[ -z "$file" ]] && continue
            has_waiver "$file" "$line_no" "secrets-hygiene" && continue
            violation "$file:$line_no — possible $label"
        done < <(git grep -InE "$pattern" -- "${_excludes[@]}" 2>/dev/null || true)
    done
fi

# ── dotenv ──────────────────────────────────────────────────────
if is_enabled dotenv; then
    while IFS= read -r tracked; do
        [[ -z "$tracked" ]] && continue
        violation "$tracked is tracked — remove with: git rm --cached $tracked"
    done < <(git ls-files -- '.env' '.env.*' ':!.env.example' ':!.env.sample' ':!.env.template' 2>/dev/null || true)

    if [[ ! -f .gitignore ]]; then
        violation ".gitignore is missing at repo root"
    elif ! git check-ignore -q .env 2>/dev/null; then
        if ! grep -qE '^\.env(\s|$|#)' .gitignore && ! grep -qE '^\*\.env(\s|$|#)' .gitignore; then
            violation ".gitignore does not list .env"
        fi
    fi
fi

rule_end
