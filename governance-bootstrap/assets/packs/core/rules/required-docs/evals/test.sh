#!/usr/bin/env bash
set -u
EVAL_ID="required-docs"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../../../.." && pwd)"
source "$ROOT/governance-bootstrap/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/governance-bootstrap/assets/packs/core"
RULE="tests/governance/rules/$EVAL_ID/check.sh"

fixture_init
install_rule "$PACK_DIR" "$EVAL_ID"

# pass — baseline fixture ships all required docs + githooks scaffolding
EVAL_LABEL="$EVAL_ID" expect_pass "$RULE"

# fail — missing CONSTITUTION.md
rm CONSTITUTION.md
EVAL_LABEL="$EVAL_ID missing constitution" expect_fail "$RULE"

# restore constitution, then break a different sub-check: stub README
cat > CONSTITUTION.md <<'EOF'
# Constitution

## Principles

Placeholder principle.

## Guidelines

Placeholder guideline.

## Invariants

Placeholder invariant.

## Evolution Log

Placeholder entry.
EOF
printf '# Hi\n' > README.md
EVAL_LABEL="$EVAL_ID stub readme" expect_fail "$RULE"

# restore README, then fail via missing LICENSE
cat > README.md <<'EOF'
# Fixture repo

Minimal seed for the governance pack eval harness. Every eval under
governance-bootstrap/assets/packs/\*/evals/\*/test.sh spins up a copy of
this tree, installs exactly one rule under test, and then mutates the
parts of the fixture the rule cares about — pass then fail assertions
run through the same harness.
EOF
rm LICENSE
EVAL_LABEL="$EVAL_ID missing license" expect_fail "$RULE"

# restore LICENSE, then verify DISABLE env var suppresses the missing check
cat > LICENSE <<'EOF'
MIT License

Copyright (c) 2026

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software to deal in the Software without restriction.
EOF

# break license + architecture simultaneously, then disable both sub-checks → should pass
rm LICENSE
rm ARCHITECTURE.md
GOVERNANCE_REQUIRED_DOCS_DISABLE="license,architecture" \
    EVAL_LABEL="$EVAL_ID disable skips sub-checks" expect_pass "$RULE"

eval_done
