#!/usr/bin/env bash
set -u
EVAL_ID="repo-hygiene"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
[[ -f "$ROOT/governance/assets/packs/lib/eval-lib.sh" ]] || { echo "eval: ROOT misresolved to $ROOT — refusing to run with broken eval-lib.sh path" >&2; exit 1; }
source "$ROOT/governance/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/packs/core"
CHECK=".governance/packs/governance-kit/core/directives/$EVAL_ID/check.sh"

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

# fail — file-size-limit: a 12-line .ts file with the limit forced down to 5
{
    for i in $(seq 1 12); do
        printf 'export const k%d = %d;\n' "$i" "$i"
    done
} > big.ts
git add big.ts
git commit --quiet --no-verify -m "chore: oversized ts"
GOVERNANCE_FILE_SIZE_LIMIT=5 EVAL_LABEL="$EVAL_ID file-size-limit" expect_fail "$CHECK"

# pass — same file with a head-of-file waiver token
{
    printf '// governance: allow-repo-hygiene file-size-limit ISSUE-124 entrypoint kept whole\n'
    for i in $(seq 1 12); do
        printf 'export const k%d = %d;\n' "$i" "$i"
    done
} > big.ts
git add big.ts
git commit --quiet --no-verify -m "chore: waiver"
GOVERNANCE_FILE_SIZE_LIMIT=5 EVAL_LABEL="$EVAL_ID file-size-limit waiver" expect_pass "$CHECK"
git rm --quiet big.ts
git commit --quiet --no-verify -m "chore: drop big.ts"

# fail — FILE_SIZE_LIMIT comes from the user conf (no env var this time)
mkdir -p .governance/conf
printf 'FILE_SIZE_LIMIT=5\n' > .governance/conf/repo-hygiene.conf
{
    for i in $(seq 1 12); do
        printf 'export const m%d = %d;\n' "$i" "$i"
    done
} > big2.ts
git add big2.ts
git commit --quiet --no-verify -m "chore: oversized ts via conf"
EVAL_LABEL="$EVAL_ID file-size-limit from conf" expect_fail "$CHECK"
git rm --quiet big2.ts
git commit --quiet --no-verify -m "chore: drop big2.ts"
rm -f .governance/conf/repo-hygiene.conf

eval_done
