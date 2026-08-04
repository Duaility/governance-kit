#!/usr/bin/env bash
# agent-token-accounting eval — identity at commit, measurement at rest (#355).
#
# Every fixture is about ONE of the two halves: identity (the commit path
# records who is committing, from the environment or a fresh identity file, and
# never from a guess) or measurement (numbers arrive off the commit path, via an
# adapter's `resolve` verb writing the kit-owned snapshot sidecar, and fold into
# the row on the next commit). Adapters are STUBS created inside the fixture and
# reached through GOVERNANCE_RUNTIMES_DIR, so this eval pins the directive's
# contract with the registry rather than any particular shipped adapter.
set -u
EVAL_ID="agent-token-accounting"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
[[ -f "$ROOT/kit/assets/packs/lib/eval-lib.sh" ]] || { echo "eval: ROOT misresolved to $ROOT — refusing to run with broken eval-lib.sh path" >&2; exit 1; }
source "$ROOT/kit/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/packs/audit"
CHECK=".governance/packs/governance-kit/audit/directives/$EVAL_ID/check.sh"

fixture_init
install_directive "$PACK_DIR" "$EVAL_ID"

git add -A .governance
git commit --quiet --no-verify -m "feat(governance): install directive (#1)"

DIR="$PWD/.governance/packs/governance-kit/audit/directives/$EVAL_ID"
LIB="$DIR/lib"
HOOKS="$DIR/hooks"
GITD="$(git rev-parse --absolute-git-dir)"

# The directive's own bash stack, sourced straight into the eval so fixtures
# read and write through exactly the code the hook uses (no python anywhere).
# shellcheck disable=SC1090
source "$LIB/receipt.sh"
# shellcheck disable=SC1090
source "$LIB/costs.sh"
# shellcheck disable=SC1090
source "$LIB/validate.sh"
# shellcheck disable=SC1090
source "$LIB/runtime.sh"
# shellcheck disable=SC1090
source "$LIB/resolve.sh"

pass_assert() {  # pass_assert <already-evaluated-rc> <label>
    eval_assertions=$(( eval_assertions + 1 ))
    if [[ "$1" -eq 0 ]]; then
        printf '    ✓ %s — %s\n' "$EVAL_ID" "$2"
    else
        printf '    ✗ %s — %s\n' "$EVAL_ID" "$2" >&2
        eval_failures=$(( eval_failures + 1 ))
    fi
}

# ── Stub adapter registry ─────────────────────────────────────
# `resolve` answers from STUB_RESOLVE_OUT (or exits 2 — "cannot resolve, record
# nothing"); the manual stub passes the environment through, exactly as the
# shipped manual seam does.
STUBS="$PWD/stub-runtimes"
mkdir -p "$STUBS"
for _h in claude-code codex pi cursor-agent opencode grok; do
    cat > "$STUBS/$_h.sh" <<'EOF'
#!/usr/bin/env bash
set -u
case "${1:-}" in
    resolve)
        [ -n "${STUB_RESOLVE_OUT:-}" ] || exit 2
        printf '%s\n' "$STUB_RESOLVE_OUT"
        ;;
    *) exit 2 ;;
esac
EOF
done
cat > "$STUBS/manual.sh" <<'EOF'
#!/usr/bin/env bash
set -u
case "${1:-}" in
    resolve)
        [ -n "${AGENT_CUM_INPUT:-}" ] || exit 2
        printf '%s %s %s %s %s %s manual\n' \
            "$AGENT_CUM_INPUT" "${AGENT_CUM_CACHE_CREATE:-0}" \
            "${AGENT_CUM_CACHE_READ:-0}" "${AGENT_CUM_OUTPUT:-0}" \
            "${AGENT_MODEL:--}" "${AGENT_COST_USD:--}"
        ;;
    *) exit 2 ;;
esac
EOF
chmod +x "$STUBS"/*.sh
export GOVERNANCE_RUNTIMES_DIR="$STUBS"

clear_env() {
    unset AGENT_NAME AGENT_SESSION_ID AGENT_MODEL AGENT_COST_USD AGENT_ISSUE \
          AGENT_CUM_INPUT AGENT_CUM_CACHE_CREATE AGENT_CUM_CACHE_READ \
          AGENT_CUM_OUTPUT STUB_RESOLVE_OUT \
          CLAUDECODE CLAUDE_CODE_SESSION_ID CLAUDE_TRANSCRIPT_PATH \
          CODEX_THREAD_ID CODEX_TRANSCRIPT_PATH \
          PI_CODING_AGENT PI_SESSION_ID PI_SESSION_FILE \
          CURSOR_AGENT OPENCODE OPENCODE_SERVER OPENCODE_SESSION_ID \
          2>/dev/null || true
}
clear_identity() { rm -f "$GITD/governance/session-identity"; }
clear_sidecars() { rm -rf "$GITD/governance/costs"; }
clear_runtime() { clear_env; clear_identity; clear_sidecars; }

write_identity() {  # <harness> <session> <declared> <epoch>
    mkdir -p "$GITD/governance"
    {
        printf 'harness=%s\n' "$1"
        printf 'session=%s\n' "$2"
        printf 'declared=%s\n' "$3"
        printf 'epoch=%s\n' "$4"
    } > "$GITD/governance/session-identity"
}

write_snapshot() {  # <harness> <session> <in> <cc> <cr> <out> <model> <cost> <source> [epoch]
    local f
    f="$(sidecar_file "$1" "$2")"
    mkdir -p "$(dirname "$f")"
    printf 'v1 %s %s %s %s %s %s %s %s\n' \
        "${10:-$(date +%s)}" "$3" "$4" "$5" "$6" "$7" "$8" "$9" >> "$f"
}

reset_receipts() {
    rm -rf receipts
    git add -A receipts 2>/dev/null || true
    git commit --quiet --no-verify -m "chore: reset receipts" >/dev/null 2>&1 || true
}

run_hook() {  # run_hook <issue> — the pre-commit stamp & fold
    AGENT_ISSUE="$1" bash "$HOOKS/pre-commit.sh" >/dev/null 2>&1
}

row_of() {  # row_of <receipt> <harness> <session>
    costs_row "$1" "$2" "$3" | head -n 1
}

clear_runtime

# ══════════════════════════════════════════════════════════════
# (a) Identity detection — the whole ladder, environment first.
# ══════════════════════════════════════════════════════════════
detect_as() {  # detect_as [VAR=VAL ...] → "<runtime> <session>" | "none"
    (
        clear_env
        while [[ $# -gt 0 ]]; do export "${1?}"; shift; done
        if detect_runtime_identity; then
            printf '%s %s\n' "$RUNTIME" "$SESSION_ID"
        else
            printf 'none\n'
        fi
    )
}

expect_identity() {  # expect_identity <expected> <label> [VAR=VAL ...]
    local want="$1" label="$2" got
    shift 2
    got="$(detect_as "$@")"
    if [[ "$got" == "$want" ]]; then pass_assert 0 "$label"; else pass_assert 1 "$label (got '$got', want '$want')"; fi
}

expect_identity "manual m-1"        "AGENT_NAME → manual runtime"        AGENT_NAME=me AGENT_SESSION_ID=m-1
expect_identity "manual manual"     "AGENT_NAME with no session id"      AGENT_NAME=me
expect_identity "claude-code cc-1"  "CLAUDECODE + CLAUDE_CODE_SESSION_ID" CLAUDECODE=1 CLAUDE_CODE_SESSION_ID=cc-1
expect_identity "claude-code -"     "CLAUDECODE alone → session '-'"     CLAUDECODE=1
expect_identity "codex cx-1"        "CODEX_THREAD_ID → codex"            CODEX_THREAD_ID=cx-1
expect_identity "codex -"           "CODEX_TRANSCRIPT_PATH alone"        CODEX_TRANSCRIPT_PATH=/tmp/nope.jsonl
expect_identity "pi pi-1"           "PI_CODING_AGENT + PI_SESSION_ID"    PI_CODING_AGENT=true PI_SESSION_ID=pi-1
expect_identity "pi pi-2"           "PI_SESSION_ID alone"                PI_SESSION_ID=pi-2
expect_identity "cursor-agent -"    "CURSOR_AGENT → cursor-agent"        CURSOR_AGENT=1
expect_identity "opencode oc-1"     "OPENCODE + OPENCODE_SESSION_ID"     OPENCODE=1 OPENCODE_SESSION_ID=oc-1
expect_identity "opencode -"        "OPENCODE_SERVER alone"              OPENCODE_SERVER=http://127.0.0.1:4096
expect_identity "none"              "no signal → no runtime (human commit)"

# The identity-file seam: how a harness that exports nothing (grok, wired via a
# SessionStart hook) still gets identified — and how a stale file expires.
write_identity grok grok-sess-1 "" "$(date +%s)"
expect_identity "grok grok-sess-1"  "fresh identity file identifies a silent harness"
write_identity grok grok-sess-1 "" "$(( $(date +%s) - 200000 ))"
expect_identity "none"              "identity file older than the trust window is ignored"
# Env identity wins, but the file may fill a session the env left blank.
write_identity claude-code cc-file-1 "" "$(date +%s)"
expect_identity "claude-code cc-file-1" "identity file fills a blank session for the same harness" CLAUDECODE=1
expect_identity "claude-code cc-env-1"  "env session beats the identity file" CLAUDECODE=1 CLAUDE_CODE_SESSION_ID=cc-env-1
write_identity codex other-sess "" "$(date +%s)"
expect_identity "claude-code -"     "identity file for another harness never fills the session" CLAUDECODE=1
clear_runtime

# ══════════════════════════════════════════════════════════════
# The stamp: a v6 row carrying identity, with no measurement yet.
# ══════════════════════════════════════════════════════════════
reset_receipts
clear_runtime
export CLAUDECODE=1 CLAUDE_CODE_SESSION_ID=stamp-1
run_hook '#60'
ROW="$(row_of receipts/issue-60.md claude-code stamp-1)"
rc=0
grep -q '^### Costs$' receipts/issue-60.md || rc=1
grep -q "^$COSTS_HEADER\$" receipts/issue-60.md || rc=1
[[ "$ROW" == *"| claude-code | stamp-1 | - | - | - | - | - | - | unresolved |" ]] || rc=1
[[ "$(printf '%s\n' "$ROW" | awk -F'[|]' '{print NF - 2}')" == "10" ]] || rc=1
costs_validate_dir receipts >/dev/null || rc=1
pass_assert $rc "an unmeasured session stamps an honest identity-only row ($ROW)"

# Mode A accepts it: identity truth, never number equality.
printf 'feat: stamped agent commit (#60)\n' > /tmp/gk-msg-stamped
EVAL_LABEL="$EVAL_ID mode-a-identity-row-present" expect_pass "$CHECK" /tmp/gk-msg-stamped

# A second commit from the same session updates the row in place — one row per
# session per issue, not one per commit.
run_hook '#60'
rc=0
[[ "$(costs_row receipts/issue-60.md claude-code stamp-1 | wc -l | tr -d ' ')" == "1" ]] || rc=1
costs_validate_dir receipts >/dev/null || rc=1
pass_assert $rc "a second commit from the same session updates the row, never appends"
clear_runtime

# ══════════════════════════════════════════════════════════════
# (b) Fold from the sidecar — measurement taken at rest lands in the row.
# ══════════════════════════════════════════════════════════════
reset_receipts
clear_runtime
write_snapshot claude-code fold-1 100 20 300 40 stub-sonnet 1.2345 session-file
export CLAUDECODE=1 CLAUDE_CODE_SESSION_ID=fold-1
run_hook '#61'
ROW="$(row_of receipts/issue-61.md claude-code fold-1)"
rc=0
[[ "$ROW" == *"| claude-code | fold-1 | stub-sonnet | 100 | 20 | 300 | 40 | 1.2345 | session-file |" ]] || rc=1
costs_validate_dir receipts >/dev/null || rc=1
pass_assert $rc "the sidecar's snapshot folds into the row verbatim ($ROW)"

# Source preference: a same-epoch `session-file` reading beats a `harness-feed`
# push (which may carry cost only), but an OLDER one does not.
clear_sidecars
write_snapshot claude-code pref-1 0 0 0 0 stub-sonnet 0.90 harness-feed 1000
write_snapshot claude-code pref-1 5 6 7 8 stub-sonnet 0.80 session-file 1000
rc=0
[[ "$(costs_fold_snapshot "$(sidecar_file claude-code pref-1)")" == "5 6 7 8 stub-sonnet 0.80 session-file" ]] || rc=1
pass_assert $rc "a same-epoch session-file reading wins the fold over a harness-feed push"
clear_sidecars
write_snapshot claude-code pref-2 5 6 7 8 stub-sonnet 0.80 session-file 1000
write_snapshot claude-code pref-2 0 0 0 0 stub-sonnet 0.95 harness-feed 2000
rc=0
[[ "$(costs_fold_snapshot "$(sidecar_file claude-code pref-2)")" == "0 0 0 0 stub-sonnet 0.95 harness-feed" ]] || rc=1
pass_assert $rc "a strictly newer harness-feed push still wins over an older file reading"

# Self-healing: a LATER session's commit repairs an EARLIER session's tail.
clear_sidecars
reset_receipts
write_snapshot claude-code old-sess 10 0 0 5 stub-sonnet 0.10 session-file
export CLAUDECODE=1 CLAUDE_CODE_SESSION_ID=old-sess
run_hook '#61'
clear_env
write_snapshot claude-code old-sess 999 0 0 111 stub-sonnet 9.99 session-file
export CLAUDECODE=1 CLAUDE_CODE_SESSION_ID=new-sess
run_hook '#61'
ROW="$(row_of receipts/issue-61.md claude-code old-sess)"
rc=0
[[ "$ROW" == *"| 999 | 0 | 0 | 111 | 9.99 | session-file |" ]] || rc=1
[[ -n "$(row_of receipts/issue-61.md claude-code new-sess)" ]] || rc=1
costs_validate_dir receipts >/dev/null || rc=1
pass_assert $rc "a later session's commit folds the earlier session's newer total ($ROW)"
clear_runtime

# ══════════════════════════════════════════════════════════════
# (f) The resolve sweep — the only thing that reads a harness surface.
# ══════════════════════════════════════════════════════════════
reset_receipts
clear_runtime
write_identity claude-code sweep-1 "" "$(date +%s)"
export STUB_RESOLVE_OUT="11 22 33 44 stub-opus 2.50 session-file"
bash "$HOOKS/post-commit.sh"
post_rc=$?
SIDE="$(sidecar_file claude-code sweep-1)"
rc=0
[[ $post_rc -eq 0 ]] || rc=1
[[ -f "$SIDE" ]] || rc=1
grep -q ' 11 22 33 44 stub-opus 2.50 session-file$' "$SIDE" 2>/dev/null || rc=1
pass_assert $rc "post-commit resolve sweep appends the adapter's snapshot"

bash "$HOOKS/post-commit.sh"
rc=0
[[ "$(wc -l < "$SIDE" | tr -d ' ')" == "1" ]] || rc=1
pass_assert $rc "an unchanged snapshot is not re-appended (append-only, not append-always)"

export STUB_RESOLVE_OUT="99 22 33 44 stub-opus 3.50 session-file"
bash "$HOOKS/pre-push.sh" origin https://example.invalid/repo.git </dev/null >/dev/null 2>&1
pre_push_rc=$?
rc=0
[[ $pre_push_rc -eq 0 ]] || rc=1
[[ "$(wc -l < "$SIDE" | tr -d ' ')" == "2" ]] || rc=1
pass_assert $rc "pre-push sweeps again and never blocks the push"

# An adapter that cannot resolve records NOTHING — no guess, no partial row.
unset STUB_RESOLVE_OUT
clear_sidecars
write_identity cursor-agent cur-1 "" "$(date +%s)"
bash "$HOOKS/post-commit.sh"
rc=0
[[ -f "$(sidecar_file cursor-agent cur-1)" ]] && rc=1
pass_assert $rc "an adapter that exits 2 leaves no snapshot behind"

# A malformed adapter line is rejected outright rather than written.
export STUB_RESOLVE_OUT="10 20 nonsense 40 m - session-file"
bash "$HOOKS/post-commit.sh"
rc=0
[[ -f "$(sidecar_file cursor-agent cur-1)" ]] && rc=1
pass_assert $rc "a malformed adapter reading is refused, not recorded"

# The session the ENVIRONMENT announces is a candidate in its own right. Without
# it a harness whose emitter is not wired would never get a first snapshot —
# nothing would exist to enumerate.
clear_runtime
export CLAUDECODE=1 CLAUDE_CODE_SESSION_ID=env-sweep-1
export STUB_RESOLVE_OUT="1 2 3 4 stub-haiku - session-file"
bash "$HOOKS/post-commit.sh"
rc=0
[[ -f "$(sidecar_file claude-code env-sweep-1)" ]] || rc=1
pass_assert $rc "the environment-announced session is swept with no identity file present"
clear_runtime

# ══════════════════════════════════════════════════════════════
# (e) Manual passthrough — a human-supplied number, labelled as such.
# ══════════════════════════════════════════════════════════════
reset_receipts
clear_runtime
export AGENT_NAME=eval-human AGENT_SESSION_ID=man-1 \
       AGENT_CUM_INPUT=1000 AGENT_CUM_CACHE_CREATE=10 AGENT_CUM_CACHE_READ=20 \
       AGENT_CUM_OUTPUT=500 AGENT_MODEL=some-model-9 AGENT_COST_USD=0.4200
write_identity manual man-1 "" "$(date +%s)"
bash "$HOOKS/post-commit.sh"
run_hook '#62'
ROW="$(row_of receipts/issue-62.md manual man-1)"
rc=0
[[ "$ROW" == *"| manual | man-1 | some-model-9 | 1000 | 10 | 20 | 500 | 0.4200 | manual |" ]] || rc=1
costs_validate_dir receipts >/dev/null || rc=1
pass_assert $rc "the manual seam carries its own numbers through, labelled manual ($ROW)"
clear_runtime

# ══════════════════════════════════════════════════════════════
# (g) No mtime guessing — two transcripts, no identity, no numbers.
# ══════════════════════════════════════════════════════════════
reset_receipts
clear_runtime
mkdir -p fixtures
printf '{"sessionId":"ghost-a"}\n' > fixtures/a.jsonl
sleep 1
printf '{"sessionId":"ghost-b"}\n' > fixtures/b.jsonl
export CLAUDECODE=1
run_hook '#64'
ROW="$(row_of receipts/issue-64.md claude-code -)"
rc=0
[[ "$ROW" == *"| claude-code | - | - | - | - | - | - | - | unresolved |" ]] || rc=1
grep -q 'ghost-' receipts/issue-64.md && rc=1
costs_validate_dir receipts >/dev/null || rc=1
pass_assert $rc "with no session id the row stays unresolved — no newest-file guess ($ROW)"
rm -rf fixtures
clear_runtime

rc=0
if grep -rnE '(ls[[:space:]]+-[A-Za-z]*t|[[:space:]]-mmin[[:space:]]|[[:space:]]-newer[[:space:]])' \
    "$DIR/check.sh" "$DIR/hooks" "$LIB"/*.sh 2>/dev/null | grep -q .; then
    rc=1
fi
pass_assert $rc "no mtime / newest-file selection survives anywhere in the directive"

# ══════════════════════════════════════════════════════════════
# (c) v6 validation — shape only, and it must be strict about shape.
# ══════════════════════════════════════════════════════════════
bad_receipt() {  # bad_receipt <issue> <row-line...> — sole receipt in the dir
    local issue="$1"
    shift
    rm -rf receipts
    mkdir -p receipts
    {
        printf '# Receipt\n\n## Accounting\n\n### Costs\n\n'
        printf '%s\n' "$COSTS_HEADER" "$COSTS_SEPARATOR" "$@"
    } > "receipts/issue-$issue.md"
}

reset_receipts
bad_receipt 70 "| 2026-08-04 | claude-code | s70 | m | 10 | 0 | 0 | 5 | 0.10 | session-file |"
costs_validate_dir receipts >/dev/null 2>&1
pass_assert $? "a well-formed v6 row validates"

bad_receipt 71 "| 2026-08-04 | claude-code | s71 | m | 10 | 0 | 0 | 5 | 0.10 | telepathy |"
OUT="$(costs_validate_dir receipts 2>&1)"; VRC=$?
rc=0; [[ $VRC -ne 0 ]] || rc=1
printf '%s' "$OUT" | grep -q "unknown source" || rc=1
pass_assert $rc "a source outside the closed set is rejected"

bad_receipt 72 \
    "| 2026-08-04 | claude-code | dupe | m | 10 | 0 | 0 | 5 | - | session-file |" \
    "| 2026-08-05 | claude-code | dupe | m | 20 | 0 | 0 | 6 | - | session-file |"
OUT="$(costs_validate_dir receipts 2>&1)"; VRC=$?
rc=0; [[ $VRC -ne 0 ]] || rc=1
printf '%s' "$OUT" | grep -q "more than one Costs row" || rc=1
pass_assert $rc "two rows for one session in one receipt are rejected"

bad_receipt 73 "| 2026-08-04 | claude-code | s73 | m | 10 | oops | 0 | 5 | - | session-file |"
costs_validate_dir receipts >/dev/null 2>&1; VRC=$?
rc=0; [[ $VRC -ne 0 ]] || rc=1
pass_assert $rc "a token cell that is neither an integer nor - is rejected"

bad_receipt 74 "| yesterday | claude-code | s74 | m | 10 | 0 | 0 | 5 | - | session-file |"
costs_validate_dir receipts >/dev/null 2>&1; VRC=$?
rc=0; [[ $VRC -ne 0 ]] || rc=1
pass_assert $rc "a malformed date cell is rejected"

bad_receipt 75 "| 2026-08-04 | claude-code | s75 | m | 10 | 0 | 0 | 5 | free | session-file |"
costs_validate_dir receipts >/dev/null 2>&1; VRC=$?
rc=0; [[ $VRC -ne 0 ]] || rc=1
pass_assert $rc "a non-decimal cost-usd is rejected"

bad_receipt 76 "| 2026-08-04 | claude-code | s76 | m | 10 | 0 | 5 | - | session-file |"
OUT="$(costs_validate_dir receipts 2>&1)"; VRC=$?
rc=0; [[ $VRC -ne 0 ]] || rc=1
printf '%s' "$OUT" | grep -q "expected 10 (v6" || rc=1
pass_assert $rc "a row with the wrong cell count is rejected"
reset_receipts

# The whole check fails loudly on a malformed row, in both modes.
bad_receipt 77 "| 2026-08-04 | claude-code | s77 | m | 10 | 0 | 0 | 5 | 0.1 | telepathy |"
printf 'feat: malformed cost row (#77)\n' > /tmp/gk-msg-badrow
EVAL_LABEL="$EVAL_ID malformed-row-mode-b" expect_fail "$CHECK"
EVAL_LABEL="$EVAL_ID malformed-row-mode-a" expect_fail "$CHECK" /tmp/gk-msg-badrow
reset_receipts

# Legacy rows are tolerated: a receipt written under v5 keeps passing.
mkdir -p receipts
cat > receipts/issue-78.md <<'EOF'
# Receipt

## Accounting

### Costs

| cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | cum-input | cum-cache-create | cum-cache-read | cum-output | source | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ck-v5-1 | claude-code | v5-sess | #78 | claude-sonnet-4-5 | 1000 | 0 | 0 | 500 | 1500 | | 1000 | 0 | 0 | 500 | claude-code | legacy v5 row |
EOF
costs_validate_dir receipts >/dev/null 2>&1
pass_assert $? "legacy v5 / v4 / v3 rows are structurally tolerated, not re-judged"
reset_receipts

# ══════════════════════════════════════════════════════════════
# (d) Mode B allows unresolved; Mode A demands identity, not numbers.
# ══════════════════════════════════════════════════════════════
reset_receipts
clear_runtime
bad_receipt 80 "| 2026-08-04 | grok | g-1 | - | - | - | - | - | - | unresolved |"
git add -A receipts
EVAL_LABEL="$EVAL_ID mode-b-allows-unresolved" expect_pass "$CHECK"
reset_receipts

# No runtime → Mode A no-ops (a human / plain-git commit).
clear_runtime
printf 'feat: human commit (#81)\n' > /tmp/gk-msg-human
EVAL_LABEL="$EVAL_ID no-runtime-no-op" expect_pass "$CHECK" /tmp/gk-msg-human

# Runtime detected but no row staged → the hook did not run.
export CLAUDECODE=1 CLAUDE_CODE_SESSION_ID=missing-1
printf 'feat: hook was skipped (#82)\n' > /tmp/gk-msg-norow
EVAL_LABEL="$EVAL_ID mode-a-missing-row-fails" expect_fail "$CHECK" /tmp/gk-msg-norow

# A row for a DIFFERENT session does not satisfy this session's identity.
bad_receipt 82 "| 2026-08-04 | claude-code | someone-else | - | - | - | - | - | - | unresolved |"
git add -A receipts
EVAL_LABEL="$EVAL_ID mode-a-other-session-row-fails" expect_fail "$CHECK" /tmp/gk-msg-norow

# The body waiver bypasses the identity check.
{ printf 'feat: out-of-hook commit (#82)\n\n'; printf 'governance: allow-agent-token-accounting committed outside the runtime hook for a one-off\n'; } > /tmp/gk-msg-waiver
EVAL_LABEL="$EVAL_ID identity-waiver" expect_pass "$CHECK" /tmp/gk-msg-waiver

# Revert commits are exempt.
printf 'Revert "feat: something (#83)"\n' > /tmp/gk-msg-revert
EVAL_LABEL="$EVAL_ID revert-exempt" expect_pass "$CHECK" /tmp/gk-msg-revert
reset_receipts
clear_runtime

# ══════════════════════════════════════════════════════════════
# Hardening: nothing on any path here is python, and the retired
# endpoint / checkpoint machinery is gone for good.
# ══════════════════════════════════════════════════════════════
rc=0
if grep -rnE '(^|[^[:alnum:]_])python3?[[:space:]]' \
    "$DIR/check.sh" "$DIR/hooks" "$LIB"/*.sh 2>/dev/null \
    | grep -vE ':[[:space:]]*#' | grep -q .; then
    rc=1
fi
[[ -n "$(find "$DIR" -name '*.py' 2>/dev/null)" ]] && rc=1
pass_assert $rc "no python invocation and no python file remains in the directive"

rc=0
if grep -rniE 'governance-token-(endpoint|checkpoint)|endpoint_write|checkpoint_set' \
    "$DIR/check.sh" "$DIR/hooks" "$LIB"/*.sh 2>/dev/null | grep -q .; then
    rc=1
fi
pass_assert $rc "the endpoint / checkpoint machinery is fully removed"

eval_done
