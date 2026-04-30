#!/usr/bin/env bash
# DRIFT: a contributor relaxed the naming pattern locally. Reset must restore
# the pristine source pinned at acme/widgets@5f3c0a1b.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../../../../lib.sh"
directive_start "widget-naming"
require_git
# DRIFT: original pattern was `^Widget[A-Z]` — relaxed locally to permit lowercase
while IFS= read -r f; do
  [[ "$f" =~ widgets/.*\.ts$ ]] || continue
  if ! grep -qE '^export class [Ww]idget' "$f" 2>/dev/null; then
    violation "$f — widget filename does not declare a Widget* class"
  fi
done < <(git ls-files)
directive_end
