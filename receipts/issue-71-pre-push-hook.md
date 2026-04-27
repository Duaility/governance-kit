# Receipt: add pre-push as a supported hook kind

Issue: [#71](https://github.com/Duaility/governance-kit/issues/71)

## Checklist

- [x] _emit_pre_push added to hooks.sh
- [x] generate_hooks loop extended to emit pre-push
- [x] hooks.sh header docstring updated to mention pre-push
- [x] test-packs.sh helper detection loop extended
- [x] SKILL.md dispatcher list extended
- [x] AGENTS.md hook enum extended
- [x] AUTHORING_PACKS.md hook enum and section 10 extended
- [x] INIT_FLOW.md dispatcher mentions extended
- [x] UNINSTALL_FLOW.md and UNINSTALL_MATRIX.md extended

## What changed

- `_emit_pre_push` added to `hooks.sh` — emits a blocking dispatcher that captures git's ref-update lines from stdin into a tempfile and replays them to each helper / `check.sh`, passing the remote name and URL as `$1`/`$2`. Honors `SKIP_GOVERNANCE=1` and `git push --no-verify`.
- `generate_hooks` loop extended to emit pre-push alongside `pre-commit`, `commit-msg`, `prepare-commit-msg`, and `post-commit`.
- `hooks.sh` header docstring updated to mention pre-push in the dispatcher list it advertises.
- `test-packs.sh` helper detection loop extended to scan for `hooks/post-commit.sh` and `hooks/pre-push.sh` in addition to the three commit-time kinds, so directives shipping pre-push helpers are picked up by the pack-author smoke test.
- `SKILL.md` dispatcher list extended in the `governance init` overview to enumerate `pre-push` (and the previously-missing `post-commit`) and to include `git push --no-verify` as an escape hatch.
- `AGENTS.md` hook enum extended in the directive-authoring section: the `hook:` field now lists `post-commit` and `pre-push` as valid values, and the helper-hooks subdirectory pattern lists the same five kinds.
- `AUTHORING_PACKS.md` hook enum and section 10 extended: the YAML schema block, the "Enforced by" boilerplate, and the bootstrap step listing the generated dispatchers all include pre-push, with a note describing the args/stdin contract.
- `INIT_FLOW.md` dispatcher mentions extended: the overview sentence, the collision-detection table row, the "all dispatchers" sentence in the directive-author scenario, and the Path A generation step now enumerate pre-push.
- `UNINSTALL_FLOW.md` and `UNINSTALL_MATRIX.md` extended: the discovery list and the per-path table both add `.githooks/post-commit` and `.githooks/pre-push` rows so reset removes them.

No new directive ships in `core` or `agent-governance` — this is plumbing.

## Out of scope

- **Shipping a sample pre-push directive.** Reserved for follow-up issues; this PR is the dispatcher infrastructure.
- **Husky / pre-commit.com framework snippets.** `NATIVE_TESTS.md` will get a pre-push snippet when a real directive ships.
- **Multi-hook directives.** `hook:` remains scalar; declaring both a fast pre-commit check and an expensive pre-push check from a single directive is not yet supported.
- **A new `surface:` enum value for the push range.** Pre-push directives consume the ref-update stream directly from stdin; the existing `surface` field is unchanged.

## Verification

A reviewer can confirm the change is complete by checking:

1. **`_emit_pre_push` exists and is wired.** `governance/assets/packs/lib/hooks.sh` defines `_emit_pre_push` and the `generate_hooks` loop iterates `pre-commit commit-msg prepare-commit-msg post-commit pre-push`.
2. **Hook generation smoke covers it.** `bash scripts/test-packs.sh` prints `✓ pre-push` in the "hook generation smoke" section alongside the four existing dispatchers; the generated dispatcher carries the line-2 ownership marker and passes `bash -n`.
3. **Dispatcher contract is correct.** The emitted pre-push hook reads `REMOTE_NAME="${1:-}"` and `REMOTE_URL="${2:-}"`, slurps stdin into a tempfile via `cat > "$REFS_FILE"` cleaned up by `trap`, and replays the file to every `hooks/pre-push.sh` helper and every `check.sh` whose `hook:` field is `pre-push`.
4. **Escape hatches behave.** `SKIP_GOVERNANCE=1 git push` exits early with the `⊘ governance pre-push skipped` message; `git push --no-verify` is documented as the all-hooks bypass and is mentioned in the failure banner.
5. **Docs enumerate the new kind.** `grep -n pre-push governance/SKILL.md AGENTS.md governance/references/AUTHORING_PACKS.md governance/references/INIT_FLOW.md governance/references/UNINSTALL_FLOW.md governance/references/UNINSTALL_MATRIX.md` returns at least one hit per file; the AUTHORING_PACKS.md schema lists `pre-commit | commit-msg | prepare-commit-msg | post-commit | pre-push | none`.
6. **Helper detection updated.** `scripts/test-packs.sh` helper detection loop iterates the same five hook kinds as the generator, so a future directive shipping a `hooks/pre-push.sh` is included in the smoke spec.
7. **Dogfood green except the pre-existing PR gate.** `bash tests/governance/run.sh` shows 14/15 passing; the single failure is `pr-required-when-checklist-complete` which depends on PR existence, not on this change.
