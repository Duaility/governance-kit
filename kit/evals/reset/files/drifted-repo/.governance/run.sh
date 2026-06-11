#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fail=0
while IFS= read -r -d '' check; do
  bash "$check" || fail=1
done < <(find "$SCRIPT_DIR/packs" -mindepth 5 -maxdepth 5 -name check.sh -print0)
exit $fail
