#!/usr/bin/env bash
directive_start() { echo "[$1] start"; }
violation() { echo "  violation: $1"; return 1; }
directive_end() { echo "[done]"; }
require_git() { git rev-parse --show-toplevel >/dev/null; }
has_waiver() { return 1; }
