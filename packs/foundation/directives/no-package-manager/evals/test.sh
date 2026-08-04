#!/usr/bin/env bash
set -u
EVAL_ID="no-package-manager"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
[[ -f "$ROOT/kit/assets/packs/lib/eval-lib.sh" ]] || { echo "eval: ROOT misresolved to $ROOT — refusing to run with broken eval-lib.sh path" >&2; exit 1; }
source "$ROOT/kit/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/packs/foundation"
CHECK=".governance/packs/governance-kit/foundation/directives/$EVAL_ID/check.sh"

fixture_init
install_directive "$PACK_DIR" "$EVAL_ID"

# pass — baseline fixture invokes no package manager
EVAL_LABEL="$EVAL_ID" expect_pass "$CHECK"

# fail — uv invocation in a governance-managed shell script
cat > .governance/tool.sh <<'EOF'
#!/usr/bin/env bash
uv run --with pyyaml script.py
EOF
git add .governance/tool.sh
git commit --quiet --no-verify -m "chore: add uv invocation"
EVAL_LABEL="$EVAL_ID uv" expect_fail "$CHECK"
git rm --quiet .governance/tool.sh
git commit --quiet --no-verify -m "chore: drop uv invocation"

# fail — npx invocation in a governance-managed yml
cat > .governance/tool.yml <<'EOF'
steps:
  - run: npx something
EOF
git add .governance/tool.yml
git commit --quiet --no-verify -m "chore: add npx invocation"
EVAL_LABEL="$EVAL_ID npx" expect_fail "$CHECK"
git rm --quiet .governance/tool.yml
git commit --quiet --no-verify -m "chore: drop npx invocation"

# fail — pip install in an extensionless .githooks/ script
cat > .githooks/pre-commit <<'EOF'
#!/usr/bin/env bash
pip install -r requirements.txt
exit 0
EOF
git add .githooks/pre-commit
git commit --quiet --no-verify -m "chore: githook pip install"
EVAL_LABEL="$EVAL_ID githooks pip" expect_fail "$CHECK"

# pass — same line, but commented out (comment lines are not scanned)
cat > .githooks/pre-commit <<'EOF'
#!/usr/bin/env bash
# pip install -r requirements.txt  (left as a note, not executed)
exit 0
EOF
git add .githooks/pre-commit
git commit --quiet --no-verify -m "chore: comment out pip install"
EVAL_LABEL="$EVAL_ID commented pip" expect_pass "$CHECK"

# fail again, then pass via a path-glob waiver in the user overlay
cat > .githooks/pre-commit <<'EOF'
#!/usr/bin/env bash
pip install -r requirements.txt
exit 0
EOF
git add .githooks/pre-commit
git commit --quiet --no-verify -m "chore: githook pip install again"
EVAL_LABEL="$EVAL_ID githooks pip (before waiver)" expect_fail "$CHECK"
printf '.githooks/pre-commit\n' > "$EVAL_CONF"
EVAL_LABEL="$EVAL_ID githooks pip (waived)" expect_pass "$CHECK"
rm -f "$EVAL_CONF"

# restore a clean githook so the fixture ends tidy
cat > .githooks/pre-commit <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
git add .githooks/pre-commit
git commit --quiet --no-verify -m "chore: restore clean githook"
EVAL_LABEL="$EVAL_ID restored" expect_pass "$CHECK"

eval_done
