#!/usr/bin/env bash
# CUSTOMIZED — hand-tuned secret patterns for this repo. Do not overwrite.
set -u
source "$(dirname "$0")/../../../lib.sh"
directive_start "no-secrets"
matches=$(git ls-files -z | xargs -0 grep -InE 'AKIA[0-9A-Z]{16}|-----BEGIN (RSA |EC )?PRIVATE KEY-----' 2>/dev/null || true)
[[ -n "$matches" ]] && violation "$matches"
directive_end
