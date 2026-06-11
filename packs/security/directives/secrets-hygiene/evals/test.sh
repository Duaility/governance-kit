#!/usr/bin/env bash
set -u
EVAL_ID="secrets-hygiene"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
[[ -f "$ROOT/governance/assets/packs/lib/eval-lib.sh" ]] || { echo "eval: ROOT misresolved to $ROOT — refusing to run with broken eval-lib.sh path" >&2; exit 1; }
source "$ROOT/governance/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/packs/security"
CHECK=".governance/packs/governance-kit/security/directives/$EVAL_ID/check.sh"

fixture_init
install_directive "$PACK_DIR" "$EVAL_ID"

# pass — baseline fixture has no secrets and .env is gitignored
EVAL_LABEL="$EVAL_ID" expect_pass "$CHECK"

# fail — AWS access key lands in config.txt
cat > config.txt <<'EOF'
AWS_KEY = AKIAIOSFODNN7EXAMPLE
EOF
git add config.txt
git commit --quiet --no-verify -m "chore: add config with key"
EVAL_LABEL="$EVAL_ID aws key" expect_fail "$CHECK"
git rm --quiet config.txt
git commit --quiet --no-verify -m "chore: remove config"

# fail — .env committed
cat > .env <<'EOF'
DATABASE_URL=postgres://localhost/db
EOF
# Force-add to bypass .gitignore for the test.
git add -f .env
git commit --quiet --no-verify -m "chore: track env"
EVAL_LABEL="$EVAL_ID dotenv tracked" expect_fail "$CHECK"
git rm --quiet -f .env
git commit --quiet --no-verify -m "chore: untrack env"

# waiver suppresses no-secrets violation
cat > fixture.txt <<'EOF'
AWS_KEY = AKIAIOSFODNN7EXAMPLE  # governance: allow-secrets-hygiene fixture data
EOF
git add fixture.txt
git commit --quiet --no-verify -m "chore: waivered fixture"
EVAL_LABEL="$EVAL_ID waiver" expect_pass "$CHECK"
git rm --quiet fixture.txt
git commit --quiet --no-verify -m "chore: drop waivered fixture"

eval_done
