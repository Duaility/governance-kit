#!/usr/bin/env bash
# Directive: layer-boundaries — for each change set, a fresh-context sub-agent
# attests that the diff honors the repo's declared layer model: no logic landing
# in the wrong layer (e.g. kit/engine code dropped under a pack), and no
# dependency pointing the wrong way across a layer edge. Whether a change
# *belongs* to a layer is a judgment about its role, not its path — grep cannot
# see it — so this is NOT a mechanical edge check. It is the second consumer of
# the shared sub-agent-attestation infra (issue #272): the directive requires the
# verdict to be *recorded* and *verdict-bearing*; the truth of the verdict is
# re-derived off the commit path by the merge-time sweep lane.
#
# The remediation loop (no hook spawns anything):
#   git commit
#     → check.sh: a receipt added in this change set lacks a verdict-bearing
#       '## Layer boundaries' section → FAIL; the violation message IS the
#       fresh-context sub-agent authoring instruction (from attestation_prompt).
#     → the harness agent spawns the sub-agent with the diff + the declared
#       layer model, the sub-agent writes the section, re-stages, re-commits.
#     → check.sh: section present + carries PASS/REFUTED → PASS.
#
# Ground truth handed to the sub-agent = the diff + the layer model declared in
# LAYER_DOC (default ARCHITECTURE.md; the `## Layer map` that architecture-map-holds
# keeps honest about the tree). Configure LAYER_DOC via the overlay
# `.governance/conf/duaility/governance-kit/layer-boundaries.conf` (or env
# GOVERNANCE_LAYER_DOC). The directive is a no-op when no layer model is declared
# or when the change set adds no receipt — new work owes the discipline; the
# historical corpus is grandfathered.
#
# Host = the receipt added in the change set (the same artifact #272's '## Audit'
# uses). Scope = staged additions at pre-commit, plus base..HEAD additions in CI,
# so the one argless check covers both the hook and run.sh.
#
# Exceptions: per-receipt waiver `governance: allow-layer-boundaries <reason>`
# in the receipt's first 10 lines (reason required). Audit:
# `grep -r 'allow-layer-boundaries' receipts/`.
set -u
source "$(dirname "$0")/../../../../../lib.sh"
directive_start "layer-boundaries"
require_git

# Runtime-dependency guard. This directive declares a `judge:` block and
# gates it through `judge_attest` (issue #325), which the kit ships in the
# runtime `lib.sh` from the release that carries that infra. On an older runtime
# (`.governance/lib.sh` synced from a kit predating it) the helper is undefined —
# enforcing here would either crash or silently false-pass. So skip cleanly when
# it is absent; the directive auto-activates the moment this repo updates to a
# kit whose `lib.sh` defines it. (The dogfood lags the source by one release by
# design, so this no-ops on this repo's own commits until the next kit sync.)
if ! declare -F judge_attest >/dev/null 2>&1; then
    directive_end
fi

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT" || exit 1

# ── The declared layer model is the ground truth. No model → nothing to attest
#    against → no-op (a repo that has not declared its layers pays nothing).
DEFAULTS="$(dirname "$0")/defaults.conf"
[[ -f "$DEFAULTS" ]] || { violation "broken install: $DEFAULTS missing (LAYER_DOC default unavailable)"; directive_end; }
LAYER_DOC="$(conf_get layer-boundaries LAYER_DOC "$DEFAULTS")"
if [[ -z "$LAYER_DOC" || ! -f "$ROOT/$LAYER_DOC" ]]; then
    directive_end
fi
# Expose the resolved doc to judge_attest's `layer-map` input resolution.
export GOVERNANCE_LAYER_DOC="$LAYER_DOC"

# The receipt is the attestation host; without one there is nowhere to record a
# verdict, and the change-set scoping below would find nothing.
[[ -d "$ROOT/receipts" ]] || directive_end

# ── Build the set of receipts ADDED in the current change set — these owe the
#    attestation; pre-existing receipts are grandfathered. Union of two sources
#    so the same argless check covers both hooks:
#      * pre-commit  — staged additions (`git diff --cached --diff-filter=A`).
#      * CI / run.sh — additions across base..HEAD (default-branch merge-base).
#    When no base resolves (e.g. on the default branch) only staged additions
#    apply; re-flagging receipts already on the trunk is out of scope, matching
#    commit-issue-receipt-match / receipt-per-issue.
ADDED_RECEIPTS=$'\n'
add_to_scope() {
    local f
    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        case "$ADDED_RECEIPTS" in
            *$'\n'"$f"$'\n'*) ;;
            *) ADDED_RECEIPTS+="$f"$'\n' ;;
        esac
    done
}
add_to_scope < <(git diff --cached --no-renames --diff-filter=A --name-only -- 'receipts/*.md' 2>/dev/null || true)
cs_base=""
for candidate in origin/main origin/master main master; do
    if git rev-parse --verify "$candidate" >/dev/null 2>&1; then
        mb=$(git merge-base HEAD "$candidate" 2>/dev/null || echo "")
        if [[ -n "$mb" && "$mb" != "$(git rev-parse HEAD 2>/dev/null)" ]]; then
            cs_base="$mb"
            break
        fi
    fi
done
if [[ -n "$cs_base" ]]; then
    while IFS= read -r sha; do
        [[ -z "$sha" ]] && continue
        add_to_scope < <(git diff-tree --no-commit-id --no-renames --name-only --diff-filter=A -r "$sha" -- 'receipts/*.md' 2>/dev/null || true)
    done < <(git log "$cs_base..HEAD" --format='%H' 2>/dev/null || true)
fi

# No receipt added in this change set → nothing to attest on → no-op.
if [[ "$ADDED_RECEIPTS" == $'\n' ]]; then
    directive_end
fi

# Per-receipt waiver: a `governance: allow-layer-boundaries <reason>` comment in
# the receipt's first 10 lines exempts it. Reason required; HTML comment markers
# are stripped so `<!-- ... -->` does not count as the reason.
has_layer_waiver() {
    local file="$1"
    [[ -f "$file" ]] || return 1
    head -n 10 "$file" 2>/dev/null \
        | sed -E 's/<!--//g; s/-->//g' \
        | grep -qE 'governance:[[:space:]]*allow-layer-boundaries[[:space:]]+[^[:space:]]'
}

# Accounting-only stub: a receipt whose only level-2 heading is `## Accounting`
# (created by the accounting hooks before the agent writes the narrative). Not a
# real receipt yet — skip it, exactly as receipt-per-issue does.
is_accounting_stub() {
    local file="$1"
    [[ -f "$file" ]] || return 1
    local h2
    h2="$(grep -E '^##[[:space:]]+' "$file" 2>/dev/null | sed -E 's/^##[[:space:]]+//; s/[[:space:]]+$//')"
    [[ "$h2" == "Accounting" ]]
}

# ── For each receipt added in this change set, demand the recorded attestation.
while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    [[ -f "$f" ]] || continue
    is_accounting_stub "$f" && continue
    has_layer_waiver "$f" && continue
    # The judgment task is declared once in directive.yaml's `judge:` block.
    # judge_attest reads it, gates the section's presence + verdict, and
    # registers it (isolation: shared) so the run-level orchestrator batches it
    # with receipt-per-issue's `## Audit` into a single sub-agent per commit.
    judge_attest "$f"
done <<< "$ADDED_RECEIPTS"

directive_end
