#!/usr/bin/env bash
# DRIFT: this check.sh has been edited locally — a contributor added an extra
# extension that the pristine kit-bundled version does not include. Reset must
# overwrite this file with the pristine source.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../../../../lib.sh"
directive_start "secrets-hygiene"
require_git
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  # DRIFT: extra `local-secrets` extension added below the canonical list
  if [[ "$f" =~ \.(pem|key|p12|env|local-secrets)$ ]]; then
    violation "$f — credential-like file in tracked tree"
  fi
done < <(git ls-files)
directive_end
