#!/usr/bin/env bash
set -u
EVAL_ID="version-consistency"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
[[ -f "$ROOT/governance/assets/packs/lib/eval-lib.sh" ]] || { echo "eval: ROOT misresolved to $ROOT — refusing to run with broken eval-lib.sh path" >&2; exit 1; }
source "$ROOT/governance/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/packs/core"
CHECK=".governance/packs/governance-kit/core/directives/$EVAL_ID/check.sh"

# Pin the fixture's stamps to whatever the harness's installed lib.sh carries,
# so the eval doesn't break when the kit version bumps.
KITV="$(sed -nE 's/^version:[[:space:]]*"?([^"#[:space:]]+)"?.*/\1/p' "$ROOT/governance/assets/kit.yaml" | head -1)"
[[ -n "$KITV" ]] || KITV="0.3"

fixture_init
install_directive "$PACK_DIR" "$EVAL_ID"

write_marked() { printf '# governance-kit:managed kit-version=%s\nplaceholder\n' "$2" > "$1"; }

mkdir -p .governance .github/workflows scripts .githooks
cat > .governance/install.yaml <<EOF
version: "3"
kit_version: "$KITV"
tests_dir: .governance
ci_workflow: .github/workflows/governance.yml
enable_governance_script: scripts/enable-governance.sh
hook_strategy: githooks
EOF
write_marked .governance/run.sh "$KITV"
write_marked .github/workflows/governance.yml "$KITV"
write_marked scripts/enable-governance.sh "$KITV"
write_marked .githooks/pre-commit "$KITV"
stage_all
commit_quiet "fixture: consistent stamps"
EVAL_LABEL="$EVAL_ID" expect_pass "$CHECK"

# fail — one managed file drifts to a different kit version
write_marked .github/workflows/governance.yml "0.0"
stage_all
commit_quiet "fixture: drift one stamp"
EVAL_LABEL="$EVAL_ID drift" expect_fail "$CHECK"

# pass (no-op) — manifest absent
rm -f .governance/install.yaml
stage_all
commit_quiet "fixture: no manifest"
EVAL_LABEL="$EVAL_ID no-manifest noop" expect_pass "$CHECK"

# pass (no-op) — manifest present but carries no kit_version
printf 'version: "3"\nowner: acme\n' > .governance/install.yaml
stage_all
commit_quiet "fixture: manifest without kit_version"
EVAL_LABEL="$EVAL_ID no-kit_version noop" expect_pass "$CHECK"

eval_done
