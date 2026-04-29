#!/usr/bin/env bash
set -u
EVAL_ID="agent-token-accounting"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../../.." && pwd)"
source "$ROOT/governance/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/extensions/packs/agent-governance"
CHECK=".governance/packs/duaility/agent-governance/directives/$EVAL_ID/check.sh"

command -v python3 >/dev/null 2>&1 || {
    echo "    ⊘ skipped — python3 not available"
    exit 0
}

fixture_init
# install_directive copies the whole directive folder — lib/ (ledger, trailers, rates),
# hooks/ (pre-commit side effects + prepare-commit-msg stamping) and
# runtimes/ come with it. Nothing lives outside the directive folder.
