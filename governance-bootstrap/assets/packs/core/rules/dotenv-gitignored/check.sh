#!/usr/bin/env bash
# Rule: .env is gitignored and not currently tracked.
# Rationale: The most common path for real secrets to land in a repo. Grep-based
# scanners miss secrets that never match a known pattern; this rule closes the
# door entirely by keeping .env out of git.
set -u
source "$(dirname "$0")/../lib.sh"
rule_start "dotenv-gitignored"
require_git

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT" || exit 1

# Check 1 — .env files must not be tracked.
while IFS= read -r tracked; do
    [[ -z "$tracked" ]] && continue
    violation "$tracked is tracked — remove with: git rm --cached $tracked"
done < <(git ls-files -- '.env' '.env.*' ':!.env.example' ':!.env.sample' ':!.env.template' 2>/dev/null || true)

# Check 2 — .gitignore must cover .env.
if [[ ! -f .gitignore ]]; then
    violation ".gitignore is missing at repo root"
elif ! git check-ignore -q .env 2>/dev/null; then
    # git check-ignore only works if .env is not tracked; fall back to grep if needed.
    if ! grep -qE '^\.env(\s|$|#)' .gitignore && ! grep -qE '^\*\.env(\s|$|#)' .gitignore; then
        violation ".gitignore does not list .env"
    fi
fi

rule_end
