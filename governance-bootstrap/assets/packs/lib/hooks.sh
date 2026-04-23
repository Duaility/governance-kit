#!/usr/bin/env bash
# hooks.sh — manifest-driven git-hook generator for governance-bootstrap.
#
# Emits dispatcher hooks that iterate only the rules the user actually
# selected, based on each rule's `hook:` declaration in pack.yaml. The
# set of hook kinds produced (pre-commit, commit-msg,
# prepare-commit-msg) depends on which selected rules declare each hook.
#
# Every generated hook carries an ownership marker on line 2:
#   # governance-kit:managed pack-version=<v> generated=<YYYY-MM-DD>
# so a second bootstrap run can recognize its own output and overwrite
# silently. Unmarked pre-existing hooks trip the collision detector and
# the skill prompts the user (wrap / merge / overwrite).
#
# The contract with callers:
#   generate_hooks <target-hooks-dir> <pack-version> <rule-spec-file>
#       Writes one hook per kind that has at least one selected rule.
#       <rule-spec-file> is a TSV: "<rule-id>\t<hook>\t<surface>".
#       Already-existing marker-bearing hooks are overwritten silently;
#       unmarked files are left alone (caller handles collision).
#
#   hook_has_marker <hook-path>
#       Exits 0 if line 2 starts with `# governance-kit:managed`.
#
#   collision_check <target-hooks-dir> <hook-kind>...
#       Prints the set of unmarked hook kinds that would be clobbered.
#       Exits 0 always; caller decides what to do with the list.
#
# The generated hooks call scripts by path under `tests/governance/`,
# the install location the skill copies rules into. They do not import
# this library at runtime — it is a compile-time emitter.

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

# _rules_for_hook <spec-file> <hook-kind>
#   prints rule ids (one per line) whose hook field matches.
_rules_for_hook() {
    local spec="$1" kind="$2"
    awk -F'\t' -v k="$kind" '$2 == k { print $1 }' "$spec"
}

# _emit_pre_commit <out-path> <version> <rule-ids...>
_emit_pre_commit() {
    local out="$1" version="$2"
    shift 2
    local ids=("$@")

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

# Agent-accounting: if the commit is agent-authored (detected via runtime env
# vars), append the COSTS.md row and stage it BEFORE governance tests run.
ACCOUNTING="$ROOT/scripts/governance/agent-accounting.sh"
if [[ -x "$ACCOUNTING" ]]; then
    bash "$ACCOUNTING" || exit 1
fi

fail=0
HEADER

        for id in "${ids[@]}"; do
            cat <<RULE
if [[ -x "\$RULES_DIR/${id}.sh" ]]; then
    bash "\$RULES_DIR/${id}.sh" || fail=1
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

# _emit_commit_msg <out-path> <version> <rule-ids...>
_emit_commit_msg() {
    local out="$1" version="$2"
    shift 2
    local ids=("$@")

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

        for id in "${ids[@]}"; do
            cat <<RULE

if [[ -x "\$RULES_DIR/${id}.sh" ]]; then
    if ! bash "\$RULES_DIR/${id}.sh" "\$MSG_FILE"; then
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

# _emit_prepare_commit_msg <out-path> <version> <rule-ids...>
_emit_prepare_commit_msg() {
    local out="$1" version="$2"
    shift 2
    local ids=("$@")

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

        for id in "${ids[@]}"; do
            cat <<RULE

if [[ -x "\$RULES_DIR/${id}.sh" ]]; then
    bash "\$RULES_DIR/${id}.sh" "\$MSG_FILE" "\$SOURCE" "\$SHA" || exit 1
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
        # shellcheck disable=SC2207
        local ids=( $(_rules_for_hook "$spec" "$kind") )
        if [[ ${#ids[@]} -eq 0 ]]; then
            continue
        fi

        local out="$dir/$kind"
        # Refuse to clobber an unmarked file. Caller should have run
        # collision_check and resolved the prompt before calling us.
        if [[ -f "$out" ]] && ! hook_has_marker "$out"; then
            echo "hooks.sh: refusing to overwrite unmanaged $out" >&2
            return 2
        fi

        case "$kind" in
            pre-commit)         _emit_pre_commit "$out" "$version" "${ids[@]}" ;;
            commit-msg)         _emit_commit_msg "$out" "$version" "${ids[@]}" ;;
            prepare-commit-msg) _emit_prepare_commit_msg "$out" "$version" "${ids[@]}" ;;
        esac
    done
}
