#!/usr/bin/env bash
# Agent token accounting — the commit-path writer. "Stamp & fold" (issue #355).
#
# This hook does exactly two cheap, local things and nothing else:
#
#   STAMP  record WHO is committing — the harness and session the environment
#          announces — as a v6 Costs row in the issue's receipt.
#   FOLD   copy the newest snapshot the off-commit-path resolve sweep has
#          already written to the kit-owned sidecar into that row, and into any
#          OTHER session row in the same receipt whose sidecar has moved. That
#          second half is what makes the ledger self-healing: a later commit
#          repairs the tail spend of an earlier session, which no per-commit
#          row could ever do.
#
# It never reads a harness file, never parses a transcript, never sums a token.
# A pre-commit hook is the worst possible measurement point — synchronous,
# blocking, unretryable, racing a live session — and a session's cost is not
# final at commit time anyway. So measurement lives in hooks/post-commit.sh and
# hooks/pre-push.sh, where a failure means "try again later".
#
# Why pre-commit and not a later hook: pre-commit runs before git snapshots the
# tree, so the `git add` of the receipt row lands in the CURRENT commit. From a
# post-snapshot hook it would land in the NEXT commit's index instead.
#
# The only thing that can block a commit here is structural impossibility: an
# agent runtime is present but there is no issue anchor, so there is no receipt
# to stamp. Nothing about measurement can block anything.
#
# Issue anchor inference reads the parent git process's argv via
# /proc/$PPID/cmdline (Linux) or `ps -ww -o args=` (macOS/BSD). Set AGENT_ISSUE
# explicitly to skip inference (useful for editor-mode commits where argv has
# no -m).
#
# Receipt parsing / appending goes through sibling lib/receipt.sh + lib/costs.sh;
# identity detection and the kit-owned artifact paths through lib/runtime.sh.
# Bash + POSIX awk only, so the commit path stays python-free. Per-harness
# adapters are kit-level, in the shared registry at `.governance/runtimes/`.

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

# The installed lib.sh sits five levels above the directive folder. It is what
# makes `conf_get` (and therefore the identity-file trust window) resolve
# through the normal env > overlay > defaults ladder here exactly as it does in
# check.sh. Absent only when this folder is run straight out of the kit source
# tree, where no hook fires anyway.
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

# ── Detect the session's identity ─────────────────────────────
# Identity only: RUNTIME / SESSION_ID / DECLARED. No tokens, no cost, and no
# guessing — a harness that does not name its session gets the literal `-`,
# which is a truthful row, not a broken one.
if ! detect_runtime_identity; then
    # No agent runtime — a human commit. Exit silently (no row to write).
    exit 0
fi

# ── Read git's argv to recover the -m / --message subject ─────
# This script runs as: git → pre-commit hook → bash pre-commit.sh.
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
        # mangled (issue #140). The consequence is bounded: the issue anchor is
        # matched as `(#N)` (pure ASCII, unaffected). Set AGENT_ISSUE to skip
        # argv inference entirely when that matters.
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

# ── Resolve the receipt this issue's accounting rows belong in ──
# Prefer an existing issue-N.md / issue-N-<slug>.md; create-if-absent lands
# the slugless issue-N.md, which the agent later fleshes out (or renames).
mkdir -p "$RECEIPTS_DIR"
RECEIPT="$(receipt_resolve "$RECEIPTS_DIR" "$ISSUE")"

# ── Stamp: this session's row, refreshed from its sidecar ─────
# One row per session per issue, updated in place. With no snapshot yet the
# row is honestly `-` everywhere with source `unresolved`; the resolve sweep
# and the next commit's fold converge it on the truth.
SNAP="$(costs_fold_snapshot "$(sidecar_file "$RUNTIME" "$SESSION_ID")")"
S_IN="-"; S_CC="-"; S_CR="-"; S_OUT="-"; S_MODEL="-"; S_COST="-"; S_SRC="unresolved"
if [[ -n "$SNAP" ]]; then
    read -r S_IN S_CC S_CR S_OUT S_MODEL S_COST S_SRC <<< "$SNAP"
fi
costs_upsert_row "$RECEIPT" "$RUNTIME" "$SESSION_ID" "$S_MODEL" \
    "$S_IN" "$S_CC" "$S_CR" "$S_OUT" "$S_COST" "$S_SRC"

# ── Fold: every OTHER session row in this receipt ─────────────
# Self-healing convergence. A session whose spend kept growing after its last
# commit gets repaired here, by whichever session commits next.
KEYS="$(costs_session_keys "$RECEIPT")"
FOLDED=0
while IFS=$'\t' read -r f_harness f_session; do
    [[ -z "$f_harness" ]] && continue
    [[ "$f_harness" == "$RUNTIME" && "$f_session" == "$SESSION_ID" ]] && continue
    f_side="$(sidecar_file "$f_harness" "$f_session")" || continue
    f_snap="$(costs_fold_snapshot "$f_side")"
    [[ -z "$f_snap" ]] && continue
    [[ "$f_snap" == "$(costs_row_snapshot "$RECEIPT" "$f_harness" "$f_session")" ]] && continue
    read -r f_in f_cc f_cr f_out f_model f_cost f_src <<< "$f_snap"
    costs_upsert_row "$RECEIPT" "$f_harness" "$f_session" "$f_model" \
        "$f_in" "$f_cc" "$f_cr" "$f_out" "$f_cost" "$f_src"
    FOLDED=$(( FOLDED + 1 ))
done <<< "$KEYS"

git add "$RECEIPT"

printf 'agent-accounting: harness=%s session=%s model=%s cost-usd=%s source=%s%s\n' \
    "$RUNTIME" "$SESSION_ID" "$S_MODEL" "$S_COST" "$S_SRC" \
    "$([[ $FOLDED -gt 0 ]] && printf ' (+%d folded)' "$FOLDED")" >&2

exit 0
