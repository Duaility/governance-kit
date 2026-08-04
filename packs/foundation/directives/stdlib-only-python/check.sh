#!/usr/bin/env bash
# Directive: stdlib-only-python — every tracked `.py` file the kit ships
# under `.governance/` imports only the Python standard library.
#
# Rationale: issue #355 locks the product's dependency posture — the kit's
# OWN tooling needs nothing but a bare `python3`: no `pip install`, no venv,
# no lockfile. A single `import requests` (or any third-party import)
# silently breaks every consumer that hasn't separately provisioned that
# package, and there is no signal until the script is actually invoked
# (often off the commit path, e.g. the scheduled sweep workflow).
#
# Only top-level (zero-indent) `import X` / `from X import ...` lines are
# parsed — an import nested inside a function or class body is scoped to
# code that already needs its own justification, and indentation styles vary
# enough that a deeper parse would be guessing. Relative imports
# (`from . import x`, `from .foo import bar`) are always allowed — they
# reach into the kit's own package, never a third party.
#
# The stdlib allowlist ships in the sibling `defaults.conf` (pack-owned,
# live) with the user overlay
# `.governance/conf/governance-kit/foundation/stdlib-only-python.conf`
# layered on top — a bare line ADDS an allowed root module, `!<module>`
# REMOVES a default one (e.g. a repo that wants to forbid `ctypes`).
set -u
source "$(dirname "$0")/../../../../../lib.sh"
directive_start "stdlib-only-python"
require_git

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT" || exit 1

DEFAULTS="$(dirname "$0")/defaults.conf"
[[ -f "$DEFAULTS" ]] || { violation "broken install: $DEFAULTS missing (stdlib allowlist unavailable)"; directive_end; }

# ── Effective stdlib allowlist ──────────────────────────────────
ALLOW=$'\n'
while IFS= read -r m; do
    [[ -z "$m" ]] && continue
    ALLOW+="$m"$'\n'
done < <(conf_list stdlib-only-python "$DEFAULTS" 2>/dev/null || true)

is_allowed() {
    case "$ALLOW" in
        *$'\n'"$1"$'\n'*) return 0 ;;
        *) return 1 ;;
    esac
}

# extract_roots <file> — print "<line>:<root-module>" for every top-level
# `import X[, Y ...]` / `from X import ...` statement. Relative `from`
# imports (module starts with `.`) are skipped entirely.
extract_roots() {
    awk '
        /^import[ \t]/ {
            rest = $0
            sub(/^import[ \t]+/, "", rest)
            n = split(rest, items, ",")
            for (i = 1; i <= n; i++) {
                item = items[i]
                gsub(/^[ \t]+|[ \t]+$/, "", item)
                sub(/[ \t]+as[ \t]+.*$/, "", item)
                if (item == "") continue
                split(item, comps, ".")
                if (comps[1] != "") print NR ":" comps[1]
            }
            next
        }
        /^from[ \t]/ {
            rest = $0
            sub(/^from[ \t]+/, "", rest)
            split(rest, parts, /[ \t]+/)
            mod = parts[1]
            if (mod == "" || mod ~ /^\./) next
            split(mod, comps, ".")
            if (comps[1] != "") print NR ":" comps[1]
        }
    ' "$1" 2>/dev/null
}

FILES=()
while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    FILES+=("$f")
done < <(tracked_files '.governance/*.py' 2>/dev/null)

for f in ${FILES[@]+"${FILES[@]}"}; do
    [[ -f "$f" ]] || continue
    while IFS= read -r hit; do
        [[ -z "$hit" ]] && continue
        line_no="${hit%%:*}"
        mod="${hit#*:}"
        [[ -z "$mod" ]] && continue
        is_allowed "$mod" && continue
        violation "$f:$line_no — imports non-stdlib module '$mod' (kit tooling must run on a bare python3; issue #355)"
    done < <(extract_roots "$f")
done

directive_end
