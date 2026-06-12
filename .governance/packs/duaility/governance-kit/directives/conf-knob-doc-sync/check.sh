#!/usr/bin/env bash
# Directive: Every scalar knob a bundled directive's check.sh reads via
# `conf_get <id> <KEY> <default>` (under packs/*/directives/*/) is documented
# in that directive's sibling config.conf template, and the documented default
# matches the literal default in the code.
#
# Rationale: Scalar defaults deliberately live as constants at the conf_get
# read site (replace-semantics knobs need no defaults.conf data file), which
# leaves the config.conf comment as the only user-facing statement of the
# default. Nothing else ties the two together: bumping a default in check.sh
# without touching the template silently mis-documents the knob for every
# consumer. This lint closes that drift channel.
#
# A documented default counts when config.conf contains either
#   <KEY>=<default>            (commented canonical line, postgres-style), or
#   Default <default> / default of <default>   (prose).
set -u
source "$(dirname "$0")/../../../../../lib.sh"
directive_start "conf-knob-doc-sync"
require_git

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT" || exit 1

# Only meaningful in the kit source repo; consumer repos have no packs/ tree.
if [[ ! -d "$ROOT/packs" ]]; then
    directive_end
fi

# Suffix that ends a documented value: end-of-line, a non-numeric char, or a
# literal '.' that is not the start of more digits — so for default 5,
# "Default 5." matches while "Default 50" and "Default 5.5" do not.
_VAL_END='(\.([^0-9]|$)|[^0-9.]|$)'

while IFS= read -r check; do
    [[ -z "$check" ]] && continue
    conf="$(dirname "$check")/config.conf"

    while IFS=: read -r line_no call; do
        [[ -z "$line_no" ]] && continue
        read -r _id key def _rest <<< "${call#*conf_get }"
        def="${def%%[)\"\']*}"          # strip the closing of $(...) wrappers
        [[ -z "${key:-}" ]] && continue
        [[ "${def:-}" == *'$'* ]] && def=""   # non-literal default: only check docs presence
        has_waiver "$check" "$line_no" "conf-knob-doc-sync" && continue

        if [[ ! -f "$conf" ]]; then
            violation "$check:$line_no — reads knob ${key} via conf_get but the directive ships no config.conf template"
            continue
        fi
        if ! grep -Eq "(^|[^A-Za-z0-9_])${key}([^A-Za-z0-9_]|$)" "$conf"; then
            violation "$check:$line_no — knob ${key} is not documented in ${conf}"
            continue
        fi
        if [[ -n "$def" ]]; then
            esc="$(printf '%s' "$def" | sed -e 's/[][\.*^$()+?{}|\\/]/\\&/g')"
            if ! grep -Eq "${key}=${esc}${_VAL_END}|[Dd]efault( of)? ${esc}${_VAL_END}" "$conf"; then
                violation "$check:$line_no — ${conf} does not document the code default for ${key} (code says ${def})"
            fi
        fi
    done < <(grep -nE '^[^#]*conf_get[[:space:]]+[a-z0-9][a-z0-9-]*[[:space:]]+[A-Z_]+' "$check" 2>/dev/null || true)
done < <(git ls-files -- 'packs/*/directives/*/check.sh' 2>/dev/null || true)

directive_end
