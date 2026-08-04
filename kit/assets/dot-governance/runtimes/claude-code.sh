#!/usr/bin/env bash
# governance-kit:managed kit-version=0.12.0
# Claude Code runtime adapter — one file per harness, two verbs (issue #355).
#
# Verb interface (argv[1]; a bare invocation defaults to `cost`):
#
#   cost — the harness's OWN reported session usage, one line to stdout:
#       <session_id> <cum_input> <cum_cache_create> <cum_cache_read> <cum_output> <model> <cost_usd>
#
#     `cost_usd` is the figure the HARNESS reported — the sum of the
#     transcript's own per-entry `costUSD` values — or the literal `-` when the
#     transcript carries none. The adapter may sum harness-reported numbers into
#     a cumulative, but it NEVER prices: issue #355 deleted the kit's rate card,
#     because a kit-computed dollar figure is a guess about someone else's
#     billing that looks like a fact.
#
#   judge [<tier>] [<model>] — read a fully-built adjudication prompt on stdin,
#     run the CLI non-interactively, and print exactly:
#         VERDICT: PASS            (or VERDICT: REFUTED)
#         REASON: <text>           (zero or more lines)
#     <tier> is the capability tier (low | medium | high; empty → low) and picks
#     this adapter's own default model; <model> overrides it outright (the
#     caller's SUBAGENT_MODELS_<TIER> conf value). The prompt is built by the
#     caller from the directive's declaration — never by the agent under audit.
#
# Exit codes: 0 ok · 2 the runtime is present but its surface is unusable —
# an unreadable transcript (`cost`), or a missing CLI / transport failure /
# unparseable answer (`judge`). Exit 2 is never fatal to the caller: the commit
# lane degrades to the harness (sub-agent) path rather than blocking on a
# broken side channel.
#
# The four token numbers are cumulative across the whole session transcript;
# the caller derives the per-commit delta from its own session checkpoint.
#
# `model` is the latest `model` seen on an assistant entry (latest wins, so a
# mid-session /model switch propagates forward), or `unknown`. Nothing is
# blocked on it any more — it is a label on the row, not a pricing key.
#
# Environment overrides:
#   CLAUDE_TRANSCRIPT_PATH    absolute path to the session JSONL
#   CLAUDE_PROJECTS_DIR       override ~/.claude/projects
#   CLAUDE_CODE_SESSION_ID    the live session id (exported into the hook env by
#                             Claude Code) — names the transcript exactly, so we
#                             never have to guess by mtime when it is present.
#   AGENT_JUDGE_TIMEOUT       seconds to allow the judge CLI (default 120), when
#                             a `timeout` binary is available.
#
# Self-contained by design: an adapter is one droppable file resolved by name,
# so the small verdict normalizer below is duplicated per adapter rather than
# sourced from a sibling.

set -u

VERB="${1:-cost}"

# Every environment handle that ties a nested CLI run to the CALLING session:
# the git plumbing a hook exports (which would make the judge operate on the
# caller's index) and the harness session ids (which would bill the audit to the
# session under audit and hand it that session's context). A judge that inherits
# the author's session is not an independent judge.
judge_env_clean() {
    env -u GIT_DIR -u GIT_INDEX_FILE -u GIT_WORK_TREE -u GIT_PREFIX \
        -u GIT_COMMON_DIR -u GIT_AUTHOR_DATE -u GIT_COMMITTER_DATE \
        -u CLAUDE_CODE_SESSION_ID -u CLAUDECODE -u CLAUDE_TRANSCRIPT_PATH \
        -u CODEX_THREAD_ID -u CODEX_TRANSCRIPT_PATH \
        "$@"
}

# Normalize raw CLI stdout to the judge contract: the first well-formed VERDICT
# line, then any REASON lines. No verdict → exit 2 (the caller degrades).
emit_verdict() {
    awk '
        !v && $0 ~ /^[ \t]*VERDICT:[ \t]*(PASS|REFUTED)[ \t]*\r?$/ {
            line = $0
            sub(/^[ \t]*VERDICT:[ \t]*/, "", line)
            sub(/[ \t\r]*$/, "", line)
            v = line
            print "VERDICT: " v
            next
        }
        v && $0 ~ /^[ \t]*REASON:/ {
            line = $0
            sub(/^[ \t]*/, "", line)
            sub(/[ \t\r]*$/, "", line)
            print line
        }
        END { if (!v) { exit 2 } }
    '
}

do_judge() {
    local tier="${1:-low}" model="${2:-}"
    command -v claude >/dev/null 2>&1 || {
        printf 'claude-code adapter: no `claude` CLI on PATH\n' >&2
        return 2
    }
    if [[ -z "$model" ]]; then
        # This adapter's own per-tier defaults, as CLI aliases rather than
        # pinned model ids — an alias keeps working across model releases, and
        # the kit has no business pinning someone else's model catalog.
        case "$tier" in
            high)   model="opus" ;;
            medium) model="sonnet" ;;
            *)      model="haiku" ;;
        esac
    fi
    local prompt
    prompt="$(cat)"
    [[ -n "$prompt" ]] || return 2

    local -a runner=()
    if command -v timeout >/dev/null 2>&1; then
        runner=(timeout "${AGENT_JUDGE_TIMEOUT:-120}")
    elif command -v gtimeout >/dev/null 2>&1; then
        runner=(gtimeout "${AGENT_JUDGE_TIMEOUT:-120}")
    fi

    local out
    out="$(printf '%s\n' "$prompt" | judge_env_clean ${runner[@]+"${runner[@]}"} \
        claude -p --output-format text --model "$model" 2>/dev/null)" || return 2
    printf '%s\n' "$out" | emit_verdict || return 2
    return 0
}

case "$VERB" in
    cost) ;;
    judge)
        do_judge "${2:-}" "${3:-}"
        exit $?
        ;;
    *)
        printf 'claude-code adapter: unknown verb %s (supported: cost, judge)\n' "$VERB" >&2
        exit 2
        ;;
esac

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
CLAUDE_PROJECTS="${CLAUDE_PROJECTS_DIR:-${HOME}/.claude/projects}"

encode_path() {
    # Replace every `/` and `.` with `-`, matching Claude Code's project-dir convention.
    printf '%s' "$1" | sed -E 's#[/.]#-#g'
}

TRANSCRIPT="${CLAUDE_TRANSCRIPT_PATH:-}"

# Deterministic resolution (issue #325): Claude Code exports
# CLAUDE_CODE_SESSION_ID into the hook environment, and the active session's
# transcript is `<projects>/<encoded-cwd>/<session-id>.jsonl`. Naming the file
# directly removes the newest-mtime guess that, in the same commit, could grab a
# *throwaway* transcript (e.g. one written by a headless shell-out) instead of
# the real session — recording a near-zero cost row for a long session. Probe
# both the repo-root and the cwd encodings before falling back.
if [[ -z "$TRANSCRIPT" && -n "${CLAUDE_CODE_SESSION_ID:-}" ]]; then
    for candidate in "$REPO_ROOT" "$PWD"; do
        f="$CLAUDE_PROJECTS/$(encode_path "$candidate")/${CLAUDE_CODE_SESSION_ID}.jsonl"
        if [[ -f "$f" ]]; then
            TRANSCRIPT="$f"
            break
        fi
    done
    # Last resort under a known session id: the encoded-cwd dir didn't match
    # (cross-worktree commit), so find the file named for this exact session
    # anywhere under CLAUDE_PROJECTS. Still identity-pinned — never an mtime guess.
    if [[ -z "$TRANSCRIPT" && -d "$CLAUDE_PROJECTS" ]]; then
        f="$(find "$CLAUDE_PROJECTS" -type f -name "${CLAUDE_CODE_SESSION_ID}.jsonl" 2>/dev/null | head -n1)"
        [[ -n "$f" && -f "$f" ]] && TRANSCRIPT="$f"
    fi
fi

if [[ -z "$TRANSCRIPT" ]]; then
    for candidate in "$REPO_ROOT" "$PWD"; do
        dir="$CLAUDE_PROJECTS/$(encode_path "$candidate")"
        if [[ -d "$dir" ]]; then
            TRANSCRIPT="$(ls -t "$dir"/*.jsonl 2>/dev/null | head -n1)"
            [[ -n "$TRANSCRIPT" ]] && break
        fi
    done
fi

# Cross-worktree fallback: the cwd-encoded lookup above misses when the
# user starts a Claude session in worktree A and runs `git commit` from
# worktree B (different `git rev-parse --show-toplevel`, so a different
# encoded project dir) AND no CLAUDE_CODE_SESSION_ID is exported. When
# CLAUDECODE=1 confirms a live session, the active transcript is being
# written to *now* — so the most recently modified `.jsonl` anywhere under
# CLAUDE_PROJECTS is almost always it. A 10-minute mtime window keeps
# long-closed sessions out. If multiple Claude sessions are running
# concurrently, set CLAUDE_TRANSCRIPT_PATH explicitly to disambiguate.
if [[ -z "$TRANSCRIPT" && "${CLAUDECODE:-}" == "1" && -d "$CLAUDE_PROJECTS" ]]; then
    candidate=""
    while IFS= read -r f; do
        if [[ -z "$candidate" || "$f" -nt "$candidate" ]]; then
            candidate="$f"
        fi
    done < <(find "$CLAUDE_PROJECTS" -type f -name '*.jsonl' -mmin -10 2>/dev/null)
    [[ -n "$candidate" && -f "$candidate" ]] && TRANSCRIPT="$candidate"
fi

[[ -z "$TRANSCRIPT" || ! -f "$TRANSCRIPT" ]] && exit 2

# JSONL extraction in POSIX awk (issue #355 — no python on the commit path).
# Conservative, per-line, key-anchored substring lookups; a malformed line
# simply contributes nothing. The four usage fields are reported separately so
# the ledger can split them:
#   input_tokens                  → new tokens this turn (not from cache)
#   cache_creation_input_tokens   → tokens written to the prompt cache
#   cache_read_input_tokens       → tokens re-read from the prompt cache
#   output_tokens                 → model output
# Each lookup anchors on the opening quote of its key, so `"input_tokens":`
# cannot match inside `"cache_read_input_tokens":`.
awk '
function jstr(line, key,   p, rest, e) {
    p = index(line, "\"" key "\":\"")
    if (p == 0) { return "" }
    rest = substr(line, p + length(key) + 4)
    e = index(rest, "\"")
    if (e == 0) { return "" }
    return substr(rest, 1, e - 1)
}
function jnum(line, key,   p, rest, i, ch, out) {
    p = index(line, "\"" key "\":")
    if (p == 0) { return -1 }
    rest = substr(line, p + length(key) + 3)
    while (substr(rest, 1, 1) == " ") { rest = substr(rest, 2) }
    out = ""
    for (i = 1; i <= length(rest); i++) {
        ch = substr(rest, i, 1)
        if (ch ~ /[0-9.eE+-]/) { out = out ch } else { break }
    }
    if (out == "") { return -1 }
    return out + 0
}
{
    if (sid == "") { v = jstr($0, "sessionId"); if (v != "") { sid = v } }
    if ($0 ~ /"type"[ ]*:[ ]*"assistant"/ || $0 ~ /"role"[ ]*:[ ]*"assistant"/) {
        m = jstr($0, "model")
        if (m != "" && m != "<synthetic>") { model = m }
    }
    if (index($0, "\"usage\"") > 0) {
        v = jnum($0, "input_tokens");                if (v >= 0) { t_in += v }
        v = jnum($0, "cache_creation_input_tokens"); if (v >= 0) { t_cc += v }
        v = jnum($0, "cache_read_input_tokens");     if (v >= 0) { t_cr += v }
        v = jnum($0, "output_tokens");               if (v >= 0) { t_out += v }
    }
    v = jnum($0, "costUSD")
    if (v < 0) { v = jnum($0, "total_cost_usd") }
    if (v >= 0) { cost += v; have_cost = 1 }
}
END {
    if (sid == "") { exit 2 }
    if (model == "") { model = "unknown" }
    c = have_cost ? sprintf("%.4f", cost) : "-"
    printf "%s %d %d %d %d %s %s\n", sid, t_in, t_cc, t_cr, t_out, model, c
}
' "$TRANSCRIPT"
