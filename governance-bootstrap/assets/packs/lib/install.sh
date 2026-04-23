#!/usr/bin/env bash
# install.sh — installer-facing helpers for pack-based governance bootstrap.
#
# These helpers define the installed-repo contract that bootstrap, tests,
# amend, gardener, and generated hooks agree on:
#
#   tests/governance/rules/<rule-id>/
#     rule.yaml
#     check.sh
#     constitution.md
#     hooks/*.sh        # optional hook side-effect helpers
#     lib/              # optional rule-owned libraries
#     runtimes/         # optional runtime adapters
#
# Pack evals are author-side tests and are never copied into target repos.

set -u

_INSTALL_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$_INSTALL_LIB_DIR/packs.sh"

rule_supports_hook_strategy() {
    local pack_dir="$1" rule_id="$2" hook_strategy="$3"
    local required
    required="$(rule_field "$pack_dir" "$rule_id" requires_hook_strategy)"
    [[ -z "$required" || "$required" == "$hook_strategy" ]]
}

copy_tree_without_evals() {
    local src="$1" dest="$2"
    rm -rf "$dest"
    mkdir -p "$dest"
    local entry base
    for entry in "$src"/*; do
        [[ -e "$entry" ]] || continue
        base="$(basename "$entry")"
        [[ "$base" == "evals" ]] && continue
        cp -R "$entry" "$dest/"
    done
}

install_rule_folder() {
    local pack_dir="$1" rule_id="$2" target_repo="$3"
    local src="$pack_dir/rules/$rule_id"
    local dest="$target_repo/tests/governance/rules/$rule_id"
    [[ -d "$src" ]] || {
        echo "install_rule_folder: missing rule folder: $src" >&2
        return 1
    }
    mkdir -p "$target_repo/tests/governance/rules"
    copy_tree_without_evals "$src" "$dest"
    chmod +x "$dest/check.sh"
    if [[ -d "$dest/hooks" ]]; then
        chmod +x "$dest/hooks/"*.sh 2>/dev/null || true
    fi
    if [[ -d "$dest/runtimes" ]]; then
        chmod +x "$dest/runtimes/"*.sh 2>/dev/null || true
    fi
}

install_rule_assets() {
    local pack_dir="$1" rule_id="$2" target_repo="$3" mode="${4:-augment}"
    local assets_dir="$pack_dir/rules/$rule_id/install-assets"
    [[ -d "$assets_dir" ]] || return 0

    local src rel dest
    while IFS= read -r src; do
        [[ -z "$src" ]] && continue
        rel="${src#$assets_dir/}"
        dest="$target_repo/$rel"
        mkdir -p "$(dirname "$dest")"
        if [[ -e "$dest" && "$mode" != "overwrite" ]]; then
            continue
        fi
        cp "$src" "$dest"
    done < <(find "$assets_dir" -type f | sort)
}

build_hook_spec_from_installed_rules() {
    local target_repo="$1" out="$2"
    local rules_dir="$target_repo/tests/governance/rules"
    : > "$out"
    [[ -d "$rules_dir" ]] || return 0

    local dir id hook surface
    for dir in "$rules_dir"/*; do
        [[ -d "$dir" && -f "$dir/rule.yaml" ]] || continue
        id="${dir##*/}"
        hook="$(uv run --quiet --isolated --with PyYAML python - "$dir/rule.yaml" hook <<'PY'
import sys, yaml
data = yaml.safe_load(open(sys.argv[1])) or {}
print(data.get(sys.argv[2]) or "none")
PY
)"
        surface="$(uv run --quiet --isolated --with PyYAML python - "$dir/rule.yaml" surface <<'PY'
import sys, yaml
data = yaml.safe_load(open(sys.argv[1])) or {}
print(data.get(sys.argv[2]) or "")
PY
)"
        printf '%s\t%s\t%s\t%s\n' "$id" "$hook" "$surface" "$dir" >> "$out"
    done
}

write_installed_manifest() {
    local target_repo="$1"
    local out="$target_repo/.governance-kit/installed-packs.yaml"
    shift
    mkdir -p "$(dirname "$out")"
    {
        printf 'version: "0.1"\n'
        printf 'rules:\n'
        local pack_dir rule_id pack_id pack_version
        while [[ $# -gt 0 ]]; do
            pack_dir="$1"
            rule_id="$2"
            shift 2
            pack_id="$(pack_field "$pack_dir" id)"
            pack_version="$(pack_field "$pack_dir" version)"
            printf '  - id: %s\n' "$rule_id"
            printf '    pack: %s\n' "$pack_id"
            printf '    pack_version: "%s"\n' "$pack_version"
            printf '    installed_path: tests/governance/rules/%s\n' "$rule_id"
        done
    } > "$out"
}
