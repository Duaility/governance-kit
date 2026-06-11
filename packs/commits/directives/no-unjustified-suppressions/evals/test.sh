#!/usr/bin/env bash
set -u
EVAL_ID="no-unjustified-suppressions"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
[[ -f "$ROOT/governance/assets/packs/lib/eval-lib.sh" ]] || { echo "eval: ROOT misresolved to $ROOT — refusing to run with broken eval-lib.sh path" >&2; exit 1; }
source "$ROOT/governance/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/packs/commits"
CHECK=".governance/packs/governance-kit/commits/directives/$EVAL_ID/check.sh"

fixture_init
install_directive "$PACK_DIR" "$EVAL_ID"

# pass — clean baseline, no suppressions anywhere
EVAL_LABEL="$EVAL_ID" expect_pass "$CHECK"

# pass — a suppression that cites a tracker on the same line
mkdir -p src
cat > src/a.ts <<'EOF'
// eslint-disable-next-line no-console -- #42 console kept for the CLI entrypoint
console.log("hi");
EOF
cat > src/b.py <<'EOF'
x = legacy_call()  # type: ignore  # ABC-123 upstream stub has no types yet
EOF
stage_all
commit_quiet "feat: justified suppressions"
EVAL_LABEL="$EVAL_ID tracked" expect_pass "$CHECK"

# fail — an unjustified TypeScript suppression
cat > src/c.ts <<'EOF'
// @ts-ignore
const y = whatever.shape;
EOF
stage_all
commit_quiet "feat: ts-ignore"
EVAL_LABEL="$EVAL_ID ts-ignore-orphan" expect_fail "$CHECK"

# fail — an unjustified Python noqa
rm src/c.ts
cat > src/d.py <<'EOF'
import os  # noqa
EOF
stage_all
commit_quiet "feat: noqa"
EVAL_LABEL="$EVAL_ID noqa-orphan" expect_fail "$CHECK"

# pass — same noqa with a line-level governance waiver
cat > src/d.py <<'EOF'
import os  # noqa  # governance: allow-no-unjustified-suppressions re-exported for the public API
EOF
stage_all
EVAL_LABEL="$EVAL_ID waiver" expect_pass "$CHECK"

# pass — a suppression token quoted in markdown prose is not scanned
rm src/d.py
cat > NOTES.md <<'EOF'
# Notes

Use `// @ts-ignore` only as a last resort.
EOF
stage_all
commit_quiet "docs: mention ts-ignore in prose"
EVAL_LABEL="$EVAL_ID markdown-ignored" expect_pass "$CHECK"

eval_done
