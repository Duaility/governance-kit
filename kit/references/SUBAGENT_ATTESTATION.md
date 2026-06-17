# Sub-agent attestation sections

Shared kit infrastructure for directives that need a section a **fresh-context
sub-agent** must populate — a verdict against ground truth the mechanical check
structurally cannot read. First shipped for `receipt-per-issue`'s `## Audit`
rule (issue #272); the second consumer is the repo-local `duaility/governance-kit`
pack's `layer-boundaries` dogfood directive (issue #277), whose `## Layer boundaries`
section records a verdict on whether a diff honors the repo's declared layer
model — the architectural-invariant case this pattern was designed for.

## The problem it solves

A form-checked directive proves an artifact is *internally consistent* — its
`check.sh` re-executes a relationship between strings the artifact already
carries. It cannot prove the artifact *corresponds to reality*, because the
ground truth (the diff, the linked issue, the running system) is exactly what a
pre-commit hook does not read. `receipt-per-issue`'s checklist crosswalk is the
canonical example: it confirms each `- [x]` item is echoed in the receipt's own
prose, never that either matches the diff.

Closing that gap needs an **independent reader** of the ground truth. The kit
already has two enforcement lanes — the deterministic commit hook and the
off-path `surface: sweep` LLM judge (see [SWEEP_FLOW.md](SWEEP_FLOW.md)). This is
a third shape that sits between them: an **author-time** independent audit,
recorded into the artifact and gated for *presence*, with the truth of its
verdict deferred to the sweep lane at merge.

## The remediation loop (no hook ever spawns anything)

A git hook can neither spawn a sub-agent nor judge its output, and in both
Claude Code and Codex sub-agent spawning is a model/user decision, never a
primitive a hook can trigger. So the directive follows the standard GDD
remediation loop:

```
git commit
  → check.sh: '## <Section>' missing → FAIL, and the violation message
    IS the authoring instruction (the sub-agent prompt)
  → the harness agent reads stderr, spawns a fresh-context sub-agent,
    the sub-agent reads ground truth and writes the section
  → agent re-stages the artifact, re-commits
  → check.sh: section present + carries a verdict → PASS
```

Two honest limits this pattern owns rather than hides:

- **It records; it does not adjudicate.** `check.sh` can verify the section
  *exists and is verdict-bearing*, never that the verdict is *true*. Trusting
  the verdict is the merge-time sweep lane's job (deferred). The commit-path
  guarantee is "the audit was recorded," not "the audit passed."
- **Harness-only authoring.** The instruction only lands where an agent is
  reading stderr. A bare human commit or a CI run has no agent to spawn
  anything, so `check.sh` simply hard-fails on the missing section — correct
  (the audit step did not run), but the hook can *demand* the section, never
  *manufacture* it.

The independence is the whole point: a sub-agent handed only the ground truth —
never the code-author's reasoning — is a genuinely independent auditor. That is
the author≠auditor split happening at author-time instead of at merge.

## The helpers (in `lib.sh`)

Any directive's `check.sh` can source `lib.sh` and call:

- **`extract_md_section <file> <heading>`** — print the body of the
  `## <heading>` section (case-insensitive), stopping at the next `## `. The
  generic markdown-section reader.
- **`attestation_prompt <section> <inputs> <check-1> [<check-2> ...]`** — print
  the canonical sub-agent authoring instruction: spawn a fresh-context
  sub-agent **on a small, low-cost model** (see [Model tier](#model-tier-use-a-small-model) below),
  with `<inputs>`, report PASS/REFUTED + evidence for each numbered
  check, default to REFUTED if uncertain, write into `## <section>`, and the
  hook never spawns anything. One envelope so every attestation-backed
  directive emits the same recognizable instruction.
- **`require_attestation <file> <section> <why> <inputs> <check-1> [...]`** —
  the deterministic gate. Records a `violation` when `<file>` lacks a
  well-formed `## <section>`: absent → `<why>` + the `attestation_prompt`
  instruction; present but with no PASS/REFUTED verdict → a "fill in the
  verdict" message. Returns 0 on a well-formed section, 1 otherwise. Purely
  mechanical: presence + a verdict token, never the verdict's truth.

The verdict token the gate looks for is `PASS` or `REFUTED` (case-insensitive),
so the sub-agent prompt should instruct the auditor to render exactly those.

## Model tier: use a small model

The author-time attestation is a **bounded read-and-record audit**, not the
final word on truth. The commit-path gate only checks the section is *present
and verdict-bearing*; the verdict's correctness is independently re-derived by
the merge-time **sweep lane** (`surface: sweep`), which picks its own
`model_tier`. So the expensive reasoning belongs there — the author-time pass
should run on a **small, low-cost model** (the *low* capability tier — e.g.
Claude Haiku or a comparable GPT-mini-class model). This is a deliberate cost
optimization (issue #321): the audit fires on every newly added attested
artifact, and over-provisioning it with a large model buys little when a cheap
model can read the diff, compare it to the artifact, and record a verdict.

`attestation_prompt` bakes this request into the instruction it emits, so every
attestation-backed directive inherits the small-model guidance from one surface
— there is no per-directive knob. Two practical notes:

- The guidance names a **capability tier**, not a pinned model id (mirroring the
  sweep lane's `model_tier`), so a model upgrade within the tier doesn't silently
  change behavior.
- Small models occasionally fumble strict output formatting. The prompt asks the
  auditor to render the verdict as literally `PASS` or `REFUTED`, and the gate
  matches that token case-insensitively anywhere in the section — so a verbose or
  slightly-off-format audit still passes as long as it records the token.

## Wiring a directive onto it

```sh
# In a change-set-scoped block (only newly added artifacts owe the attestation):
require_attestation "$f" "Audit" \
    "The mechanical checks prove this artifact is internally consistent, never that it matches reality." \
    "the diff (\`git diff\`), this receipt, and the linked issue (\`gh issue view $issue_ref\`)" \
    "'## What changed' faithfully describes the diff" \
    "each '- [x]' item is realized in the diff" \
    "the '## Checklist' mirrors the issue's checklist"
```

Scope the requirement to the change set (new work owes the new discipline; the
historical corpus is grandfathered), exactly as `receipt-per-issue` scopes its
`## Decisions` rule.

## Versioning note

Because the helpers live in kit-owned `lib.sh`, a pack whose directive uses them
must declare a `min_governance_kit` floor at the kit version that ships them —
`require_attestation` landed on the kit's 0.9.0 source line (issue #272), so the
`governance-kit/audit` pack floors at `0.9.0`. See [VERSIONING.md](VERSIONING.md).

## See also

- [SWEEP_FLOW.md](SWEEP_FLOW.md) — the off-path LLM-judge lane that re-derives
  recorded verdicts at merge (the deferred "adjudicate" half).
- [DIRECTIVE_AUTHORING.md](DIRECTIVE_AUTHORING.md) — patterns for writing checks.
- [PHILOSOPHY.md](PHILOSOPHY.md) — receipts over transcripts; why a recorded,
  attributable verdict is worth more than a ticked box.
