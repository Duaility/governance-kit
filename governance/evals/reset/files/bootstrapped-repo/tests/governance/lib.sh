#!/usr/bin/env bash
# Shared helpers for rule check scripts.
rule_start() { echo "▶ $1"; }
violation() { echo "  ✗ $*" >&2; VIOLATIONS=$((${VIOLATIONS:-0}+1)); }
rule_end() { [[ ${VIOLATIONS:-0} -eq 0 ]] && echo "✓ passed" || return 1; }
