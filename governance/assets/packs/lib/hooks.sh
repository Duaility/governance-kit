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
#       Writes dispatchers for pre-commit, commit-msg, prepare-commit-msg,
#       post-commit, and pre-push. The spec file is still accepted so callers can
#       validate the selected install set before generation, but generated
#       hooks do not bake in selected directive ids. They scan installed
#       `.governance/packs/*/directives/<id>/directive.yaml` and
#       `.governance/local/directives/<id>/directive.yaml` files on every
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

directive_dirs_for_hook() {
    local kind="$1" mode="$2"
    local dir hook helper
    [[ -d "$GOVERNANCE_DIR" ]] || return 0
    while IFS= read -r dir; do
        [[ -d "$dir" && -f "$dir/directive.yaml" ]] || continue
        hook="$(directive_field "$dir/directive.yaml" hook)"
        helper="$dir/hooks/$kind.sh"
        case "$mode" in
            helper)
                [[ -x "$helper" ]] && printf '%s\n' "$dir"
                ;;
            check)
                [[ "$hook" == "$kind" && -x "$dir/check.sh" ]] && printf '%s\n' "$dir"
                ;;
        esac
    done < <(
        {
            [[ -d "$GOVERNANCE_DIR/packs" ]] && find "$GOVERNANCE_DIR/packs" -type d -path '*/directives/*'
            [[ -d "$GOVERNANCE_DIR/local/directives" ]] && find "$GOVERNANCE_DIR/local/directives" -mindepth 1 -maxdepth 1 -type d
        } | sort
    )
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
GOVERNANCE_DIR="$ROOT/.governance"

HEADER
        _emit_runtime_discovery_helpers
        cat <<'FOOTER'
if [[ -x "$ROOT/scripts/test-packs.sh" ]]; then
    bash "$ROOT/scripts/test-packs.sh" || exit 1
fi

while IFS= read -r dir; do
    [[ -z "$dir" ]] && continue
    bash "$dir/hooks/pre-commit.sh" || exit 1
done < <(directive_dirs_for_hook pre-commit helper)

fail=0
while IFS= read -r dir; do
    [[ -z "$dir" ]] && continue
    bash "$dir/check.sh" || fail=1
done < <(directive_dirs_for_hook pre-commit check)

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
GOVERNANCE_DIR="$ROOT/.governance"
MSG_FILE="$1"
HEADER
        _emit_runtime_discovery_helpers
        cat <<'FOOTER'
while IFS= read -r dir; do
    [[ -z "$dir" ]] && continue
    bash "$dir/hooks/commit-msg.sh" "$MSG_FILE" || exit 1
done < <(directive_dirs_for_hook commit-msg helper)

while IFS= read -r dir; do
    [[ -z "$dir" ]] && continue
    id="${dir##*/}"
    if ! bash "$dir/check.sh" "$MSG_FILE"; then
        echo "✗ commit blocked by governance (${id})" >&2
        exit 1
    fi
done < <(directive_dirs_for_hook commit-msg check)

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
GOVERNANCE_DIR="$ROOT/.governance"
MSG_FILE="$1"
SOURCE="${2:-}"
SHA="${3:-}"
HEADER
        _emit_runtime_discovery_helpers
        cat <<'FOOTER'
while IFS= read -r dir; do
    [[ -z "$dir" ]] && continue
    bash "$dir/hooks/prepare-commit-msg.sh" "$MSG_FILE" "$SOURCE" "$SHA" || exit 1
done < <(directive_dirs_for_hook prepare-commit-msg helper)

while IFS= read -r dir; do
    [[ -z "$dir" ]] && continue
    bash "$dir/check.sh" "$MSG_FILE" "$SOURCE" "$SHA" || exit 1
done < <(directive_dirs_for_hook prepare-commit-msg check)

exit 0
FOOTER
    } > "$out"
    chmod +x "$out"
}

# _emit_post_commit <out> <version>
#
# Post-commit cannot block — `git commit` has already succeeded by the time
# this hook fires, and git ignores this hook's exit code by design (so the
# shell always returns 0). Each directive's check.sh runs and any non-zero
# exit increments the advisories counter. When advisories > 0 the dispatcher
# prints a loud "POST-COMMIT GOVERNANCE FAILED" banner addressed at agent
# readers — the framing exists specifically to compensate for the missing
# exit-code signal. The agent's contract is to execute the mandated action
# from each directive's violation message and re-run
# `bash .governance/run.sh` until clean.
_emit_post_commit() {
    local out="$1" version="$2"

    {
        _write_marker "$version"
        cat <<'HEADER'
# Governance post-commit hook — generated by governance-bootstrap.
#
# Post-commit cannot block — `git commit` has already succeeded and git
# ignores this hook's exit code by design. Violations are surfaced as a
# loud "POST-COMMIT GOVERNANCE FAILED" banner addressed at agent readers,
# compensating for the missing exit-code signal. The agent contract is to
# execute the mandated action(s) and re-run governance until clean.
#
# Escape hatch:
#   SKIP_GOVERNANCE=1 git commit ...    # silences the failure banner too

set -u

if [[ "${SKIP_GOVERNANCE:-0}" == "1" ]]; then
    exit 0
fi

ROOT="$(git rev-parse --show-toplevel)"
GOVERNANCE_DIR="$ROOT/.governance"
HEADER
        _emit_runtime_discovery_helpers
        cat <<'FOOTER'
while IFS= read -r dir; do
    [[ -z "$dir" ]] && continue
    bash "$dir/hooks/post-commit.sh" || true
done < <(directive_dirs_for_hook post-commit helper)

advisories=0
while IFS= read -r dir; do
    [[ -z "$dir" ]] && continue
    if ! bash "$dir/check.sh"; then
        advisories=$((advisories + 1))
    fi
done < <(directive_dirs_for_hook post-commit check)

if [[ $advisories -gt 0 ]]; then
    cat >&2 <<EOF

═══════════════════════════════════════════════════════════════════
  ✗ POST-COMMIT GOVERNANCE FAILED — ${advisories} directive(s) violated

  Agent reader: git ignores post-commit hook exit codes by design,
  so this shell returned 0 even though governance failed. This is
  NOT a successful command. The directive(s) printed above describe
  state the repo MUST converge to before continuing other work.

  Execute the mandated action(s) shown in each directive's output,
  then re-run:

      bash .governance/run.sh

  to confirm convergence. The directive's firing is the durable
  authorization — run the mandated step now, do not re-pose it as a
  question to the user.
═══════════════════════════════════════════════════════════════════
EOF
fi

exit 0
FOOTER
    } > "$out"
    chmod +x "$out"
}

# _emit_pre_push <out> <version>
#
# Pre-push fires once per `git push`, before any objects leave the client.
# Git passes the remote name as $1 and the remote URL as $2, then streams
# one line per ref being pushed on stdin:
#     <local-ref> <local-sha> <remote-ref> <remote-sha>
# A non-zero exit aborts the push. Multiple directives may need to read
# the ref list, so we slurp stdin into a tempfile once and replay it to
# each helper / check.sh invocation.
_emit_pre_push() {
    local out="$1" version="$2"

    {
        _write_marker "$version"
        cat <<'HEADER'
# Governance pre-push hook — generated by governance-bootstrap.
#
# Escape hatches:
#   SKIP_GOVERNANCE=1 git push ...      # telegraphs intent; CI still enforces
#   git push --no-verify                # skips all hooks

set -u

if [[ "${SKIP_GOVERNANCE:-0}" == "1" ]]; then
    echo "⊘ governance pre-push skipped (SKIP_GOVERNANCE=1)" >&2
    exit 0
fi

ROOT="$(git rev-parse --show-toplevel)"
GOVERNANCE_DIR="$ROOT/.governance"
REMOTE_NAME="${1:-}"
REMOTE_URL="${2:-}"

REFS_FILE="$(mktemp)"
trap 'rm -f "$REFS_FILE"' EXIT
cat > "$REFS_FILE"
HEADER
        _emit_runtime_discovery_helpers
        cat <<'FOOTER'
while IFS= read -r dir; do
    [[ -z "$dir" ]] && continue
    bash "$dir/hooks/pre-push.sh" "$REMOTE_NAME" "$REMOTE_URL" < "$REFS_FILE" || exit 1
done < <(directive_dirs_for_hook pre-push helper)

fail=0
while IFS= read -r dir; do
    [[ -z "$dir" ]] && continue
    bash "$dir/check.sh" "$REMOTE_NAME" "$REMOTE_URL" < "$REFS_FILE" || fail=1
done < <(directive_dirs_for_hook pre-push check)

if [[ $fail -ne 0 ]]; then
    cat >&2 <<EOF

────────────────────────────────────────
✗ Push blocked by governance.

Fix the violations above, or bypass (CI will still enforce):
    SKIP_GOVERNANCE=1 git push ...
    git push --no-verify
────────────────────────────────────────
EOF
    exit 1
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
    for kind in pre-commit commit-msg prepare-commit-msg post-commit pre-push; do
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
            pre-push)           _emit_pre_push           "$out" "$version" ;;
        esac
    done
}
