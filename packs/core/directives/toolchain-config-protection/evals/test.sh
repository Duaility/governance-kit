#!/usr/bin/env bash
set -u
EVAL_ID="toolchain-config-protection"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
[[ -f "$ROOT/governance/assets/packs/lib/eval-lib.sh" ]] || { echo "eval: ROOT misresolved to $ROOT — refusing to run with broken eval-lib.sh path" >&2; exit 1; }
source "$ROOT/governance/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/packs/core"
CHECK=".governance/packs/governance-kit/core/directives/$EVAL_ID/check.sh"

fixture_init
install_directive "$PACK_DIR" "$EVAL_ID"

msg="$(mktemp)"

# pass — staged change touches only ordinary source, no config
mkdir -p src
echo "export const x = 1;" > src/a.ts
git add src/a.ts
printf 'feat: add x (#1)\n' > "$msg"
EVAL_LABEL="$EVAL_ID plain-source" expect_pass "$CHECK" "$msg"

# fail — staged change edits a tsconfig with no waiver
echo '{ "compilerOptions": { "strict": false } }' > tsconfig.json
git add tsconfig.json
printf 'chore: relax tsconfig (#2)\n' > "$msg"
EVAL_LABEL="$EVAL_ID config-no-waiver" expect_fail "$CHECK" "$msg"

# pass — same config change with a waiver line in the body
cat > "$msg" <<'EOF'
chore: relax tsconfig (#2)

governance: allow-toolchain-config intentionally enabling incremental migration
EOF
EVAL_LABEL="$EVAL_ID config-waiver" expect_pass "$CHECK" "$msg"

# fail — touching a CI workflow without a waiver
git reset --quiet HEAD tsconfig.json && rm -f tsconfig.json
mkdir -p .github/workflows
echo "name: ci" > .github/workflows/ci.yml
git add .github/workflows/ci.yml
printf 'ci: tweak workflow (#3)\n' > "$msg"
EVAL_LABEL="$EVAL_ID workflow-no-waiver" expect_fail "$CHECK" "$msg"

# fail — bare waiver token without a reason does not waive
cat > "$msg" <<'EOF'
ci: tweak workflow (#3)

governance: allow-toolchain-config
EOF
EVAL_LABEL="$EVAL_ID bare-waiver" expect_fail "$CHECK" "$msg"

# ── overlay layering on the pack-owned default pattern list ──
git reset --quiet HEAD .github/workflows/ci.yml && rm -rf .github
mkdir -p .governance/conf

# pass — overlay drops the tsconfig default with `!`, so editing it no longer
# needs a waiver. (.governance/conf is untracked, so it doesn't count as a
# touched file itself.)
printf '!tsconfig.json\n' > .governance/conf/toolchain-config-protection.conf
echo '{ "compilerOptions": {} }' > tsconfig.json
git add tsconfig.json
printf 'chore: edit tsconfig after dropping its default (#4)\n' > "$msg"
EVAL_LABEL="$EVAL_ID overlay-removes-default" expect_pass "$CHECK" "$msg"

# fail — a still-default pattern (Makefile) stays protected
printf 'all:\n\techo hi\n' > Makefile
git add Makefile
printf 'build: change Makefile (#5)\n' > "$msg"
EVAL_LABEL="$EVAL_ID default-still-protects" expect_fail "$CHECK" "$msg"
git reset --quiet HEAD Makefile && rm -f Makefile

# fail — overlay ADDS a custom pattern, which is then protected
printf '+app.config.json\n' > .governance/conf/toolchain-config-protection.conf
echo '{ "feature": true }' > app.config.json
git add app.config.json
printf 'chore: edit custom protected config (#6)\n' > "$msg"
EVAL_LABEL="$EVAL_ID overlay-adds-pattern" expect_fail "$CHECK" "$msg"

rm -f "$msg"
eval_done
