#!/usr/bin/env bash
set -u
EVAL_ID="no-commit-path-python"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
[[ -f "$ROOT/kit/assets/packs/lib/eval-lib.sh" ]] || { echo "eval: ROOT misresolved to $ROOT — refusing to run with broken eval-lib.sh path" >&2; exit 1; }
source "$ROOT/kit/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/packs/foundation"
CHECK=".governance/packs/governance-kit/foundation/directives/$EVAL_ID/check.sh"

fixture_init
install_directive "$PACK_DIR" "$EVAL_ID"

# pass — baseline fixture has no python on the commit path
EVAL_LABEL="$EVAL_ID" expect_pass "$CHECK"

# fail — a python invocation in some other installed directive's check.sh
mkdir -p .governance/packs/some-owner/some-pack/directives/some-id
cat > .governance/packs/some-owner/some-pack/directives/some-id/check.sh <<'EOF'
#!/usr/bin/env bash
python3 -c "print('hi')"
EOF
git add .governance/packs/some-owner/some-pack/directives/some-id/check.sh
git commit --quiet --no-verify -m "chore: add python check.sh"
EVAL_LABEL="$EVAL_ID check.sh python" expect_fail "$CHECK"
git rm --quiet -r .governance/packs/some-owner
git commit --quiet --no-verify -m "chore: remove python check.sh"

# fail — .githooks/pre-commit invokes python
cat > .githooks/pre-commit <<'EOF'
#!/usr/bin/env bash
python other-thing.py
exit 0
EOF
git add .githooks/pre-commit
git commit --quiet --no-verify -m "chore: githook python"
EVAL_LABEL="$EVAL_ID githooks python" expect_fail "$CHECK"

# pass — same line, but commented out (comment lines are not scanned)
cat > .githooks/pre-commit <<'EOF'
#!/usr/bin/env bash
# python other-thing.py  (left as a note, not executed)
exit 0
EOF
git add .githooks/pre-commit
git commit --quiet --no-verify -m "chore: comment out python"
EVAL_LABEL="$EVAL_ID commented python" expect_pass "$CHECK"

# fail again, then pass via a path-glob waiver in the user overlay
cat > .githooks/pre-commit <<'EOF'
#!/usr/bin/env bash
python other-thing.py
exit 0
EOF
git add .githooks/pre-commit
git commit --quiet --no-verify -m "chore: githook python again"
EVAL_LABEL="$EVAL_ID githooks python (before waiver)" expect_fail "$CHECK"
printf '.githooks/pre-commit\n' > "$EVAL_CONF"
EVAL_LABEL="$EVAL_ID githooks python (waived)" expect_pass "$CHECK"
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
