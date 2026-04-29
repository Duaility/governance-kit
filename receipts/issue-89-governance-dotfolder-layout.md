# Issue 89: Governance Dotfolder Layout

## Checklist

- [x] Move dogfood governance state into `.governance/`.
- [x] Split pack-installed directives from local directives.
- [x] Update installer, runner, hook generator, and manifest paths.
- [x] Update docs, eval fixtures, and pack tests for the new layout.
- [x] Verify no legacy target-repo governance paths remain.
- [x] Repair garbled `lib.sh` source-path comment.
- [x] Add cross-worktree transcript fallback to claude-code locators.

## What changed

The dogfood install now lives under `.governance/`: runner files and config at the dotfolder root, pack-owned directives under `.governance/packs/<pack-id>/directives/<id>/`, and hand-authored directives under `.governance/local/directives/<id>/`.

Move dogfood governance state into `.governance/`.

Split pack-installed directives from local directives.

The bash runner discovers both pack and local directive trees. Installer helpers write pack directives to the pack-owned tree and emit manifest paths there. Generated hooks discover both directive roots at runtime and still run `scripts/test-packs.sh` in this source repo when present.

Update installer, runner, hook generator, and manifest paths.

Pack evals, reset/amend/bootstrap fixtures, workflow templates, docs, and the dogfood manifest were updated to the new layout.

Update docs, eval fixtures, and pack tests for the new layout.

Two follow-up fixes landed on top of the relocation.

Repair garbled `lib.sh` source-path comment. The `.governance/lib.sh` (and its source template at `governance/assets/dot-governance/lib.sh`) header comment had been corrupted by a botched search/replace during the move. The single-line `source` example was replaced with one example per directive depth: local directives, flat-namespace pack directives, and namespaced pack directives.

Add cross-worktree transcript fallback to claude-code locators. The Claude Code transcript locator in `agent-token-accounting/runtimes/claude-code.sh` and `agent-steering-accounting/runtimes/claude-code.sh` (canonical extensions copies plus dogfood mirrors) gained a third-pass fallback that fires only when the cwd-encoded lookup misses, `CLAUDECODE=1` confirms a live Claude session, and `~/.claude/projects/` exists. The pass picks the most recently modified `.jsonl` across all project dirs within a 10-minute window. This keeps a `git commit` running from worktree B finding the live session that started in worktree A — without picking up stale transcripts. Concurrent-session disambiguation still routes through `CLAUDE_TRANSCRIPT_PATH`.

## Out of scope

No compatibility shim or symlink fallback was added for the legacy layout. No drift-detection directive was added for hand-edits inside `.governance/`.

## Verification

- `bash .governance/run.sh`
- `bash scripts/test-packs.sh`
- `bash -n .governance/run.sh governance/assets/dot-governance/run.sh governance/assets/packs/lib/hooks.sh governance/assets/packs/lib/install.sh scripts/test-packs.sh`
- Legacy-path grep for the old runner tree, old manifest dotfolder, deleted flat directive root, and renamed asset folder returned no matches outside this receipt before the command was paraphrased here.
- Commit-hook fixture isolation was verified by rerunning `scripts/test-packs.sh` during the normal pre-commit path.
- Verify no legacy target-repo governance paths remain.
