#!/usr/bin/env bash
# hooks.sh — manifest-driven git-hook generator for governance-bootstrap.
#
# Emits dispatcher hooks that discover installed directive folders at runtime.
# Two things drive what a dispatcher invokes:
#
#   1. The directive's `hook:` field — tells the generator which dispatcher
#      should invoke `check.sh`. (A directive declaring `hook: commit-msg`
#      has its validator wired into the commit-msg dispatcher.)
#   2. Any file at `directives/<id>/hooks/<kind>.sh` inside the directive
#      folder — a directive-owned side-effect helper for that hook kind. The
#      agent-token-accounting directive, for example, validates in
#      commit-msg but ALSO writes the ledger row from pre-commit and
#      stamps trailers from prepare-commit-msg; both side effects are
#      shipped as sibling `hooks/pre-commit.sh` and
#      `hooks/prepare-commit-msg.sh` inside the directive folder, so the
#      generator wires them in without the generator itself knowing
#      anything about that directive.
#
# Every generated hook carries an ownership marker on line 2:
#   # governance-kit:managed pack-version=<v> generated=<YYYY-MM-DD>
# so a second bootstrap run can recognize its own output and overwrite
# silently. Unmarked pre-existing hooks trip the collision detector and
# the skill prompts the user (wrap / merge / overwrite).
#
# The contract with callers:
#   generate_hooks <target-hooks-dir> <pack-version> <directive-spec-file>
#       Writes dispatchers for pre-commit, commit-msg, and
#       prepare-commit-msg. The spec file is still accepted so callers can
#       validate the selected install set before generation, but generated
#       hooks do not bake in selected directive ids. They scan installed
#       `tests/governance/directives/<id>/directive.yaml` files on every
#       invocation. This keeps user-owned post-install amendments working
#       without perfect hook regeneration.
#
#         <directive-id>\t<hook>\t<surface>\t<directive-folder>
#
#       <directive-folder> is the absolute path to the installed directive folder.
#       Already-existing marker-bearing hooks are overwritten silently;
#       unmarked files are left alone (caller handles collision).
#
#   hook_has_marker <hook-path>
#       Exits 0 if line 2 starts with `# governance-kit:managed`.
#
#   collision_check <target-hooks-dir> <hook-kind>...
#       Prints the set of unmarked hook kinds that would be clobbered.
#       Exits 0 always; caller decides what to do with the list.

set -eu

MARKER_PREFIX="# governance-kit:managed"

hook_has_marker() {
    local path="$1"
    [[ -f "$path" ]] || return 1
    local line2
    line2=$(sed -n '2p' "$path" 2>/dev/null || true)
    [[ "$line2" == "$MARKER_PREFIX"* ]]
}

collision_check() {
    local dir="$1"
    shift
    local kind hit=""
    for kind in "$@"; do
        local path="$dir/$kind"
        if [[ -f "$path" ]] && ! hook_has_marker "$path"; then
            hit+="$kind "
        fi
    done
    printf '%s' "$hit"
}

_write_marker() {
    # Writes shebang + marker directly to stdout so no command-substitution
    # strips the trailing newline.
    local version="$1"
    local date
    date=$(date +%Y-%m-%d)
    printf '#!/usr/bin/env bash\n%s pack-version=%s generated=%s\n' \
        "$MARKER_PREFIX" "$version" "$date"
}

# _check_ids_for_hook <spec-file> <hook-kind>
#   prints directive ids whose hook field (col 2) matches — these get check.sh run.
_check_ids_for_hook() {
    local spec="$1" kind="$2"
    awk -F'\t' -v k="$kind" '$2 == k { print $1 }' "$spec"
}

# _helper_ids_for_hook <spec-file> <hook-kind>
#   prints directive ids that ship a directives/<id>/hooks/<kind>.sh helper. Detected
#   by inspecting col 4 (the directive folder) at generation time.
_helper_ids_for_hook() {
    local spec="$1" kind="$2"
    local id directive_dir
    while IFS=$'\t' read -r id _ _ directive_dir; do
        [[ -z "$id" || -z "$directive_dir" ]] && continue
        if [[ -f "$directive_dir/hooks/$kind.sh" ]]; then
            printf '%s\n' "$id"
        fi
    done < "$spec"
}

_emit_runtime_discovery_helpers() {
    cat <<'HEADER'
directive_field() {
    local manifest="$1" field="$2"
    [[ -f "$manifest" ]] || return 0
    awk -v k="$field" '
        /^[[:space:]]*#/ { next }
        $0 ~ "^[[:space:]]*" k ":[[:space:]]*" {
            line = $0
            sub(/^[[:space:]]*[^:]+:[[:space:]]*/, "", line)
            sub(/[[:space:]]+#.*$/, "", line)
            sub(/^[[:space:]]+/, "", line)
            sub(/[[:space:]]+$/, "", line)
            if (line ~ /^".*"$/ || line ~ /^'\''.*'\''$/) {
                line = substr(line, 2, length(line) - 2)
            }
            print line
            exit
        }
    ' "$manifest"
}

directive_ids_for_hook() {
    local kind="$1" mode="$2"
    local dir id hook helper
    [[ -d "$DIRECTIVES_DIR" ]] || return 0
    for dir in "$DIRECTIVES_DIR"/*; do
        [[ -d "$dir" && -f "$dir/directive.yaml" ]] || continue
        id="${dir##*/}"
        hook="$(directive_field "$dir/directive.yaml" hook)"
        helper="$dir/hooks/$kind.sh"
        case "$mode" in
            helper)
                [[ -x "$helper" ]] && printf '%s\n' "$id"
                ;;
            check)
                [[ "$hook" == "$kind" && -x "$dir/check.sh" ]] && printf '%s\n' "$id"
                ;;
        esac
    done | sort
}
HEADER
}

# _emit_pre_commit <out> <version>
_emit_pre_commit() {
    local out="$1" version="$2"

    {
        _write_marker "$version"
        cat <<'HEADER'
# Governance pre-commit hook — generated by governance-bootstrap.
#
# Escape hatches:
#   SKIP_GOVERNANCE=1 git commit ...    # telegraphs intent; CI still enforces
#   git commit --no-verify              # skips all hooks

set -u

if [[ "${SKIP_GOVERNANCE:-0}" == "1" ]]; then
    echo "⊘ governance pre-commit skipped (SKIP_GOVERNANCE=1)" >&2
    exit 0
fi

ROOT="$(git rev-parse --show-toplevel)"
DIRECTIVES_DIR="$ROOT/tests/governance/directives"

HEADER
        _emit_runtime_discovery_helpers
        cat <<'FOOTER'
while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    bash "$DIRECTIVES_DIR/$id/hooks/pre-commit.sh" || exit 1
done < <(directive_ids_for_hook pre-commit helper)

fail=0
while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    bash "$DIRECTIVES_DIR/$id/check.sh" || fail=1
done < <(directive_ids_for_hook pre-commit check)

if [[ $fail -ne 0 ]]; then
    cat >&2 <<EOF

────────────────────────────────────────
✗ Commit blocked by governance.

Fix the violations above, or bypass (CI will still enforce):
    SKIP_GOVERNANCE=1 git commit ...
    git commit --no-verify
────────────────────────────────────────
EOF
    exit 1
fi

exit 0
FOOTER
    } > "$out"
    chmod +x "$out"
}

# _emit_commit_msg <out> <version>
_emit_commit_msg() {
    local out="$1" version="$2"

    {
        _write_marker "$version"
        cat <<'HEADER'
# Governance commit-msg hook — generated by governance-bootstrap.
#
# Escape hatches:
#   SKIP_GOVERNANCE=1 git commit ...
#   git commit --no-verify

set -u

if [[ "${SKIP_GOVERNANCE:-0}" == "1" ]]; then
    exit 0
fi

ROOT="$(git rev-parse --show-toplevel)"
DIRECTIVES_DIR="$ROOT/tests/governance/directives"
MSG_FILE="$1"
HEADER
        _emit_runtime_discovery_helpers
        cat <<'FOOTER'
while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    bash "$DIRECTIVES_DIR/$id/hooks/commit-msg.sh" "$MSG_FILE" || exit 1
done < <(directive_ids_for_hook commit-msg helper)

while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    if ! bash "$DIRECTIVES_DIR/$id/check.sh" "$MSG_FILE"; then
        echo "✗ commit blocked by governance (${id})" >&2
        exit 1
    fi
done < <(directive_ids_for_hook commit-msg check)

exit 0
FOOTER
    } > "$out"
    chmod +x "$out"
}

# _emit_prepare_commit_msg <out> <version>
_emit_prepare_commit_msg() {
    local out="$1" version="$2"

    {
        _write_marker "$version"
        cat <<'HEADER'
# Governance prepare-commit-msg hook — generated by governance-bootstrap.

set -u

if [[ "${SKIP_GOVERNANCE:-0}" == "1" ]]; then
    exit 0
fi

ROOT="$(git rev-parse --show-toplevel)"
DIRECTIVES_DIR="$ROOT/tests/governance/directives"
MSG_FILE="$1"
SOURCE="${2:-}"
SHA="${3:-}"
HEADER
        _emit_runtime_discovery_helpers
        cat <<'FOOTER'
while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    bash "$DIRECTIVES_DIR/$id/hooks/prepare-commit-msg.sh" "$MSG_FILE" "$SOURCE" "$SHA" || exit 1
done < <(directive_ids_for_hook prepare-commit-msg helper)

while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    bash "$DIRECTIVES_DIR/$id/check.sh" "$MSG_FILE" "$SOURCE" "$SHA" || exit 1
done < <(directive_ids_for_hook prepare-commit-msg check)

exit 0
FOOTER
    } > "$out"
    chmod +x "$out"
}

# _emit_post_commit <out> <version>
#
# Post-commit cannot block — `git commit` has already succeeded by the time
# this hook fires. Directives wired here run as **advisories**: each
# check.sh's exit code is captured, violations are surfaced (the directive's
# own stderr/stdout passes through), and the dispatcher always exits 0.
# CI (`tests/governance/run.sh`) is the hard enforcement point for these
# directives — local post-commit is the immediate-feedback nudge.
_emit_post_commit() {
    local out="$1" version="$2"

    {
        _write_marker "$version"
        cat <<'HEADER'
# Governance post-commit hook — generated by governance-bootstrap.
#
# Post-commit cannot block. Directives wired here are advisories: violations
# are printed but the commit has already landed. CI (running
# tests/governance/run.sh) is the hard gate for these directives.
#
# Escape hatch:
#   SKIP_GOVERNANCE=1 git commit ...    # silences the advisories too

set -u

if [[ "${SKIP_GOVERNANCE:-0}" == "1" ]]; then
    exit 0
fi

ROOT="$(git rev-parse --show-toplevel)"
DIRECTIVES_DIR="$ROOT/tests/governance/directives"
HEADER
        _emit_runtime_discovery_helpers
        cat <<'FOOTER'
while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    bash "$DIRECTIVES_DIR/$id/hooks/post-commit.sh" || true
done < <(directive_ids_for_hook post-commit helper)

advisories=0
while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    if ! bash "$DIRECTIVES_DIR/$id/check.sh"; then
        advisories=$((advisories + 1))
    fi
done < <(directive_ids_for_hook post-commit check)

if [[ $advisories -gt 0 ]]; then
    cat >&2 <<EOF

────────────────────────────────────────
⚠ Post-commit advisory: ${advisories} directive(s) reported violations.
The commit was not blocked. CI will enforce these on push.
────────────────────────────────────────
EOF
fi

exit 0
FOOTER
    } > "$out"
    chmod +x "$out"
}

generate_hooks() {
    local dir="$1" version="$2" spec="$3"
    mkdir -p "$dir"

    local kind
    for kind in pre-commit commit-msg prepare-commit-msg post-commit; do
        local out="$dir/$kind"
        if [[ -f "$out" ]] && ! hook_has_marker "$out"; then
            echo "hooks.sh: refusing to overwrite unmanaged $out" >&2
            return 2
        fi

        case "$kind" in
            pre-commit)         _emit_pre_commit         "$out" "$version" ;;
            commit-msg)         _emit_commit_msg         "$out" "$version" ;;
            prepare-commit-msg) _emit_prepare_commit_msg "$out" "$version" ;;
            post-commit)        _emit_post_commit        "$out" "$version" ;;
        esac
    done
}
