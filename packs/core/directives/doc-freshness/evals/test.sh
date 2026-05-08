#!/usr/bin/env bash
set -u
EVAL_ID="doc-freshness"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
[[ -f "$ROOT/governance/assets/packs/lib/eval-lib.sh" ]] || { echo "eval: ROOT misresolved to $ROOT — refusing to run with broken eval-lib.sh path" >&2; exit 1; }
source "$ROOT/governance/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/packs/core"
CHECK=".governance/packs/governance-kit/core/directives/$EVAL_ID/check.sh"

fixture_init
install_directive "$PACK_DIR" "$EVAL_ID"

# pass — no freshness.conf means the directive is a no-op
EVAL_LABEL="$EVAL_ID no-conf" expect_pass "$CHECK"

# pass — tracked doc with a recent last-verified marker
printf 'docs/fresh.md\n' > .governance/freshness.conf
mkdir -p docs
printf '<!-- last-verified: %s -->\n# Fresh\n' "$(date +%Y-%m-%d)" > docs/fresh.md
stage_all
EVAL_LABEL="$EVAL_ID fresh" expect_pass "$CHECK"

# fail — marker is older than the staleness window
printf '<!-- last-verified: 2020-01-01 -->\n# Stale\n' > docs/fresh.md
stage_all
EVAL_LABEL="$EVAL_ID stale" expect_fail "$CHECK"

# fail — doc listed in freshness.conf has no marker at all
printf '# Unmarked\n' > docs/fresh.md
stage_all
EVAL_LABEL="$EVAL_ID missing-marker" expect_fail "$CHECK"

eval_done
