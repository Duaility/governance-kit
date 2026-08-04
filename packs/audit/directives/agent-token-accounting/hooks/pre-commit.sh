#!/usr/bin/env bash
# Agent token accounting — invoked from the pre-commit hook.
#
# This is what makes `git commit` the baseline for agent-authored commits.
# The pre-commit hook runs it before governance tests; if the commit is
# agent-authored, it appends the cost row to the issue's receipt and `git add`s
# it (so the row lands in the CURRENT commit's tree). It then writes a frozen
# endpoint file keyed by the staged tree id; check.sh reconciles the staged row
# against that endpoint at commit-msg time (issues #293, #305) — no trailers are
# stamped.
#
# Why pre-commit and not a later hook: pre-commit runs before git snapshots the
# tree, so the `git add` of the receipt row lands in the CURRENT commit. From a
# post-snapshot hook it would land in the NEXT commit's index instead.
#
# Runtime detection is automatic from the environment:
#   CLAUDECODE=1                 → claude-code
#   CODEX_THREAD_ID or CODEX_TRANSCRIPT_PATH set
#                                  → codex
#   AGENT_NAME set manually      → whatever the user said, with explicit
#                                   AGENT_SESSION_ID / AGENT_CUM_INPUT /
#                                   AGENT_CUM_CACHE_CREATE /
#                                   AGENT_CUM_CACHE_READ / AGENT_CUM_OUTPUT /
#                                   AGENT_MODEL / AGENT_COST_USD
# Otherwise the commit is treated as a human commit and this script no-ops.
#
# Nothing here prices anything (issue #355). The cost cell is whatever the
# runtime adapter reported, verbatim, and an unreported cost writes an empty
# cell — the commit is never blocked over a model the kit doesn't recognise,
# because the kit no longer keeps a list of models.
#
# Issue anchor inference reads the parent git process's argv via
# /proc/$PPID/cmdline (Linux) or `ps -ww -o args=` (macOS/BSD). Set AGENT_ISSUE
# explicitly to skip inference (useful for editor-mode commits where argv has
# no -m).
#
# All receipt parsing / appending goes through sibling lib/receipt.sh +
# lib/costs.sh; runtime detection through lib/runtime.sh; endpoint and
# checkpoint persistence through lib/endpoint.sh. Bash + POSIX awk only, so the
# commit path stays python-free. Per-runtime adapters are kit-level, in the
# shared registry at `.governance/runtimes/` (issue #355).

set -u

if [[ "${SKIP_GOVERNANCE:-0}" == "1" ]]; then
    exit 0
fi

ROOT="$(git rev-parse --show-toplevel)"
HERE="$(cd "$(dirname "$0")" && pwd)"
RULE_DIR="$(cd "$HERE/.." && pwd)"
# Accounting rows live in per-issue receipts (issue #201), not a central
# COSTS.md. The receipt is resolved from the issue anchor below.
RECEIPTS_DIR="$ROOT/receipts"
LIB="$RULE_DIR/lib"

# shellcheck disable=SC1090
source "$LIB/receipt.sh"
# shellcheck disable=SC1090
source "$LIB/costs.sh"
# shellcheck disable=SC1090
source "$LIB/endpoint.sh"

# ── Detect runtime + resolve the session's cumulative counters ──
# lib/runtime.sh resolves the writer's sampled cumulative coordinate and the
# harness's own cost figure. check.sh only uses runtime detection before
# verifying the frozen staged-tree endpoint; it deliberately does not compare
# against a later live coordinate.
# shellcheck disable=SC1090
source "$LIB/runtime.sh"
resolve_runtime_cumulative
rc=$?
# rc == 1: no agent runtime — a human commit. Exit silently (no row to write).
[[ $rc -eq 1 ]] && exit 0
if [[ $rc -eq 2 ]]; then
    echo "✗ agent-token-accounting: runtime '$RUNTIME' detected but its session usage was unreadable" >&2
    exit 1
fi
# rc == 0: RUNTIME / SESSION_ID / CUM_* / MODEL / COST_USD are set. The ledger's
# agent name is the user's AGENT_NAME for the manual runtime, else the runtime
# id itself; the `source` column always names the adapter.
AGENT_NAME="${AGENT_NAME:-$RUNTIME}"
SOURCE_ID="$RUNTIME"

# ── Read git's argv to recover the -m / --message subject ─────
# This script runs as: git → pre-commit hook → bash agent-accounting.sh.
# $PPID is the hook, not git. Walk up one more level to find git.
grandparent_pid() {
    local pid="$PPID"
    if [[ -r "/proc/$pid/status" ]]; then
        awk '/^PPid:/ {print $2}' "/proc/$pid/status"
    else
        ps -p "$pid" -o ppid= 2>/dev/null | tr -d ' '
    fi
}

parent_argv_string() {
    local pid="$1"
    if [[ -r "/proc/$pid/cmdline" ]]; then
        tr '\0' ' ' < "/proc/$pid/cmdline"
    else
        # BSD/macOS `ps` cat-v-escapes bytes >= 0x80 under the LC_ALL=C locale
        # git hooks usually run with, so a non-ASCII commit subject comes back
        # mangled (`M-bM-^@M-^Y` for a curly quote — issue #140). The
        # consequence is cosmetic and bounded: the issue anchor is matched as
        # `(#N)` (pure ASCII, unaffected), and the mangled tail only reaches the
        # row's free-text `note` cell, which receipt_safe_cell truncates at the
        # first backslash anyway. Set AGENT_ISSUE to skip argv inference
        # entirely when that matters.
        ps -ww -p "$pid" -o args= 2>/dev/null
    fi
}

GIT_PID="$(grandparent_pid)"
ARGV="$(parent_argv_string "${GIT_PID:-$PPID}")"
# Fallback to the immediate parent if the grandparent argv doesn't look
# like a git commit invocation (e.g. a rebase driving the hook).
if [[ "$ARGV" != *git* ]]; then
    ARGV="$(parent_argv_string "$PPID")"
fi

# ── Infer the issue anchor ─────────────────────────────────────
ISSUE="${AGENT_ISSUE:-}"
if [[ -z "$ISSUE" && "$ARGV" =~ \(#([1-9][0-9]*)\) ]]; then
    ISSUE="#${BASH_REMATCH[1]}"
fi
if [[ -z "$ISSUE" ]]; then
    cat >&2 <<EOF

────────────────────────────────────────
✗ Agent commit blocked by governance.

Detected agent runtime: $RUNTIME
Could not infer issue anchor from the commit subject.

Pass '(#N)' in the subject:
    git commit -m "feat: thing (#123)"

Or set AGENT_ISSUE explicitly (useful for editor-mode commits):
    AGENT_ISSUE='#123' git commit
────────────────────────────────────────
EOF
    exit 1
fi

# ── Pull a subject for the ledger's note column (best-effort) ──
SUBJECT=""
if [[ "$ARGV" =~ [[:space:]](-m|--message)[[:space:]]+(.+) ]]; then
    SUBJECT="${BASH_REMATCH[2]}"
elif [[ "$ARGV" =~ --message=(.+) ]]; then
    SUBJECT="${BASH_REMATCH[1]}"
fi

# ── Resolve the receipt this issue's accounting rows belong in ──
# Prefer an existing issue-N.md / issue-N-<slug>.md; create-if-absent lands
# the slugless issue-N.md, which the agent later fleshes out (or renames).
RECEIPT="$(receipt_resolve "$RECEIPTS_DIR" "$ISSUE")"

# ── Compute per-commit delta from a per-session checkpoint ────
# Issue #229: the write path reads the session's last-written cumulative
# coordinate from a git-dir checkpoint (not from the receipts), so a delta
# never depends on which sibling receipts are visible in this branch's tree —
# the cross-branch double-count is structurally gone. The cumulative columns
# written below are the accounting truth; this delta is a derived claim for
# display, proven later by reconciliation once rows are co-visible. A
# missing/stale checkpoint degrades the claim (caught by reconciliation), never
# blocks. The checkpoint lives in the git dir so it survives branch switches
# within a worktree (the canonical one-issue-one-branch workflow).
CHECKPOINT_DIR="$(git rev-parse --git-path governance-token-checkpoints)"
read -r PREV_INPUT PREV_CACHE_CREATE PREV_CACHE_READ PREV_OUTPUT < <(
    checkpoint_get "$CHECKPOINT_DIR" "$SESSION_ID"
)

TOKEN_INPUT=$(( CUM_INPUT         - PREV_INPUT         ))
TOKEN_CACHE_CREATE=$(( CUM_CACHE_CREATE - PREV_CACHE_CREATE ))
TOKEN_CACHE_READ=$(( CUM_CACHE_READ   - PREV_CACHE_READ   ))
TOKEN_OUTPUT=$(( CUM_OUTPUT        - PREV_OUTPUT        ))
(( TOKEN_INPUT         < 0 )) && TOKEN_INPUT=0
(( TOKEN_CACHE_CREATE  < 0 )) && TOKEN_CACHE_CREATE=0
(( TOKEN_CACHE_READ    < 0 )) && TOKEN_CACHE_READ=0
(( TOKEN_OUTPUT        < 0 )) && TOKEN_OUTPUT=0

# ── Compute cost-key ──────────────────────────────────────────
# Opaque key: <agent>-<session-short>-<epoch>-<n>. The per-(prefix) counter
# <n> closes the same-second collision window — two commits in one session
# within the same epoch second mint distinct keys (matching steer-key's
# scheme). The key is a join token, not a parseable structure.
SESSION_SHORT="${SESSION_ID:0:12}"
SESSION_SHORT="${SESSION_SHORT%%[-._]}"
EPOCH="$(date +%s)"
KEY_PREFIX="${AGENT_NAME}-${SESSION_SHORT}-${EPOCH}-"
COST_INDEX="$(costs_next_index "$RECEIPTS_DIR" "$KEY_PREFIX")"
COST_KEY="${AGENT_COST_KEY:-${KEY_PREFIX}${COST_INDEX}}"

# ── Append the cost row to the issue's receipt ────────────────
# Creates receipts/issue-<N>.md with a `## Accounting` → `### Costs` section
# if it doesn't exist yet; otherwise slots the row into the existing table.
# COST_USD is the harness's own figure or `-` (→ an empty cell). There is no
# pricing step and therefore no way for this hook to block on an unknown model.
mkdir -p "$RECEIPTS_DIR"
costs_append_row \
    "$RECEIPT" \
    "$COST_KEY" "$AGENT_NAME" "$SESSION_ID" "$ISSUE" "$MODEL" \
    "$TOKEN_INPUT" "$TOKEN_CACHE_CREATE" "$TOKEN_CACHE_READ" "$TOKEN_OUTPUT" \
    "$CUM_INPUT" "$CUM_CACHE_CREATE" "$CUM_CACHE_READ" "$CUM_OUTPUT" \
    "$COST_USD" "$SOURCE_ID" "$SUBJECT"
git add "$RECEIPT"

# ── Freeze the endpoint for commit-msg reconciliation ──────────
# The live transcript can advance after this writer runs. Key the endpoint by
# the post-row staged tree so commit-msg verifies exactly the coordinate this
# writer used, without accepting a stale endpoint from an earlier attempt.
TREE_ID="$(git write-tree)"
ENDPOINT="$(git rev-parse --git-path "governance-token-endpoints/${TREE_ID}.endpoint")"
RECEIPT_REL="${RECEIPT#$ROOT/}"
endpoint_write "$ENDPOINT" "$SESSION_ID" \
    "$CUM_INPUT" "$CUM_CACHE_CREATE" "$CUM_CACHE_READ" "$CUM_OUTPUT" \
    "$RECEIPT_REL" "$COST_KEY"

# ── Advance the per-session checkpoint to this commit's cumulative ──
# Written after the row lands so a retry (transcript cumulative unchanged) sees
# the checkpoint already at cum → derives a zero delta, exactly as the old
# sum-by-session path did once its own row was staged.
checkpoint_set "$CHECKPOINT_DIR" "$SESSION_ID" \
    "$CUM_INPUT" "$CUM_CACHE_CREATE" "$CUM_CACHE_READ" "$CUM_OUTPUT"

printf 'agent-accounting: runtime=%s model=%s session=%s input=+%d cache_create=+%d cache_read=+%d output=+%d cost-key=%s cost-usd=%s\n' \
    "$RUNTIME" "$MODEL" "$SESSION_ID" "$TOKEN_INPUT" "$TOKEN_CACHE_CREATE" "$TOKEN_CACHE_READ" "$TOKEN_OUTPUT" "$COST_KEY" "$COST_USD" >&2

exit 0
