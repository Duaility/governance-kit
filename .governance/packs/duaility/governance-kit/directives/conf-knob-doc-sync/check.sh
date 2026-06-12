#!/usr/bin/env bash
# Directive: Every scalar knob a bundled directive's check.sh reads via
# `conf_get <id> <KEY> <defaults-file>` (under packs/*/directives/*/) has a
# matching `<KEY>=` row in that directive's sibling `defaults.conf`.
#
# Rationale: Since issue #210 a knob's default *and* its documentation live in
# exactly one place — the pack-owned `defaults.conf` row, which `conf_get`
# reads (env > overlay > defaults.conf). There is no in-code default constant
# and no separate `config.conf` template, so value/doc drift is impossible by
# construction. What remains to verify is purely structural: a `conf_get` whose
# `defaults.conf` carries no `<KEY>=` row would fail loud at runtime (broken
# install). This lint catches that authoring slip at commit time instead.
#
# This is the exact form the #210 design called for: a knob read ⇔ a defaults
# row. It carries no value or prose matching, so the two weaknesses of the old
# heuristic — two-form text matching and cross-knob value-collision false-pass —
# cannot arise.
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

while IFS= read -r check; do
    [[ -z "$check" ]] && continue
    defaults="$(dirname "$check")/defaults.conf"

    while IFS=: read -r line_no _; do
        [[ -z "$line_no" ]] && continue
        call="$(sed -n "${line_no}p" "$check")"
        # The knob is the second token after `conf_get`: `conf_get <id> <KEY>`.
        read -r _id key _rest <<< "${call#*conf_get }"
        [[ -z "${key:-}" ]] && continue
        has_waiver "$check" "$line_no" "conf-knob-doc-sync" && continue

        if [[ ! -f "$defaults" ]]; then
            violation "$check:$line_no — reads knob ${key} via conf_get but the directive ships no defaults.conf"
            continue
        fi
        if ! grep -Eq "^${key}=" "$defaults"; then
            violation "$check:$line_no — knob ${key} read via conf_get has no '${key}=' row in ${defaults}"
        fi
    done < <(grep -nE '^[^#]*conf_get[[:space:]]+[a-z0-9][a-z0-9-]*[[:space:]]+[A-Z_]+' "$check" 2>/dev/null || true)
done < <(git ls-files -- 'packs/*/directives/*/check.sh' 2>/dev/null || true)

directive_end
