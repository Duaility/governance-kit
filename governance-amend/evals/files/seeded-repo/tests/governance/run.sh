#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
for rule in "$HERE"/rules/*/check.sh; do
    [[ -f "$rule" ]] || continue
    bash "$rule"
done
