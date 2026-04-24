#!/usr/bin/env bash
# Shared helpers for rule check scripts.
directive_start() { echo "▶ $1"; }
violation() { echo "  ✗ $*" >&2; VIOLATIONS=$((${VIOLATIONS:-0}+1)); }
directive_end() { [[ ${VIOLATIONS:-0} -eq 0 ]] && echo "✓ passed" || return 1; }
