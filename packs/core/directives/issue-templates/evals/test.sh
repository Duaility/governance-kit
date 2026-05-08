#!/usr/bin/env bash
set -u
EVAL_ID="issue-templates"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
[[ -f "$ROOT/governance/assets/packs/lib/eval-lib.sh" ]] || { echo "eval: ROOT misresolved to $ROOT — refusing to run with broken eval-lib.sh path" >&2; exit 1; }
source "$ROOT/governance/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/packs/core"
CHECK=".governance/packs/governance-kit/core/directives/$EVAL_ID/check.sh"

fixture_init
install_directive "$PACK_DIR" "$EVAL_ID"

mkdir -p .github/ISSUE_TEMPLATE
cp "$PACK_DIR/directives/$EVAL_ID/install-assets/.github/ISSUE_TEMPLATE/"*.yml .github/ISSUE_TEMPLATE/
stage_all
commit_quiet "chore: add issue templates"
EVAL_LABEL="$EVAL_ID complete" expect_pass "$CHECK"

rm .github/ISSUE_TEMPLATE/proposal.yml
stage_all
commit_quiet "chore: remove proposal template"
EVAL_LABEL="$EVAL_ID missing-proposal" expect_fail "$CHECK"

cp "$PACK_DIR/directives/$EVAL_ID/install-assets/.github/ISSUE_TEMPLATE/proposal.yml" .github/ISSUE_TEMPLATE/proposal.yml
sed -i.bak '/id: validation/d' .github/ISSUE_TEMPLATE/proposal.yml
rm .github/ISSUE_TEMPLATE/proposal.yml.bak
stage_all
commit_quiet "chore: break proposal template"
EVAL_LABEL="$EVAL_ID missing-validation" expect_fail "$CHECK"

cp "$PACK_DIR/directives/$EVAL_ID/install-assets/.github/ISSUE_TEMPLATE/proposal.yml" .github/ISSUE_TEMPLATE/proposal.yml
sed -i.bak 's/blank_issues_enabled: false/blank_issues_enabled: true/' .github/ISSUE_TEMPLATE/config.yml
rm .github/ISSUE_TEMPLATE/config.yml.bak
stage_all
commit_quiet "chore: enable blank issues"
EVAL_LABEL="$EVAL_ID blank-issues" expect_fail "$CHECK"

eval_done
