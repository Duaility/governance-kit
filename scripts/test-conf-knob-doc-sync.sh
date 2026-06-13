#!/usr/bin/env bash
# scripts/test-conf-knob-doc-sync.sh — every scalar knob a bundled directive's
# check.sh reads via `conf_get <id> <KEY> <defaults-file>` (under
# packs/*/directives/*/) has a matching `<KEY>=` row in that directive's sibling
# `defaults.conf`. Ported from the former dogfood directive `conf-knob-doc-sync`
# (issue #251): it validates the kit's own pack sources, not a consumer repo.
#
# Since issue #210 a knob's default *and* its docs live in exactly one place —
# the pack-owned `defaults.conf` row that `conf_get` reads. A `conf_get` whose
# `defaults.conf` carries no `<KEY>=` row would fail loud at runtime (broken
# install); this lint catches that authoring slip at test time. It carries no
# value or prose matching — purely structural: a knob read <=> a defaults row.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

fail=0
note() { printf '  ✗ %s\n' "$1" >&2; fail=1; }

# A line-level waiver, mirroring the directive's `has_waiver`: an inline
# `# governance: allow-conf-knob-doc-sync` on the conf_get line skips it.
line_waived() { sed -n "${2}p" "$1" | grep -q "governance: allow-conf-knob-doc-sync"; }

while IFS= read -r check; do
    [[ -z "$check" ]] && continue
    defaults="$(dirname "$check")/defaults.conf"

    while IFS=: read -r line_no _; do
        [[ -z "$line_no" ]] && continue
        call="$(sed -n "${line_no}p" "$check")"
        # The knob is the second token after `conf_get`: `conf_get <id> <KEY>`.
        read -r _id key _rest <<< "${call#*conf_get }"
        [[ -z "${key:-}" ]] && continue
        line_waived "$check" "$line_no" && continue

        if [[ ! -f "$defaults" ]]; then
            note "$check:$line_no — reads knob ${key} via conf_get but the directive ships no defaults.conf"
            continue
        fi
        grep -Eq "^${key}=" "$defaults" \
            || note "$check:$line_no — knob ${key} read via conf_get has no '${key}=' row in ${defaults}"
    done < <(grep -nE '^[^#]*conf_get[[:space:]]+[a-z0-9][a-z0-9-]*[[:space:]]+[A-Z_]+' "$check" 2>/dev/null || true)
done < <(git ls-files -- 'packs/*/directives/*/check.sh' 2>/dev/null || true)

if [[ $fail -eq 0 ]]; then
    printf '  ✓ conf-knob-doc-sync: every conf_get knob has a defaults.conf row\n'
fi
exit $fail
