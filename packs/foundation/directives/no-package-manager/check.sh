#!/usr/bin/env bash
# Directive: no-package-manager — no tracked file under `.governance/` or
# `.githooks/` invokes a package manager (`uv`, `pip`/`pipx`, `npx`,
# `pnpm dlx`, `yarn dlx`).
#
# Rationale: issue #355 locks the product's dependency posture — nothing in
# governance-kit's own machinery ever needs a package manager: the commit
# path runs on bash + git (see the sibling `no-commit-path-python`), and the
# kit's own tooling runs on a bare python3 (see `stdlib-only-python`).
# Reaching for `uv run --with X` or `npx X` to route around either of those
# rules defeats the posture as surely as a raw third-party import would —
# it's still a package manager doing an install at commit/run time.
#
# Scan scope is deliberately pragmatic rather than a full shell-command-
# position parser: non-comment lines of tracked `*.sh` / `*.py` / `*.yml`
# files under `.governance/`, plus every `.githooks/*` dispatcher (those are
# always shell scripts even though they carry no extension).
#
# Waivers: a path-glob exemption list in the sibling `defaults.conf`
# (pack-owned, empty by default), layered with the user overlay
# `.governance/conf/governance-kit/foundation/no-package-manager.conf` — a
# bare line EXEMPTS a path, `!<pattern>` un-exempts a default one.
set -u
source "$(dirname "$0")/../../../../../lib.sh"
directive_start "no-package-manager"
require_git

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT" || exit 1

DEFAULTS="$(dirname "$0")/defaults.conf"
[[ -f "$DEFAULTS" ]] || { violation "broken install: $DEFAULTS missing (waiver list unavailable)"; directive_end; }

# ── Exemptions ───────────────────────────────────────────────────
EXEMPT=()
while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    EXEMPT+=("$p")
done < <(conf_list no-package-manager "$DEFAULTS" 2>/dev/null || true)

is_exempt() {
    local f="$1" base p
    base="${f##*/}"
    for p in ${EXEMPT[@]+"${EXEMPT[@]}"}; do
        case "$p" in
            */)   [[ "$f" == "$p"* ]] && return 0 ;;   # directory prefix
            */*)  [[ "$f" == $p ]]   && return 0 ;;    # full-path glob
            *)    [[ "$base" == $p ]] && return 0 ;;   # basename glob
        esac
    done
    return 1
}

# ── The scanned file set ────────────────────────────────────────
FILES=()
while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    FILES+=("$f")
done < <(tracked_files \
    '.governance/*.sh' \
    '.governance/*.py' \
    '.governance/*.yml' \
    '.githooks/*' \
    2>/dev/null)

_PATTERN='(uv|pipx?|npx|pnpm dlx|yarn dlx)'

for f in ${FILES[@]+"${FILES[@]}"}; do
    [[ -f "$f" ]] || continue
    is_exempt "$f" && continue
    while IFS= read -r hit; do
        [[ -z "$hit" ]] && continue
        line_no="${hit%%:*}"
        content="${hit#*:}"
        leading="${content%%[![:space:]]*}"
        stripped="${content#"$leading"}"
        [[ "${stripped:0:1}" == "#" ]] && continue
        violation "$f:$line_no — package-manager invocation on a governance-managed path (nothing here needs a package manager; issue #355): ${stripped:0:80}"
    done < <(LC_ALL=C grep -nwE "$_PATTERN" "$f" 2>/dev/null || true)
done

directive_end
