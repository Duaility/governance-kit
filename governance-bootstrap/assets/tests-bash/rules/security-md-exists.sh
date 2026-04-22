#!/usr/bin/env bash
# Rule: SECURITY.md exists and tells people how to report a vulnerability.
# Accepts SECURITY.md at repo root, in docs/, or in .github/ (GitHub community
# health file). Must contain a contact mechanism — an email address or URL.
set -u
source "$(dirname "$0")/../lib.sh"
rule_start "security-md-exists"
require_git

ROOT="$(git rev-parse --show-toplevel)"
FILE=""
for candidate in SECURITY.md docs/SECURITY.md .github/SECURITY.md; do
    [[ -f "$ROOT/$candidate" ]] && { FILE="$ROOT/$candidate"; break; }
done

if [[ -z "$FILE" ]]; then
    violation "no SECURITY.md (looked at: SECURITY.md, docs/SECURITY.md, .github/SECURITY.md)"
    rule_end
fi

if [[ ! -s "$FILE" ]]; then
    violation "$FILE exists but is empty"
    rule_end
fi

# Needs at least one way to get hold of a human — email, URL, or hackerone/bugcrowd ref.
if ! grep -qE '([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}|https?://|hackerone|bugcrowd)' "$FILE"; then
    violation "$FILE has no contact email, URL, or vulnerability-disclosure platform reference"
fi

rule_end
