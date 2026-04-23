#!/usr/bin/env bash
# hooks.sh — manifest-driven git-hook generator for governance-bootstrap.
#
# Emits dispatcher hooks that iterate only the rules the user actually
# selected. Two things drive what a dispatcher invokes:
#
#   1. The rule's `hook:` field — tells the generator which dispatcher
#      should invoke `check.sh`. (A rule declaring `hook: commit-msg`
#      has its validator wired into the commit-msg dispatcher.)
#   2. Any file at `rules/<id>/hooks/<kind>.sh` inside the rule folder —
#      a rule-owned side-effect helper for that hook kind. The
#      agent-token-accounting rule, for example, validates in
#      commit-msg but ALSO writes the ledger row from pre-commit and
#      stamps trailers from prepare-commit-msg; both side effects are
#      shipped as sibling `hooks/pre-commit.sh` and
#      `hooks/prepare-commit-msg.sh` inside the rule folder, so the
#      generator wires them in without the generator itself knowing
#      anything about that rule.
#
# Every generated hook carries an ownership marker on line 2:
#   # governance-kit:managed pack-version=<v> generated=<YYYY-MM-DD>
# so a second bootstrap run can recognize its own output and overwrite
# silently. Unmarked pre-existing hooks trip the collision detector and
# the skill prompts the user (wrap / merge / overwrite).
#
# The contract with callers:
#   generate_hooks <target-hooks-dir> <pack-version> <rule-spec-file>
#       Writes one hook per kind that has at least one selected rule
#       or rule-owned helper. <rule-spec-file> is a TSV, one line per
#       selected rule:
#
#         <rule-id>\t<hook>\t<surface>\t<rule-folder>
#
#       <rule-folder> is the absolute path to the rule's installed
#       folder (e.g. `/repo/tests/governance/rules/<id>`). The
#       generator inspects `<rule-folder>/hooks/<kind>.sh` to decide
#       whether the rule contributes a helper to each dispatcher.
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
#   prints rule ids whose hook field (col 2) matches — these get check.sh run.
_check_ids_for_hook() {
    local spec="$1" kind="$2"
    awk -F'\t' -v k="$kind" '$2 == k { print $1 }' "$spec"
}

# _helper_ids_for_hook <spec-file> <hook-kind>
#   prints rule ids that ship a rules/<id>/hooks/<kind>.sh helper. Detected
#   by inspecting col 4 (the rule folder) at generation time.
_helper_ids_for_hook() {
    local spec="$1" kind="$2"
    local id rule_dir
    while IFS=$'\t' read -r id _ _ rule_dir; do
        [[ -z "$id" || -z "$rule_dir" ]] && continue
        if [[ -f "$rule_dir/hooks/$kind.sh" ]]; then
            printf '%s\n' "$id"
        fi
    done < "$spec"
}

# _emit_pre_commit <out> <version> <spec-file>
_emit_pre_commit() {
    local out="$1" version="$2" spec="$3"
    # shellcheck disable=SC2207
    local helpers=( $(_helper_ids_for_hook "$spec" pre-commit) )
    # shellcheck disable=SC2207
    local checks=(  $(_check_ids_for_hook  "$spec" pre-commit) )

    {
        _write_marker "$version"
        cat <<'HEADER'
# Governance pre-commit hook — generated from selected pack rules.
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
RULES_DIR="$ROOT/tests/governance/rules"

HEADER

        if [[ ${#helpers[@]} -gt 0 ]]; then
            printf '# Rule-owned pre-commit helpers (side effects — run before validation).\n'
            for id in "${helpers[@]}"; do
                cat <<RULE
if [[ -x "\$RULES_DIR/${id}/hooks/pre-commit.sh" ]]; then
    bash "\$RULES_DIR/${id}/hooks/pre-commit.sh" || exit 1
fi
RULE
            done
            printf '\n'
        fi

        printf 'fail=0\n'
        for id in ${checks[@]+"${checks[@]}"}; do
            cat <<RULE
if [[ -x "\$RULES_DIR/${id}/check.sh" ]]; then
    bash "\$RULES_DIR/${id}/check.sh" || fail=1
fi
RULE
        done

        cat <<'FOOTER'

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

# _emit_commit_msg <out> <version> <spec-file>
_emit_commit_msg() {
    local out="$1" version="$2" spec="$3"
    # shellcheck disable=SC2207
    local helpers=( $(_helper_ids_for_hook "$spec" commit-msg) )
    # shellcheck disable=SC2207
    local checks=(  $(_check_ids_for_hook  "$spec" commit-msg) )

    {
        _write_marker "$version"
        cat <<'HEADER'
# Governance commit-msg hook — generated from selected pack rules.
#
# Escape hatches:
#   SKIP_GOVERNANCE=1 git commit ...
#   git commit --no-verify

set -u

if [[ "${SKIP_GOVERNANCE:-0}" == "1" ]]; then
    exit 0
fi

ROOT="$(git rev-parse --show-toplevel)"
RULES_DIR="$ROOT/tests/governance/rules"
MSG_FILE="$1"
HEADER

        for id in ${helpers[@]+"${helpers[@]}"}; do
            cat <<RULE

if [[ -x "\$RULES_DIR/${id}/hooks/commit-msg.sh" ]]; then
    bash "\$RULES_DIR/${id}/hooks/commit-msg.sh" "\$MSG_FILE" || exit 1
fi
RULE
        done

        for id in ${checks[@]+"${checks[@]}"}; do
            cat <<RULE

if [[ -x "\$RULES_DIR/${id}/check.sh" ]]; then
    if ! bash "\$RULES_DIR/${id}/check.sh" "\$MSG_FILE"; then
        echo "✗ commit blocked by governance (${id})" >&2
        exit 1
    fi
fi
RULE
        done

        printf '\nexit 0\n'
    } > "$out"
    chmod +x "$out"
}

# _emit_prepare_commit_msg <out> <version> <spec-file>
_emit_prepare_commit_msg() {
    local out="$1" version="$2" spec="$3"
    # shellcheck disable=SC2207
    local helpers=( $(_helper_ids_for_hook "$spec" prepare-commit-msg) )
    # shellcheck disable=SC2207
    local checks=(  $(_check_ids_for_hook  "$spec" prepare-commit-msg) )

    {
        _write_marker "$version"
        cat <<'HEADER'
# Governance prepare-commit-msg hook — generated from selected pack rules.

set -u

if [[ "${SKIP_GOVERNANCE:-0}" == "1" ]]; then
    exit 0
fi

ROOT="$(git rev-parse --show-toplevel)"
RULES_DIR="$ROOT/tests/governance/rules"
MSG_FILE="$1"
SOURCE="${2:-}"
SHA="${3:-}"
HEADER

        for id in ${helpers[@]+"${helpers[@]}"}; do
            cat <<RULE

if [[ -x "\$RULES_DIR/${id}/hooks/prepare-commit-msg.sh" ]]; then
    bash "\$RULES_DIR/${id}/hooks/prepare-commit-msg.sh" "\$MSG_FILE" "\$SOURCE" "\$SHA" || exit 1
fi
RULE
        done

        for id in ${checks[@]+"${checks[@]}"}; do
            cat <<RULE

if [[ -x "\$RULES_DIR/${id}/check.sh" ]]; then
    bash "\$RULES_DIR/${id}/check.sh" "\$MSG_FILE" "\$SOURCE" "\$SHA" || exit 1
fi
RULE
        done

        printf '\nexit 0\n'
    } > "$out"
    chmod +x "$out"
}

generate_hooks() {
    local dir="$1" version="$2" spec="$3"
    mkdir -p "$dir"

    local kind
    for kind in pre-commit commit-msg prepare-commit-msg; do
        local have_helper=0 have_check=0
        if _helper_ids_for_hook "$spec" "$kind" | grep -q .; then
            have_helper=1
        fi
        if _check_ids_for_hook "$spec" "$kind" | grep -q .; then
            have_check=1
        fi
        if [[ $have_helper -eq 0 && $have_check -eq 0 ]]; then
            continue
        fi

        local out="$dir/$kind"
        if [[ -f "$out" ]] && ! hook_has_marker "$out"; then
            echo "hooks.sh: refusing to overwrite unmanaged $out" >&2
            return 2
        fi

        case "$kind" in
            pre-commit)         _emit_pre_commit         "$out" "$version" "$spec" ;;
            commit-msg)         _emit_commit_msg         "$out" "$version" "$spec" ;;
            prepare-commit-msg) _emit_prepare_commit_msg "$out" "$version" "$spec" ;;
        esac
    done
}
