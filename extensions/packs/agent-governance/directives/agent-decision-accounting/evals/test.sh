#!/usr/bin/env bash
set -u
EVAL_ID="agent-decision-accounting"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../../.." && pwd)"
source "$ROOT/governance/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/extensions/packs/agent-governance"
CHECK="tests/governance/directives/$EVAL_ID/check.sh"

command -v python3 >/dev/null 2>&1 || {
    echo "    ⊘ skipped — python3 not available"
    exit 0
}

fixture_init
install_directive "$PACK_DIR" "$EVAL_ID"

# Seed DECISIONS.md with three rows: one overrode, one reframed, one agreed.
cat > DECISIONS.md <<'EOF'
<!-- DECISIONS.md — append-only human-vs-agent decision ledger -->
<!-- governance: allow-plan-captured -->

# DECISIONS.md

## Ledger

| decision-key | agent | session | issue | phase | question | lean | choice | diverged | cost-key | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| codex-abc-d001 | codex | abc123 | #42 | plan-review | Scope rewrite to quickstart? | yes | no | overrode |  | wanted philosophy framing |
| codex-abc-d002 | codex | abc123 | #42 | pr-review | Wrong question? | n/a | n/a | reframed |  | replaced by d003 |
| codex-abc-d003 | codex | abc123 | #42 | scoping | Include tests? | yes | yes | agreed |  |  |
EOF

# pass — trailer references two non-agreed rows, counter matches.
stage_all
commit_quiet "feat: baseline ledger (#42)"
MSG_FILE="$(mktemp)"
cat > "$MSG_FILE" <<'EOF'
feat: thing (#42)

body

Decision-Key: codex-abc-d001,codex-abc-d002,codex-abc-d003
Decision-Diverged: 2/3
EOF
EVAL_LABEL="$EVAL_ID trailer-consistent" expect_pass "$CHECK" "$MSG_FILE"

# pass — commit with no Decision-Key trailer is exempt.
cat > "$MSG_FILE" <<'EOF'
feat: plain (#42)

no decisions recorded on this commit.
EOF
EVAL_LABEL="$EVAL_ID no-trailer" expect_pass "$CHECK" "$MSG_FILE"

# fail — Decision-Diverged numerator is wrong.
cat > "$MSG_FILE" <<'EOF'
feat: thing (#42)

Decision-Key: codex-abc-d001,codex-abc-d002,codex-abc-d003
Decision-Diverged: 0/3
EOF
EVAL_LABEL="$EVAL_ID bad-numerator" expect_fail "$CHECK" "$MSG_FILE"

# fail — Decision-Key references a row that doesn't exist in DECISIONS.md.
cat > "$MSG_FILE" <<'EOF'
feat: thing (#42)

Decision-Key: ghost-key
Decision-Diverged: 0/1
EOF
EVAL_LABEL="$EVAL_ID missing-key" expect_fail "$CHECK" "$MSG_FILE"

# fail — only one of the required trailer pair present.
cat > "$MSG_FILE" <<'EOF'
feat: thing (#42)

Decision-Diverged: 1/1
EOF
EVAL_LABEL="$EVAL_ID counter-without-key" expect_fail "$CHECK" "$MSG_FILE"

# fail — DECISIONS.md has a bad `diverged` value.
cat >> DECISIONS.md <<'EOF'
| codex-abc-d004 | codex | abc123 | #42 | scoping | q | a | a | maybe |  |  |
EOF
stage_all
commit_quiet "chore: corrupt ledger (#42)"
cat > "$MSG_FILE" <<'EOF'
feat: clean commit (#42)
EOF
EVAL_LABEL="$EVAL_ID bad-vocab" expect_fail "$CHECK" "$MSG_FILE"

# Reset DECISIONS.md to the clean baseline for the remaining ledger-shape
# assertions — each case seeds its own bad row.
reset_ledger() {
    cat > DECISIONS.md <<'EOF'
# DECISIONS.md

## Ledger

| decision-key | agent | session | issue | phase | question | lean | choice | diverged | cost-key | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| codex-abc-d001 | codex | abc123 | #42 | plan-review | q | yes | no | overrode |  |  |
EOF
}

# fail — DECISIONS.md has a bad `phase` value.
reset_ledger
cat >> DECISIONS.md <<'EOF'
| codex-abc-bp | codex | abc123 | #42 | brainstorm | q | a | a | agreed |  |  |
EOF
stage_all
commit_quiet "chore: bad phase (#42)"
EVAL_LABEL="$EVAL_ID bad-phase" expect_fail "$CHECK" "$MSG_FILE"

# fail — duplicate decision-key (append-only violation).
reset_ledger
cat >> DECISIONS.md <<'EOF'
| codex-abc-d001 | codex | abc123 | #42 | pr-review | q2 | a | a | agreed |  |  |
EOF
stage_all
commit_quiet "chore: duplicate key (#42)"
EVAL_LABEL="$EVAL_ID duplicate-key" expect_fail "$CHECK" "$MSG_FILE"

# fail — row has the wrong column count (10 cells instead of 11).
reset_ledger
cat >> DECISIONS.md <<'EOF'
| codex-abc-sh | codex | abc123 | #42 | scoping | q | a | a | agreed |  |
EOF
stage_all
commit_quiet "chore: wrong column count (#42)"
EVAL_LABEL="$EVAL_ID bad-column-count" expect_fail "$CHECK" "$MSG_FILE"

# fail — issue cell is not shaped like '#N'.
reset_ledger
cat >> DECISIONS.md <<'EOF'
| codex-abc-is | codex | abc123 | PROJ-42 | scoping | q | a | a | agreed |  |  |
EOF
stage_all
commit_quiet "chore: bad issue format (#42)"
EVAL_LABEL="$EVAL_ID bad-issue-format" expect_fail "$CHECK" "$MSG_FILE"

# fail — DECISIONS row references a cost-key that does not exist in COSTS.md.
reset_ledger
cat >> DECISIONS.md <<'EOF'
| codex-abc-ck | codex | abc123 | #42 | scoping | q | a | a | overrode | ghost-cost-key |  |
EOF
cat > COSTS.md <<'EOF'
# COSTS.md
| cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| real-cost-key | codex | abc123 | #42 | gpt-5 | 100 | 0 | 0 | 50 | 150 | 0.0015 |  |
EOF
stage_all
commit_quiet "chore: dangling cost-key (#42)"
EVAL_LABEL="$EVAL_ID dangling-cost-key" expect_fail "$CHECK" "$MSG_FILE"

# pass — DECISIONS row's cost-key resolves to a real COSTS.md row.
reset_ledger
cat >> DECISIONS.md <<'EOF'
| codex-abc-ck | codex | abc123 | #42 | scoping | q | a | a | overrode | real-cost-key |  |
EOF
stage_all
commit_quiet "chore: good cost-key (#42)"
EVAL_LABEL="$EVAL_ID cost-key-resolved" expect_pass "$CHECK" "$MSG_FILE"

# pass — DECISIONS row carries a cost-key but COSTS.md is absent;
# cross-ref is a soft no-op (this directive does not hard-require
# agent-token-accounting to be installed).
reset_ledger
cat >> DECISIONS.md <<'EOF'
| codex-abc-ck | codex | abc123 | #42 | scoping | q | a | a | overrode | whatever-key |  |
EOF
rm -f COSTS.md
stage_all
commit_quiet "chore: no costs file (#42)"
EVAL_LABEL="$EVAL_ID cost-key-no-costs-md" expect_pass "$CHECK" "$MSG_FILE"

# fail — Mode A must validate the *staged* ledger, not the worktree.
# Regression guard for the bug where a bad staged row could be masked
# by an unstaged worktree fix and slip past the commit-msg hook while
# CI (which sees only committed state) would reject it.
reset_ledger
cat >> DECISIONS.md <<'EOF'
| codex-abc-st | codex | abc123 | #42 | scoping | q | a | a | maybe |  |  |
EOF
stage_all
# Overwrite the worktree with a fixed copy AFTER staging the bad one.
# No stage_all here — the index keeps the 'maybe' row.
cat > DECISIONS.md <<'EOF'
# DECISIONS.md
| decision-key | agent | session | issue | phase | question | lean | choice | diverged | cost-key | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| codex-abc-d001 | codex | abc123 | #42 | plan-review | q | yes | no | overrode |  |  |
| codex-abc-st | codex | abc123 | #42 | scoping | q | a | a | overrode |  | fixed in worktree only |
EOF
cat > "$MSG_FILE" <<'EOF'
feat: staged-bad (#42)
EOF
EVAL_LABEL="$EVAL_ID staged-vs-worktree" expect_fail "$CHECK" "$MSG_FILE"

rm -f "$MSG_FILE"
eval_done
