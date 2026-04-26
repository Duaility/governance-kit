#!/usr/bin/env bash
# Agent steering accounting — prepare-commit-msg hook.
#
# Reads the handoff env file written by hooks/pre-commit.sh and stamps:
#   - Steer-Count: <N>                  — total events recorded on this commit
#   - Steer-Types: interrupt=2,...      — per-type breakdown (sorted, or `none`)
#   - Steer-Tiers: structural=3,...     — per-tier breakdown (sorted, or `none`)
#
# The summary triple parallels Token-Total / Cost-USD on the
# agent-token-accounting side: a reviewer skimming `git log` can see the
# steering volume without joining against STEERING.md. The row → commit
# join uses STEERING.md's `commit |` column; per-event `Steer-Key:`
# trailers were retired in #66.
#
# Always-on contract: when pre-commit detected a runtime + transcript, the
# handoff is written even on zero-event commits, and the three trailers are
# stamped here as `Steer-Count: 0` / `Steer-Types: none` / `Steer-Tiers: none`.
# If the handoff file doesn't exist (no runtime, no transcript, or pre-commit
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

# Idempotent on amends/retries: skip if Steer-Count is already stamped. The
# pre-commit hook re-derives the summary from the staged STEERING.md diff
# every run, so a clean re-stamp would be safe; this guard is belt-and-
# braces against a stale handoff lingering past a failed commit-msg check.
if grep -qE '^Steer-Count:[[:space:]]' "$MSG_FILE"; then
    exit 0
fi

{
    cat "$MSG_FILE"
    printf '\n'
    printf 'Steer-Count: %s\n' "${AGENT_STEERING_COUNT:-0}"
    printf 'Steer-Types: %s\n' "${AGENT_STEERING_TYPES:-none}"
    printf 'Steer-Tiers: %s\n' "${AGENT_STEERING_TIERS:-none}"
} > "$MSG_FILE.new"
mv "$MSG_FILE.new" "$MSG_FILE"

exit 0
