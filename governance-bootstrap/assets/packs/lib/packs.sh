#!/usr/bin/env bash
# packs.sh — shell API for governance-bootstrap pack manifests.
#
# YAML parsing and structural validation are delegated to packctl.py, which is
# executed with `uv run --with PyYAML`. Keep this file as the stable bash
# surface consumed by SKILL.md, scripts/test-packs.sh, and eval helpers.

set -u

_PACKS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_PACKCTL="$_PACKS_LIB_DIR/packctl.py"

_packctl() {
    uv run --quiet --isolated --with PyYAML python "$_PACKCTL" "$@"
}

kit_version() {
    _packctl kit-version
}

list_packs() {
    _packctl list-packs "$1"
}

pack_field() {
    _packctl pack-field "$1" "$2"
}

rule_dir() {
    local pack_dir="$1" rule_id="$2"
    printf '%s/rules/%s' "$pack_dir" "$rule_id"
}

rules_for() {
    _packctl rules-for "$1"
}

rule_field() {
    _packctl rule-field "$1" "$2" "$3"
}

preset_resolve() {
    _packctl preset-resolve "$1" "$2"
}

union_preset() {
    local preset="$1"
    shift
    _packctl union-preset "$preset" "$@"
}

always_install_rules() {
    _packctl always-install-rules "$1"
}

validate_pack() {
    _packctl validate-pack "$1"
}

validate_pack_set() {
    _packctl validate-pack-set "$@"
}
