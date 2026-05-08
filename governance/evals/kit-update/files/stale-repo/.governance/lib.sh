#!/usr/bin/env bash
# governance-kit:managed
# Old v0.1 helpers. Current kit ships directive_start / directive_end /
# violation / has_waiver helpers; this stub has none of them.
pass() { printf '✓ %s\n' "$1"; }
fail_msg() { printf '✗ %s\n' "$1"; }
