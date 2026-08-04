#!/usr/bin/env bash
# Directive: no-commit-path-python — nothing on the consumer commit path
# (`.governance/lib.sh`, `.governance/run.sh`, every installed
# `check.sh` / `hooks/*.sh` / `runtimes/*.sh`, and `.githooks/*`) invokes
# `python` or `python3`.
#
# Rationale: issue #355 locks the product's dependency posture — a consumer
# repo needs nothing but bash + git to commit. Python is fine for the kit's
# OWN tooling off the commit path (lifecycle verbs, sweep — see the sibling
# `stdlib-only-python` directive), but a `python3` call sitting on the hook
# every commit runs through means a consumer without python3 on PATH gets a
# broken hook, silently, the first time they clone the repo.
#
# Waivers: a path-glob exemption list in the sibling `defaults.conf`
# (pack-owned, empty by default — the directive is absolute out of the box),
# layered with the user overlay
# `.governance/conf/governance-kit/foundation/no-commit-path-python.conf` — a
# bare line EXEMPTS a path, `!<pattern>` un-exempts a default one.
set -u
source "$(dirname "$0")/../../../../../lib.sh"
directive_start "no-commit-path-python"
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
done < <(conf_list no-commit-path-python "$DEFAULTS" 2>/dev/null || true)

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

# ── The commit-path file set ────────────────────────────────────
# Every file a pre-commit / commit-msg / prepare-commit-msg / post-commit /
# pre-push run actually executes: lib.sh, run.sh, any per-runtime helper, and
# every installed directive's check.sh + its hook / runtime side-effect
# scripts, plus the .githooks/ dispatchers themselves.
FILES=()
while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    FILES+=("$f")
done < <(tracked_files \
    '.governance/lib.sh' \
    '.governance/run.sh' \
    '.governance/runtimes/*.sh' \
    '.governance/packs/*/*/directives/*/check.sh' \
    '.governance/packs/*/*/directives/*/hooks/*.sh' \
    '.governance/packs/*/*/directives/*/runtimes/*.sh' \
    '.githooks/*' \
    2>/dev/null)

for f in ${FILES[@]+"${FILES[@]}"}; do
    [[ -f "$f" ]] || continue
    is_exempt "$f" && continue
    while IFS= read -r hit; do
        [[ -z "$hit" ]] && continue
        line_no="${hit%%:*}"
        content="${hit#*:}"
        # Strip leading whitespace to test whether the line is a comment —
        # same idiom lib.sh's own conf helpers use.
        leading="${content%%[![:space:]]*}"
        stripped="${content#"$leading"}"
        [[ "${stripped:0:1}" == "#" ]] && continue
        violation "$f:$line_no — python invocation on the commit path (consumer commits need nothing but bash + git; issue #355): ${stripped:0:80}"
    done < <(LC_ALL=C grep -nwE 'python3?' "$f" 2>/dev/null || true)
done

directive_end
