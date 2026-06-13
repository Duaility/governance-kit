# issue-249 — surface each directive's rationale when its check fails

Closes [#249](https://github.com/Duaility/governance-kit/issues/249).

## Checklist

- [x] Rationale injection in `directive_end` (kit source only; consumed tree untouched)
- [x] Multi-line rationale extraction is robust for community packs
- [x] README opening restructured into a problem-first narrative
- [x] Suite green; pass path stays silent

## What changed

- **Rationale injection in `directive_end` (kit source only; consumed tree untouched).** `directive_end` in `lib.sh` now, on the failure path only, reads the `constitution.md` that sits beside the running `check.sh` (`$(dirname "$0")/constitution.md`), extracts the directive's `**Rationale**:` field, and prints it in yellow beneath the violation list. The success path is untouched, so a green check prints nothing extra. A missing `constitution.md` is guarded with `[[ -f ]]` and degrades silently — community packs are not forced to ship one. The change lands **only** in the kit source (`kit/assets/dot-governance/lib.sh`) — the product. The repo's own consumed copy (`.governance/lib.sh`) is deliberately left at the pinned release (`kit-version=0.7.2`): per Lane 1 it is an honest customer of the last release and moves only via `governance kit update` in a post-release PR, so it picks up this feature when the next kit version is cut. The kit's own test suite validates the change from the source asset — `scripts/test-runtime.sh` copies `kit/assets/dot-governance/lib.sh` into a throwaway repo and exercises `directive_end` there — so no dogfood edit is needed. This makes the README's standing claim — that a failing check surfaces the rule's rationale at the moment of violation — factually true of the product; previously only the directive name and raw violation strings were emitted.
- **Multi-line rationale extraction is robust for community packs.** The extractor is an `awk` pass (not `grep -m1`/`sed`) that captures the `**Rationale**:` bullet, strips the label, and joins any wrapped continuation lines into one until it hits a blank line, the next `- **` field, or a heading. All 23 bundled directives happen to use single-line rationales, but the kit ingests third-party packs, so a wrapped rationale must not be silently truncated.
- **README opening restructured into a problem-first narrative.** The opening no longer leads with a "What it does" bullet wall. It now ramps: the drift-across-sessions problem → the harness-engineering insight (credited and linked to OpenAI's post) → our take (rules live in composable, pinnable, locally-authorable **packs**, plus a git-native audit trail). Four quick-scan bullets follow the story rather than precede it, and the harness-engineering failure-mode mapping table is demoted into a `<details>` block so it no longer blocks the path to the quickstart. Nothing below "How it works (30 seconds)" changed.

## Out of scope

- Touching the `packs/` source tree or any directive folder — the rationale logic lives entirely in `lib.sh`, which every `check.sh` already sources, so all directives (bundled and community) gain the behavior without per-directive edits.
- Editing the consumed tree (`.governance/lib.sh`, `.governance/run.sh`, `.governance/packs/**`) — that tree is regenerated only by `governance kit update` / `pack update` at release time; an initial draft of this change hand-edited `.governance/lib.sh` and was reverted (see Decisions).
- The four minimal eval-fixture `lib.sh` stubs (`kit/evals/**`) — they are intentionally terse hand-authored stubs that exist only to make the eval test repos runnable, not byte-copies of the kit `lib.sh`; they are deliberately left untouched.
- The pre-existing `commit-message-format` failure on HEAD `0281cb1` (its 104-char subject exceeds the 100-char limit) — unrelated to this change and not in scope to fix here.
- The banner PNGs (`docs/assets/banner-{light,dark}.png`) carried in alongside this change are the earlier README banner-alignment fix; they are not part of the rationale feature but ride in this commit.

## Decisions

- **Read the rationale from `constitution.md` at runtime rather than baking it into `check.sh`.** The constitution subsection is the single source of the *why* and already sits beside the check; reading it on demand keeps one copy of the rationale and means a `directive modify` that updates the rationale needs no second edit.
- **`awk` join over `grep -m1`.** Chosen specifically to not truncate a community pack's wrapped rationale; the bundled directives wouldn't have exposed the bug, but the kit's purpose is third-party packs.
- **Bundled the README narrative restructure and the `lib.sh` feature in one PR.** They are causally linked — the README claim drove the discovery that the feature was missing — and this repo follows one-issue/one-PR/one-receipt, so they land together.
- **Reverted an initial hand-edit to the consumed `.governance/lib.sh`.** The first draft changed both the kit source and the repo's vendored copy. That breaks Lane 1 (the consumed tree must equal the pinned release and move only via the lifecycle verb). It also slipped through every gate — `consumed-tree-integrity` globs `.governance/packs/**` only, and `kit-version-sync` checks just the version marker (left at `0.7.2`), so neither flagged the content drift. The product change is kept in the kit source; the consumed copy was restored to the pinned release. (Gap noted: no directive currently byte-matches the top-level managed files against the pinned kit — a candidate follow-up.)

## Verification

Single-line rationale (real directive), multi-line (synthetic), and missing-file (graceful) all behaved correctly when run against the kit-source `lib.sh`. Suite green; pass path stays silent — the full kit-internal and dogfood suites pass and a passing check emits no rationale line. The consumed `.governance/lib.sh` is intentionally NOT modified, so it still matches the pinned release:

```sh
# the product change is in the kit source; the consumed copy stays at the pin
grep -c constitution.md kit/assets/dot-governance/lib.sh   # → 2 (feature present)
grep -c constitution.md .governance/lib.sh                 # → 0 (pinned release, untouched)

# rationale surfaces on a real failure, exercised from the kit source via the eval suite
bash scripts/test.sh          # → ✓ all kit-internal test layers passed (test-runtime sources kit/assets/dot-governance/lib.sh)
bash .governance/run.sh       # → all directives green
```

## Accounting

<!-- Accounting rows are maintained by the agent-token-accounting and agent-steering-accounting pre-commit hooks. Keys are opaque — do not parse. -->

### Steering

| steer-key | session | issue | type | tier | user-reason | commit |
| --- | --- | --- | --- | --- | --- | --- |
| steer-1e57cae2837-1781354629-1 | 1e57cae2-8379-4355-a13d-9864aea0247b | #249 | interrupt | structural |  | feat(lib): surface each directive's rationale when its check fails (#249) |
| steer-1e57cae2837-1781354629-2 | 1e57cae2-8379-4355-a13d-9864aea0247b | #249 | correction | classifier | Banner alignment fix failed; alignment still disturbed in user's renderer | feat(lib): surface each directive's rationale when its check fails (#249) |
| steer-1e57cae2837-1781354629-3 | 1e57cae2-8379-4355-a13d-9864aea0247b | #249 | correction | classifier | README still too rule-first/vague; wants context ramp-up before rules | feat(lib): surface each directive's rationale when its check fails (#249) |
| steer-1e57cae2837-1781354629-4 | 1e57cae2-8379-4355-a13d-9864aea0247b | #249 | correction | classifier | Asked to step back and re-review the code before proceeding | feat(lib): surface each directive's rationale when its check fails (#249) |
| steer-1e57cae2837-1781354629-5 | 1e57cae2-8379-4355-a13d-9864aea0247b | #249 | correction | classifier | Touched .governance folder which should only change during kit upgrades | feat(lib): surface each directive's rationale when its check fails (#249) |

### Costs

| cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| claude-code-57064747-e90-1781354630-1 | claude-code | 57064747-e900-416a-be7f-f1df94156d5c | #249 | claude-opus-4-8 | 2763 | 13892 | 16003 | 215 | 16870 | 0.1140 | feat(lib): surface each directive's rationale when its check fails (#249) |
