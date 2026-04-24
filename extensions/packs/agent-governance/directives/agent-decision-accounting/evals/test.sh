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

rm -f "$MSG_FILE"
eval_done
