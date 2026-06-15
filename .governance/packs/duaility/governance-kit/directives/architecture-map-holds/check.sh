#!/usr/bin/env bash
# Directive: architecture-map-holds (dogfood) — the layer / responsibility map
# carried as a Mermaid `flowchart` block in ARCHITECTURE.md must stay true to
# the real tree. Three groups of assertions, all mechanical and offline:
#
#   1. block shape   — exactly one non-empty ```mermaid fenced block that
#                      declares a `flowchart`. (Structural; no `mmdc` needed, so
#                      the check runs the same in the hook and in CI.)
#   2. paths resolve — every token tagged with an `arch-map-path:` HTML comment
#                      beside the block must (a) resolve to a real path and
#                      (b) appear verbatim inside the block. This is the cheap,
#                      high-value rename-drift catch: rename a layer dir without
#                      updating the map and the gate fails.
#   3. boundary edges — the rules the arrows assert actually hold:
#                      • skill/ carries no kit version string and contains only
#                        SKILL.md + bootstrap.py (the installer carries no kit
#                        code) — the thin-skill boundary from the #198 split;
#                      • the repo pins both axes: .governance/install.yaml has a
#                        non-empty kit_version, .governance/packs.lock lists at
#                        least one pack;
#                      • the diagram carries the two downward edges
#                        (skill → kit, kit → packs) and no upward edge.
#
# The analogy text and "the kit hardcodes no pack version" are intentionally NOT
# gated here — they're prose claims whose mechanical form false-positives on
# docs/examples (issue #271 bucket 3, audit-only). See constitution.md.
set -u
source "$(dirname "$0")/../../../../../lib.sh"
directive_start "architecture-map-holds"
require_git
ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT" || exit 1

DOC="ARCHITECTURE.md"
if [[ ! -f "$DOC" ]]; then
    violation "$DOC not found at repo root — the layer map lives there"
    directive_end
fi

# ── extract the single mermaid fenced block ─────────────────────────────────
# Pull the lines strictly between the opening ```mermaid fence and its closing
# ``` fence. Also count how many mermaid blocks the file has, so we can flag a
# split/duplicated map (the check targets exactly one stable block).
mermaid_count="$(grep -cE '^[[:space:]]*```mermaid[[:space:]]*$' "$DOC")"
MERMAID="$(awk '
    /^[[:space:]]*```mermaid[[:space:]]*$/ { ingrab=1; next }
    ingrab && /^[[:space:]]*```[[:space:]]*$/ { ingrab=0; next }
    ingrab { print }
' "$DOC")"

if [[ "$mermaid_count" -eq 0 ]]; then
    violation "no \`\`\`mermaid block in $DOC — the layer map must be carried as a Mermaid diagram"
    directive_end
elif [[ "$mermaid_count" -gt 1 ]]; then
    violation "$DOC has $mermaid_count mermaid blocks — the layer map must be a single block (the check targets one stable target)"
fi

if [[ -z "${MERMAID//[[:space:]]/}" ]]; then
    violation "the mermaid block in $DOC is empty"
    directive_end
fi
if ! grep -qE '\bflowchart\b' <<<"$MERMAID"; then
    violation "the mermaid block in $DOC does not declare a \`flowchart\` (the layer map is a flowchart)"
fi

# ── (2) every tagged path token resolves AND appears in the block ───────────
tag_count=0
while IFS= read -r token; do
    [[ -z "$token" ]] && continue
    tag_count=$((tag_count + 1))
    if [[ ! -e "$ROOT/$token" ]]; then
        violation "arch-map-path '$token' does not resolve to a real path — the map names a directory the tree no longer has (update the diagram + tag)"
    fi
    if ! grep -qF "$token" <<<"$MERMAID"; then
        violation "arch-map-path '$token' is tagged for the check but does not appear in the mermaid block — diagram and tags have drifted"
    fi
done < <(grep -oE 'arch-map-path:[[:space:]]*[^[:space:]-][^[:space:]]*' "$DOC" \
            | sed -E 's/^arch-map-path:[[:space:]]*//')

if [[ "$tag_count" -eq 0 ]]; then
    violation "no \`arch-map-path:\` tags found beside the map in $DOC — at least the layer dirs (skill/, kit/, packs/) must be tagged so renames are caught"
fi

# ── (3a) skill/ carries no kit code or version (installer is thin) ──────────
# The diagram claims the skill is the installer and carries no kit code/version.
# Real form: skill/ has exactly SKILL.md + bootstrap.py, and no kit version
# string anywhere under it.
skill_files="$(git ls-files skill/ | sort)"
expected_skill_files=$'skill/SKILL.md\nskill/bootstrap.py'
expected_skill_sorted="$(printf '%s\n' "$expected_skill_files" | sort)"
if [[ "$skill_files" != "$expected_skill_sorted" ]]; then
    extra="$(comm -23 <(printf '%s\n' "$skill_files") <(printf '%s\n' "$expected_skill_sorted") | paste -sd' ' -)"
    [[ -n "$extra" ]] \
        && violation "skill/ carries more than the installer shim — unexpected tracked file(s): $extra (the diagram says skill/ holds no kit code)" \
        || violation "skill/ is missing the expected installer files (expected only skill/SKILL.md + skill/bootstrap.py)"
fi
if kit_ver="$(git grep -nE 'kit[-_]version|kit/v[0-9]' -- skill/ 2>/dev/null)" && [[ -n "$kit_ver" ]]; then
    violation "skill/ contains a kit version string — the installer must carry no kit version (it honors the repo's pin): ${kit_ver%%$'\n'*}"
fi

# ── (3b) the repo pins both axes ────────────────────────────────────────────
INSTALL_YAML=".governance/install.yaml"
LOCK=".governance/packs.lock"
if [[ ! -f "$INSTALL_YAML" ]]; then
    violation "$INSTALL_YAML missing — the diagram says the repo pins the kit there"
elif ! grep -qE '^kit_version:[[:space:]]*["'"'"']?[0-9]' "$INSTALL_YAML"; then
    violation "$INSTALL_YAML has no non-empty kit_version — the kit pin the diagram asserts is absent"
fi
if [[ ! -f "$LOCK" ]]; then
    violation "$LOCK missing — the diagram says the repo pins the packs there"
elif ! grep -qE '^[[:space:]]*-[[:space:]]+id:' "$LOCK"; then
    violation "$LOCK lists no packs — the pack pin the diagram asserts is absent"
fi

# ── (3c) the layering arrows stay one-way ───────────────────────────────────
# Operate only on edge lines (those containing `--`), so node-definition labels
# that merely mention "skill"/"kit"/"packs" never trip the upward-edge check.
edges="$(grep -E -- '--' <<<"$MERMAID" || true)"
grep -qE '^[[:space:]]*skill[[:space:]]*--+>?.*\bkit\b' <<<"$edges" \
    || violation "the diagram is missing the downward edge skill → kit"
grep -qE '^[[:space:]]*kit[[:space:]]*--+>?.*\bpacks\b' <<<"$edges" \
    || violation "the diagram is missing the downward edge kit → packs"
if grep -qE '^[[:space:]]*kit[[:space:]]*-.*\bskill\b' <<<"$edges"; then
    violation "the diagram carries an upward edge kit → skill — the layering must point only downward (skill → kit → packs)"
fi
if grep -qE '^[[:space:]]*packs[[:space:]]*-.*\bkit\b' <<<"$edges"; then
    violation "the diagram carries an upward edge packs → kit — the layering must point only downward (skill → kit → packs)"
fi

directive_end
