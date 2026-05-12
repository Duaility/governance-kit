#!/usr/bin/env bash
set -u
EVAL_ID="agent-token-accounting"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
[[ -f "$ROOT/governance/assets/packs/lib/eval-lib.sh" ]] || { echo "eval: ROOT misresolved to $ROOT — refusing to run with broken eval-lib.sh path" >&2; exit 1; }
source "$ROOT/governance/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/packs/core"
CHECK=".governance/packs/governance-kit/core/directives/$EVAL_ID/check.sh"

command -v python3 >/dev/null 2>&1 || {
    echo "    ⊘ skipped — python3 not available"
    exit 0
}

fixture_init
install_directive "$PACK_DIR" "$EVAL_ID"

# Seed COSTS.md so the ledger-shape probe at the top of check.sh has a file to look at.
cp "$PACK_DIR/directives/$EVAL_ID/install-assets/COSTS.md" COSTS.md
git add -A .governance COSTS.md
git commit --quiet --no-verify -m "feat(governance): install directive (#1)"

# ──────────────────────────────────────────────────────────────
# Case 1 — pass: unsupported-runtime waiver with a reason
# ──────────────────────────────────────────────────────────────
cat > /tmp/msg-unsupported-ok <<'EOF'
feat: change from cursor (#3)

governance: allow-agent-token-accounting unsupported-runtime: cursor runtime has no runtimes/cursor.sh adapter yet
EOF
EVAL_LABEL="$EVAL_ID unsupported-runtime-pass" expect_pass "$CHECK" /tmp/msg-unsupported-ok

# ──────────────────────────────────────────────────────────────
# Case 2 — fail: unsupported-runtime waiver without a reason
# ──────────────────────────────────────────────────────────────
cat > /tmp/msg-unsupported-empty <<'EOF'
feat: change from cursor (#4)

governance: allow-agent-token-accounting unsupported-runtime:
EOF
EVAL_LABEL="$EVAL_ID unsupported-runtime-no-reason-fail" expect_fail "$CHECK" /tmp/msg-unsupported-empty

# ──────────────────────────────────────────────────────────────
# Case 3 — fail: no waiver, no trailers
# ──────────────────────────────────────────────────────────────
# Confirms the existing missing-Agent: violation still fires when no
# waiver is declared. The directive is strict by default — no
# bootstrap accommodation lives in check.sh.
cat > /tmp/msg-bare <<'EOF'
feat: bare commit (#5)
EOF
EVAL_LABEL="$EVAL_ID no-trailers-fail" expect_fail "$CHECK" /tmp/msg-bare

eval_done
