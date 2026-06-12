#!/usr/bin/env bash
directive_start() { echo "[$1] start"; }
violation() { echo "  violation: $1"; return 1; }
directive_end() { echo "[done]"; }
