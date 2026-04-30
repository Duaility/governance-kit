#!/usr/bin/env bash
# governance-kit:builtin secrets-hygiene
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../../../../lib.sh"
directive_start "secrets-hygiene"
require_git
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  if [[ "$f" =~ \.(pem|key|p12|env)$ ]]; then
    violation "$f — credential-like file in tracked tree"
  fi
done < <(git ls-files)
directive_end
