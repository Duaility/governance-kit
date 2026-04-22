#!/usr/bin/env bash
# CUSTOMIZED runner — the fixture owner edited this. Do not overwrite.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
for rule in "$HERE"/rules/*.sh; do
    bash "$rule" || exit 1
done
echo "governance: all custom rules passed"
