#!/usr/bin/env bash
# Directive: every non-merge, non-revert commit stamps the always-on summary
# triple `Steer-Count`, `Steer-Types`, `Steer-Tiers` — even when zero events
# were detected. The summary numbers must agree with the rows newly added to
# receipts by this commit: `Steer-Count` equals the number of added
# rows, and the type / tier breakdowns tally those rows' `type` and `tier`
# columns. The row → commit join uses receipts's `commit |` column.
#
# Independent of agent-token-accounting: the contract applies to every
# in-scope commit, not gated on the `Agent:` trailer. Installation is the
# gate.
#
# Per-event `Steer-Key:` trailers were retired in #66. Historical commits
# in the repo's log may still carry them; the new check ignores them.
#
# Modes:
#   Mode A — commit-msg hook:  bash check.sh <path-to-msg-file>
#       Validates the pending message: summary triple is well-formed and
#       agrees with the rows the staged receipts diff adds. Each newly
#       added row's `commit |` cell must equal the pending subject.
#   Mode B — CI / run.sh:      bash check.sh
#       Walks default-branch merge-base → HEAD and validates every
#       non-merge, non-revert commit against the same summary contract,
#       deriving "rows added by this commit" from `git show <sha>`. The
#       row.commit-cell == subject check is skipped here because squash
#       merges can rewrite the subject after the row was stamped.
#
# No self-bootstrap exemption: `governance init` is responsible for making
# the install commit pass this directive on the first try. prepare-commit-msg
# stamps the zero-default summary triple even when no runtime is detected,
# so a normal `git commit` from the init flow always satisfies the contract
# without a waiver. No bootstrap accommodation lives in check.sh.
#
# Skips merge commits and revert commits, identical to agent-token-accounting.
#
# Independent ledger-shape check runs first so even branches with no
# steering activity catch a malformed receipt steering table.

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$(dirname "$0")/../../../../../lib.sh"
directive_start "agent-steering-accounting"
require_git

ROOT="$(git rev-parse --show-toplevel)"
RECEIPTS_DIR="$ROOT/receipts"
LIB="$HERE/lib"

if [[ ! -f "$LIB/ledger.py" || ! -f "$LIB/trailers.py" ]]; then
    violation "directive folder is missing lib/{ledger,trailers}.py — cannot validate"
    directive_end
fi

# ──────────────────────────────────────────────────────────────
# Receipt steering-table shape check (independent of any commits).
# ──────────────────────────────────────────────────────────────
if [[ -d "$RECEIPTS_DIR" ]]; then
    while IFS= read -r v; do
        [[ -z "$v" ]] && continue
        violation "$v"
    done < <(python3 "$LIB/ledger.py" validate-dir "$RECEIPTS_DIR" || true)
fi

# Print the steer-keys of steering rows newly added to receipts in this commit.
# Mode A reads the staged diff (the pending commit's contribution); Mode B
# reads `git show <sha> -- receipts`. In both cases, an added steering row is a
# `+| ... |` line with 7 cells whose first cell starts with `steer-` (the
# receipt diff also carries 12-cell cost rows and prose, which we skip).
new_row_keys() {
    local mode="$1"
    local sha="${2:-}"
    if [[ "$mode" == "A" ]]; then
        git diff --cached -- "$RECEIPTS_DIR" 2>/dev/null || true
    else
        git show --no-color --format= "$sha" -- "$RECEIPTS_DIR" 2>/dev/null || true
    fi | python3 -c '
import sys
for line in sys.stdin:
    line = line.rstrip("\n")
    if not line.startswith("+") or line.startswith("+++"):
        continue
    body = line[1:].strip()
    if not body.startswith("|"):
        continue
    cells = [c.strip() for c in body.split("|")[1:-1]]
    if len(cells) != 7:
        continue
    key = cells[0]
    # Skip the table header (its first cell is the literal "steer-key", which
    # also starts with "steer-") and the separator; keep real rows only.
    if key == "steer-key" or not key.startswith("steer-"):
        continue
    print(key)
'
}

validate_commit_message() {
    local label="$1"
    local mode="$2"   # A or B
    local sha="${3:-}"
    local subject="${4:-}"
    local msg
    msg="$(cat)"

    # Collect added keys into an array. Bash 3.2 compatible (no mapfile).
    local keys_raw
    keys_raw="$(new_row_keys "$mode" "$sha")"
    local -a keys=()
    if [[ -n "$keys_raw" ]]; then
        local k
        while IFS= read -r k; do
            [[ -z "$k" ]] && continue
            keys+=("$k")
        done <<<"$keys_raw"
    fi

    local -a args=("validate" "$label" "$RECEIPTS_DIR")
    if [[ -n "$subject" ]]; then
        args+=("--subject" "$subject")
    fi
    args+=("-")
    if (( ${#keys[@]} > 0 )); then
        args+=("${keys[@]}")
    fi

    while IFS= read -r v; do
        [[ -z "$v" ]] && continue
        violation "$v"
    done < <(printf '%s' "$msg" | python3 "$LIB/trailers.py" "${args[@]}" || true)
}

# Returns 0 if the commit body carries a valid waiver line.
# `governance: allow-agent-steering-accounting <reason>` — reason required.
msg_has_waiver() {
    local msg="$1"
    printf '%s\n' "$msg" \
        | grep -qE '^[[:space:]]*(<!--)?[[:space:]]*governance:[[:space:]]*allow-agent-steering-accounting[[:space:]]+.+'
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
    pending_subject=$(grep -vE '^[[:space:]]*($|#)' "$msg_file" | head -n1)
    if [[ "$pending_subject" == Revert\ \"* ]]; then
        directive_end
    fi
    if msg_has_waiver "$(cat "$msg_file")"; then
        directive_end
    fi
    validate_commit_message "pending commit" "A" "" "$pending_subject" <"$msg_file"
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
    # No new work on this branch relative to the default — but on `main`
    # itself, HEAD is the freshly-landed (often squash-merge) commit whose
    # trailers are the durable record. A squash-merge bypasses the local
    # commit-msg hook (it runs on GitHub's server), so without this
    # single-commit fallback its summary triple goes unchecked. Validate
    # HEAD on its own so the trailer contract still applies post-merge.
    # `--verify` is what distinguishes "HEAD resolves to a commit" from
    # the empty-repo case (where `git rev-parse HEAD` prints the literal
    # string "HEAD" on stdout and exits 128).
    if git rev-parse --verify HEAD >/dev/null 2>&1; then
        head_sha=$(git rev-parse HEAD)
        if ! is_exempt_commit "$head_sha"; then
            msg=$(git log -1 --format=%B "$head_sha")
            if ! msg_has_waiver "$msg"; then
                validate_commit_message "$head_sha" "B" "$head_sha" "" <<<"$msg"
            fi
        fi
    fi
    directive_end
fi

while IFS= read -r sha; do
    [[ -z "$sha" ]] && continue
    if is_exempt_commit "$sha"; then
        continue
    fi
    msg=$(git log -1 --format=%B "$sha")
    if msg_has_waiver "$msg"; then
        continue
    fi
    validate_commit_message "$sha" "B" "$sha" "" <<<"$msg"
done < <(git log "$base..HEAD" --format='%H')

directive_end
