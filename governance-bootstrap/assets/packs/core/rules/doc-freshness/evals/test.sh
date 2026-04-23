#!/usr/bin/env bash
set -u
EVAL_ID="doc-freshness"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../../../.." && pwd)"
source "$ROOT/governance-bootstrap/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/governance-bootstrap/assets/packs/core"
RULE="tests/governance/rules/$EVAL_ID/check.sh"

fixture_init
install_rule "$PACK_DIR" "$EVAL_ID"

# pass — no freshness.conf means the rule is a no-op
EVAL_LABEL="$EVAL_ID no-conf" expect_pass "$RULE"

# pass — tracked doc with a recent last-verified marker
printf 'docs/fresh.md\n' > tests/governance/freshness.conf
mkdir -p docs
printf '<!-- last-verified: %s -->\n# Fresh\n' "$(date +%Y-%m-%d)" > docs/fresh.md
stage_all
EVAL_LABEL="$EVAL_ID fresh" expect_pass "$RULE"

# fail — marker is older than the staleness window
printf '<!-- last-verified: 2020-01-01 -->\n# Stale\n' > docs/fresh.md
stage_all
EVAL_LABEL="$EVAL_ID stale" expect_fail "$RULE"

# fail — doc listed in freshness.conf has no marker at all
printf '# Unmarked\n' > docs/fresh.md
stage_all
EVAL_LABEL="$EVAL_ID missing-marker" expect_fail "$RULE"

eval_done
