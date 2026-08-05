#!/usr/bin/env bash
# Directive: every agent-authored commit carries the identity of the session
# that produced it into the issue's receipt (`receipts/issue-<N>.md`, under
# `## Accounting` → `### Costs`), and the Costs table is well-formed. This repo
# is agent-driven only — a commit with no accounted session is a bug.
#
# Identity at commit, measurement at rest (issue #355). A pre-commit hook is
# the worst possible measurement point: synchronous, blocking, unretryable, and
# racing a session whose cost is not final at commit time anyway — the session
# keeps running. So the two halves split:
#
#   Identity  is cheap and only knowable at commit time: the harness announces
#             itself in the environment. The commit path records it and
#             validates structure. It never reads a harness file, never parses
#             a transcript, never does arithmetic on tokens.
#   Measurement happens off the commit path. Adapters refresh a kit-owned
#             snapshot sidecar from each harness's declared surfaces; the next
#             commit folds the newest snapshot into the row. A failed read
#             means "try again later", never "commit blocked" and never a
#             guessed number.
#
# Receipt Costs sub-table — v6, one row per SESSION per issue (not per commit),
# updated in place while the PR is open:
#   | date | harness | session | model | input | cache-create | cache-read | output | cost-usd | source |
# `cost-usd` is the harness's own figure verbatim or `-`; the kit owns no rate
# card and never prices. `source` is the provenance of the numbers
# (`harness-feed` / `session-file` / `server` / `manual` / `unresolved`).
# Legacy rows (17 = v5, 16 = v4, 12 = v3) are structurally tolerated.
#
# Modes:
#   Mode A — commit-msg hook:  bash check.sh <path-to-msg-file>
#       Runs the repo-wide Costs-table shape check (below), then — when an
#       agent runtime is detected — asserts that a staged receipt carries a v6
#       row for exactly that harness + session. This is an IDENTITY-truth
#       check: it never compares a number, because the numbers are best-effort
#       measurements of a session that is still running. A missing row means
#       the runtime-aware pre-commit hook did not run.
#   Mode B — CI / run.sh:      bash check.sh
#       Shape check only. Unresolved rows are explicitly ALLOWED: CI has no
#       session state, and honesty beats pretense.
#
# Markdown/table plumbing lives in sibling lib/receipt.sh; the row + sidecar
# schema in lib/costs.sh; validation in lib/validate.sh; identity detection and
# the kit-owned artifact paths in lib/runtime.sh; the off-commit-path resolve
# sweep in lib/resolve.sh (driven by hooks/post-commit.sh and hooks/pre-push.sh,
# never from here). All bash + POSIX awk.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$(dirname "$0")/../../../../../lib.sh"
directive_start "agent-token-accounting"
require_git

ROOT="$(git rev-parse --show-toplevel)"
RECEIPTS_DIR="$ROOT/receipts"
LIB="$HERE/lib"

for _f in receipt.sh costs.sh validate.sh runtime.sh; do
    if [[ ! -f "$LIB/$_f" ]]; then
        violation "directive folder is missing lib/$_f — cannot validate"
        directive_end
    fi
done
# shellcheck disable=SC1090
source "$LIB/receipt.sh"
# shellcheck disable=SC1090
source "$LIB/costs.sh"
# shellcheck disable=SC1090
source "$LIB/validate.sh"

# ──────────────────────────────────────────────────────────────
# Costs-table shape check (independent of any commit). Runs in both modes so
# a malformed row is reported everywhere: bad cell count, a token cell that is
# neither an integer nor `-`, a cost that is neither a decimal nor `-`, an
# unknown provenance label, or two rows for one session in one receipt.
# ──────────────────────────────────────────────────────────────
if [[ -d "$RECEIPTS_DIR" ]]; then
    while IFS= read -r v; do
        [[ -z "$v" ]] && continue
        violation "$v"
    done < <(costs_validate_dir "$RECEIPTS_DIR" || true)
fi

# Returns 0 if the commit message carries a valid escape-hatch waiver.
# `governance: allow-agent-token-accounting <reason>` — reason required. Covers
# the rare legitimate out-of-hook commit.
msg_has_waiver() {
    printf '%s\n' "$1" \
        | grep -qE '^[[:space:]]*(<!--)?[[:space:]]*governance:[[:space:]]*allow-agent-token-accounting[[:space:]]+.+'
}

# ──────────────────────────────────────────────────────────────
# Mode A — commit-msg hook: identity truth for the staged tree.
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
    msg="$(cat "$msg_file")"
    if msg_has_waiver "$msg"; then
        directive_end
    fi

    # shellcheck disable=SC1090
    source "$LIB/runtime.sh"
    if ! detect_runtime_identity; then
        # No agent runtime — a human / plain-git commit. Nothing to account.
        directive_end
    fi

    staged="$(git diff --cached --no-renames --name-only -- 'receipts/*.md' 2>/dev/null)" \
        || staged="$(git ls-files -- 'receipts/*.md' 2>/dev/null || true)"

    found=0
    while IFS= read -r rel; do
        [[ -z "$rel" ]] && continue
        [[ -f "$ROOT/$rel" ]] || continue
        if [[ -n "$(costs_row "$ROOT/$rel" "$RUNTIME" "$SESSION_ID")" ]]; then
            found=1
            break
        fi
    done <<< "$staged"

    if [[ $found -eq 0 ]]; then
        violation "pending commit — agent runtime '$RUNTIME' (session '$SESSION_ID') is active but no staged receipt carries a Costs row for it. The row is written by the runtime-aware pre-commit hook: commit through it (a plain \`git commit\`, not --no-verify / SKIP_GOVERNANCE=1), or add a 'governance: allow-agent-token-accounting <reason>' waiver. Note the row's numbers are NOT checked here — an unresolved row is a valid row; only the identity has to be recorded."
    fi
    directive_end
fi

# ──────────────────────────────────────────────────────────────
# Mode B — CI / run.sh: Costs-table shape only (ran above). Unresolved rows
# are allowed by design: CI has no session state and cannot measure anything,
# so demanding numbers there would only teach agents to invent them.
# ──────────────────────────────────────────────────────────────
directive_end
