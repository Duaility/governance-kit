#!/usr/bin/env bash
# release.sh — cut a governance-kit release on one of the two semantic axes.
#
#   bash scripts/release.sh <kit|core> <version> [--dry-run] [--push]
#
# governance-kit ships two independently-versioned artifacts from one repo (see
# governance/references/VERSIONING.md):
#
#   kit   — the framework. Source of truth: governance/assets/kit.yaml `version`.
#           Re-stamps every derived copy (SKILL.md frontmatter, install.yaml
#           kit_version, the `kit-version=` managed markers).
#   core  — the bundled governance-kit/core pack. Source of truth:
#           packs/core/pack.yaml `version`.
#
# This is the ONLY sanctioned writer of version lines — feature/fix PRs never
# touch them. The script: validates a clean tree on `main` with a green suite,
# bumps the one source of truth, re-derives every stamp, regenerates the
# CHANGELOG.md section from the Conventional Commits since the last matching
# tag, makes the `chore(release)` commit (through the hook path, so accounting
# trailers attach), and creates the prefixed annotated tag `<axis>/vX.Y.Z`.
# Pushing the tag (`--push`, or `git push --tags` later) triggers release.yml.
#
# Escape hatch: RELEASE_SKIP_SUITE=1 bypasses the green-suite preflight (use
# only when the suite is red for reasons unrelated to the release).

set -euo pipefail

die() { echo "release: $*" >&2; exit 1; }
note() { echo "release: $*" >&2; }

# ── args ──────────────────────────────────────────────────────────────────
AXIS="${1:-}"; VERSION="${2:-}"; shift $(( $# >= 2 ? 2 : $# )) || true
DRY_RUN=0; PUSH=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --push)    PUSH=1 ;;
        *) die "unknown flag: $arg" ;;
    esac
done

[[ "$AXIS" == "kit" || "$AXIS" == "core" ]] || die "usage: release.sh <kit|core> <version> [--dry-run] [--push]"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version must be semver X.Y.Z (got '${VERSION:-}')"

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repo"
cd "$ROOT"
# shellcheck disable=SC1091
source "governance/assets/packs/lib/install.sh"   # stamp_managed_marker

# ── helpers ───────────────────────────────────────────────────────────────
read_quoted_field() {   # <file> <anchor-regex> → first quoted value on the matching line
    awk -v a="$2" '$0 ~ a { if (match($0, /"[^"]*"/)) { print substr($0, RSTART+1, RLENGTH-2); exit } }' "$1"
}
set_quoted_field() {    # <file> <anchor-regex> <newval> — replace first quoted value on first matching line
    local file="$1" anchor="$2" newval="$3" tmp
    tmp="$(mktemp)"
    awk -v a="$anchor" -v v="$newval" '
        !done && $0 ~ a { sub(/"[^"]*"/, "\"" v "\""); done=1 }
        { print }
    ' "$file" > "$tmp"
    cat "$tmp" > "$file"; rm -f "$tmp"
}
semver_gt() {           # true when $1 > $2
    [[ "$1" != "$2" ]] && [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" == "$1" ]]
}

# ── resolve current version + tag ─────────────────────────────────────────
if [[ "$AXIS" == "kit" ]]; then
    SRC="governance/assets/kit.yaml";   ANCHOR='^version: "'
else
    SRC="packs/core/pack.yaml";         ANCHOR='^version: "'
fi
CURRENT="$(read_quoted_field "$SRC" "$ANCHOR")"
[[ -n "$CURRENT" ]] || die "could not read current $AXIS version from $SRC"
TAG="${AXIS}/v${VERSION}"

semver_gt "$VERSION" "$CURRENT" || die "$VERSION is not greater than current $AXIS version $CURRENT"
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1 && die "tag $TAG already exists"

note "axis=$AXIS  $CURRENT → $VERSION  tag=$TAG  dry-run=$DRY_RUN"

# ── preflight ─────────────────────────────────────────────────────────────
# The branch + clean-tree gates apply to real releases only; --dry-run is a
# preview that runs from any branch/state.
branch="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$DRY_RUN" -eq 0 ]]; then
    [[ "$branch" == "main" || "$branch" == "master" ]] || die "must release from main (on '$branch')"
    [[ -z "$(git status --porcelain)" ]] || die "working tree is dirty — commit or stash first"
fi
if [[ "${RELEASE_SKIP_SUITE:-0}" != "1" ]]; then
    if bash .governance/run.sh >/tmp/release-suite.log 2>&1; then
        note "suite: green"
    elif [[ "$DRY_RUN" -eq 1 ]]; then
        note "suite: RED (dry-run — continuing; see /tmp/release-suite.log)"
    else
        die "suite is red — fix it or set RELEASE_SKIP_SUITE=1 (see /tmp/release-suite.log)"
    fi
fi

# ── collect the files to re-stamp ─────────────────────────────────────────
# kit releases re-stamp every derived kit-version copy. core releases only
# touch the pack manifest. Marker files are auto-discovered from tracked files
# carrying the leading marker, minus generator code, test data, and eval
# fixtures (whose markers are deliberately pinned to old versions).
marker_files=()
if [[ "$AXIS" == "kit" ]]; then
    while IFS= read -r f; do marker_files+=("$f"); done < <(
        git grep -lE '^# governance-kit:managed' -- \
            ':(exclude)governance/evals/*' \
            ':(exclude)governance/assets/packs/lib/*' \
            ':(exclude)governance/references/*' \
            ':(exclude)scripts/test-*' 2>/dev/null | sort
    )
fi

# ── changelog section ─────────────────────────────────────────────────────
build_changelog_section() {
    local date base range
    date="$(date +%Y-%m-%d)"
    base="$(git describe --tags --match "${AXIS}/v*" --abbrev=0 2>/dev/null || true)"
    if [[ -z "$base" ]]; then
        # First tagged release on this axis — don't dump all of history; the
        # curated seed section in CHANGELOG.md already covers pre-tag changes.
        printf '## [%s] - %s\n\n- Initial tagged release on the %s axis. Pre-tag history is in the curated entries below.\n\n' "$TAG" "$date" "$AXIS"
        return
    fi
    range="${base}..HEAD"
    printf '## [%s] - %s\n\n' "$TAG" "$date"
    local added fixed changed
    added="$(git log "$range" --no-merges --format='%s' | sed -nE 's/^feat(\([^)]*\))?(!)?: (.+)/- \3/p')"
    fixed="$(git log "$range" --no-merges --format='%s' | sed -nE 's/^fix(\([^)]*\))?(!)?: (.+)/- \3/p')"
    changed="$(git log "$range" --no-merges --format='%s' | sed -nE 's/^(refactor|perf|docs|build|ci|chore|revert|style|test)(\([^)]*\))?(!)?: (.+)/- \4/p')"
    [[ -n "$added"   ]] && printf '### Added\n%s\n\n' "$added"
    [[ -n "$fixed"   ]] && printf '### Fixed\n%s\n\n' "$fixed"
    [[ -n "$changed" ]] && printf '### Changed\n%s\n\n' "$changed"
}
SECTION="$(build_changelog_section)"

prepend_changelog() {   # insert SECTION above the first existing "## [" entry, or append
    local cl="CHANGELOG.md" tmp; tmp="$(mktemp)"
    if [[ ! -f "$cl" ]]; then
        { printf '# Changelog\n\nAll notable changes to governance-kit. Kit and core-pack releases are\ntagged `kit/vX.Y.Z` / `core/vX.Y.Z`; see governance/references/VERSIONING.md.\n\n'; printf '%s' "$SECTION"; } > "$cl"
        return
    fi
    # Insert the new release section after the [Unreleased] block — before the
    # first *versioned* entry or the `---` separator that precedes the
    # historical section — so [Unreleased] stays on top, newest release next.
    # Find the insertion line (a single value, awk-safe), then splice with
    # head/tail — awk -v can't carry a multi-line section string.
    # `$(...)` strips SECTION's trailing newlines, so emit a blank line after it
    # to keep sections separated.
    local at
    at="$(awk '(/^## \[/ && $0 !~ /\[Unreleased\]/) || /^---[[:space:]]*$/ { print NR; exit }' "$cl")"
    if [[ -n "$at" ]]; then
        { head -n "$((at - 1))" "$cl"; printf '%s\n\n' "$SECTION"; tail -n "+$at" "$cl"; } > "$tmp"
    else
        { cat "$cl"; printf '\n%s\n' "$SECTION"; } > "$tmp"
    fi
    cat "$tmp" > "$cl"; rm -f "$tmp"
}

# ── dry-run: show the plan and stop ───────────────────────────────────────
if [[ "$DRY_RUN" -eq 1 ]]; then
    note "── DRY RUN — no files written ──"
    echo "source bump:   $SRC  $CURRENT → $VERSION"
    if [[ "$AXIS" == "kit" ]]; then
        echo "frontmatter:   governance/SKILL.md  version → $VERSION"
        echo "manifest:      .governance/install.yaml  kit_version → $VERSION"
        echo "markers (${#marker_files[@]}):"
        printf '   %s\n' "${marker_files[@]}"
    fi
    echo "tag:           $TAG (annotated)"
    echo "changelog section:"
    printf '%s\n' "$SECTION" | sed 's/^/   /'
    exit 0
fi

# ── apply ─────────────────────────────────────────────────────────────────
set_quoted_field "$SRC" "$ANCHOR" "$VERSION"
if [[ "$AXIS" == "kit" ]]; then
    set_quoted_field "governance/SKILL.md" '^  version: "' "$VERSION"
    set_quoted_field ".governance/install.yaml" '^kit_version: "' "$VERSION"
    for f in "${marker_files[@]}"; do
        [[ -f "$f" ]] && stamp_managed_marker "$f" "$VERSION"
    done
fi
prepend_changelog

git add -A
# A `chore(release)` commit is a mechanical version bump: it has no feature
# issue to anchor (so it can't satisfy commit-message-format's `(#N)` suffix)
# and touches no receipt (so commit-issue-receipt-match has nothing to match).
# Both are waived in-body; the accounting directives still apply and are stamped
# by the runtime populator like any other agent commit.
git commit \
    -m "chore(release): ${AXIS} v${CURRENT} → v${VERSION}" \
    -m "governance: allow-commit-message-format release commits are mechanical version bumps, not tied to a feature issue" \
    -m "governance: allow-commit-issue-receipt-match release commits carry no receipt"
git tag -a "$TAG" -m "${AXIS} release ${VERSION}"
note "committed + tagged $TAG"

if [[ "$PUSH" -eq 1 ]]; then
    git push origin "$branch"
    git push origin "$TAG"
    note "pushed $branch + $TAG"
else
    note "not pushed — run: git push origin $branch && git push origin $TAG"
fi
