#!/usr/bin/env bash
# Directive: no-commit-path-python (repo-local dogfood) — nothing governance-kit
# authors for the consumer commit path invokes `python` or `python3`.
#
# This is a SELF-directive about what THIS repo ships, not a rule the kit hands
# to consumers. The scanned set is therefore the SOURCE commit path — the files
# this repo writes that become a consumer's commit path once installed:
#
#   kit/assets/dot-governance/lib.sh
#   kit/assets/dot-governance/run.sh
#   kit/assets/dot-governance/runtimes/*.sh
#   packs/*/directives/*/check.sh
#   packs/*/directives/*/hooks/*.sh
#   packs/*/directives/*/runtimes/*.sh
#   .githooks/*
#
# Deliberately NOT scanned:
#   - kit/assets/dot-governance/sweep.py — the sweep engine is the scheduled
#     cron lane, not the commit path; issue #355's lane table allows python there.
#   - kit/assets/packs/lib/** — the lifecycle lane (install/update/pack verbs),
#     also allowed python by the same lane table. It is governed instead by the
#     sibling `stdlib-only-python`.
#   - .governance/** — this repo's own installed tree is vendored from the LAST
#     release and lags `packs/` / `kit/` by one cycle by design (see AGENTS.md,
#     "The dogfood: a protected consumer"). Policing it here would gate this
#     repo on content it cannot fix without cutting a release.
#
# Rationale: issue #355 locks the product's dependency posture — a consumer repo
# needs nothing but bash + git to commit. A `python3` call sitting on the hook
# every commit runs through means a consumer without python3 on PATH gets a
# broken hook, silently, the first time they clone the repo. Because governance-
# kit authors that commit path for everyone else, the promise has to bind here.
#
# Detection: a python *invocation*, not the word "python". The token must sit at
# a shell command position (line start after indentation, or right after `;`
# `&` `|` `(` or `$(`, with an optional leading shell keyword / launcher), or be
# the file's shebang. That keeps the check from firing on prose — including the
# `python` tail of a hyphenated identifier such as this directive's own id, or a
# sibling check's violation-message string.
#
# Waivers: a path-glob exemption list in the sibling `defaults.conf` (empty by
# default — the directive is absolute out of the box), layered with the overlay
# `.governance/conf/duaility/governance-kit/no-commit-path-python.conf` — a bare
# line EXEMPTS a path, `!<pattern>` un-exempts a default one.
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

# ── The source commit-path file set ─────────────────────────────
# Everything this repo authors that a pre-commit / commit-msg /
# prepare-commit-msg / post-commit / pre-push run will actually execute in a
# consumer repo, plus this repo's own .githooks/ dispatchers.
FILES=()
while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    FILES+=("$f")
done < <(tracked_files \
    'kit/assets/dot-governance/lib.sh' \
    'kit/assets/dot-governance/run.sh' \
    'kit/assets/dot-governance/runtimes/*.sh' \
    'packs/*/directives/*/check.sh' \
    'packs/*/directives/*/hooks/*.sh' \
    'packs/*/directives/*/runtimes/*.sh' \
    '.githooks/*' \
    2>/dev/null)

# `python` / `python3` at a shell command position. Anchored on line start (with
# optional indentation) or on a command separator, so the bare word inside prose
# or inside a hyphenated identifier never matches.
_PY_CMD='(^|[;&|(]|\$\()[[:space:]]*((if|then|else|elif|do|while|until|exec|env|time|xargs|sudo|!)[[:space:]]+)*python3?([[:space:]]|$)'

for f in ${FILES[@]+"${FILES[@]}"}; do
    [[ -f "$f" ]] || continue
    is_exempt "$f" && continue

    # A shebang is an invocation even though the line begins with `#`.
    first="$(head -n 1 "$f" 2>/dev/null || true)"
    case "$first" in
        '#!'*python*) violation "$f:1 — python shebang on the commit path (consumer commits need nothing but bash + git; issue #355): ${first:0:80}" ;;
    esac

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
    done < <(LC_ALL=C grep -nE "$_PY_CMD" "$f" 2>/dev/null || true)
done

directive_end
