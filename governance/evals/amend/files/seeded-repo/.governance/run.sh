#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
for directive in "$HERE"/directives/*/check.sh; do
    [[ -f "$directive" ]] || continue
    bash "$directive"
done
