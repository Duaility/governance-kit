#!/usr/bin/env bash
set -u
EVAL_ID="repo-hygiene"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../../../.." && pwd)"
source "$ROOT/governance/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/governance/assets/packs/core"
CHECK="tests/governance/directives/$EVAL_ID/check.sh"

fixture_init
install_directive "$PACK_DIR" "$EVAL_ID"

# pass — baseline fixture has no hygiene violations
EVAL_LABEL="$EVAL_ID" expect_pass "$CHECK"

# fail — merge conflict marker
cat > conflict.md <<'EOF'
<<<<<<< HEAD
alpha
=======
beta
>>>>>>> feature
EOF
git add conflict.md
git commit --quiet --no-verify -m "chore: add conflict"
EVAL_LABEL="$EVAL_ID merge markers" expect_fail "$CHECK"
git rm --quiet conflict.md
git commit --quiet --no-verify -m "chore: remove conflict"

# fail — build artefact
printf 'bytecode placeholder\n' > module.pyc
git add module.pyc
git commit --quiet --no-verify -m "chore: bytecode"
EVAL_LABEL="$EVAL_ID build artefact" expect_fail "$CHECK"
git rm --quiet module.pyc
git commit --quiet --no-verify -m "chore: drop bytecode"

# fail — oversized file (1 MB file, limit 0 MB ⇒ any file fails)
# Use a small but non-zero limit so a 2 KB file fails cleanly.
printf '%.0s.' {1..2048} > bloat.bin
git add bloat.bin
git commit --quiet --no-verify -m "chore: bloat"
GOVERNANCE_MAX_FILE_SIZE_MB=0 EVAL_LABEL="$EVAL_ID large file" expect_fail "$CHECK"
git rm --quiet bloat.bin
git commit --quiet --no-verify -m "chore: drop bloat"

eval_done
