#!/usr/bin/env bash
# Directive: stdlib-only-python (repo-local dogfood) — every tracked `.py` file
# this repo SHIPS imports only the Python standard library.
#
# This is a SELF-directive about what THIS repo authors, not a rule the kit
# hands to consumers. Scanned set: `kit/**/*.py` (the lifecycle engines under
# `kit/assets/packs/lib/`, the sweep engine `kit/assets/dot-governance/sweep.py`,
# and anything else inside the kit artifact) plus `skill/*.py` (the published
# bootstrap shim).
#
# Deliberately NOT scanned:
#   - scripts/** — this repo's own test harness. It never ships to a consumer,
#     so issue #355's lane table leaves it unconstrained.
#   - .governance/** — this repo's installed tree is vendored from the LAST
#     release and lags `kit/` by one cycle by design (see AGENTS.md, "The
#     dogfood: a protected consumer").
#
# Rationale: issue #355 locks the product's dependency posture — the kit's own
# tooling needs nothing but a bare `python3`: no `pip install`, no venv, no
# lockfile. A single third-party import silently breaks every consumer that
# hasn't separately provisioned that package, and there is no signal until the
# script is actually invoked (often off the commit path, e.g. the scheduled
# sweep workflow, days after the import landed).
#
# Only top-level (zero-indent) `import X` / `from X import ...` lines are
# parsed — an import nested inside a function or class body is scoped to code
# that already needs its own justification, and indentation styles vary enough
# that a deeper parse would be guessing. The parser also requires the module
# token to be a real dotted identifier and a `from` line to carry the `import`
# keyword, so a prose line inside a module docstring is not mistaken for an
# import statement.
#
# Two kinds of import are first-party and always allowed: a relative import
# (`from . import x`, `from .foo import bar`), and a flat sibling import whose
# root resolves to a `.py` file or package directory next to the importing file
# — that is how the kit's own engines under `kit/assets/packs/lib/` reference
# each other (`import kityaml`, `from packctl import scalar`).
#
# The stdlib allowlist is the sibling `defaults.conf`, layered with the overlay
# `.governance/conf/duaility/governance-kit/stdlib-only-python.conf` — a bare
# line ADDS an allowed root module, `!<module>` REMOVES a default one.
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

# is_sibling <importing-file> <root-module> — true when the root module is a
# `.py` file or package directory sitting next to the importing file. The kit's
# engines are a flat package on sys.path, so these are first-party, not vendor.
is_sibling() {
    local dir
    dir="$(dirname "$1")"
    [[ -f "$dir/$2.py" || -f "$dir/$2/__init__.py" ]]
}

# extract_roots <file> — print "<line>:<root-module>" for every top-level
# `import X[, Y ...]` / `from X import ...` statement. Relative `from` imports
# (module starts with `.`) are skipped entirely, as is anything whose module
# token is not a dotted identifier (prose in a module docstring).
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
                if (item !~ /^[A-Za-z_][A-Za-z0-9_.]*$/) continue
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
            if (parts[2] != "import") next
            if (mod == "" || mod ~ /^\./) next
            if (mod !~ /^[A-Za-z_][A-Za-z0-9_.]*$/) next
            split(mod, comps, ".")
            if (comps[1] != "") print NR ":" comps[1]
        }
    ' "$1" 2>/dev/null
}

FILES=()
while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    FILES+=("$f")
# git pathspec globs are fnmatch WITHOUT FNM_PATHNAME, so `*` spans `/`:
# `kit/*.py` means "every .py anywhere under kit/".
done < <(tracked_files 'kit/*.py' 'skill/*.py' 2>/dev/null)

for f in ${FILES[@]+"${FILES[@]}"}; do
    [[ -f "$f" ]] || continue
    while IFS= read -r hit; do
        [[ -z "$hit" ]] && continue
        line_no="${hit%%:*}"
        mod="${hit#*:}"
        [[ -z "$mod" ]] && continue
        is_allowed "$mod" && continue
        is_sibling "$f" "$mod" && continue
        violation "$f:$line_no — imports non-stdlib module '$mod' (everything this repo ships must run on a bare python3; issue #355)"
    done < <(extract_roots "$f")
done

directive_end
