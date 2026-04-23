#!/usr/bin/env bash
# Rule: .env.example lists every key present in a local .env (if one exists).
# Keeps the reference file in sync so new contributors know what env vars they need.
# .env itself is assumed to be gitignored — this rule is a no-op when no local .env exists.
set -u
source "$(dirname "$0")/../../lib.sh"
rule_start "env-example-current"
require_git

ROOT="$(git rev-parse --show-toplevel)"
ENV_FILE="$ROOT/.env"
EXAMPLE_FILE="$ROOT/.env.example"

if [[ ! -f "$ENV_FILE" ]]; then
    # No local .env; nothing to compare against. This is the expected state in CI.
    rule_end
fi

if [[ ! -f "$EXAMPLE_FILE" ]]; then
    violation ".env exists but .env.example is missing"
    rule_end
fi

# Extract keys (left side of `=`), ignore blank lines and comments.
extract_keys() {
    grep -vE '^[[:space:]]*(#|$)' "$1" | sed -E 's/^[[:space:]]*export[[:space:]]+//' \
        | awk -F= '{print $1}' | sed 's/[[:space:]]*$//' | sort -u
}

env_keys=$(extract_keys "$ENV_FILE")
example_keys=$(extract_keys "$EXAMPLE_FILE")

while IFS= read -r key; do
    [[ -z "$key" ]] && continue
    if ! grep -qxF "$key" <<<"$example_keys"; then
        violation ".env has key '$key' but .env.example does not"
    fi
done <<<"$env_keys"

rule_end
