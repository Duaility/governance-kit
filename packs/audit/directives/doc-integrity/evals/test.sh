#!/usr/bin/env bash
set -u
EVAL_ID="doc-integrity"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
[[ -f "$ROOT/kit/assets/packs/lib/eval-lib.sh" ]] || { echo "eval: ROOT misresolved to $ROOT — refusing to run with broken eval-lib.sh path" >&2; exit 1; }
source "$ROOT/kit/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/packs/audit"
CHECK=".governance/packs/governance-kit/audit/directives/$EVAL_ID/check.sh"

fixture_init
install_directive "$PACK_DIR" "$EVAL_ID"

# Opt two documents in via the overlay (one per remaining mode). receipts/*.md
# is already frozen by the pack-owned defaults.conf — exercising that the
# defaults are live without being restated here.
mkdir -p .governance/conf
cat > $EVAL_CONF <<'EOF'
append-only     LEDGER.md
frozen-section  NOTES.md   Resolved
EOF

# Land the protected corpus on the default branch (main).
mkdir -p receipts
printf '# Receipt 7\n\n## Verification\n\nok\n' > receipts/issue-7-thing.md
cat > LEDGER.md <<'EOF'
# Ledger

| key | value |
|-----|-------|
| a   | 1     |
| b   | 2     |
EOF
cat > NOTES.md <<'EOF'
# Notes

## Open

- still working on this

## Resolved

- 2026-01-01 — fixed thing one
- 2026-01-02 — fixed thing two
EOF
git add receipts/issue-7-thing.md LEDGER.md NOTES.md
git commit --quiet --no-verify -m "chore: seed protected corpus (#7)"

# Scope the clean to test paths so the untracked .governance/ install + config survive.
reset_clean() { git checkout --quiet -f main; git clean -fdq -- receipts; }
msg="$(mktemp)"; printf 'chore: pending (#7)\n' > "$msg"
wmsg() { printf '%s\n' "$1" > "$msg"; }

# ══════════════════════════════════════════════════════════════
# Mode A — commit-msg hook (baseline vs staged tree)
# ══════════════════════════════════════════════════════════════
git checkout --quiet -b mode-a

# ── frozen-files ──
# pass — adding a new receipt is never a mutation
printf '# Receipt 8\n\n## Verification\n\nok\n' > receipts/issue-8-new.md
git add receipts/issue-8-new.md
EVAL_LABEL="$EVAL_ID frozen-files add" expect_pass "$CHECK" "$msg"
git reset --quiet --hard HEAD; git clean -fdq -- receipts

# fail — modifying a past receipt
printf 'sneaky edit\n' >> receipts/issue-7-thing.md
git add receipts/issue-7-thing.md
EVAL_LABEL="$EVAL_ID frozen-files modify" expect_fail "$CHECK" "$msg"
git reset --quiet --hard HEAD

# fail — deleting a past receipt
git rm --quiet receipts/issue-7-thing.md
EVAL_LABEL="$EVAL_ID frozen-files delete" expect_fail "$CHECK" "$msg"
git reset --quiet --hard HEAD

# pass — modifying a past receipt with a path-scoped waiver
printf 'justified edit\n' >> receipts/issue-7-thing.md
git add receipts/issue-7-thing.md
wmsg 'fix: forced (#7)

governance: allow-doc-integrity receipts/issue-7-thing.md link target moved'
EVAL_LABEL="$EVAL_ID frozen-files waiver" expect_pass "$CHECK" "$msg"
git reset --quiet --hard HEAD; printf 'chore: pending (#7)\n' > "$msg"

# ── append-only ──
# pass — appending a row to the ledger
printf '| c   | 3     |\n' >> LEDGER.md
git add LEDGER.md
EVAL_LABEL="$EVAL_ID append-only append" expect_pass "$CHECK" "$msg"
git reset --quiet --hard HEAD

# fail — editing an existing ledger row
sed -i.bak 's/| a   | 1     |/| a   | 9     |/' LEDGER.md && rm -f LEDGER.md.bak
git add LEDGER.md
EVAL_LABEL="$EVAL_ID append-only edit-row" expect_fail "$CHECK" "$msg"
git reset --quiet --hard HEAD

# fail — removing a ledger line (file shrinks below the baseline prefix)
grep -v '| b   | 2     |' LEDGER.md > LEDGER.tmp && mv LEDGER.tmp LEDGER.md
git add LEDGER.md
EVAL_LABEL="$EVAL_ID append-only remove-row" expect_fail "$CHECK" "$msg"
git reset --quiet --hard HEAD

# pass — rewriting the ledger with a waiver
sed -i.bak 's/| a   | 1     |/| a   | 9     |/' LEDGER.md && rm -f LEDGER.md.bak
git add LEDGER.md
wmsg 'chore: migrate ledger (#7)

governance: allow-doc-integrity LEDGER.md one-time schema migration'
EVAL_LABEL="$EVAL_ID append-only waiver" expect_pass "$CHECK" "$msg"
git reset --quiet --hard HEAD; printf 'chore: pending (#7)\n' > "$msg"

# ── frozen-section ──
# pass — appending a new Resolved entry
printf -- '- 2026-01-03 — fixed thing three\n' >> NOTES.md
git add NOTES.md
EVAL_LABEL="$EVAL_ID frozen-section append-resolved" expect_pass "$CHECK" "$msg"
git reset --quiet --hard HEAD

# pass — editing the Open section (not frozen)
sed -i.bak 's/still working on this/now working on that/' NOTES.md && rm -f NOTES.bak NOTES.md.bak
git add NOTES.md
EVAL_LABEL="$EVAL_ID frozen-section edit-open" expect_pass "$CHECK" "$msg"
git reset --quiet --hard HEAD

# fail — editing an existing Resolved entry
sed -i.bak 's/fixed thing one/fixed thing ONE/' NOTES.md && rm -f NOTES.md.bak
git add NOTES.md
EVAL_LABEL="$EVAL_ID frozen-section edit-resolved" expect_fail "$CHECK" "$msg"
git reset --quiet --hard HEAD

# fail — deleting an existing Resolved entry
grep -v 'fixed thing two' NOTES.md > NOTES.tmp && mv NOTES.tmp NOTES.md
git add NOTES.md
EVAL_LABEL="$EVAL_ID frozen-section delete-resolved" expect_fail "$CHECK" "$msg"
git reset --quiet --hard HEAD

rm -f "$msg"
reset_clean

# ══════════════════════════════════════════════════════════════
# Mode B — CI / run.sh walk (baseline vs HEAD)
# ══════════════════════════════════════════════════════════════

# pass — a branch that only adds a new receipt and appends a ledger row
git checkout --quiet -b add-only
printf '# Receipt 9\n\n## Verification\n\nok\n' > receipts/issue-9-fresh.md
printf '| c   | 3     |\n' >> LEDGER.md
git add receipts/issue-9-fresh.md LEDGER.md
git commit --quiet --no-verify -m "feat: add receipt 9 and a ledger row (#9)"
EVAL_LABEL="$EVAL_ID modeB-additions" expect_pass "$CHECK"
# pass — editing the branch-authored receipt is fine (absent at the baseline)
printf 'a follow-up bullet\n' >> receipts/issue-9-fresh.md
git commit --quiet --no-verify -am "feat: expand receipt 9 (#9)"
EVAL_LABEL="$EVAL_ID modeB-edit-branch-receipt" expect_pass "$CHECK"
reset_clean

# fail — a branch commit that edits a past receipt
git checkout --quiet -b touch-receipt
printf 'after the fact\n' >> receipts/issue-7-thing.md
git commit --quiet --no-verify -am "fix: edit past receipt (#7)"
EVAL_LABEL="$EVAL_ID modeB-frozen-files" expect_fail "$CHECK"
reset_clean

# fail — a branch commit that rewrites a ledger row
git checkout --quiet -b touch-ledger
sed -i.bak 's/| a   | 1     |/| a   | 9     |/' LEDGER.md && rm -f LEDGER.md.bak
git commit --quiet --no-verify -am "chore: rewrite ledger row (#7)"
EVAL_LABEL="$EVAL_ID modeB-append-only" expect_fail "$CHECK"
reset_clean

# fail — a branch commit that deletes a Resolved entry
git checkout --quiet -b touch-section
grep -v 'fixed thing two' NOTES.md > NOTES.tmp && mv NOTES.tmp NOTES.md
git commit --quiet --no-verify -am "docs: drop a resolved note (#7)"
EVAL_LABEL="$EVAL_ID modeB-frozen-section" expect_fail "$CHECK"
reset_clean

# pass — same ledger rewrite, but waived on the offending commit
git checkout --quiet -b waiver-b
sed -i.bak 's/| a   | 1     |/| a   | 9     |/' LEDGER.md && rm -f LEDGER.md.bak
git commit --quiet --no-verify -am "chore: migrate ledger (#7)

governance: allow-doc-integrity LEDGER.md one-time migration"
EVAL_LABEL="$EVAL_ID modeB-waiver" expect_pass "$CHECK"
reset_clean

# ══════════════════════════════════════════════════════════════
# Overlay layering — a default rule can be dropped with `!` negation
# ══════════════════════════════════════════════════════════════
# COSTS.md is append-only by the pack-owned defaults. Seed it on main.
git checkout --quiet main
printf '# Costs\n\nbaseline line\n' > COSTS.md
git add COSTS.md
git commit --quiet --no-verify -m "chore: seed COSTS (#7)"

# fail — editing the baseline line trips the *default* append-only COSTS.md rule
git checkout --quiet -b touch-costs
sed -i.bak 's/baseline line/rewritten line/' COSTS.md && rm -f COSTS.md.bak
git commit --quiet --no-verify -am "chore: rewrite COSTS (#7)"
EVAL_LABEL="$EVAL_ID modeB-default-rule-active" expect_fail "$CHECK"

# pass — the overlay drops that default with `!append-only COSTS.md`
printf '!append-only COSTS.md\n' >> $EVAL_CONF
EVAL_LABEL="$EVAL_ID modeB-overlay-removes-default" expect_pass "$CHECK"
# restore the overlay for hygiene
sed -i.bak '/!append-only COSTS.md/d' $EVAL_CONF && rm -f $EVAL_CONF.bak
reset_clean

eval_done
