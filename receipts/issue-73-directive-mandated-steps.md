# Receipt: encode 'directive-mandated steps aren't optional' into the kit

Issue: [#73](https://github.com/Duaility/governance-kit/issues/73)

## Checklist

- [x] pr-required-when-checklist-complete violation message rewritten as imperative agent-directed mandate
- [x] check.sh header docstring updated to flag that the message imperative is intentional
- [x] Agent contract bullet added to the directive's constitution.md (pack copy)
- [x] Agent contract bullet mirrored into root CONSTITUTION.md directive section
- [x] pack copy and dogfood install edited together per the dual-edit rule
- [x] eval suite re-run and stays green
- [x] dogfood tests/governance/run.sh re-run; the only failure is the directive itself firing on this branch with the new imperative message
- [x] Evolution Log entry appended to CONSTITUTION.md
- [ ] AGENTS.md subsection capturing the norm with a canonical example and bounded exceptions (deferred — the in-pack tightening is the load-bearing change; the prose pass can follow)
- [ ] CONSTITUTION.md Principles entry cross-linked from the AGENTS.md subsection (deferred with the AGENTS.md prose)

## What changed

Issue #73's original "Decision" leaned on agent-facing prose in `AGENTS.md` plus an optional Principles entry, and explicitly listed pack-directive edits as out-of-scope. This receipt records a different (and stronger) approach taken in conversation: encode the mandate **inside the directive itself** so it travels with the pack — every repo that installs `agent-governance` picks up the agent contract, not just this one.

- `pr-required-when-checklist-complete` violation message rewritten as imperative agent-directed mandate. Old soft hint: "open one with: gh pr create --fill ...". New: "this directive mandates opening one now. Execute: gh pr create --fill --base main --head '<branch>' (receipts: ...). The directive's firing is the durable authorization; agents must run the command, not re-pose it as a 'want me to open the PR?' offer." The message is what an agent reads when the directive fires, so this is where the behavior shaping has to live.
- check.sh header docstring updated to flag that the message imperative is intentional — the next maintainer reading the file should not soften the message back into a hint.
- Agent contract bullet added to the directive's constitution.md (pack copy) under `extensions/packs/agent-governance/directives/pr-required-when-checklist-complete/`. Names the next action explicitly (`gh pr create --fill --base main --head <branch>`), rules out the question form ("want me to open the PR?"), and cabin's the exception (if the agent has a real blocker — auth failure, network failure, branch-state ambiguity — it surfaces the blocker and remediation, not a request for permission).
- Agent contract bullet mirrored into root CONSTITUTION.md directive section so the dogfood and the pack export the same text.
- pack copy and dogfood install edited together per the dual-edit rule (`extensions/packs/agent-governance/directives/...` and `tests/governance/directives/...`).
- eval suite re-run and stays green: 8/8 cases pass. The eval matches exit codes, not message text, so the rewrite is invisible to the harness — which is correct (the eval is testing the gate's logic, not the prose).
- dogfood tests/governance/run.sh re-run; the only failure is the directive itself firing on this branch with the new imperative message — expected, because the branch carries fully-ticked historical receipts (#63, #65, #66, #69, #71) and no PR yet. The fail surfaces the new message verbatim so the change is self-evident in the suite output.
- Evolution Log entry appended to CONSTITUTION.md describing the divergence from #73's original "Decision" and the rationale (encoding the mandate in the pack directive ships the norm to every install, not just this repo's docs).

The two unchecked items capture the original-issue scope that this commit deliberately defers: an AGENTS.md subsection with a canonical example and a Principles entry. The in-pack tightening is the load-bearing change; the prose pass can follow as a separate amendment without changing the directive's mechanism.

## Out of scope

- **AGENTS.md prose subsection.** The original #73 plan called for a stand-alone subsection capturing the norm with a worked example and bounded exceptions. Deferred; this commit is the in-pack change that the AGENTS.md prose would point at anyway.
- **CONSTITUTION.md Principles section entry.** Deferred with the AGENTS.md prose so they land together.
- **Promoting the directive from post-commit advisory to a pre-push hard gate.** Separate decision — out of scope per #73's own scope statement and unchanged here.
- **Editing the eval to match on message text.** The eval validates the gate, not the prose; coupling the two would force a message rewrite to also touch the harness without any safety gain.
- **Backfilling the same imperative tone into other agent-governance directives' violation messages.** Would be a sweep across `agent-token-accounting`, `agent-steering-accounting`, etc. Reserved for a follow-up if those directives' messages similarly read as soft hints rather than mandates.

## Verification

A reviewer can confirm the change is complete by checking:

1. **Violation message is imperative and agent-directed.** `grep -n "directive mandates opening one now" extensions/packs/agent-governance/directives/pr-required-when-checklist-complete/check.sh tests/governance/directives/pr-required-when-checklist-complete/check.sh` returns one hit per file; both occurrences are inside the `if [[ "$count" -eq 0 ]]` violation branch.
2. **check.sh header docstring is updated.** `grep -n "violation message is imperative on purpose" extensions/packs/agent-governance/directives/pr-required-when-checklist-complete/check.sh tests/governance/directives/pr-required-when-checklist-complete/check.sh` returns one hit per file in the top-of-file comment block.
3. **Agent contract bullet is present in pack copy.** `grep -n "Agent contract" extensions/packs/agent-governance/directives/pr-required-when-checklist-complete/constitution.md` returns one hit; the bullet names `gh pr create --fill --base main --head <branch>` and explicitly forbids the "want me to open the PR?" question form.
4. **Agent contract bullet is mirrored into root CONSTITUTION.md.** `grep -n "Agent contract" CONSTITUTION.md` returns one hit inside the `### pr-required-when-checklist-complete` section.
5. **Pack and dogfood diff is identical.** `diff extensions/packs/agent-governance/directives/pr-required-when-checklist-complete/check.sh tests/governance/directives/pr-required-when-checklist-complete/check.sh` prints nothing — the dual-edit rule held.
6. **Eval suite stays green.** `bash extensions/packs/agent-governance/directives/pr-required-when-checklist-complete/evals/test.sh` shows 8 passing cases.
7. **Dogfood suite fails only on the expected directive.** `bash tests/governance/run.sh` reports `14 passed, 1 failed`; the failure is `pr-required-when-checklist-complete` and its violation message contains the new imperative phrasing ("this directive mandates opening one now").
8. **Evolution Log entry is appended.** The latest Evolution Log entry in `CONSTITUTION.md` is dated 2026-04-27 and references the tightening of `pr-required-when-checklist-complete` and the agent contract bullet.
