#!/usr/bin/env bash
set -u
EVAL_ID="layer-boundaries"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
[[ -f "$ROOT/kit/assets/packs/lib/eval-lib.sh" ]] || { echo "eval: ROOT misresolved to $ROOT — refusing to run with broken eval-lib.sh path" >&2; exit 1; }
source "$ROOT/kit/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/packs/architecture"
CHECK=".governance/packs/governance-kit/architecture/directives/$EVAL_ID/check.sh"

fixture_init
install_directive "$PACK_DIR" "$EVAL_ID"

# The declared layer model (LAYER_DOC default ARCHITECTURE.md). Present for most
# cases; one case removes it to exercise the no-model no-op.
write_layer_doc() {
    cat > ARCHITECTURE.md <<'EOF'
# Architecture

## Layer map

skill -> kit -> packs (arrows point only downward).
EOF
}
write_layer_doc

# A receipt that records a fresh-context sub-agent's PASS verdict.
attested_receipt() {
    cat <<'EOF'
# Receipt (#1)

## What changed

Moved a shared helper into the kit layer.

## Layer boundaries

Fresh-context sub-agent audit against the diff and the declared layer model:

- PASS — every changed file sits in the layer its role belongs to.
- PASS — no dependency points the wrong way across a layer edge.
- PASS — new shared logic lives in the layer that owns it.
EOF
}

# pass — no receipts/ directory: nothing to attest on, no-op.
rm -rf receipts
EVAL_LABEL="$EVAL_ID no-receipts" expect_pass "$CHECK"

mkdir -p receipts

# pass — no layer model declared (LAYER_DOC absent): directive is a no-op even
# though a receipt is added in the change set.
rm -f ARCHITECTURE.md
rm -f receipts/*.md
cat > receipts/issue-1-no-model.md <<'EOF'
# Receipt (#1)

## What changed

Some change, no layer model declared in the repo.
EOF
stage_all
EVAL_LABEL="$EVAL_ID no-layer-model" expect_pass "$CHECK"
write_layer_doc

# pass — a newly added (staged) receipt carrying a verdict-bearing
# `## Layer boundaries` section.
rm -f receipts/*.md
attested_receipt > receipts/issue-2-attested.md
stage_all
EVAL_LABEL="$EVAL_ID added-with-attestation" expect_pass "$CHECK"

# fail — a newly added receipt missing the `## Layer boundaries` section.
rm -f receipts/*.md
cat > receipts/issue-3-missing.md <<'EOF'
# Receipt (#3)

## What changed

A change with no layer-boundary attestation recorded.
EOF
stage_all
EVAL_LABEL="$EVAL_ID added-missing-attestation" expect_fail "$CHECK"

# fail — section present but records no PASS/REFUTED verdict.
rm -f receipts/*.md
cat > receipts/issue-4-no-verdict.md <<'EOF'
# Receipt (#4)

## What changed

A change.

## Layer boundaries

The sub-agent looked at the diff and the layer model.
EOF
stage_all
EVAL_LABEL="$EVAL_ID added-no-verdict" expect_fail "$CHECK"

# pass — a REFUTED verdict still satisfies the gate (it records; it does not
# adjudicate — the truth is the sweep lane's job at merge).
rm -f receipts/*.md
cat > receipts/issue-5-refuted.md <<'EOF'
# Receipt (#5)

## What changed

A change.

## Layer boundaries

Fresh-context sub-agent audit:

- REFUTED — a helper that belongs in the kit layer was placed under a pack.
EOF
stage_all
EVAL_LABEL="$EVAL_ID added-refuted-records" expect_pass "$CHECK"

# pass — a per-receipt waiver exempts the added receipt.
rm -f receipts/*.md
cat > receipts/issue-6-waived.md <<'EOF'
<!-- governance: allow-layer-boundaries trivial docs-only change, no layer impact -->
# Receipt (#6)

## What changed

A docs-only change.
EOF
stage_all
EVAL_LABEL="$EVAL_ID waiver" expect_pass "$CHECK"

# fail — a bare waiver with no reason does not exempt.
rm -f receipts/*.md
cat > receipts/issue-7-bare-waiver.md <<'EOF'
<!-- governance: allow-layer-boundaries -->
# Receipt (#7)

## What changed

A change.
EOF
stage_all
EVAL_LABEL="$EVAL_ID bare-waiver-fails" expect_fail "$CHECK"

# pass — a pre-existing (committed) receipt without the section is grandfathered;
# only receipts ADDED in the change set owe the attestation.
rm -f receipts/*.md
cat > receipts/issue-8-historical.md <<'EOF'
# Receipt (#8)

## What changed

A historical receipt that predates the directive.
EOF
stage_all
commit_quiet "docs: historical receipt"
EVAL_LABEL="$EVAL_ID grandfathered" expect_pass "$CHECK"

# pass — accounting-only stub (created by the accounting hooks before the agent
# writes the narrative) is skipped.
rm -f receipts/*.md
cat > receipts/issue-9-stub.md <<'EOF'
## Accounting

### Costs

| cost-key | note |
| --- | --- |
EOF
stage_all
EVAL_LABEL="$EVAL_ID accounting-stub-skipped" expect_pass "$CHECK"
