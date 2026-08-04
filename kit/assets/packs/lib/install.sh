#!/usr/bin/env bash
# install.sh — installer-facing helpers for pack-based governance bootstrap.
#
# These helpers define the installed-repo contract that bootstrap, tests,
# amend, and generated hooks agree on. Every pack lives at the same shape on
# disk, mirroring its `<owner>/<name>` GitHub identity:
#
#   .governance/packs/<owner>/<name>/directives/<directive-id>/
#     directive.yaml
#     check.sh
#     constitution.md
#     hooks/*.sh        # optional hook side-effect helpers
#     lib/              # optional directive-owned libraries
#     runtimes/         # optional runtime adapters
#
# Hand-authored repo-local packs use the repo's own `<owner>/<name>` (the
# default is the pack at `<repo-owner>/<repo-name>/`); they are distinguished
# from installed packs by the absence of a `source:` field in their
# `pack.yaml`. The runner does not care which is which.
#
# Pack evals are author-side tests and are never copied into target repos.

set -u

_INSTALL_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$_INSTALL_LIB_DIR/packs.sh"

directive_supports_hook_strategy() {
    local pack_dir="$1" directive_id="$2" hook_strategy="$3"
    local required
    required="$(directive_field "$pack_dir" "$directive_id" requires_hook_strategy)"
    [[ -z "$required" || "$required" == "$hook_strategy" ]]
}

stamp_managed_marker() {
    # Rewrites the `# governance-kit:managed` marker line in <dest> to the
    # versioned form:
    #
    #   # governance-kit:managed kit-version=<v>
    #
    # Used by `init`, `kit update`, and any future writer that copies a
    # kit-runtime template into a target repo. The marker line lives in the
    # file's leading comment block (line 1 for YAML, line 2 for shebang
    # scripts); this helper finds whichever of the first 3 lines carries the
    # bare-or-versioned marker and rewrites it in place.
    #
    # Fully idempotent and reproducible — re-stamping a file already on the
    # target version produces byte-identical output (the marker carries no
    # wall-clock date, so stamping the same version twice is a no-op diff).
    #
    # The marker is the per-file version pin: `governance kit update` reads
    # `kit-version=<v>` from each managed file to detect drift, treating
    # `install.yaml.kit_version` as a cache. A target repo whose manifest is
    # missing can still be updated as long as runtime markers are present.
    local dest="$1" kit_version="$2"
    if [[ ! -f "$dest" ]]; then
        echo "stamp_managed_marker: $dest does not exist" >&2
        return 1
    fi
    local marker line_no
    marker="# governance-kit:managed kit-version=${kit_version}"
    line_no=$(awk '/^# governance-kit:managed/ { print NR; exit }' "$dest")
    if [[ -z "$line_no" ]]; then
        echo "stamp_managed_marker: $dest does not carry the managed marker" >&2
        return 1
    fi
    if (( line_no > 3 )); then
        echo "stamp_managed_marker: marker on $dest is past line 3 (line $line_no)" >&2
        return 1
    fi
    local tmp
    tmp=$(mktemp)
    awk -v ln="$line_no" -v m="$marker" 'NR==ln { print m; next } { print }' "$dest" > "$tmp"
    cat "$tmp" > "$dest"
    rm -f "$tmp"
}

read_marker_kit_version() {
    # Reads `kit-version=<v>` from the marker line in <file> (scanning the
    # first 3 lines for the marker). Prints the version on stdout and exits
    # 0; prints nothing and exits 1 if the marker is absent, and prints
    # nothing and exits 0 if the marker is present but unversioned (the
    # bare `# governance-kit:managed` form pre-dating the kit-version
    # field — caller treats that as "version unknown").
    local file="$1"
    [[ -f "$file" ]] || return 1
    local line
    line=$(awk '/^# governance-kit:managed/ { print; exit }' "$file" \
            | head -c 4096)
    [[ -n "$line" ]] || return 1
    if [[ "$line" =~ kit-version=([^[:space:]]+) ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
    fi
    return 0
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
    # Never vendor Python bytecode: a stray __pycache__/*.pyc (e.g. left by a
    # test that imported a directive's lib/) would otherwise land in the
    # consumed tree and trip repo-hygiene. digestlib excludes these from the
    # content digest too, so pruning here keeps copy and digest consistent.
    find "$dest" -name '__pycache__' -type d -prune -exec rm -rf {} + 2>/dev/null || true
    find "$dest" -name '*.pyc' -delete 2>/dev/null || true
}

install_directive_folder() {
    local pack_dir="$1" directive_id="$2" target_repo="$3"
    local src="$pack_dir/directives/$directive_id"
    local pack_id
    pack_id="$(pack_field "$pack_dir" id)"
    local dest="$target_repo/.governance/packs/$pack_id/directives/$directive_id"
    [[ -d "$src" ]] || {
        echo "install_directive_folder: missing directive folder: $src" >&2
        return 1
    }
    mkdir -p "$(dirname "$dest")"
    copy_tree_without_evals "$src" "$dest"
    # A directive ships check.sh, the commit/CI-lane pass/fail test — except a
    # sweep-only discovery directive (`judge.sink: none`, issue #355), which
    # ships no executable at all: it is judged only by the at-rest sweep driver.
    # chmod it if it came across; its absence is not an error here (packctl.py
    # validates when it's required).
    [[ -f "$dest/check.sh" ]] && chmod +x "$dest/check.sh"
    if [[ -d "$dest/hooks" ]]; then
        chmod +x "$dest/hooks/"*.sh 2>/dev/null || true
    fi
    if [[ -d "$dest/runtimes" ]]; then
        chmod +x "$dest/runtimes/"*.sh 2>/dev/null || true
    fi
}

install_directive_assets() {
    local pack_dir="$1" directive_id="$2" target_repo="$3" mode="${4:-augment}"
    local assets_dir="$pack_dir/directives/$directive_id/install-assets"
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

seed_directive_conf() {
    # Seed a configurable directive's user overlay at
    # `.governance/conf/<owner>/<pack>/<directive-id>.conf`. The path is
    # pack-qualified so homonym directives from different packs get independent
    # overlays — matching how `conf_file` resolves it at runtime.
    #
    # A directive is "configurable" iff it ships a `defaults.conf` (issue #210):
    # that one pack-owned file holds the live defaults *and* their docs, and it
    # is refreshed by `pack update`. The overlay seeded here is NOT a copy of
    # anything directive-specific — it is one generic kit stub
    # (kit/assets/conf-overlay.stub.conf) with the directive id and the path to
    # its defaults.conf interpolated in. So nothing seeded into user space can
    # ever go stale: the docs live in the refreshed defaults.conf, and the stub
    # only points at it.
    #
    # Augment-only: an existing dest is left untouched — user edits are sacred,
    # and `pack update` / `reset` never call this on already-installed
    # directives. Echoes the repo-relative seeded path on stdout when it writes
    # one (for the apply-engine `conf_seeded` report); silent no-op when the
    # directive ships no `defaults.conf` or the dest already exists.
    local pack_dir="$1" directive_id="$2" target_repo="$3"
    local defaults="$pack_dir/directives/$directive_id/defaults.conf"
    [[ -f "$defaults" ]] || return 0
    local pack_id
    pack_id="$(pack_field "$pack_dir" id)"
    local rel=".governance/conf/$pack_id/$directive_id.conf"
    local dest="$target_repo/$rel"
    [[ -e "$dest" ]] && return 0
    local stub="$_INSTALL_LIB_DIR/../../conf-overlay.stub.conf"
    [[ -f "$stub" ]] || return 0
    local defaults_rel=".governance/packs/$pack_id/directives/$directive_id/defaults.conf"
    local content
    content="$(cat "$stub")"
    content="${content//__DIRECTIVE_ID__/$directive_id}"
    content="${content//__DEFAULTS_PATH__/$defaults_rel}"
    mkdir -p "$(dirname "$dest")"
    printf '%s\n' "$content" > "$dest"
    printf '%s\n' "$rel"
}

_directive_yaml_scalar() {
    # Read a top-level flat scalar `<key>: value` line out of a directive.yaml
    # (unquoted, no inline comment — the only shape `hook:`/`surface:` ever
    # take in this corpus). kityaml.py in this same directory is the full
    # restricted-YAML parser used everywhere else; this awk one-liner avoids
    # spawning python for a single flat read per directive while building the
    # hook spec (issue #355 — zero python invocations on the commit/install
    # path).
    local file="$1" key="$2"
    awk -v key="$key" '
        index($0, key ":") == 1 {
            v = $0
            sub("^" key ":[ \t]*", "", v)
            sub("[ \t]*$", "", v)
            print v
            exit
        }
    ' "$file"
}

build_hook_spec_from_installed_directives() {
    local target_repo="$1" out="$2"
    local governance_dir="$target_repo/.governance"
    : > "$out"
    [[ -d "$governance_dir" ]] || return 0

    local dir id hook surface
    while IFS= read -r dir; do
        [[ -d "$dir" && -f "$dir/directive.yaml" ]] || continue
        id="${dir##*/}"
        hook="$(_directive_yaml_scalar "$dir/directive.yaml" hook)"
        [[ -z "$hook" ]] && hook="none"
        surface="$(_directive_yaml_scalar "$dir/directive.yaml" surface)"
        printf '%s\t%s\t%s\t%s\n' "$id" "$hook" "$surface" "$dir" >> "$out"
    done < <(
        [[ -d "$governance_dir/packs" ]] && find "$governance_dir/packs" -type d -path '*/directives/*' | sort
    )
}

write_installed_manifest() {
    # install.yaml schema v3. Call shape:
    #
    #   write_installed_manifest <target_repo> \
    #       --owner <github-owner> \
    #       --repo <github-repo-name> \
    #       [--kit-version <semver>] \
    #       [--kit-ref <gh-ref>] [--kit-sha <40-hex>] \
    #       [--kit-provenance published-tag|explicit|cache|installed-skill] \
    #       [--hook-strategy githooks|husky|pre-commit] \
    #       [--ci-workflow <path>] \
    #       [--tests-dir <path>] \
    #       [--no-constitution] \
    #       [--agents-md-snippet] \
    #       [--agents-md-created] \
    #       [--install-asset <path>]     (repeatable)
    #       [--collision <path>:<resolution>[:<extra>]]  (repeatable)
    #       [--path-b-framework husky|pre-commit] \
    #       [--path-b-entry <file>:<fingerprint>]        (repeatable)
    #
    # `--kit-version` is the `KIT_VERSION` (kit/assets/packs/lib/packctl.py)
    # of the kit doing the install or `kit update`. Optional within v3 — if
    # absent the field is omitted from the emitted YAML, which `kit update`
    # later reads as a pre-tracking install.
    #
    # `--kit-ref` / `--kit-sha` record the content-addressed pin of the kit
    # that did the install — the repo-pinned model (issue #177): the manifest is
    # the authoritative statement of which kit this repo runs, and `kit update`
    # fetches that ref and delegates apply to its engine. Both optional; emitted
    # only when supplied (init resolves the sha via `git ls-remote` and omits it
    # when offline, leaving it to be backfilled on the first `kit update`).
    #
    # `--kit-provenance` records *how* `init` resolved the kit it installed from
    # (issue #194): `published-tag` (fetched the latest `kit/vX.Y.Z` tag),
    # `explicit` (`--to`), or `installed-skill` (offline fallback to the machine
    # copy). Optional; emitted only when supplied. It documents whether the
    # install ran from a released artifact or the local skill — the audit trail
    # for the tag-resolved-install milestone.
    #
    # `owner` and `repo` are the GitHub-shaped identity of the bootstrapping
    # repo, lowercased. They define the default repo-local pack at
    # `.governance/packs/<owner>/<repo>/`, which is where `governance directive
    # add` lands directives when no `--pack` is given.
    #
    # Pack pin state is **not** written here — it lives in `.governance/packs.lock`
    # and is managed via `packverb.py lock-add`. install.yaml carries only the
    # init-time choices and side-effect ledgers (install_assets_seeded,
    # collisions, path_b). See kit/references/INSTALL_SCHEMA.md and
    # LOCK_SCHEMA.md for the contracts.
    local target_repo="$1"; shift
    local out="$target_repo/.governance/install.yaml"

    local hook_strategy="githooks"
    local ci_workflow=".github/workflows/governance.yml"
    local tests_dir=".governance"
    local constitution_flag="true"
    local agents_md_snippet="false" agents_md_created="false"
    local path_b_framework=""
    local owner="" repo="" kit_version="" kit_ref="" kit_sha="" kit_provenance=""
    local -a install_assets=() collisions=() path_b_entries=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --owner)             owner="$2";             shift 2 ;;
            --repo)              repo="$2";              shift 2 ;;
            --kit-version)       kit_version="$2";       shift 2 ;;
            --kit-ref)           kit_ref="$2";           shift 2 ;;
            --kit-sha)           kit_sha="$2";           shift 2 ;;
            --kit-provenance)    kit_provenance="$2";    shift 2 ;;
            --hook-strategy)     hook_strategy="$2";     shift 2 ;;
            --ci-workflow)       ci_workflow="$2";       shift 2 ;;
            --tests-dir)         tests_dir="$2";         shift 2 ;;
            --no-constitution)   constitution_flag="false";  shift ;;
            --agents-md-snippet) agents_md_snippet="true"; shift ;;
            --agents-md-created)   agents_md_created="true";   shift ;;
            --install-asset)     install_assets+=("$2"); shift 2 ;;
            --collision)         collisions+=("$2");     shift 2 ;;
            --path-b-framework)  path_b_framework="$2";  shift 2 ;;
            --path-b-entry)      path_b_entries+=("$2"); shift 2 ;;
            --)                                           shift; break ;;
            *) echo "write_installed_manifest: unknown flag: $1" >&2; return 1 ;;
        esac
    done

    if [[ -z "$owner" || -z "$repo" ]]; then
        echo "write_installed_manifest: --owner and --repo are required" >&2
        return 1
    fi

    if (( $# > 0 )); then
        echo "write_installed_manifest: unexpected positional args (pack/directive pairs moved to packs.lock)" >&2
        return 1
    fi

    mkdir -p "$(dirname "$out")"
    {
        printf 'version: "3"\n'
        printf 'generated_at: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        printf 'owner: %s\n' "$owner"
        printf 'repo: %s\n' "$repo"
        if [[ -n "$kit_version" ]]; then
            printf 'kit_version: "%s"\n' "$kit_version"
        fi
        if [[ -n "$kit_ref" ]]; then
            printf 'kit_ref: %s\n' "$kit_ref"
        fi
        if [[ -n "$kit_sha" ]]; then
            printf 'kit_sha: %s\n' "$kit_sha"
        fi
        if [[ -n "$kit_provenance" ]]; then
            printf 'kit_provenance: %s\n' "$kit_provenance"
        fi
        printf 'hook_strategy: %s\n' "$hook_strategy"
        printf 'constitution: %s\n' "$constitution_flag"
        printf 'ci_workflow: %s\n' "$ci_workflow"
        printf 'tests_dir: %s\n' "$tests_dir"
        printf 'agents_md_snippet: %s\n' "$agents_md_snippet"
        printf 'agents_md_created: %s\n' "$agents_md_created"

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
