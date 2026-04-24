<!-- governance: allow-plan-validation legacy -->
<!-- last-verified: 2026-04-23 -->

# 2026-04-23 — Ship `scripts/setup-clone.sh` and fix `install-assets/` leak

## Goal

Two small, related corrections to `governance-bootstrap` surfaced while re-bootstrapping this repo via `governance-reset`:

1. **Per-clone onboarding UX.** Path A bootstrap currently runs `git config core.hooksPath .githooks` in the bootstrapping clone, then relies on every subsequent contributor hearing the "run this one command after you clone" reminder through the `hooks-configured` nag. With worktrees in the picture, the nag is misleading in one direction (worktrees inherit `.git/config` from their parent, so no per-worktree action is needed) and under-served in the other (a fresh human clone gets a cryptic "core.hooksPath is not set" message with no canonical command to point to). Ship a tiny, idempotent `scripts/setup-clone.sh` so the bootstrap step is discoverable, greppable, and one command.

2. **`copy_tree_without_evals` leaked `install-assets/`.** The installer copies rule folders into `tests/governance/rules/<id>/` while excluding `evals/`. It did not exclude `install-assets/`, so repos using rules that seed root-level files (e.g. `issues-tracked` → `QUALITY.md`, `agent-token-accounting` → `COSTS.md`) ended up with a duplicate copy of those files nested inside the installed rule folder. The duplicates were harmless (no rule reads them from that path) but unmistakably noise in `git status` after every re-bootstrap.

Closes [#27](https://github.com/Duaility/governance-kit/issues/27).

## Why a one-liner script and not just a README paragraph

Three alternatives were considered and rejected:

- **"Just tell the user" (status quo).** The `hooks-configured` rule already prints the exact command (`git config core.hooksPath .githooks`). But the command is buried in a failure message the contributor only sees on their first commit attempt, and the failure mode is "hook didn't fire" — quiet, not loud. A named script is discoverable from `README.md` and from `ls scripts/` without any commit having to fail first.
- **Auto-repair inside the pre-commit hook.** Chicken-and-egg: if `core.hooksPath` is unset, the hook never runs, so it can never self-heal. Dead end.
- **Switch Path A to husky / pre-commit.com.** Their install step handles this via a framework lifecycle hook. Trades one nag for an npm (or Python) dependency and breaks the bash-first promise. Not worth it.

The one-line script is the minimum viable improvement: explicit, idempotent, worktree-inherit-aware in its header comment, and greppable.

## Scope

### Changes to `governance-bootstrap`

- New asset `governance-bootstrap/assets/setup-clone.sh` — runs `git rev-parse --show-toplevel`, checks `.githooks/` exists, runs `git config core.hooksPath .githooks`, echoes the resolved value.
- SKILL.md Step 6 Path A gains a **step 5**: copy the asset to `<repo-root>/scripts/setup-clone.sh`, chmod +x, tell the user to mention it in their README. The existing step 4 (bootstrapping-clone `git config`) stays, because the bootstrapping clone still needs its own one-shot config.
- `write_installed_manifest` in `assets/packs/lib/install.sh` gains `--setup-clone-script <path>` which emits `setup_clone_script: <path>` between `agents_md_created` and `packs`. Omitted under Path B.
- `install.sh::copy_tree_without_evals` also skips `install-assets/` (fix).

### Changes to `governance-reset`

- `references/UNINSTALL_MATRIX.md` — new row for `scripts/setup-clone.sh` in the core-artifacts table. Soft + hard both delete; `rmdir scripts/` only if it ends up empty (it usually does not).
- `references/MANIFEST_SCHEMA.md` — documents the new `setup_clone_script` field in the v1 shape block and the fields-reset-relies-on table. Existing manifests without the field fall through the "omitted" case (reset treats absence as "not installed", which is correct for Path B and pre-this-PR manifests).

### Changes to this repo (dogfood)

- `scripts/setup-clone.sh` installed from the new asset.
- `README.md` gains an **After cloning** section with the command.
- `.governance-kit/installed-packs.yaml` regenerated with the new `setup_clone_script` field.
- `CONSTITUTION.md` is a complete re-write from the rebootstrap earlier in this session (principles and evolution log preserved from the pre-reset HEAD; invariants regenerated from the pack-source snippets so a handful of stale wording differences in the installed rule folders get reconciled).

## Steps

1. Edit `governance-bootstrap/assets/packs/lib/install.sh` — skip `install-assets/` in `copy_tree_without_evals`; add `--setup-clone-script` flag + `setup_clone_script:` emission to `write_installed_manifest`.
2. Add `governance-bootstrap/assets/setup-clone.sh` and chmod +x.
3. Edit `governance-bootstrap/SKILL.md` Step 6 Path A — split the existing step 4 into steps 4 (bootstrapping-clone config) and 5 (setup-clone asset copy for other contributors). Mention worktree inheritance and where the user should point new contributors.
4. Edit `governance-reset/references/UNINSTALL_MATRIX.md` — add the `scripts/setup-clone.sh` row.
5. Edit `governance-reset/references/MANIFEST_SCHEMA.md` — document `setup_clone_script` in both the v1 shape block and the reset-relies-on table.
6. Apply the fix + enhancement locally: reset, rebootstrap, install `scripts/setup-clone.sh`, rewrite manifest with `--setup-clone-script scripts/setup-clone.sh`, clean up leftover `install-assets/` duplicates inside `tests/governance/rules/*/`.
7. Update `README.md` with the **After cloning** section.
8. Run `bash tests/governance/run.sh` — all 16 rules should pass.
9. Commit with `(#27)` and push.
10. Open PR.

## Notes

- The setup script is intentionally a shell one-liner rather than a Makefile target. Many downstream repos are bash-first and have no Makefile; adding one just for this would expand the bootstrap surface area for every target repo, which is backwards.
- The `hooks-configured` check.sh is already worktree-aware (tolerates an absolute path whose basename is `.githooks`) and CI-aware (skips when `CI` or `GITHUB_ACTIONS` is set). No changes to the rule itself — the nag behavior is fine once the script exists to quiet it in one command.
- The `install-assets/` leak was dormant — nothing in the repo reads files from `tests/governance/rules/<id>/install-assets/`, so the duplicates were not load-bearing. But they polluted the post-bootstrap `git status` and would have rotted out of sync with the root-level seeds over time.
