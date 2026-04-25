#!/usr/bin/env bash
# Agent steering accounting — prepare-commit-msg hook.
#
# Reads the handoff env file written by hooks/pre-commit.sh and stamps one
# Steer-Key: trailer per recorded steering row. If the handoff file doesn't
# exist (no events extracted, or pre-commit didn't run), this hook is a
# silent no-op.
#
# Trailer shape:
#
#     Steer-Key: steer-<session-short>-<epoch>-1
#     Steer-Key: steer-<session-short>-<epoch>-2
#
# Multiple trailers per commit by design — git trailers natively support
# repeated keys, and one row per trailer keeps the join trivial.
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

# Idempotent on amends/retries: skip if any Steer-Key trailer is already
# stamped. The pre-commit hook always rewrites the handoff with the full
# current key set, so a clean re-stamp would be safe; this guard is just
# belt-and-braces against a stale handoff lingering past a failed commit.
if grep -qE '^Steer-Key:[[:space:]]' "$MSG_FILE"; then
    exit 0
fi

# Nothing to stamp.
[[ -z "${AGENT_STEERING_KEYS:-}" ]] && exit 0

{
    cat "$MSG_FILE"
    printf '\n'
    while IFS= read -r key; do
        [[ -z "$key" ]] && continue
        printf 'Steer-Key: %s\n' "$key"
    done <<<"$AGENT_STEERING_KEYS"
} > "$MSG_FILE.new"
mv "$MSG_FILE.new" "$MSG_FILE"

exit 0
