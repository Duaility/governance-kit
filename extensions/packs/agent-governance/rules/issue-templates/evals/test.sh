#!/usr/bin/env bash
set -u
EVAL_ID="issue-templates"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../../.." && pwd)"
source "$ROOT/governance/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/extensions/packs/agent-governance"
RULE="tests/governance/rules/$EVAL_ID/check.sh"

fixture_init
install_rule "$PACK_DIR" "$EVAL_ID"

mkdir -p .github/ISSUE_TEMPLATE
cp "$PACK_DIR/rules/$EVAL_ID/install-assets/.github/ISSUE_TEMPLATE/"*.yml .github/ISSUE_TEMPLATE/
stage_all
commit_quiet "chore: add issue templates"
EVAL_LABEL="$EVAL_ID complete" expect_pass "$RULE"

rm .github/ISSUE_TEMPLATE/proposal.yml
stage_all
commit_quiet "chore: remove proposal template"
EVAL_LABEL="$EVAL_ID missing-proposal" expect_fail "$RULE"

cp "$PACK_DIR/rules/$EVAL_ID/install-assets/.github/ISSUE_TEMPLATE/proposal.yml" .github/ISSUE_TEMPLATE/proposal.yml
sed -i.bak '/id: validation/d' .github/ISSUE_TEMPLATE/proposal.yml
rm .github/ISSUE_TEMPLATE/proposal.yml.bak
stage_all
commit_quiet "chore: break proposal template"
EVAL_LABEL="$EVAL_ID missing-validation" expect_fail "$RULE"

cp "$PACK_DIR/rules/$EVAL_ID/install-assets/.github/ISSUE_TEMPLATE/proposal.yml" .github/ISSUE_TEMPLATE/proposal.yml
sed -i.bak 's/blank_issues_enabled: false/blank_issues_enabled: true/' .github/ISSUE_TEMPLATE/config.yml
rm .github/ISSUE_TEMPLATE/config.yml.bak
stage_all
commit_quiet "chore: enable blank issues"
EVAL_LABEL="$EVAL_ID blank-issues" expect_fail "$RULE"

eval_done
