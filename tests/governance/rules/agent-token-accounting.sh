#!/usr/bin/env bash
# Rule: Agent-authored commits carry full token-accounting trailers and a
# matching append-only row in COSTS.md.
#
# Required trailers on any commit whose message contains `Agent: <name>`:
#   Agent:         free-form runtime identifier (codex, claude-code, cursor, ...)
#   Issue:         #123 — the GitHub issue anchor
#   Session:       the runtime's session / thread id
#   Token-Input:   non-negative integer (= input + cache_create)
#   Token-Output:  non-negative integer (= output)
#   Token-Total:   non-negative integer, == Token-Input + Token-Output
#   Cost-Key:      <agent>-<session-short>-<epoch>, unique within COSTS.md
#
# COSTS.md ledger format — one row per agent-authored commit, append-only:
#   | cost-key | agent | session | issue | input | cache-create | cache-read | output | total | note |
#
# Where row.total == input + cache_create + output (self-checking). cache_read
# is tracked but deliberately excluded from total — it's the same bytes re-read
# each turn, not new work, so row.total == Token-Total in the trailer.
# Legacy 8-column rows (from before the cache split) are accepted with
# cache_create/cache_read defaulted to 0.
#
# Modes:
#   Mode A — commit-msg hook:  bash agent-token-accounting.sh <path-to-msg-file>
#   Mode B — CI / run.sh:      bash agent-token-accounting.sh
#       Walks default-branch merge-base → HEAD and validates every commit
#       that declares an Agent: trailer. Also validates COSTS.md shape
#       independently, so post-squash repos still get ledger integrity.
#
# Ledger parsing, trailer parsing, and cross-check math are in
# scripts/governance/lib/ledger.py and scripts/governance/lib/trailers.py.
# This script is the bash shell — detect mode, walk commits, aggregate
# violations.
set -u
source "$(dirname "$0")/../lib.sh"
rule_start "agent-token-accounting"
require_git

ROOT="$(git rev-parse --show-toplevel)"
LEDGER="$ROOT/COSTS.md"

# Locate the Python libs. Prefer the installed-in-target-repo path; fall back
# to the bootstrap asset path so this rule works even when vendored.
LIB=""
for candidate in "$ROOT/scripts/governance/lib" \
                 "$ROOT/governance-bootstrap/assets/scripts/governance/lib"; do
    if [[ -f "$candidate/ledger.py" && -f "$candidate/trailers.py" ]]; then
        LIB="$candidate"
        break
    fi
done
if [[ -z "$LIB" ]]; then
    violation "scripts/governance/lib/{ledger,trailers}.py not found — cannot validate"
    rule_end
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
# Per-commit validation — shared between Mode A and Mode B.
# Args: <label>  <msg> (on stdin)
# ──────────────────────────────────────────────────────────────
validate_commit_message() {
    local label="$1"
    local msg
    msg="$(cat)"

    # Quick exit: no Agent: trailer → not an agent commit.
    if ! printf '%s\n' "$msg" | grep -qE '^Agent:[[:space:]]'; then
        return 0
    fi

    # Extract Cost-Key so we can look it up in the ledger. Use the last
    # occurrence (git trailer semantics) just like trailers.py does.
    local cost_key
    cost_key="$(printf '%s\n' "$msg" | awk -F': *' '/^Cost-Key:[[:space:]]/ {val=$2} END {print val}')"

    # Look up the ledger row.
    local found=0 row_input=0 row_cc=0 row_cr=0 row_output=0 row_total=0
    if [[ -n "$cost_key" && -f "$LEDGER" ]]; then
        if row_output_line="$(python3 "$LIB/ledger.py" find-by-cost-key "$LEDGER" "$cost_key" 2>/dev/null)"; then
            read -r row_input row_cc row_cr row_output row_total <<<"$row_output_line"
            found=1
        fi
    fi

    # First-class ledger-presence violation is independent of the trailer shape.
    if [[ "$found" == "0" ]]; then
        if [[ ! -f "$LEDGER" ]]; then
            violation "$label — agent-authored commit but COSTS.md does not exist at repo root"
        else
            local count
            count="$(python3 "$LIB/ledger.py" find-by-cost-key "$LEDGER" "$cost_key" 2>&1 1>/dev/null | grep -oE 'found [0-9]+' | awk '{print $2}')"
            violation "$label — Cost-Key '${cost_key:-<missing>}' should have exactly 1 row in COSTS.md, found ${count:-0}"
        fi
    fi

    # Trailer shape + cross-check math (only when we have the row; otherwise
    # trailers.py just skips the cross-check).
    local v
    while IFS= read -r v; do
        [[ -z "$v" ]] && continue
        violation "$v"
    done < <(
        printf '%s' "$msg" | python3 "$LIB/trailers.py" validate \
            "$label" "$found" \
            "$row_input" "$row_cc" "$row_cr" "$row_output" "$row_total" \
            - 2>/dev/null || true
    )
}

# ──────────────────────────────────────────────────────────────
# Mode A — commit-msg hook
# ──────────────────────────────────────────────────────────────
if [[ $# -gt 0 ]]; then
    msg_file="$1"
    if [[ ! -f "$msg_file" ]]; then
        violation "commit-msg file not found: $msg_file"
        rule_end
    fi
    validate_commit_message "pending commit" <"$msg_file"
    rule_end
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

if [[ -z "$base" ]]; then
    # Fall back to validating HEAD alone so the rule still exercises.
    msg=$(git log -1 --format=%B HEAD 2>/dev/null || echo "")
    [[ -n "$msg" ]] && printf '%s' "$msg" | validate_commit_message "HEAD"
    rule_end
fi

while IFS= read -r sha; do
    [[ -z "$sha" ]] && continue
    msg=$(git log -1 --format=%B "$sha")
    printf '%s' "$msg" | validate_commit_message "$sha"
done < <(git log "$base..HEAD" --format='%H')

rule_end
