#!/usr/bin/env bash
# Produces a coverage/readiness report for the skill evals in this repo.
#
# Evals are behavioral (prompt + expected_output + assertions) and are graded by
# an LLM, so this script does not execute them. It inspects each skill's
# evals/evals.json and reports: case counts, assertion counts, and whether the
# referenced fixture directories exist and contain more than a placeholder.
#
# Usage:
#   bash scripts/eval-report.sh              # markdown report to stdout
#   bash scripts/eval-report.sh --out FILE   # also write report to FILE
#   bash scripts/eval-report.sh --json       # machine-readable JSON summary

set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILLS=(governance-bootstrap governance-amend)

OUT=""
FORMAT="md"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --out) OUT="$2"; shift 2 ;;
        --json) FORMAT="json"; shift ;;
        -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

if ! command -v jq >/dev/null 2>&1; then
    echo "error: jq is required" >&2
    exit 2
fi

# Collect results into parallel arrays (bash 3.2 compatible).
names=()
statuses=()
case_counts=()
assertion_counts=()
fixture_missing=()
fixture_placeholder=()
issues=()

overall_ready=1

for skill in "${SKILLS[@]}"; do
    spec="$ROOT/$skill/evals/evals.json"
    names+=("$skill")

    if [[ ! -f "$spec" ]]; then
        statuses+=("missing")
        case_counts+=(0)
        assertion_counts+=(0)
        fixture_missing+=(0)
        fixture_placeholder+=(0)
        issues+=("no evals/evals.json")
        overall_ready=0
        continue
    fi

    if ! jq -e . "$spec" >/dev/null 2>&1; then
        statuses+=("invalid-json")
        case_counts+=(0)
        assertion_counts+=(0)
        fixture_missing+=(0)
        fixture_placeholder+=(0)
        issues+=("evals.json is not valid JSON")
        overall_ready=0
        continue
    fi

    n_cases=$(jq '.evals | length' "$spec")
    n_assert=$(jq '[.evals[].assertions | length] | add // 0' "$spec")

    miss=0
    place=0
    skill_issues=""
    while IFS= read -r rel; do
        [[ -z "$rel" ]] && continue
        path="$ROOT/$skill/$rel"
        if [[ ! -e "$path" ]]; then
            miss=$((miss + 1))
            skill_issues+="missing fixture: $rel; "
        elif [[ -d "$path" ]]; then
            # Placeholder = directory contains only a README.md (no seeded repo).
            entries=$(find "$path" -mindepth 1 -maxdepth 1 ! -name README.md | head -n 1)
            if [[ -z "$entries" ]]; then
                place=$((place + 1))
                skill_issues+="fixture is placeholder only: $rel; "
            fi
        fi
    done < <(jq -r '.evals[].files[]?' "$spec")

    fixture_missing+=("$miss")
    fixture_placeholder+=("$place")
    case_counts+=("$n_cases")
    assertion_counts+=("$n_assert")

    if [[ $miss -gt 0 || $place -gt 0 ]]; then
        statuses+=("fixtures-incomplete")
        overall_ready=0
    else
        statuses+=("ready")
    fi
    issues+=("${skill_issues%% ; }")
done

emit_md() {
    printf '# Skill evals report\n\n'
    printf '_Generated %s_\n\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '| Skill | Status | Cases | Assertions | Missing fixtures | Placeholder fixtures |\n'
    printf '|---|---|---:|---:|---:|---:|\n'
    for i in "${!names[@]}"; do
        printf '| %s | %s | %s | %s | %s | %s |\n' \
            "${names[$i]}" "${statuses[$i]}" "${case_counts[$i]}" \
            "${assertion_counts[$i]}" "${fixture_missing[$i]}" "${fixture_placeholder[$i]}"
    done
    printf '\n## Notes\n\n'
    for i in "${!names[@]}"; do
        if [[ -n "${issues[$i]}" ]]; then
            printf -- '- **%s**: %s\n' "${names[$i]}" "${issues[$i]}"
        fi
    done
    printf '\n## How to run the evals\n\n'
    printf 'Evals are LLM-graded behavioral checks, not unit tests. For each case in '
    printf 'a skill'\''s `evals.json`:\n\n'
    printf '1. Copy the fixture under `<skill>/evals/files/<fixture>/` into a fresh temp dir and `git init` it.\n'
    printf '2. Start a Claude Code session scoped to that dir with the skill installed.\n'
    printf '3. Paste the `prompt` field verbatim.\n'
    printf '4. Compare the resulting state against `expected_output` and each item in `assertions`.\n\n'
    if [[ $overall_ready -eq 1 ]]; then
        printf '**All skills have complete eval specs and fixtures.**\n'
    else
        printf '**Some skills are not eval-ready** — see the Notes section.\n'
    fi
}

emit_json() {
    local first=1
    printf '{"generated_at":"%s","skills":[' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    for i in "${!names[@]}"; do
        [[ $first -eq 0 ]] && printf ','
        first=0
        printf '{"name":"%s","status":"%s","cases":%s,"assertions":%s,"missing_fixtures":%s,"placeholder_fixtures":%s,"notes":%s}' \
            "${names[$i]}" "${statuses[$i]}" "${case_counts[$i]}" \
            "${assertion_counts[$i]}" "${fixture_missing[$i]}" "${fixture_placeholder[$i]}" \
            "$(printf '%s' "${issues[$i]}" | jq -Rs .)"
    done
    printf '],"ready":%s}\n' "$([[ $overall_ready -eq 1 ]] && echo true || echo false)"
}

if [[ "$FORMAT" == "json" ]]; then
    if [[ -n "$OUT" ]]; then emit_json | tee "$OUT"; else emit_json; fi
else
    if [[ -n "$OUT" ]]; then emit_md | tee "$OUT"; else emit_md; fi
fi

[[ $overall_ready -eq 1 ]]
