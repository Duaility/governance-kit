#!/usr/bin/env bash
set -u
EVAL_ID="internal-doc-links"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
[[ -f "$ROOT/kit/assets/packs/lib/eval-lib.sh" ]] || { echo "eval: ROOT misresolved to $ROOT — refusing to run with broken eval-lib.sh path" >&2; exit 1; }
source "$ROOT/kit/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/packs/foundation"
CHECK=".governance/packs/governance-kit/foundation/directives/$EVAL_ID/check.sh"

fixture_init
install_directive "$PACK_DIR" "$EVAL_ID"

# ── sub-check: resolve (always on, no config) ─────────────────

# pass — baseline links only to files that exist
EVAL_LABEL="$EVAL_ID resolve-baseline" expect_pass "$CHECK"

# fail — a doc with a broken relative link
cat > NOTES.md <<'EOF'
# Notes

See [the missing doc](docs/missing.md).
EOF
stage_all
commit_quiet "docs: add notes with broken link"
EVAL_LABEL="$EVAL_ID resolve-broken" expect_fail "$CHECK"

# pass — same broken link plus a line-level waiver (new token)
cat > NOTES.md <<'EOF'
# Notes

See [the missing doc](docs/missing.md). <!-- governance: allow-internal-doc-links placeholder for upcoming docs/missing.md -->
EOF
stage_all
EVAL_LABEL="$EVAL_ID resolve-waiver" expect_pass "$CHECK"

# clean up before the reachable cases so no stray broken link trips resolve
rm -f NOTES.md
stage_all
commit_quiet "docs: drop notes"

# ── sub-check: reachable (opt-in via $EVAL_CONF) ──

# pass — no config file → reachable is a no-op even with an orphan present
mkdir -p docs
cat > docs/orphan.md <<'EOF'
# Orphan

Nothing links here.
EOF
stage_all
commit_quiet "docs: orphan with no config"
EVAL_LABEL="$EVAL_ID reachable-noop-no-config" expect_pass "$CHECK"

# Configure: root docs/index.md; exclude the uppercase baseline root docs so the
# reachable requirement scopes to the docs/ subtree under test.
mkdir -p .governance/conf
cat > $EVAL_CONF <<'EOF'
# entry points
root docs/index.md
exclude [A-Z]*.md
EOF

# fail — orphan exists but docs/index.md does not lead to it
cat > docs/index.md <<'EOF'
# Index

See [the guide](guide.md).
EOF
cat > docs/guide.md <<'EOF'
# Guide

Body.
EOF
stage_all
commit_quiet "docs: index + guide, orphan still unlinked"
EVAL_LABEL="$EVAL_ID reachable-orphan" expect_fail "$CHECK"

# pass — link the orphan transitively (index → guide → orphan)
cat > docs/guide.md <<'EOF'
# Guide

Body. Also see [the details](orphan.md).
EOF
stage_all
commit_quiet "docs: link orphan transitively"
EVAL_LABEL="$EVAL_ID reachable-transitive" expect_pass "$CHECK"

# fail — a brand-new orphan
cat > docs/lonely.md <<'EOF'
# Lonely

Unlinked again.
EOF
stage_all
commit_quiet "docs: new orphan"
EVAL_LABEL="$EVAL_ID reachable-new-orphan" expect_fail "$CHECK"

# pass — head-of-file reachable waiver exempts the orphan
cat > docs/lonely.md <<'EOF'
<!-- governance: allow-internal-doc-links reachable standalone changelog, intentionally unlinked -->
# Lonely

Unlinked again.
EOF
stage_all
EVAL_LABEL="$EVAL_ID reachable-waiver" expect_pass "$CHECK"

# pass — exclude it via config instead of a waiver
cat > docs/lonely.md <<'EOF'
# Lonely

Unlinked again.
EOF
cat > $EVAL_CONF <<'EOF'
root docs/index.md
exclude [A-Z]*.md
exclude docs/lonely.md
EOF
stage_all
EVAL_LABEL="$EVAL_ID reachable-conf-exclude" expect_pass "$CHECK"

# fail — a broken link still trips resolve even while reachable is configured
cat > docs/index.md <<'EOF'
# Index

See [the guide](guide.md) and [a dangling ref](nope.md).
EOF
stage_all
EVAL_LABEL="$EVAL_ID resolve-fires-under-reachable" expect_fail "$CHECK"

eval_done
