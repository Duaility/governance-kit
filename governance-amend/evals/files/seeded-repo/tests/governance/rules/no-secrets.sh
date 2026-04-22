#!/usr/bin/env bash
# Rule: reject committed credentials and private keys.
set -u
source "$(dirname "$0")/../lib.sh"
rule_start "no-secrets"
require_git
while IFS= read -r hit; do
    [[ -z "$hit" ]] && continue
    violation "$hit"
done < <(git ls-files -z | xargs -0 grep -InE 'AKIA[0-9A-Z]{16}|-----BEGIN (RSA |EC )?PRIVATE KEY-----' 2>/dev/null || true)
rule_end
