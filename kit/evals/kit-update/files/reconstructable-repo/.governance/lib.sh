#!/usr/bin/env bash
# governance-kit:managed kit-version=0.1 generated=2026-04-01
# Old v0.1 helpers stub. The marker above is the per-file version pin
# `kit update` reads when reconstructing `install.yaml` from scratch.
pass() { printf '✓ %s\n' "$1"; }
fail() { printf '✗ %s\n' "$1" >&2; return 1; }
