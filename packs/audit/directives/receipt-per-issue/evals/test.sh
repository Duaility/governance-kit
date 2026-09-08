#!/usr/bin/env bash
set -u
EVAL_ID="receipt-per-issue"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
[[ -f "$ROOT/kit/assets/packs/lib/eval-lib.sh" ]] || { echo "eval: ROOT misresolved to $ROOT — refusing to run with broken eval-lib.sh path" >&2; exit 1; }
source "$ROOT/kit/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/packs/audit"
CHECK=".governance/packs/governance-kit/audit/directives/$EVAL_ID/check.sh"

complete_receipt() {
    local path="$1"
    cat > "$path" <<'EOF'
# Receipt

## What changed

Shipped the outcome for issue #12: the loader now rejects empty configs.

## Verification

```sh
bash .governance/run.sh
```

exit 0 — suite passed.

## Audit

- PASS — `## What changed` describes the outcome of the diff.
- PASS — verification evidence would support the claim if true (not proof of execution).
- PASS — applicable acceptance criteria from the work item are met.
EOF
}

fixture_init
install_directive "$PACK_DIR" "$EVAL_ID"

EVAL_LABEL="$EVAL_ID no-receipts" expect_pass "$CHECK"

mkdir -p receipts

# Historical receipts (committed on default, clean index) are grandfathered.
cat > receipts/issue-1-alpha.md <<'EOF'
# Receipt: alpha

## Checklist

- [x] Add the alpha module

## What changed

Add the alpha module.

## Out of scope

Beta is deferred.

## Verification

Directive evals pass.
EOF
stage_all
commit_quiet "docs: historical receipt"
EVAL_LABEL="$EVAL_ID historical-grandfathered" expect_pass "$CHECK"

# Duplicate issue numbers fail at any boundary.
cat > receipts/issue-1-dup.md <<'EOF'
# Duplicate
## What changed
dup
## Verification
https://example.test/run/1
EOF
stage_all
commit_quiet "docs: dup receipt"
EVAL_LABEL="$EVAL_ID dup" expect_fail "$CHECK"
rm receipts/issue-1-dup.md
git add -A
commit_quiet "docs: drop dup"

# Invalid filename
cat > receipts/rogue.md <<'EOF'
# Rogue
## What changed
x
## Verification
https://example.test/run/1
EOF
stage_all
commit_quiet "docs: untokened receipt"
EVAL_LABEL="$EVAL_ID no-token" expect_fail "$CHECK"
rm receipts/rogue.md
git add -A
commit_quiet "docs: drop rogue"

# New slugless receipt on default (completed) is accepted — slug is optional.
rm -f receipts/*.md
complete_receipt receipts/issue-12.md
stage_all
EVAL_LABEL="$EVAL_ID new-slugless-ok" expect_pass "$CHECK"

# Uppercase slug still invalid.
rm -f receipts/issue-12.md
complete_receipt receipts/issue-10-Foo.md
stage_all
EVAL_LABEL="$EVAL_ID uppercase-slug" expect_fail "$CHECK"
rm -f receipts/issue-10-Foo.md

# Completed change: missing What changed
cat > receipts/issue-5.md <<'EOF'
# No What changed

## Verification

```sh
true
```

exit 0

## Audit

- PASS — placeholder.
EOF
stage_all
EVAL_LABEL="$EVAL_ID missing-what-changed" expect_fail "$CHECK"
rm -f receipts/issue-5.md

# Completed change: missing Verification
cat > receipts/issue-4.md <<'EOF'
# No Verification

## What changed

thing happened.

## Audit

- PASS — placeholder.
EOF
stage_all
EVAL_LABEL="$EVAL_ID missing-verification" expect_fail "$CHECK"
rm -f receipts/issue-4.md

# Fence alone is not evidence
cat > receipts/issue-34.md <<'EOF'
# Fence only

## What changed

thing happened.

## Verification

```sh
bash .governance/run.sh
```

## Audit

- PASS — placeholder.
EOF
stage_all
EVAL_LABEL="$EVAL_ID fence-only-verification" expect_fail "$CHECK"
rm -f receipts/issue-34.md

# Fence + outcome
complete_receipt receipts/issue-31.md
stage_all
EVAL_LABEL="$EVAL_ID fence-and-outcome" expect_pass "$CHECK"
rm -f receipts/issue-31.md

# Durable URL evidence without a fence
cat > receipts/issue-36.md <<'EOF'
# URL evidence

## What changed

thing happened for issue #36.

## Verification

CI run: https://example.test/actions/runs/36 passed.

## Audit

- PASS — outcome described.
- PASS — URL is durable evidence, not proof of execution.
- PASS — acceptance criteria met.
EOF
stage_all
EVAL_LABEL="$EVAL_ID url-evidence" expect_pass "$CHECK"
rm -f receipts/issue-36.md

# Decisions omitted is fine
complete_receipt receipts/issue-37.md
stage_all
EVAL_LABEL="$EVAL_ID decisions-optional" expect_pass "$CHECK"
rm -f receipts/issue-37.md

# Session stub cannot satisfy a completed change (staged on default).
cat > receipts/issue-40.md <<'EOF'
## Session

### Identifiers

| date | harness | session |
| --- | --- | --- |
| 2026-09-08 | eval | - |
EOF
stage_all
EVAL_LABEL="$EVAL_ID stub-not-complete" expect_fail "$CHECK"

# Same stub on a feature branch with staged files is intermediate — allowed.
git reset -q
git checkout -q -b wip-stub
stage_all
EVAL_LABEL="$EVAL_ID stub-intermediate" expect_pass "$CHECK"
git checkout -q main
git branch -D wip-stub >/dev/null
rm -f receipts/issue-40.md
git add -A

# Missing Audit on a completed new receipt
cat > receipts/issue-50.md <<'EOF'
# No audit

## What changed

thing happened.

## Verification

```sh
true
```

exit 0
EOF
stage_all
EVAL_LABEL="$EVAL_ID added-missing-audit" expect_fail "$CHECK"
rm -f receipts/issue-50.md

# Audit without a verdict
cat > receipts/issue-51.md <<'EOF'
# Audit without a verdict

## What changed

thing happened.

## Verification

```sh
true
```

exit 0

## Audit

I looked at the diff and it seems fine.
EOF
stage_all
EVAL_LABEL="$EVAL_ID added-audit-no-verdict" expect_fail "$CHECK"
rm -f receipts/issue-51.md

# REFUTED verdict is well-formed
cat > receipts/issue-52.md <<'EOF'
# Audit REFUTED

## What changed

thing happened.

## Verification

```sh
true
```

exit 0

## Audit

- REFUTED — verification URL was not replayed; this verdict is recorded, not proven.
EOF
stage_all
EVAL_LABEL="$EVAL_ID added-audit-refuted-ok" expect_pass "$CHECK"
rm -f receipts/issue-52.md

# File inventory is gone: unnamed extra files do not fail.
mkdir -p src
printf 'def orphan():\n    return 1\n' > src/orphan.py
complete_receipt receipts/issue-53.md
stage_all
EVAL_LABEL="$EVAL_ID no-file-inventory" expect_pass "$CHECK"
rm -f receipts/issue-53.md src/orphan.py

# Waiver
rm -f receipts/*.md
cat > receipts/issue-99-waivered.md <<'EOF'
<!-- governance: allow-receipt-per-issue stub receipt while issue is in triage -->
# Receipt: waivered

(no sections yet)
EOF
stage_all
EVAL_LABEL="$EVAL_ID waiver" expect_pass "$CHECK"

# Bare waiver token does not waive
rm -f receipts/*.md
cat > receipts/issue-99-bare.md <<'EOF'
<!-- governance: allow-receipt-per-issue -->
# Receipt: bare

(no sections yet)
EOF
stage_all
EVAL_LABEL="$EVAL_ID waiver-without-reason" expect_fail "$CHECK"

eval_done
