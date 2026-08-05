#!/usr/bin/env bash
# Agent token accounting — the resolve heartbeat (issue #355).
#
# Measurement at rest: right after a commit lands, ask each known session's
# adapter what the harness now says that session has cost, and append whatever
# comes back to the kit-owned snapshot sidecar. The next commit's pre-commit
# fold copies it into the receipt row.
#
# Silent and unconditionally successful. Nothing here may ever affect whether a
# commit or a push succeeds — that is the entire point of moving measurement
# off the commit path. A harness with no adapter, no readable surface, or a
# broken adapter simply contributes nothing and the row stays honestly
# unresolved.

set -u

if [[ "${SKIP_GOVERNANCE:-0}" == "1" ]]; then
    exit 0
fi

HERE="$(cd "$(dirname "$0")" && pwd)" || exit 0
RULE_DIR="$(cd "$HERE/.." && pwd)" || exit 0
LIB="$RULE_DIR/lib"

{
    GOV_LIB="$RULE_DIR/../../../../../lib.sh"
    if [[ -f "$GOV_LIB" ]]; then
        # shellcheck disable=SC1090
        source "$GOV_LIB"
    fi
    # shellcheck disable=SC1090
    source "$LIB/receipt.sh"
    # shellcheck disable=SC1090
    source "$LIB/costs.sh"
    # shellcheck disable=SC1090
    source "$LIB/runtime.sh"
    # shellcheck disable=SC1090
    source "$LIB/resolve.sh"
    resolve_sweep
} >/dev/null 2>&1 || true

exit 0
