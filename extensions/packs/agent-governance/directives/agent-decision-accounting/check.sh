#!/usr/bin/env bash
# Directive: Commits referencing load-bearing human decisions carry
# Decision-Key / Decision-Diverged trailers matching append-only rows in
# DECISIONS.md. Commits without a Decision-Key trailer are exempt.
#
# Required trailer pair (both-or-neither) on any commit that tags decisions:
#   Decision-Key:      comma-separated list of <decision-key>s, each
#                      resolving to exactly one row in DECISIONS.md.
#   Decision-Diverged: "<M>/<N>" — N = count of listed keys, M = count
#                      of listed rows whose `diverged` is not `agreed`.
#
# DECISIONS.md ledger format (11 columns):
#   | decision-key | agent | session | issue | phase | question | lean | choice | diverged | cost-key | note |
#
# - `diverged ∈ {agreed, overrode, reframed, deferred}`
# - `phase ∈ {scoping, plan-review, pr-review, post-merge}`
# - `cost-key` (optional): when non-empty, must resolve to a COSTS.md row
#   (cross-check only runs when COSTS.md exists — this directive does not
#   require agent-token-accounting to be installed).
#
# Runtime-agnostic: unlike agent-token-accounting, rows here are authored
# by the agent at question time (the lean must be declared structurally),
# so there is no per-runtime transcript reader. Claude Code and Codex
# write the same markdown rows and stamp the same trailers.
#
# Modes:
#   Mode A — commit-msg hook:  bash agent-decision-accounting/check.sh <msg-file>
#       Validates the pending commit. Skips revert commits (subject starts
#       with `Revert "`); merge commits don't go through commit-msg.
#   Mode B — CI / run.sh:      bash agent-decision-accounting/check.sh
#       Walks default-branch merge-base → HEAD and validates every
#       non-merge, non-revert commit. Merge commits (>1 parent) and revert
#       commits (subject starts with `Revert "`) are exempt. Commits
#       without a Decision-Key trailer are exempt. Also validates
#       DECISIONS.md shape independently so post-squash repos still get
#       ledger integrity.
#
# Ledger parsing + trailer parsing live in sibling lib/ledger.py and
# lib/trailers.py — the directive folder is self-contained.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/../../lib.sh"
directive_start "agent-decision-accounting"
require_git

ROOT="$(git rev-parse --show-toplevel)"
LEDGER="$ROOT/DECISIONS.md"
COSTS="$ROOT/COSTS.md"
LIB="$HERE/lib"

if [[ ! -f "$LIB/ledger.py" || ! -f "$LIB/trailers.py" ]]; then
    violation "directive folder is missing lib/{ledger,trailers}.py — cannot validate"
    directive_end
fi

if ! command -v python3 >/dev/null 2>&1; then
    violation "python3 not found on PATH — cannot validate DECISIONS.md"
    directive_end
fi

# ──────────────────────────────────────────────────────────────
# Ledger-integrity check (independent of any commits). Runs first so
# repo-wide shape problems get reported even on human-only branches.
# ──────────────────────────────────────────────────────────────
if [[ -f "$LEDGER" ]]; then
    while IFS= read -r v; do
        [[ -z "$v" ]] && continue
        violation "$v"
    done < <(python3 "$LIB/ledger.py" validate "$LEDGER" || true)
fi

# ──────────────────────────────────────────────────────────────
# Build a snapshot TSV for a given set of decision-keys.
#   snapshot_for_keys <key1> <key2> ... → prints one "<key>\t<diverged>\t<cost_key>" per key.
# Unresolved / duplicated keys print "<key>\tMISSING\t-". Does not fail;
# the caller consumes this into trailers.py validate.
# ──────────────────────────────────────────────────────────────
snapshot_for_keys() {
    local key line
    for key in "$@"; do
        if [[ ! -f "$LEDGER" ]]; then
            printf '%s\tMISSING\t-\n' "$key"
            continue
        fi
        if line="$(python3 "$LIB/ledger.py" find-by-decision-key "$LEDGER" "$key" 2>/dev/null)"; then
            # line is "<diverged> <cost_key>"
            local diverged cost_key
            diverged="$(printf '%s' "$line" | awk '{print $1}')"
            cost_key="$(printf '%s' "$line" | awk '{print $2}')"
            [[ -z "$cost_key" ]] && cost_key="-"
            printf '%s\t%s\t%s\n' "$key" "$diverged" "$cost_key"
        else
            printf '%s\tMISSING\t-\n' "$key"
        fi
    done
}

# Extract the Decision-Key trailer value (last occurrence wins per git
# trailer semantics). Returns the comma-separated raw string or empty.
extract_decision_key_trailer() {
    awk -F': *' '/^Decision-Key:[[:space:]]*/ {val=$2} END {print val}'
}

# Cross-check cost-key cells in DECISIONS.md against COSTS.md. Only runs
# when COSTS.md is present — we do not want to hard-require
# agent-token-accounting to be installed. Uses a simple grep for the
# leading `| <cost-key> |` column match.
cost_key_cross_check() {
    [[ -f "$COSTS" ]] || return 0
    [[ -f "$LEDGER" ]] || return 0
    # Stream (decision-key, cost-key) pairs where cost-key is non-empty.
    local dkey cost_key
    while IFS=$'\t' read -r dkey cost_key; do
        [[ -z "$dkey" ]] && continue
        [[ -z "$cost_key" || "$cost_key" == "-" ]] && continue
        if ! grep -qE "^\|[[:space:]]*${cost_key}[[:space:]]*\|" "$COSTS"; then
            violation "DECISIONS.md — row '$dkey' references cost-key '$cost_key' but no matching row in COSTS.md"
        fi
    done < <(
        LIB="$LIB" LEDGER="$LEDGER" python3 -c '
import os, sys
sys.path.insert(0, os.environ["LIB"])
from ledger import parse
for r in parse(os.environ["LEDGER"]):
    ck = (r.cost_key or "").strip()
    if ck and ck != "-":
        print(f"{r.decision_key}\t{ck}")
'
    )
}
cost_key_cross_check

# ──────────────────────────────────────────────────────────────
# Per-commit validation — shared between Mode A and Mode B.
# Args: <label>  <msg> (on stdin)
# ──────────────────────────────────────────────────────────────
validate_commit_message() {
    local label="$1"
    local msg
    msg="$(cat)"

    local dkey_raw
    dkey_raw="$(printf '%s\n' "$msg" | extract_decision_key_trailer)"

    # No Decision-Key trailer → commit did not record load-bearing
    # decisions. Exempt (trailers.py will also no-op, but we short-circuit
    # to avoid the snapshot cost).
    if [[ -z "$dkey_raw" ]]; then
        # Still hand off to trailers.py in case only Decision-Diverged is
        # present — that's an inconsistency we want flagged.
        local v
        while IFS= read -r v; do
            [[ -z "$v" ]] && continue
            violation "$v"
        done < <(
            printf '%s' "$msg" | python3 "$LIB/trailers.py" validate \
                "$label" "/dev/null" - 2>/dev/null || true
        )
        return 0
    fi

    # Split on commas, strip whitespace, dedupe preserving order.
    # Portable to bash 3.2 (macOS default) — no associative arrays.
    local keys_raw=()
    IFS=',' read -r -a keys_raw <<<"$dkey_raw"
    local keys=() k seen=" "
    for k in "${keys_raw[@]}"; do
        k="${k## }"; k="${k%% }"
        [[ -z "$k" ]] && continue
        case "$seen" in
            *" $k "*) : ;;
            *) keys+=("$k"); seen="$seen$k " ;;
        esac
    done

    # Build snapshot TSV in a temp file.
    local snapshot
    snapshot="$(mktemp -t gov-decisions-XXXXXX)"
    # shellcheck disable=SC2064
    trap "rm -f '$snapshot'" RETURN
    snapshot_for_keys "${keys[@]}" >"$snapshot"

    local v
    while IFS= read -r v; do
        [[ -z "$v" ]] && continue
        violation "$v"
    done < <(
        printf '%s' "$msg" | python3 "$LIB/trailers.py" validate \
            "$label" "$snapshot" - 2>/dev/null || true
    )
}

# ──────────────────────────────────────────────────────────────
# Mode A — commit-msg hook
# ──────────────────────────────────────────────────────────────
if [[ $# -gt 0 ]]; then
    msg_file="$1"
    if [[ ! -f "$msg_file" ]]; then
        violation "commit-msg file not found: $msg_file"
        directive_end
    fi
    # Skip revert commits — git's auto-format starts with `Revert "..."`.
    pending_subject=$(grep -vE '^[[:space:]]*($|#)' "$msg_file" | head -n1)
    if [[ "$pending_subject" == Revert\ \"* ]]; then
        directive_end
    fi
    validate_commit_message "pending commit" <"$msg_file"
    directive_end
fi

# ──────────────────────────────────────────────────────────────
# Mode B — CI / run.sh — walk base..HEAD
# ──────────────────────────────────────────────────────────────
base=""
for candidate in origin/main origin/master main master; do
    if git rev-parse --verify "$candidate" >/dev/null 2>&1; then
        mb=$(git merge-base HEAD "$candidate" 2>/dev/null || echo "")
        if [[ -n "$mb" && "$mb" != "$(git rev-parse HEAD)" ]]; then
            base="$mb"
            break
        fi
    fi
done

is_exempt_commit() {
    local sha="$1"
    local parents subject
    parents=$(git log -1 --format=%P "$sha" 2>/dev/null || echo "")
    if [[ "$parents" == *' '* ]]; then
        return 0
    fi
    subject=$(git log -1 --format=%s "$sha" 2>/dev/null || echo "")
    if [[ "$subject" == Revert\ \"* ]]; then
        return 0
    fi
    return 1
}

if [[ -z "$base" ]]; then
    directive_end
fi

while IFS= read -r sha; do
    [[ -z "$sha" ]] && continue
    if is_exempt_commit "$sha"; then
        continue
    fi
    msg=$(git log -1 --format=%B "$sha")
    validate_commit_message "$sha" <<<"$msg"
done < <(git log "$base..HEAD" --format='%H')

directive_end
