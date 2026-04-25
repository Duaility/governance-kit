#!/usr/bin/env bash
# Agent steering accounting — prepare-commit-msg hook.
#
# Reads the handoff env file written by hooks/pre-commit.sh and stamps:
#   - Steer-Count: <N>                 — total events recorded on this commit
#   - Steer-Types: tool-denial=2,...   — per-type breakdown (sorted)
#   - Steer-Tiers: structural=3,...    — per-tier breakdown (sorted)
#   - Steer-Key:  steer-...            — one repeated trailer per recorded row
#
# The three summary trailers parallel Token-Total / Cost-USD on the
# agent-token-accounting side: a reviewer skimming `git log` can see the
# steering volume without joining against STEERING.md.
#
# If the handoff file doesn't exist (no events extracted, or pre-commit
# didn't run), this hook is a silent no-op.
#
# Escape hatches:
#   SKIP_GOVERNANCE=1 git commit ...
#   git commit --no-verify

set -u

if [[ "${SKIP_GOVERNANCE:-0}" == "1" ]]; then
    exit 0
fi

MSG_FILE="$1"
COMMIT_SOURCE="${2:-}"

# Skip merges, squashes, and template/edit-on-existing-message paths — the
# commit either inherits trailers from elsewhere or doesn't run pre-commit.
case "$COMMIT_SOURCE" in
    merge|squash|commit) exit 0 ;;
esac

HANDOFF="$(git rev-parse --git-path governance-pending-steering.env)"
[[ -f "$HANDOFF" ]] || exit 0

# shellcheck disable=SC1090
source "$HANDOFF"
rm -f "$HANDOFF"

# Idempotent on amends/retries: skip if any Steer-Count or Steer-Key trailer
# is already stamped. The pre-commit hook always rewrites the handoff with
# the full current key set, so a clean re-stamp would be safe; this guard is
# belt-and-braces against a stale handoff lingering past a failed commit.
if grep -qE '^(Steer-Count|Steer-Key):[[:space:]]' "$MSG_FILE"; then
    exit 0
fi

# Nothing to stamp.
[[ -z "${AGENT_STEERING_KEYS:-}" ]] && exit 0

{
    cat "$MSG_FILE"
    printf '\n'
    printf 'Steer-Count: %s\n' "${AGENT_STEERING_COUNT:-0}"
    printf 'Steer-Types: %s\n' "${AGENT_STEERING_TYPES:-none}"
    printf 'Steer-Tiers: %s\n' "${AGENT_STEERING_TIERS:-none}"
    while IFS= read -r key; do
        [[ -z "$key" ]] && continue
        printf 'Steer-Key: %s\n' "$key"
    done <<<"$AGENT_STEERING_KEYS"
} > "$MSG_FILE.new"
mv "$MSG_FILE.new" "$MSG_FILE"

exit 0
