#!/usr/bin/env bash
# Directive: no-package-manager (repo-local dogfood) — nothing governance-kit
# SHIPS invokes a package manager (`uv`, `pip`/`pipx`, `npx`, `pnpm dlx`,
# `yarn dlx`).
#
# This is a SELF-directive about what THIS repo authors, not a rule the kit
# hands to consumers. Scanned set: the executable-bearing files under the three
# shipped trees — `kit/**`, `packs/**`, `skill/**` — plus this repo's own
# `.githooks/*` dispatchers. "Executable-bearing" means `*.sh`, `*.py`, `*.yml`
# and `*.yaml`; the `.githooks/*` dispatchers carry no extension but are always
# shell scripts.
#
# Deliberately NOT scanned:
#   - .github/workflows/** — the docs site is a real npm project and docs.yml
#     legitimately runs npm to build it. The kit ships no part of that.
#   - scripts/** — this repo's own test harness, which never ships to a
#     consumer (issue #355's lane table leaves it unconstrained).
#   - packs/*/directives/*/evals/** — eval fixtures are not shipped (the
#     materializer strips `evals/`) and contain deliberate violation strings by
#     construction.
#   - .governance/** — this repo's installed tree is vendored from the LAST
#     release and lags the source trees by one cycle by design (see AGENTS.md,
#     "The dogfood: a protected consumer").
#
# Rationale: issue #355 locks the product's dependency posture — nothing in
# governance-kit's own machinery ever needs a package manager. The commit path
# runs on bash + git (sibling `no-commit-path-python`) and the shipped python
# runs on a bare python3 (sibling `stdlib-only-python`); reaching for
# `uv run --with X` or `npx X` to route around either rule defeats the posture
# as surely as a raw third-party import would.
#
# Detection is command-position, not word-match: the tool name must sit at the
# start of a shell command (line start after indentation, after `;` `&` `|` `(`
# `$(`, or after a YAML `run:` key), so the many legitimate prose mentions in
# shipped docs and docstrings — "`npx skills` installed the skill", "the kit
# used to need `uv` on PATH" — are not violations.
#
# Waivers: a path-glob exemption list in the sibling `defaults.conf` (empty by
# default), layered with the overlay
# `.governance/conf/duaility/governance-kit/no-package-manager.conf` — a bare
# line EXEMPTS a path, `!<pattern>` un-exempts a default one.
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
# NOTE: git pathspec globs are fnmatch WITHOUT FNM_PATHNAME, so `*` spans `/`
# — `kit/*.sh` already means "every .sh anywhere under kit/".
done < <(tracked_files \
    'kit/*.sh' 'kit/*.py' 'kit/*.yml' 'kit/*.yaml' \
    'packs/*.sh' 'packs/*.py' 'packs/*.yml' 'packs/*.yaml' \
    'skill/*.sh' 'skill/*.py' 'skill/*.yml' 'skill/*.yaml' \
    '.githooks/*' \
    ':!packs/*/directives/*/evals/*' \
    2>/dev/null)

# A package-manager invocation at a command position — line start (after
# indentation), after a shell separator, or after a YAML `run:` key — with the
# tool name optionally wrapped in a quote or an argv-list bracket, so
# `os.system("uv run …")` and `subprocess.run(["npx", …])` are caught too. A
# backtick is deliberately NOT a command-position character here: modern shell
# uses `$(…)`, and backticks in this corpus are Markdown, which is exactly where
# the legitimate prose mentions live ("`npx skills` installed the skill").
_PM_CMD='(^|[;&|(]|\$\(|run:)[["'\''[:space:]]*(uv|pipx?|npx|pnpm dlx|yarn dlx)(["'\''[:space:]]|$)'

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
        violation "$f:$line_no — package-manager invocation in shipped kit content (nothing governance-kit ships needs a package manager; issue #355): ${stripped:0:80}"
    done < <(LC_ALL=C grep -nE "$_PM_CMD" "$f" 2>/dev/null || true)
done

directive_end
