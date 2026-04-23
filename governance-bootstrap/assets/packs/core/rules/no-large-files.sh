#!/usr/bin/env bash
# Rule: No tracked file exceeds the size limit.
# Default: 5 MB. Override with GOVERNANCE_MAX_FILE_SIZE_MB.
# Rationale: bloated repos slow every clone. Agents create fresh worktrees
# constantly, so the cost compounds.
set -u
source "$(dirname "$0")/../lib.sh"
rule_start "no-large-files"
require_git

LIMIT_MB="${GOVERNANCE_MAX_FILE_SIZE_MB:-5}"
LIMIT_BYTES=$((LIMIT_MB * 1024 * 1024))

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT" || exit 1

# Portable byte-size for a file.
file_size() {
    # BSD stat (macOS)
    stat -f%z "$1" 2>/dev/null && return 0
    # GNU stat
    stat -c%s "$1" 2>/dev/null && return 0
    # Fallback
    wc -c < "$1" | tr -d ' '
}

while IFS= read -r f; do
    [[ -z "$f" || ! -f "$f" ]] && continue
    size=$(file_size "$f")
    [[ -z "$size" ]] && continue
    if [[ "$size" -gt "$LIMIT_BYTES" ]]; then
        hr=$(awk -v b="$size" 'BEGIN{ split("B KB MB GB", u); s=0; while (b>1024 && s<3) { b/=1024; s++ } printf "%.1f %s", b, u[s+1] }')
        violation "$f — $hr (limit: ${LIMIT_MB} MB). Use Git LFS or host externally."
    fi
done < <(git ls-files)

rule_end
