#!/usr/bin/env bash
# install.sh — installer-facing helpers for pack-based governance bootstrap.
#
# These helpers define the installed-repo contract that bootstrap, tests,
# amend, and generated hooks agree on:
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
        [[ "$base" == "install-assets" ]] && continue
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
    # Manifest schema v1. Call shape:
    #
    #   write_installed_manifest <target_repo> \
    #       [--hook-strategy githooks|husky|pre-commit] \
    #       [--stack bash|python|node|go|rust] \
    #       [--ci-workflow <path>] \
    #       [--tests-dir <path>] \
    #       [--no-constitution] \
    #       [--agents-md-directive] \
    #       [--agents-md-created] \
    #       [--install-asset <path>]     (repeatable)
    #       [--setup-clone-script <path>] \
    #       [--collision <path>:<resolution>[:<extra>]]  (repeatable)
    #       [--path-b-framework husky|pre-commit] \
    #       [--path-b-entry <file>:<fingerprint>]        (repeatable)
    #       -- <pack_dir> <rule_id> [<pack_dir> <rule_id> ...]
    #
    # Rules are grouped by pack in the output. `governance-reset` reads this
    # manifest as the authoritative record of what the kit owns in the repo;
    # every field below is consumed there. See
    # governance/references/MANIFEST_SCHEMA.md for the full contract.
    local target_repo="$1"; shift
    local out="$target_repo/.governance-kit/installed-packs.yaml"

    local hook_strategy="githooks" stack="bash"
    local ci_workflow=".github/workflows/governance.yml"
    local tests_dir="tests/governance"
    local constitution_flag="true"
    local agents_md_directive="false" agents_md_created="false"
    local path_b_framework=""
    local setup_clone_script=""
    local -a install_assets=() collisions=() path_b_entries=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --hook-strategy)     hook_strategy="$2";     shift 2 ;;
            --stack)             stack="$2";             shift 2 ;;
            --ci-workflow)       ci_workflow="$2";       shift 2 ;;
            --tests-dir)         tests_dir="$2";         shift 2 ;;
            --no-constitution)   constitution_flag="false";  shift ;;
            --agents-md-directive) agents_md_directive="true"; shift ;;
            --agents-md-created)   agents_md_created="true";   shift ;;
            --install-asset)     install_assets+=("$2"); shift 2 ;;
            --setup-clone-script) setup_clone_script="$2"; shift 2 ;;
            --collision)         collisions+=("$2");     shift 2 ;;
            --path-b-framework)  path_b_framework="$2";  shift 2 ;;
            --path-b-entry)      path_b_entries+=("$2"); shift 2 ;;
            --)                                           shift; break ;;
            *) echo "write_installed_manifest: unknown flag: $1" >&2; return 1 ;;
        esac
    done

    mkdir -p "$(dirname "$out")"
    {
        printf 'version: "1"\n'
        printf 'generated_at: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        printf 'hook_strategy: %s\n' "$hook_strategy"
        printf 'stack: %s\n' "$stack"
        printf 'constitution: %s\n' "$constitution_flag"
        printf 'ci_workflow: %s\n' "$ci_workflow"
        printf 'tests_dir: %s\n' "$tests_dir"
        printf 'agents_md_directive: %s\n' "$agents_md_directive"
        printf 'agents_md_created: %s\n' "$agents_md_created"
        if [[ -n "$setup_clone_script" ]]; then
            printf 'setup_clone_script: %s\n' "$setup_clone_script"
        fi

        # Rules grouped by pack. Iterate input pack_dir/rule_id pairs,
        # bucket by pack id, emit a pack block per unique pack_dir.
        # Uses a space-delimited string as a portable "seen" set so we stay
        # compatible with bash 3.2 (macOS default; no associative arrays).
        local seen_pack=" "
        local pack_order=()
        local pack_dir rule_id pack_id pack_version
        local i=0
        local pairs=("$@")
        # First pass: collect pack order.
        while (( i < ${#pairs[@]} )); do
            pack_dir="${pairs[i]}"
            pack_id="$(pack_field "$pack_dir" id)"
            case "$seen_pack" in
                *" $pack_id "*) ;;
                *) seen_pack="$seen_pack$pack_id "; pack_order+=("$pack_dir") ;;
            esac
            i=$(( i + 2 ))
        done

        if (( ${#pack_order[@]} > 0 )); then
            printf 'packs:\n'
            local ordered_dir ordered_id
            for ordered_dir in "${pack_order[@]}"; do
                ordered_id="$(pack_field "$ordered_dir" id)"
                pack_version="$(pack_field "$ordered_dir" version)"
                printf '  - id: %s\n' "$ordered_id"
                printf '    version: "%s"\n' "$pack_version"
                printf '    rules:\n'
                i=0
                while (( i < ${#pairs[@]} )); do
                    pack_dir="${pairs[i]}"
                    rule_id="${pairs[i+1]}"
                    pack_id="$(pack_field "$pack_dir" id)"
                    if [[ "$pack_id" == "$ordered_id" ]]; then
                        printf '      - id: %s\n' "$rule_id"
                        printf '        installed_path: tests/governance/rules/%s\n' "$rule_id"
                    fi
                    i=$(( i + 2 ))
                done
            done
        else
            printf 'packs: []\n'
        fi

        if (( ${#install_assets[@]} > 0 )); then
            printf 'install_assets_seeded:\n'
            local asset
            for asset in "${install_assets[@]}"; do
                printf '  - %s\n' "$asset"
            done
        else
            printf 'install_assets_seeded: []\n'
        fi

        if (( ${#collisions[@]} > 0 )); then
            printf 'collisions:\n'
            local entry path resolution extra
            for entry in "${collisions[@]}"; do
                path="${entry%%:*}"
                local rest="${entry#*:}"
                resolution="${rest%%:*}"
                if [[ "$rest" == "$resolution" ]]; then
                    extra=""
                else
                    extra="${rest#*:}"
                fi
                printf '  - path: %s\n' "$path"
                printf '    resolution: %s\n' "$resolution"
                if [[ -n "$extra" ]]; then
                    printf '    extra: %s\n' "$extra"
                fi
            done
        else
            printf 'collisions: []\n'
        fi

        if [[ -n "$path_b_framework" ]]; then
            printf 'path_b:\n'
            printf '  framework: %s\n' "$path_b_framework"
            if (( ${#path_b_entries[@]} > 0 )); then
                printf '  entries:\n'
                local pentry pfile pfp
                for pentry in "${path_b_entries[@]}"; do
                    pfile="${pentry%%:*}"
                    pfp="${pentry#*:}"
                    printf '    - file: %s\n' "$pfile"
                    printf '      fingerprint: %s\n' "$pfp"
                done
            else
                printf '  entries: []\n'
            fi
        fi
    } > "$out"
}
