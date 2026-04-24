### pre-commit-test-gate

- **Rule**: In this source repository, the tracked `.githooks/pre-commit` dispatcher must run `scripts/test-packs.sh` whenever the pack-author test suite exists. `scripts/test-packs.sh` must also include the `scripts/test-packverb.py` contract smoke so pack helper behavior is checked before every local commit, not only in CI or by manual discipline.
- **Rationale**: governance-kit is itself governance tooling; a commit that changes pack helpers, pack docs, or rule fixtures should not be able to bypass the pack-author tests locally. Keeping the pack test suite in the pre-commit path makes the local gate match the repository's real test surface.
- **Enforced by**: `tests/governance/rules/pre-commit-test-gate/check.sh`
- **Exceptions**: Emergency commits may use the standard hook escape hatches (`SKIP_GOVERNANCE=1 git commit ...` or `git commit --no-verify`), but CI still runs the governance and pack-test workflows.
