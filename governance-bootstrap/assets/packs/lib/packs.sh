#!/usr/bin/env bash
# packs.sh — pack loader for governance-bootstrap.
#
# Reads pack.yaml manifests from a pack root (default:
# governance-bootstrap/assets/packs/) and exposes helpers the skill and
# eval infrastructure use to drive the activation flow and hook
# generation.
#
# The manifests are intentionally shallow and regular — two top-level
# maps (`presets`, `rules`), both with flat values. That lets us parse
# them with either `yq` (when available) or a minimal pure-bash pass
# that handles exactly the shapes pack.yaml files are allowed to use.
# A general YAML parser is not warranted.
#
# The contract with callers:
#   list_packs <packs-root>
#       Prints one line per pack: "<pack-id>\t<pack-dir>"
#
#   pack_field <pack-dir> <field>
#       Prints the top-level scalar field (id, name, version, ...).
#
#   rules_for <pack-dir>
#       Prints one line per rule: "<id>" (in manifest order).
#
#   rule_field <pack-dir> <rule-id> <field>
#       Prints the scalar field for a rule (category, summary, script,
#       constitution, surface, hook, recommended, always_install).
#
#   preset_resolve <pack-dir> <preset>
#       Prints the set of rule ids in the preset after `extends:` is
#       unrolled. Empty output (and non-zero exit) if the preset is not
#       declared on the pack.
#
#   union_preset <preset> <pack-dir> [<pack-dir>...]
#       Prints the union of preset rule ids across the given packs,
#       deduplicated but order-preserving. Packs without the preset
#       contribute nothing (union, not fallback).
#
#   always_install_rules <pack-dir>
#       Prints rule ids with always_install: true. Enforced to be
#       core-only at install time by the skill.
#
#   validate_pack <pack-dir>
#       Structural checks — manifest loads, every rule has a script and
#       constitution file present on disk, pack id matches dir name, no
#       unknown hook values. Prints violations on stdout; exit non-zero
#       if any.

set -u

# ──────────────────────────────────────────────────────────────
# YAML access — prefer yq, fall back to a shallow shell parser.
# ──────────────────────────────────────────────────────────────

_have_yq() {
    command -v yq >/dev/null 2>&1
}

# _yaml_scalar_awk <file> <top-level-key>
# Pure-awk implementation. Always-available fallback.
_yaml_scalar_awk() {
    local file="$1" key="$2"
    awk -v k="$key" '
        BEGIN { in_block = 0 }
        /^[[:space:]]*#/ { next }
        /^[^[:space:]]/ {
            # New top-level key.
            line = $0
            sub(/#.*$/, "", line)
            if (match(line, "^" k ":[[:space:]]*")) {
                val = substr(line, RLENGTH + 1)
                sub(/[[:space:]]+$/, "", val)
                # Strip surrounding quotes.
                if (val ~ /^".*"$/ || val ~ /^'\''.*'\''$/) {
                    val = substr(val, 2, length(val) - 2)
                }
                print val
                exit
            }
        }
    ' "$file"
}

# _yaml_scalar <file> <top-level-key>
# Prints the scalar value of a top-level key. Empty if missing.
#
# Tries yq first when present, but yq expression dialects differ
# (mikefarah Go yq vs. python-yq vs. kislyuk/yq), so any failure or
# empty result falls back to the pure-awk parser. Pack manifests are
# intentionally regular enough that awk is always sufficient.
_yaml_scalar() {
    local file="$1" key="$2"
    if _have_yq; then
        local v
        v="$(yq -r ".${key} // \"\"" "$file" 2>/dev/null || true)"
        [[ "$v" == "null" ]] && v=""
        if [[ -n "$v" ]]; then
            printf '%s' "$v"
            return 0
        fi
    fi
    _yaml_scalar_awk "$file" "$key"
}

# _yaml_rules_block <file>
# Prints the raw YAML lines between the top-level `rules:` key and the
# next top-level key (or EOF).
_yaml_rules_block() {
    local file="$1"
    awk '
        /^[[:space:]]*#/ { next }
        /^rules:[[:space:]]*$/ { in_rules = 1; next }
        in_rules && /^[^[:space:]]/ { exit }
        in_rules { print }
    ' "$file"
}

# _yaml_presets_block <file>
_yaml_presets_block() {
    local file="$1"
    awk '
        /^[[:space:]]*#/ { next }
        /^presets:[[:space:]]*$/ { in_presets = 1; next }
        in_presets && /^[^[:space:]]/ { exit }
        in_presets { print }
    ' "$file"
}

# ──────────────────────────────────────────────────────────────
# Public helpers
# ──────────────────────────────────────────────────────────────

list_packs() {
    local root="${1:-}"
    if [[ -z "$root" || ! -d "$root" ]]; then
        return 1
    fi
    local manifest pack_dir pack_id
    while IFS= read -r manifest; do
        pack_dir="${manifest%/pack.yaml}"
        pack_id="$(_yaml_scalar "$manifest" id)"
        [[ -z "$pack_id" ]] && pack_id="${pack_dir##*/}"
        printf '%s\t%s\n' "$pack_id" "$pack_dir"
    done < <(find "$root" -maxdepth 2 -type f -name pack.yaml 2>/dev/null | sort)
}

pack_field() {
    local pack_dir="$1" field="$2"
    _yaml_scalar "$pack_dir/pack.yaml" "$field"
}

rules_for() {
    local pack_dir="$1"
    _yaml_rules_block "$pack_dir/pack.yaml" | awk '
        /^[[:space:]]*-[[:space:]]+id:[[:space:]]*/ {
            line = $0
            sub(/^[[:space:]]*-[[:space:]]+id:[[:space:]]*/, "", line)
            sub(/[[:space:]]*#.*$/, "", line)
            sub(/[[:space:]]+$/, "", line)
            # Strip quotes if present.
            if (line ~ /^".*"$/ || line ~ /^'\''.*'\''$/) {
                line = substr(line, 2, length(line) - 2)
            }
            print line
        }
    '
}

rule_field() {
    local pack_dir="$1" rule_id="$2" field="$3"
    _yaml_rules_block "$pack_dir/pack.yaml" | awk -v rid="$rule_id" -v f="$field" '
        function clean(v) {
            sub(/[[:space:]]*#.*$/, "", v)
            sub(/^[[:space:]]+/, "", v)
            sub(/[[:space:]]+$/, "", v)
            if (v ~ /^".*"$/ || v ~ /^'\''.*'\''$/) {
                v = substr(v, 2, length(v) - 2)
            }
            return v
        }
        /^[[:space:]]*-[[:space:]]+id:[[:space:]]*/ {
            line = $0
            sub(/^[[:space:]]*-[[:space:]]+id:[[:space:]]*/, "", line)
            cur = clean(line)
            match_block = (cur == rid) ? 1 : 0
            next
        }
        match_block && /^[[:space:]]+[A-Za-z_][A-Za-z0-9_]*:[[:space:]]*/ {
            # Key inside the rule block.
            line = $0
            sub(/^[[:space:]]+/, "", line)
            key = line; sub(/:.*$/, "", key)
            val = line; sub(/^[^:]*:[[:space:]]*/, "", val)
            if (key == f) {
                print clean(val)
                exit
            }
        }
    '
}

# _preset_raw <pack-dir> <preset-name>
# Prints two lines:
#   extends <parent|"">
#   rules <rule1> <rule2> ...
_preset_raw() {
    local pack_dir="$1" preset="$2"
    _yaml_presets_block "$pack_dir/pack.yaml" | awk -v p="$preset" '
        function trim(s) {
            sub(/^[[:space:]]+/, "", s)
            sub(/[[:space:]]+$/, "", s)
            return s
        }
        function indent_spaces(line,    i, n) {
            n = 0
            for (i = 1; i <= length(line); i++) {
                if (substr(line, i, 1) == " ") n++
                else break
            }
            return n
        }
        {
            ind = indent_spaces($0)
            stripped = $0
            sub(/^[[:space:]]+/, "", stripped)
            sub(/[[:space:]]*#.*$/, "", stripped)
            sub(/[[:space:]]+$/, "", stripped)

            if (ind == 2 && stripped ~ /^[A-Za-z_][A-Za-z0-9_]*:$/) {
                if (in_preset) {
                    print "extends " extends_val
                    print "rules " rules
                    in_preset = 0
                    done = 1
                    next
                }
                if (done) next
                name = stripped; sub(/:$/, "", name)
                if (name == p) {
                    in_preset = 1
                    extends_val = ""
                    rules = ""
                    in_rules_list = 0
                }
                next
            }

            if (!in_preset) next

            if (ind == 4) {
                key = stripped
                val = ""
                if (index(stripped, ":") > 0) {
                    key = stripped; sub(/:.*$/, "", key)
                    val = stripped; sub(/^[^:]*:[[:space:]]*/, "", val)
                }
                if (key == "extends") {
                    extends_val = trim(val)
                    in_rules_list = 0
                } else if (key == "rules") {
                    in_rules_list = 1
                }
                next
            }

            if (in_rules_list && ind == 6 && stripped ~ /^-[[:space:]]+/) {
                r = stripped; sub(/^-[[:space:]]+/, "", r)
                rules = rules " " trim(r)
                next
            }
        }
        END {
            if (in_preset) {
                print "extends " extends_val
                print "rules " rules
            }
        }
    '
}

preset_resolve() {
    local pack_dir="$1" preset="$2"
    local seen_presets="" out=""
    _resolve() {
        local p="$1"
        case " $seen_presets " in
            *" $p "*) return 0 ;;
        esac
        seen_presets="$seen_presets $p"
        local raw extends rules line
        raw="$(_preset_raw "$pack_dir" "$p")"
        [[ -z "$raw" ]] && return 1
        extends="$(printf '%s\n' "$raw" | awk '/^extends / {print $2; exit}')"
        rules="$(printf '%s\n' "$raw" | awk '/^rules / { for (i=2;i<=NF;i++) printf "%s ", $i; exit }')"
        if [[ -n "$extends" ]]; then
            _resolve "$extends"
        fi
        local r
        for r in $rules; do
            case " $out " in
                *" $r "*) ;;
                *) out="$out $r" ;;
            esac
        done
        return 0
    }
    if ! _resolve "$preset"; then
        return 1
    fi
    local r
    for r in $out; do
        printf '%s\n' "$r"
    done
}

union_preset() {
    local preset="$1"
    shift
    local acc="" pack_dir r
    for pack_dir in "$@"; do
        while IFS= read -r r; do
            [[ -z "$r" ]] && continue
            case " $acc " in
                *" $r "*) ;;
                *) acc="$acc $r" ;;
            esac
        done < <(preset_resolve "$pack_dir" "$preset" 2>/dev/null || true)
    done
    for r in $acc; do
        printf '%s\n' "$r"
    done
}

always_install_rules() {
    local pack_dir="$1" rule_id flag
    while IFS= read -r rule_id; do
        [[ -z "$rule_id" ]] && continue
        flag="$(rule_field "$pack_dir" "$rule_id" always_install)"
        if [[ "$flag" == "true" ]]; then
            printf '%s\n' "$rule_id"
        fi
    done < <(rules_for "$pack_dir")
}

validate_pack() {
    local pack_dir="$1"
    local manifest="$pack_dir/pack.yaml"
    local ok=0

    if [[ ! -f "$manifest" ]]; then
        printf '%s: pack.yaml missing\n' "$pack_dir"
        return 1
    fi

    local pack_id dir_name
    pack_id="$(_yaml_scalar "$manifest" id)"
    dir_name="${pack_dir##*/}"
    if [[ -z "$pack_id" ]]; then
        printf '%s: pack.yaml has no id:\n' "$pack_dir"
        ok=1
    elif [[ "$pack_id" != "$dir_name" ]]; then
        printf '%s: pack id %q does not match directory name %q\n' \
            "$pack_dir" "$pack_id" "$dir_name"
        ok=1
    fi

    local rule_id script snippet hook surface
    while IFS= read -r rule_id; do
        [[ -z "$rule_id" ]] && continue
        script="$(rule_field "$pack_dir" "$rule_id" script)"
        snippet="$(rule_field "$pack_dir" "$rule_id" constitution)"
        hook="$(rule_field "$pack_dir" "$rule_id" hook)"
        surface="$(rule_field "$pack_dir" "$rule_id" surface)"
        if [[ -z "$script" || ! -f "$pack_dir/$script" ]]; then
            printf '%s/%s: script missing (%q)\n' "$pack_dir" "$rule_id" "$script"
            ok=1
        fi
        if [[ -z "$snippet" || ! -f "$pack_dir/$snippet" ]]; then
            printf '%s/%s: constitution snippet missing (%q)\n' "$pack_dir" "$rule_id" "$snippet"
            ok=1
        fi
        case "$hook" in
            pre-commit|commit-msg|prepare-commit-msg|none|"") ;;
            *) printf '%s/%s: unknown hook value %q\n' "$pack_dir" "$rule_id" "$hook"; ok=1 ;;
        esac
        case "$surface" in
            repo-state|change-set|"") ;;
            *) printf '%s/%s: unknown surface value %q\n' "$pack_dir" "$rule_id" "$surface"; ok=1 ;;
        esac
    done < <(rules_for "$pack_dir")

    # always_install is reserved to core.
    if [[ "$pack_id" != "core" ]]; then
        local ai
        while IFS= read -r ai; do
            [[ -z "$ai" ]] && continue
            printf '%s/%s: always_install: true is reserved to the core pack\n' \
                "$pack_dir" "$ai"
            ok=1
        done < <(always_install_rules "$pack_dir")
    fi

    return $ok
}
