#!/usr/bin/env bash
# Hand-authored team policy. No upstream — reset preserves this by default.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../../../../lib.sh"
directive_start "team-policy"
directive_end
