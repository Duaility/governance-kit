#!/usr/bin/env bash
set -u
EVAL_ID="stdlib-only-python"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
[[ -f "$ROOT/kit/assets/packs/lib/eval-lib.sh" ]] || { echo "eval: ROOT misresolved to $ROOT — refusing to run with broken eval-lib.sh path" >&2; exit 1; }
source "$ROOT/kit/assets/packs/lib/eval-lib.sh"
PACK_DIR="$ROOT/packs/foundation"
CHECK=".governance/packs/governance-kit/foundation/directives/$EVAL_ID/check.sh"

fixture_init
install_directive "$PACK_DIR" "$EVAL_ID"

# pass — baseline fixture ships no .py files
EVAL_LABEL="$EVAL_ID" expect_pass "$CHECK"

# fail — a non-stdlib top-level `import`
cat > .governance/tool.py <<'EOF'
#!/usr/bin/env python3
import requests
EOF
git add .governance/tool.py
git commit --quiet --no-verify -m "chore: add non-stdlib import"
EVAL_LABEL="$EVAL_ID non-stdlib import" expect_fail "$CHECK"
git rm --quiet .governance/tool.py
git commit --quiet --no-verify -m "chore: drop non-stdlib import"

# fail — non-stdlib via `from X import Y`
cat > .governance/tool.py <<'EOF'
#!/usr/bin/env python3
from yaml import safe_load
EOF
git add .governance/tool.py
git commit --quiet --no-verify -m "chore: add non-stdlib from-import"
EVAL_LABEL="$EVAL_ID non-stdlib from-import" expect_fail "$CHECK"
git rm --quiet .governance/tool.py
git commit --quiet --no-verify -m "chore: drop non-stdlib from-import"

# pass — stdlib-only script: __future__, a comma list, and a relative import
cat > .governance/tool.py <<'EOF'
#!/usr/bin/env python3
from __future__ import annotations
import os, sys
import json
from pathlib import Path
from . import helpers
EOF
git add .governance/tool.py
git commit --quiet --no-verify -m "chore: add stdlib-only script"
EVAL_LABEL="$EVAL_ID stdlib-only script" expect_pass "$CHECK"

# pass — a non-stdlib import indented inside a function is out of scope
# (only zero-indent top-level imports are parsed)
cat >> .governance/tool.py <<'EOF'

def lazy():
    import requests
    return requests
EOF
git add .governance/tool.py
git commit --quiet --no-verify -m "chore: add indented non-stdlib import"
EVAL_LABEL="$EVAL_ID indented import out of scope" expect_pass "$CHECK"
git rm --quiet .governance/tool.py
git commit --quiet --no-verify -m "chore: drop stdlib-only script"

# fail then pass — the overlay can widen the allowlist per repo
cat > .governance/tool.py <<'EOF'
#!/usr/bin/env python3
import requests
EOF
git add .governance/tool.py
git commit --quiet --no-verify -m "chore: add requests import"
EVAL_LABEL="$EVAL_ID requests before overlay" expect_fail "$CHECK"
printf 'requests\n' > "$EVAL_CONF"
EVAL_LABEL="$EVAL_ID requests allowed via overlay" expect_pass "$CHECK"
rm -f "$EVAL_CONF"
git rm --quiet .governance/tool.py
git commit --quiet --no-verify -m "chore: drop requests import"

# pass then fail — the overlay can narrow the default allowlist too
cat > .governance/tool.py <<'EOF'
#!/usr/bin/env python3
import ctypes
EOF
git add .governance/tool.py
git commit --quiet --no-verify -m "chore: add ctypes import"
EVAL_LABEL="$EVAL_ID ctypes allowed by default" expect_pass "$CHECK"
printf '!ctypes\n' > "$EVAL_CONF"
EVAL_LABEL="$EVAL_ID ctypes removed via overlay" expect_fail "$CHECK"
rm -f "$EVAL_CONF"
git rm --quiet .governance/tool.py
git commit --quiet --no-verify -m "chore: drop ctypes import"

eval_done
