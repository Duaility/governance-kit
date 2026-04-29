# Issue 95: Bump actions/checkout to v5 and consolidate kit-internal tests into tests.yml

## Checklist

- [x] Bump actions/checkout from v4 to v5 in .github/workflows/governance.yml.
- [x] Bump actions/checkout from v4 to v5 in governance/assets/governance.yml shipped to consumer repos.
- [x] Rename .github/workflows/pack-tests.yml to tests.yml and run the full scripts/test.sh umbrella.
- [x] Strip the Install uv and Run kit-internal test umbrella steps from governance.yml.
- [x] Leave actions/checkout v4 untouched in eval fixtures workflows-hardened/evals/test.sh and packs/lib/eval-lib.sh.
- [x] Strip inherited git env vars at the top of scripts/test.sh so the umbrella is hook-safe.

## What changed

Three CI cleanups bundled because they all touch the kit-internal test plumbing.

**Bump actions/checkout from v4 to v5 in .github/workflows/governance.yml.** GitHub's deprecation notice on every Governance run flagged `actions/checkout@v4` as Node.js 20 — Node 24 becomes the runner default on June 2, 2026 and Node 20 is removed on Sept 16, 2026. Bumping to `@v5` clears the warning and gets ahead of the cutover.

**Bump actions/checkout from v4 to v5 in governance/assets/governance.yml shipped to consumer repos.** The same bump applies to the workflow template that `governance init` writes into a target repo — without it, every newly-bootstrapped repo would inherit the deprecated tag.

**Rename .github/workflows/pack-tests.yml to tests.yml and run the full scripts/test.sh umbrella.** Before this change there were two paths running the kit's own tests in CI: `pack-tests.yml` ran `scripts/test-packs.sh`, and `governance.yml` ran `scripts/test.sh` (which already includes `test-packs.sh` as layer 7). Same script, same trigger set, same runner — duplicated. After: a renamed `tests.yml` runs `bash scripts/test.sh` (the full umbrella) and is the single CI entrypoint for kit-internal tests.

**Strip the Install uv and Run kit-internal test umbrella steps from governance.yml.** With `tests.yml` now owning the umbrella, the corresponding steps are removed from `governance.yml` so the directive workflow stays focused on `bash .governance/run.sh`. `required-docs`'s "non-governance workflow" rule is still satisfied — `tests.yml` is the workflow it counts.

**Leave actions/checkout v4 untouched in eval fixtures workflows-hardened/evals/test.sh and packs/lib/eval-lib.sh.** Those embed `actions/checkout@v4` as scaffolding to exercise the `workflows-hardened` directive's pass/fail cases; bumping them would couple eval outcomes to whatever GitHub action major is current.

**Strip inherited git env vars at the top of scripts/test.sh so the umbrella is hook-safe.** Discovered while running the umbrella through the local pre-commit hook to validate the workflow change. When git invokes a hook it exports `GIT_DIR`, `GIT_INDEX_FILE`, `GIT_PREFIX`, etc., and those env vars override cwd-based discovery in every child `git` call. The kit-internal test layers (`test-runtime.sh`, `test-install-sh.sh`, `test-hooks-sh.sh`) all build throwaway repos with `git -C $tmp init -q .` — but with `GIT_DIR` set, `git init` ignores `-C $tmp` and re-initializes the *host* repo's gitdir. Because a linked-worktree gitdir has no working tree adjacent to it, git decides the host repo is bare and writes `core.bare = true` into the shared config. Every subsequent `git status` / `git commit` then fails with `fatal: this operation must be run in a work tree` until the config is hand-edited back. The fix is two lines at the top of the umbrella that walk `git rev-parse --local-env-vars` and `unset` each. `scripts/test-packs.sh` already does the same unset in its `fresh repo install contract` subshell; lifting it to the umbrella covers every layer in one place. Standalone `bash scripts/test.sh` runs are unaffected — no git env is set in that case, and the unset is a no-op.

The pre-commit hook is unchanged — it still invokes `scripts/test.sh` directly, so the local gate continues to run the full umbrella before any commit lands. After this fix it does so without corrupting the host repo's config.

## Out of scope

- Bumping `actions/checkout` in eval fixtures. Those embed `@v4` as scaffolding to exercise the `workflows-hardened` directive; coupling them to the latest action major would make the eval pass/fail cases drift on every GitHub release.
- Adding a similar env-var unset to each individual layer (`test-runtime.sh`, `test-install-sh.sh`, `test-hooks-sh.sh`). The umbrella is the canonical entrypoint for both pre-commit and CI, and `test-packs.sh` already scopes its own unset; lifting one global unset to `scripts/test.sh` covers every dispatch path. If a layer is later run directly from a hook, it can grow its own unset at that point.
- Updating any branch protection rules referencing the old `Pack tests / pack-tests` check name. None exist in this V0 sole-developer repo.

## Verification

- `bash .governance/run.sh` — all 14 directives pass.
- `bash scripts/test.sh` — all 7 kit-internal test layers pass.
- Reproducer for the env-leak: with `GIT_DIR=…/.git/worktrees/<name> GIT_INDEX_FILE=/tmp/foo bash scripts/test.sh`, the host repo's `.git/config` `core.bare` value stays `false` after the run (before this fix it flipped to `true`).
- Local `git commit` of this change went through the pre-commit hook cleanly, exercising the umbrella in its real hook-invoked form.

## Notes

- Renaming the workflow file changes the GitHub Actions check name from `Pack tests` to `Tests`. Any branch protection rules that referenced `Pack tests / pack-tests` by name will need updating; in this V0 sole-developer repo there are none.
- The `astral-sh/setup-uv` action stays SHA-pinned to `08807647e7069bb48b6ef5acd8ec9567f424441b` (v8.1.0) per `workflows-hardened`.
- The env-leak bug was latent: the seven test layers were added in #92 and the only callers were CI (where there's no parent-repo state to corrupt) and direct shell invocations (where `GIT_DIR` isn't set). It surfaced the first time the umbrella ran inside a real local pre-commit invocation.
