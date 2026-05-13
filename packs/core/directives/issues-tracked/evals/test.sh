#!/usr/bin/env bash
set -u
EVAL_ID="issues-tracked"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
[[ -f "$ROOT/governance/assets/packs/lib/eval-lib.sh" ]] || { echo "eval: ROOT misresolved to $ROOT — refusing to run with broken eval-lib.sh path" >&2; exit 1; }
source "$ROOT/governance/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/packs/core"
CHECK=".governance/packs/governance-kit/core/directives/$EVAL_ID/check.sh"

fixture_init
install_directive "$PACK_DIR" "$EVAL_ID"

# pass — QUALITY.md with Open + Resolved sections
cat > QUALITY.md <<'EOF'
# Quality tracker

## Open

- Nothing tracked right now.

## Resolved

- Placeholder for resolved issues.
EOF
stage_all
commit_quiet "docs: add quality tracker"
EVAL_LABEL="$EVAL_ID" expect_pass "$CHECK"

# fail — missing one of the required sections
cat > QUALITY.md <<'EOF'
# Quality tracker

## Open

- Nothing.
EOF
stage_all
commit_quiet "docs: drop resolved"
EVAL_LABEL="$EVAL_ID no-resolved" expect_fail "$CHECK"

# fail — QUALITY.md absent altogether
rm QUALITY.md
stage_all
commit_quiet "chore: drop quality file"
EVAL_LABEL="$EVAL_ID missing" expect_fail "$CHECK"

# pass — same missing-QUALITY.md state, but with a waiver in CONSTITUTION.md
cat > CONSTITUTION.md <<'EOF'
# Constitution

<!-- governance: allow-issues-tracked this repo tracks bugs in Linear, not QUALITY.md -->

## Principles
EOF
stage_all
commit_quiet "docs: waive issues-tracked"
EVAL_LABEL="$EVAL_ID waived" expect_pass "$CHECK"

# fail — bare waiver token (no reason) does not waive
cat > CONSTITUTION.md <<'EOF'
# Constitution

<!-- governance: allow-issues-tracked -->

## Principles
EOF
stage_all
commit_quiet "docs: bare waiver"
EVAL_LABEL="$EVAL_ID waiver-without-reason" expect_fail "$CHECK"

eval_done
