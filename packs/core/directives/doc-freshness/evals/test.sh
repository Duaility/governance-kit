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

# pass — no conf means the directive is a no-op
EVAL_LABEL="$EVAL_ID no-conf" expect_pass "$CHECK"

# pass — tracked doc with a recent last-verified marker
mkdir -p .governance/conf
printf 'docs/fresh.md\n' > .governance/conf/doc-freshness.conf
mkdir -p docs
printf '<!-- last-verified: %s -->\n# Fresh\n' "$(date +%Y-%m-%d)" > docs/fresh.md
stage_all
EVAL_LABEL="$EVAL_ID fresh" expect_pass "$CHECK"

# fail — marker is older than the staleness window
printf '<!-- last-verified: 2020-01-01 -->\n# Stale\n' > docs/fresh.md
stage_all
EVAL_LABEL="$EVAL_ID stale" expect_fail "$CHECK"

# fail — doc listed in the conf has no marker at all
printf '# Unmarked\n' > docs/fresh.md
stage_all
EVAL_LABEL="$EVAL_ID missing-marker" expect_fail "$CHECK"

# pass — a wide FRESHNESS_DAYS= window in the conf rescues a very old doc
printf '<!-- last-verified: 2020-01-01 -->\n# Old\n' > docs/fresh.md
stage_all
printf 'docs/fresh.md\nFRESHNESS_DAYS=100000\n' > .governance/conf/doc-freshness.conf
EVAL_LABEL="$EVAL_ID conf-window-widens" expect_pass "$CHECK"

# fail — GOVERNANCE_FRESHNESS_DAYS env overrides the conf window
GOVERNANCE_FRESHNESS_DAYS=1 EVAL_LABEL="$EVAL_ID env-beats-conf-window" expect_fail "$CHECK"

# restore the conf for the remaining cases
printf 'docs/fresh.md\n' > .governance/conf/doc-freshness.conf

# pass — stale doc with a waiver passes
printf '<!-- last-verified: 2020-01-01 -->\n<!-- governance: allow-doc-freshness pending rewrite in #99 -->\n# Stale\n' > docs/fresh.md
stage_all
EVAL_LABEL="$EVAL_ID waiver" expect_pass "$CHECK"

# fail — waiver token without a reason does not waive
printf '<!-- last-verified: 2020-01-01 -->\n<!-- governance: allow-doc-freshness -->\n# Stale\n' > docs/fresh.md
stage_all
EVAL_LABEL="$EVAL_ID waiver-without-reason" expect_fail "$CHECK"

eval_done
