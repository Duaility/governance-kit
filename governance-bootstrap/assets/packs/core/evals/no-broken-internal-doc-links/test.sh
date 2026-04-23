#!/usr/bin/env bash
set -u
EVAL_ID="no-broken-internal-doc-links"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../../.." && pwd)"
source "$ROOT/governance-bootstrap/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/governance-bootstrap/assets/packs/core"
RULE="tests/governance/rules/$EVAL_ID.sh"

fixture_init
install_rule "$PACK_DIR" "$EVAL_ID"

# pass — baseline AGENTS.md links only to files that exist
EVAL_LABEL="$EVAL_ID" expect_pass "$RULE"

# fail — add a doc with a broken relative link
cat > NOTES.md <<'EOF'
# Notes

See [the missing doc](docs/missing.md).
EOF
stage_all
commit_quiet "docs: add notes with broken link"
EVAL_LABEL="$EVAL_ID broken" expect_fail "$RULE"

eval_done
