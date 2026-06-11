#!/usr/bin/env bash
set -u
EVAL_ID="required-docs"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
[[ -f "$ROOT/governance/assets/packs/lib/eval-lib.sh" ]] || { echo "eval: ROOT misresolved to $ROOT — refusing to run with broken eval-lib.sh path" >&2; exit 1; }
source "$ROOT/governance/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/packs/core"
CHECK=".governance/packs/governance-kit/core/directives/$EVAL_ID/check.sh"

fixture_init
install_directive "$PACK_DIR" "$EVAL_ID"

# pass — baseline fixture ships all required docs + githooks scaffolding
EVAL_LABEL="$EVAL_ID" expect_pass "$CHECK"

# fail — AGENTS_MD_MIN from the user conf forces the (otherwise valid) baseline
# AGENTS.md to read as a stub (proves conf_get reads the conf, not just env)
mkdir -p .governance/conf
printf 'AGENTS_MD_MIN=100000\n' > .governance/conf/required-docs.conf
EVAL_LABEL="$EVAL_ID agents-min from conf" expect_fail "$CHECK"
rm -f .governance/conf/required-docs.conf

# fail — missing CONSTITUTION.md
rm CONSTITUTION.md
EVAL_LABEL="$EVAL_ID missing constitution" expect_fail "$CHECK"

# restore constitution, then break a different sub-check: stub README
cat > CONSTITUTION.md <<'EOF'
# Constitution

## Principles

Placeholder principle.

## Guidelines

Placeholder guideline.

## Directives

Placeholder directive.

## Evolution Log

Placeholder entry.
EOF
printf '# Hi\n' > README.md
EVAL_LABEL="$EVAL_ID stub readme" expect_fail "$CHECK"

# restore README, then fail via missing LICENSE
cat > README.md <<'EOF'
# Fixture repo

Minimal seed for the governance pack eval harness. Every eval under
governance/assets/packs/\*/evals/\*/test.sh spins up a copy of
this tree, installs exactly one directive under test, and then mutates the
parts of the fixture the directive cares about — pass then fail assertions
run through the same harness.
EOF
rm LICENSE
EVAL_LABEL="$EVAL_ID missing license" expect_fail "$CHECK"

# restore LICENSE so the next assertion isolates the AGENTS.md failure
cat > LICENSE <<'EOF'
MIT License

Copyright (c) 2026

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software to deal in the Software without restriction.
EOF
# rewrite AGENTS.md with required length + link count but no CONSTITUTION.md
# anchor, so only the map-to-bedrock check fires
cat > AGENTS.md <<'EOF'
# AGENTS.md

Index for agents working in this fixture. Intentionally omits a link to
CONSTITUTION.md so the map-to-bedrock check fires.

## Quick links

- [README](README.md) — public-facing overview of the fixture
- [Architecture](ARCHITECTURE.md) — top-level layering and domains
- [Security](SECURITY.md) — how to report a vulnerability

## Working in this repo

Placeholder body text to clear the minimum line count so we isolate the
missing-CONSTITUTION-link failure from the stub-length failure. The
agents sub-check should fail only because the required link is absent,
not because the file is too short.

More filler to push the document past the minimum line threshold so the
missing-link assertion is the only failure surface reported by the
directive under test.
EOF
EVAL_LABEL="$EVAL_ID agents missing constitution link" expect_fail "$CHECK"

# pass — same broken agents fixture, but with a per-sub-check waiver in
# CONSTITUTION.md exempting the `agents` sub-check.
cat > CONSTITUTION.md <<'EOF'
# Constitution

<!-- governance: allow-required-docs agents fixture has intentional missing CONSTITUTION.md link -->

## Principles

Placeholder principle.

## Guidelines

Placeholder guideline.

## Directives

Placeholder directive.

## Evolution Log

Placeholder entry.
EOF
EVAL_LABEL="$EVAL_ID agents-subcheck waived" expect_pass "$CHECK"

# fail — waiver token without a reason does not waive
cat > CONSTITUTION.md <<'EOF'
# Constitution

<!-- governance: allow-required-docs agents -->

## Principles

Placeholder principle.

## Guidelines

Placeholder guideline.

## Directives

Placeholder directive.

## Evolution Log

Placeholder entry.
EOF
EVAL_LABEL="$EVAL_ID agents-waiver-no-reason" expect_fail "$CHECK"

eval_done
