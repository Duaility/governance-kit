#!/usr/bin/env bash
# governance-kit:managed kit-version=0.5.0
# Shared helpers for governance directive tests.
# Source this from every directive's check.sh. Packs always live two levels
# deep, so directives at `.governance/packs/<owner>/<name>/directives/<id>/check.sh`
# reach lib.sh with five `..` segments:
#   source "$(dirname "$0")/../../../../../lib.sh"

set -u

# Color output only when stdout is a terminal AND terminfo reports a usable
# palette. Using tput (rather than raw \033[…] escapes) means TERM=dumb and
# stripped CI shells get empty strings — no ANSI garbage in logs. tput ships
# with ncurses on macOS and every mainstream Linux, so no new deps.
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1 && tput setaf 1 >/dev/null 2>&1; then
    readonly C_RED=$(tput setaf 1)
    readonly C_GREEN=$(tput setaf 2)
    readonly C_YELLOW=$(tput setaf 3)
    readonly C_BOLD=$(tput bold)
    readonly C_RESET=$(tput sgr0)
else
    readonly C_RED=""
    readonly C_GREEN=""
    readonly C_YELLOW=""
    readonly C_BOLD=""
    readonly C_RESET=""
fi

# Track violations for the current directive. Each directive should call
# `directive_start` at the top, then `violation` for each problem found, then
# `directive_end` at the bottom. `directive_end` exits 0 if no violations,
# 1 otherwise.
_DIRECTIVE_NAME=""
_VIOLATION_COUNT=0
_VIOLATIONS=()

directive_start() {
    _DIRECTIVE_NAME="$1"
    _VIOLATION_COUNT=0
    _VIOLATIONS=()
}

violation() {
    _VIOLATION_COUNT=$((_VIOLATION_COUNT + 1))
    _VIOLATIONS+=("$1")
}

directive_end() {
    if [[ $_VIOLATION_COUNT -eq 0 ]]; then
        printf "%s✓%s %s\n" "$C_GREEN" "$C_RESET" "$_DIRECTIVE_NAME"
        exit 0
    fi
    printf "%s✗ %s%s (%d violation%s)\n" "$C_RED" "$_DIRECTIVE_NAME" "$C_RESET" \
        "$_VIOLATION_COUNT" "$([[ $_VIOLATION_COUNT -eq 1 ]] || echo s)"
    for v in "${_VIOLATIONS[@]}"; do
        printf "    %s\n" "$v"
    done
    exit 1
}

# Emit tracked files (respects .gitignore), optionally filtered by a pathspec.
# Usage: tracked_files                → all tracked files
#        tracked_files '*.py'         → all tracked .py files
#        tracked_files ':!vendor/**'  → all tracked files excluding vendor/
tracked_files() {
    if [[ $# -eq 0 ]]; then
        git ls-files
    else
        git ls-files "$@"
    fi
}

# Exit with skip status if we're not inside a git working tree.
require_git() {
    if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
        printf "%s⊘%s %s (not a git repo — skipped)\n" \
            "$C_YELLOW" "$C_RESET" "$_DIRECTIVE_NAME"
        exit 0
    fi
}

# Allow in-source waivers. Directives that support exceptions should grep for
# `governance: allow-<directive-name>` on the violating line and skip it.
# Example: `foo = "AKIA..."  # governance: allow-secrets-hygiene TICKET-123`
has_waiver() {
    local file="$1" line_no="$2" directive="$3"
    sed -n "${line_no}p" "$file" | grep -q "governance: allow-${directive}"
}

# File-level waiver — for sub-checks where the violation is the file itself
# (not a specific line), scan the first 10 lines for a head-of-file token.
# A sub-check name is required so multiple file-level sub-checks can share
# the same `allow-<directive>` prefix without colliding.
# Example: `// governance: allow-repo-hygiene file-size-limit TICKET-123`
has_file_waiver() {
    local file="$1" directive="$2" subcheck="$3"
    [[ -f "$file" ]] || return 1
    head -n 10 "$file" 2>/dev/null \
        | grep -q "governance: allow-${directive} ${subcheck}"
}

# ── Per-directive configuration ────────────────────────────────────────────
# A directive's user-tunable config lives at `.governance/conf/<id>.conf`,
# seeded once from the directive's shipped `config.conf` template at install
# time and never overwritten by `pack update` / `reset` / `kit update`. The
# format is line-based: `KEY=value` lines (KEY is `[A-Z_]+`) are scalar
# settings; every other non-comment, non-blank line is a directive-defined
# rule line. Blank lines and `#` comments are ignored.
#
# These helpers resolve the repo root themselves, so they work identically in
# a commit-msg hook (Mode A) and under run.sh / CI (Mode B).

# conf_file <directive-id>
# Print the path to the directive's user conf and return 0 if it exists;
# return 1 (printing nothing) otherwise. Conf-driven directives typically
# treat a missing conf as "nothing opted in" and no-op.
conf_file() {
    local id="$1" root
    root="$(git rev-parse --show-toplevel 2>/dev/null)" || return 1
    local f="$root/.governance/conf/$id.conf"
    [[ -f "$f" ]] || return 1
    printf '%s\n' "$f"
}

# conf_get <directive-id> <KEY> [<default>]
# Resolve a scalar setting. Precedence: environment `GOVERNANCE_<KEY>` (when
# set and non-empty) > first `^KEY=` line in the conf > default. Always prints
# a value (the default if nothing else matches) and returns 0.
conf_get() {
    local id="$1" key="$2" default="${3:-}"
    local env_name="GOVERNANCE_${key}"
    if [[ -n "${!env_name:-}" ]]; then
        printf '%s\n' "${!env_name}"
        return 0
    fi
    local f line
    if f="$(conf_file "$id")"; then
        line="$(grep -E "^${key}=" "$f" 2>/dev/null | head -n 1)"
        if [[ -n "$line" ]]; then
            printf '%s\n' "${line#*=}"
            return 0
        fi
    fi
    printf '%s\n' "$default"
}

# conf_rule_lines <directive-id>
# Emit the directive-defined rule lines from the conf: trimmed, with `#`
# comments and blank lines stripped, and `KEY=value` scalar lines skipped.
# Emits nothing (returns 0) when no conf exists.
conf_rule_lines() {
    local f raw entry
    f="$(conf_file "$1")" || return 0
    while IFS= read -r raw || [[ -n "$raw" ]]; do
        entry="${raw%%#*}"
        entry="${entry#"${entry%%[![:space:]]*}"}"
        entry="${entry%"${entry##*[![:space:]]}"}"
        [[ -z "$entry" ]] && continue
        [[ "$entry" =~ ^[A-Z_]+= ]] && continue
        printf '%s\n' "$entry"
    done < "$f"
}

# conf_list <directive-id> <defaults-file>
# Emit the effective list for a directive whose default items ship in
# <defaults-file> (a pack-owned `defaults.conf`, one item per line), with the
# user overlay (`.governance/conf/<id>.conf`) layered on top:
#   bare line   → adds an item
#   !item       → removes the matching default item (gitignore-style negation)
#   KEY=value   → ignored here (read scalars with conf_get)
# Default items keep their order; additions follow. A `!` that matches no
# default is a harmless no-op. Comments and blank lines are stripped from both.
_conf_trim() {  # echo the argument with surrounding whitespace removed
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}
_conf_norm() {  # trim + collapse internal whitespace runs to one space
    local parts
    # shellcheck disable=SC2206
    read -ra parts <<< "$1"
    printf '%s' "${parts[*]}"
}
conf_list() {
    local id="$1" defaults="$2" overlay line item key
    local removed=$'\n' emitted=$'\n'
    local adds=()

    # Membership tests compare whitespace-normalized keys so a `!frozen-section
    # QUALITY.md Resolved` overlay line matches a column-aligned default.
    if overlay="$(conf_file "$id")"; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            line="$(_conf_trim "${line%%#*}")"
            [[ -z "$line" ]] && continue
            [[ "$line" =~ ^[A-Z_]+= ]] && continue
            if [[ "${line:0:1}" == '!' ]]; then
                item="$(_conf_norm "${line:1}")"
                [[ -n "$item" ]] && removed+="$item"$'\n'
            else
                # An explicit leading '+' is an optional "add" marker; strip it.
                [[ "${line:0:1}" == '+' ]] && line="$(_conf_trim "${line:1}")"
                [[ -n "$line" ]] && adds+=("$line")
            fi
        done < "$overlay"
    fi

    # Defaults in declared order, minus anything the overlay removed.
    if [[ -f "$defaults" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            line="$(_conf_trim "${line%%#*}")"
            [[ -z "$line" ]] && continue
            [[ "$line" =~ ^[A-Z_]+= ]] && continue
            key="$(_conf_norm "$line")"
            case "$removed" in *$'\n'"$key"$'\n'*) continue ;; esac
            case "$emitted" in *$'\n'"$key"$'\n'*) continue ;; esac
            emitted+="$key"$'\n'
            printf '%s\n' "$line"
        done < "$defaults"
    fi

    # Overlay additions (skipping ones already emitted or explicitly removed).
    # `${adds[@]+...}` keeps an empty array safe under `set -u` on bash 3.2.
    for line in ${adds[@]+"${adds[@]}"}; do
        key="$(_conf_norm "$line")"
        case "$removed" in *$'\n'"$key"$'\n'*) continue ;; esac
        case "$emitted" in *$'\n'"$key"$'\n'*) continue ;; esac
        emitted+="$key"$'\n'
        printf '%s\n' "$line"
    done
}
