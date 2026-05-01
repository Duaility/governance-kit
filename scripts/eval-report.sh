#!/usr/bin/env bash
# Produces a coverage/readiness report for the governance skill's evals.
#
# Evals are behavioral (prompt + expected_output + assertions) and are graded
# by an LLM, so this script does not execute them. It walks the verb folders
# under governance/evals/<verb>/evals.json and reports per-verb case counts,
# assertion counts, and whether the referenced fixture directories exist and
# contain more than a placeholder README.
#
# An eval case may declare `"fixture_empty_by_design": true` to mark a fixture
# whose emptiness is itself the test (e.g. uninstall on a repo with no
# governance footprint). Such fixtures are not flagged as placeholders.
#
# Usage:
#   bash scripts/eval-report.sh              # markdown report to stdout
#   bash scripts/eval-report.sh --out FILE   # also write report to FILE
#   bash scripts/eval-report.sh --json       # machine-readable JSON summary

set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_DIR="$ROOT/governance"
EVALS_ROOT="$SKILL_DIR/evals"

OUT=""
FORMAT="md"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --out) OUT="$2"; shift 2 ;;
        --json) FORMAT="json"; shift ;;
        -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

if ! command -v jq >/dev/null 2>&1; then
    echo "error: jq is required" >&2
    exit 2
fi

if [[ ! -d "$EVALS_ROOT" ]]; then
    echo "error: $EVALS_ROOT not found" >&2
    exit 2
fi

# Discover verbs by globbing evals.json files.
verbs=()
while IFS= read -r spec; do
    verb="$(basename "$(dirname "$spec")")"
    verbs+=("$verb")
done < <(find "$EVALS_ROOT" -mindepth 2 -maxdepth 2 -name evals.json | sort)

if [[ ${#verbs[@]} -eq 0 ]]; then
    echo "error: no verb evals.json files under $EVALS_ROOT" >&2
    exit 2
fi

# Parallel arrays (bash 3.2 compatible).
names=()
statuses=()
case_counts=()
assertion_counts=()
fixture_missing=()
fixture_placeholder=()
issues=()

overall_ready=1

for verb in "${verbs[@]}"; do
    spec="$EVALS_ROOT/$verb/evals.json"
    names+=("$verb")

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
    verb_issues=""
    while IFS=$'\t' read -r rel empty_flag; do
        [[ -z "$rel" ]] && continue
        path="$EVALS_ROOT/$verb/$rel"
        if [[ ! -e "$path" ]]; then
            miss=$((miss + 1))
            verb_issues+="missing fixture: $rel; "
        elif [[ -d "$path" ]]; then
            entries=$(find "$path" -mindepth 1 -maxdepth 1 ! -name README.md | head -n 1)
            if [[ -z "$entries" && "$empty_flag" != "true" ]]; then
                place=$((place + 1))
                verb_issues+="fixture is placeholder only: $rel; "
            fi
        fi
    done < <(jq -r '.evals[] | (.fixture_empty_by_design // false) as $e | (.files // []) | .[] | [., ($e|tostring)] | @tsv' "$spec")

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
    issues+=("${verb_issues%% ; }")
done

emit_md() {
    printf '# Governance skill evals report\n\n'
    printf '_Generated %s_\n\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'Skill: `governance` (single skill, one verb-folder per row).\n\n'
    printf '| Verb | Status | Cases | Assertions | Missing fixtures | Placeholder fixtures |\n'
    printf '|---|---|---:|---:|---:|---:|\n'
    local total_cases=0 total_assert=0
    for i in "${!names[@]}"; do
        printf '| %s | %s | %s | %s | %s | %s |\n' \
            "${names[$i]}" "${statuses[$i]}" "${case_counts[$i]}" \
            "${assertion_counts[$i]}" "${fixture_missing[$i]}" "${fixture_placeholder[$i]}"
        total_cases=$((total_cases + ${case_counts[$i]}))
        total_assert=$((total_assert + ${assertion_counts[$i]}))
    done
    printf '| **total** | — | **%d** | **%d** | — | — |\n' "$total_cases" "$total_assert"
    printf '\n## Notes\n\n'
    local any_notes=0
    for i in "${!names[@]}"; do
        if [[ -n "${issues[$i]}" ]]; then
            printf -- '- **%s**: %s\n' "${names[$i]}" "${issues[$i]}"
            any_notes=1
        fi
    done
    [[ $any_notes -eq 0 ]] && printf '_No issues._\n'
    printf '\n## How to run the evals\n\n'
    printf 'Evals are LLM-graded behavioral checks, not unit tests. For each case in '
    printf 'a verb'\''s `evals.json`:\n\n'
    printf '1. Copy the fixture under `governance/evals/<verb>/files/<fixture>/` into a fresh temp dir and `git init` it.\n'
    printf '2. Start a Claude Code session scoped to that dir with the `governance` skill installed.\n'
    printf '3. Paste the `prompt` field verbatim.\n'
    printf '4. Compare the resulting state against `expected_output` and each item in `assertions`.\n\n'
    if [[ $overall_ready -eq 1 ]]; then
        printf '**All verbs have complete eval specs and fixtures.**\n'
    else
        printf '**Some verbs are not eval-ready** — see the Notes section.\n'
    fi
}

emit_json() {
    local first=1
    printf '{"generated_at":"%s","skill":"governance","verbs":[' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
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
