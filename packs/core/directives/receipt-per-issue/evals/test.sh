#!/usr/bin/env bash
set -u
EVAL_ID="receipt-per-issue"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
[[ -f "$ROOT/governance/assets/packs/lib/eval-lib.sh" ]] || { echo "eval: ROOT misresolved to $ROOT — refusing to run with broken eval-lib.sh path" >&2; exit 1; }
source "$ROOT/governance/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/packs/core"
CHECK=".governance/packs/governance-kit/core/directives/$EVAL_ID/check.sh"

fixture_init
install_directive "$PACK_DIR" "$EVAL_ID"

# pass — no receipts/ directory, directive is a no-op
EVAL_LABEL="$EVAL_ID no-receipts" expect_pass "$CHECK"

mkdir -p receipts

# pass — two receipts, distinct issue numbers, all four sections present,
#        every checked item crosswalks to evidence
cat > receipts/issue-1-alpha.md <<'EOF'
# Receipt: alpha

## Checklist

- [x] Add the alpha module
- [ ] Add the beta module

## What changed

Add the alpha module.

## Out of scope

Beta is deferred.

## Verification

Directive evals pass.
EOF
cat > receipts/issue-2-beta.md <<'EOF'
# Receipt: beta

## Checklist

- [x] Add the beta module

## What changed

Add the beta module.

## Out of scope

Gamma is deferred.

## Verification

Reviewer confirms behavior on the test fixture.
EOF
stage_all
commit_quiet "docs: add two receipts"
EVAL_LABEL="$EVAL_ID distinct-and-crosswalking" expect_pass "$CHECK"

# pass — case-insensitive substring is enough for the crosswalk
cat > receipts/issue-3-gamma.md <<'EOF'
# Receipt: gamma

## Checklist

- [x] refactor the cache layer

## What changed

Refactor the Cache Layer so eviction is LRU-based.

## Out of scope

None.

## Verification

Cache hit-rate benchmarks unchanged.
EOF
stage_all
commit_quiet "docs: case-insensitive crosswalk"
EVAL_LABEL="$EVAL_ID case-insensitive" expect_pass "$CHECK"

# fail — receipt filename missing the issue token
rm receipts/issue-1-alpha.md receipts/issue-2-beta.md receipts/issue-3-gamma.md
cat > receipts/rogue.md <<'EOF'
# Rogue receipt

## Checklist

- [x] Stuff

## What changed

Stuff.

## Out of scope

Things.

## Verification

ok
EOF
stage_all
commit_quiet "docs: untokened receipt"
EVAL_LABEL="$EVAL_ID no-token" expect_fail "$CHECK"

# fail — filename has issue number but no slug
rm receipts/rogue.md
cat > receipts/issue-9.md <<'EOF'
# No slug

## Checklist

- [x] Stuff

## What changed

Stuff.

## Out of scope

None.

## Verification

ok
EOF
stage_all
commit_quiet "docs: receipt without slug"
EVAL_LABEL="$EVAL_ID no-slug" expect_fail "$CHECK"

# fail — slug contains uppercase (not kebab-case)
rm receipts/issue-9.md
cat > receipts/issue-10-Foo.md <<'EOF'
# Uppercase slug

## Checklist

- [x] Stuff

## What changed

Stuff.

## Out of scope

None.

## Verification

ok
EOF
stage_all
commit_quiet "docs: receipt with uppercase slug"
EVAL_LABEL="$EVAL_ID uppercase-slug" expect_fail "$CHECK"

# fail — slug uses underscore separator (not kebab-case)
rm receipts/issue-10-Foo.md
cat > receipts/issue-11-foo_bar.md <<'EOF'
# Underscore slug

## Checklist

- [x] Stuff

## What changed

Stuff.

## Out of scope

None.

## Verification

ok
EOF
stage_all
commit_quiet "docs: receipt with underscore in slug"
EVAL_LABEL="$EVAL_ID underscore-slug" expect_fail "$CHECK"

# fail — duplicate issue numbers across two receipts
rm receipts/issue-11-foo_bar.md
cat > receipts/issue-1-first.md <<'EOF'
# First

## Checklist

- [x] First

## What changed

First did stuff.

## Out of scope

None.

## Verification

ok.
EOF
cat > receipts/issue-1-duplicate.md <<'EOF'
# Duplicate

## Checklist

- [x] Duplicate

## What changed

Duplicate did stuff.

## Out of scope

None.

## Verification

ok.
EOF
stage_all
commit_quiet "docs: dup receipt"
EVAL_LABEL="$EVAL_ID dup" expect_fail "$CHECK"

# fail — Checklist section missing
rm receipts/issue-1-first.md receipts/issue-1-duplicate.md
cat > receipts/issue-3-no-checklist.md <<'EOF'
# No Checklist

## What changed

Stuff.

## Out of scope

None.

## Verification

ok
EOF
stage_all
commit_quiet "docs: receipt without checklist"
EVAL_LABEL="$EVAL_ID missing-checklist" expect_fail "$CHECK"

# fail — Verification section missing
rm receipts/issue-3-no-checklist.md
cat > receipts/issue-4-no-verif.md <<'EOF'
# No Verification

## Checklist

- [x] thing

## What changed

thing happened.

## Out of scope

None.
EOF
stage_all
commit_quiet "docs: receipt without verification"
EVAL_LABEL="$EVAL_ID missing-verification" expect_fail "$CHECK"

# fail — What changed section missing
rm receipts/issue-4-no-verif.md
cat > receipts/issue-5-no-what.md <<'EOF'
# No What changed

## Checklist

- [x] thing

## Out of scope

None.

## Verification

ok
EOF
stage_all
commit_quiet "docs: receipt without what-changed"
EVAL_LABEL="$EVAL_ID missing-what-changed" expect_fail "$CHECK"

# fail — Out of scope section missing
rm receipts/issue-5-no-what.md
cat > receipts/issue-6-no-oos.md <<'EOF'
# No Out of scope

## Checklist

- [x] thing

## What changed

thing happened.

## Verification

ok
EOF
stage_all
commit_quiet "docs: receipt without out-of-scope"
EVAL_LABEL="$EVAL_ID missing-out-of-scope" expect_fail "$CHECK"

# fail — checked item with no matching text in What changed or Verification
rm receipts/issue-6-no-oos.md
cat > receipts/issue-7-bad-crosswalk.md <<'EOF'
# Bad crosswalk

## Checklist

- [x] Wire the parser to the new lexer
- [x] Add observability for the dispatcher

## What changed

Wire the parser to the new lexer.

## Out of scope

Observability is deferred.

## Verification

Existing tests pass.
EOF
stage_all
commit_quiet "docs: missing crosswalk"
EVAL_LABEL="$EVAL_ID missing-crosswalk" expect_fail "$CHECK"

# fail — `* [x]` star-bullet form is also subject to the crosswalk
rm receipts/issue-7-bad-crosswalk.md
cat > receipts/issue-8-star-bullet.md <<'EOF'
# Star bullet

## Checklist

* [x] Drop the legacy auth shim

## What changed

Reorganized package layout.

## Out of scope

None.

## Verification

CI green.
EOF
stage_all
commit_quiet "docs: star bullet variant"
EVAL_LABEL="$EVAL_ID star-bullet" expect_fail "$CHECK"

eval_done
