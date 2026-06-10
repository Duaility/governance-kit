# issue-170 — `kit update` reports "up-to-date" against a stale skill; version-consistency single-quote bug; flow reproducibility

Closes [#170](https://github.com/Duaility/governance-kit/issues/170).

`governance kit update` resolves "the latest kit version" only from the locally installed skill (`packctl.py kit-version` → `kit.yaml`). When the installed skill is itself behind the published kit, the verb confidently reports `kit: up-to-date` and exits — the single most confusing failure mode of a routine "pull the latest kit", because everything *looks* current. This issue addresses that headline problem plus three separable findings filed alongside it (A: a single-quote parser bug in `version-consistency`; B: no reproducible driver for the hand-executed flow; C: a claimed anchor-inference/`commit-message-format` regex mismatch).

## Checklist

- [x] (A) version-consistency accepts single-quoted kit_version, with a regression eval
- [x] (1) up-to-date report names its provenance and points at refreshing the skill
- [x] (2) opt-in check-upstream reports how far behind the installed skill is, signal-only
- [x] (B) kit-plan helper makes the delta, reconstruction, and inventory reproducible
- [x] (C) document AGENT_ISSUE for HEREDOC commits in the kit update flow
- [x] re-pin the stale up-to-date-repo eval fixture to KIT_VERSION, with a drift guard
- [x] bash scripts/test.sh clean

## What changed

- (A) version-consistency accepts single-quoted kit_version, with a regression eval — **`packs/core/directives/version-consistency/check.sh`**: `manifest_field()`'s `sed` stripped only `"`, so a manifest pinning `kit_version: '0.3'` (the form older `init` emitted; the current writer uses double quotes, and there is no migration) left the single quotes in the captured value. `expected` became `'0.3'` and never matched a bare `kit-version=0.3` marker — every managed file then failed with a `… is stamped kit-version=0.3 but … pins kit_version='0.3'` violation whose two values look identical in the rendered error. The parser now accepts either quote style (`['\"]?…[^'\"#[:space:]]*…['\"]?`, verified on GNU + BSD `sed`), and the violation message quotes both values so any residual quote/whitespace mismatch is visible. **`packs/core/directives/version-consistency/evals/test.sh`** gains a "single-quoted pin" case that rewrites the fixture manifest to `kit_version: '<v>'` and asserts the check still passes (it failed before the fix).

- (1) up-to-date report names its provenance and points at refreshing the skill — **`governance/references/UPDATE_FLOW.md`**: the up-to-date branch (Step 2 + Step 8 report + the no-op bullet) now requires an `Assumptions:` line stating that `up-to-date` is resolved only from the locally installed skill, not the published kit, and pointing at `npx skills update governance --global`. Locked in with a new assertion on eval 2 (**`governance/evals/kit-update/evals.json`**).
- (2) opt-in check-upstream reports how far behind the installed skill is, signal-only — **`governance/assets/packs/lib/kitverb.py`** gains `kit-upstream`: a read-only `git ls-remote` against the kit's upstream that resolves the latest `kit/vX.Y.Z` tag and reports `current` / `behind` (with `releases_behind` + the refresh command) / `ahead` / `unknown` (offline). Surfaced through `governance kit update --check-upstream` as a new `Upstream:` report row (`UPDATE_FLOW.md`), documented in **`governance/SKILL.md`** and **`governance/references/VERBS.md`**. It never fetches-and-applies — when behind it routes to the skill manager and stops.
- (B) kit-plan helper makes the delta, reconstruction, and inventory reproducible — **`governance/assets/packs/lib/kitverb.py`** `kit-plan` resolves the recorded/reconstructed `installed_kit_version`, the version `delta`, and the managed-file inventory (marker state + plan-status hint) as one pure JSON-emitting call. `UPDATE_FLOW.md` Steps 1–3 now consume it instead of the hand-assembled bash arrays + min-reduction the consumer previously ran by hand. The apply primitives (`stamp_managed_marker`, `generate_hooks_for_strategy`, `write_installed_manifest`) are unchanged — only the fragile *plan* computation moved into a tested helper.
- (C) document AGENT_ISSUE for HEREDOC commits in the kit update flow — **`governance/references/UPDATE_FLOW.md`** Step 7 now prefixes the commit with `AGENT_ISSUE='#N'` and explains why (the accounting hooks read the subject from `git`'s argv, which a HEREDOC commit doesn't populate), explicitly noting this is not a regex mismatch with `commit-message-format`.
- re-pin the stale up-to-date-repo eval fixture to KIT_VERSION, with a drift guard — **`governance/evals/kit-update/files/up-to-date-repo/.governance/install.yaml`** + **`README.md`** re-pinned to the kit's current `KIT_VERSION` (was `0.3`, README said `0.2`); the eval-2 narrative is now version-agnostic, and **`scripts/test-kitverb.py`** adds a guard asserting the fixture pin equals `KIT_VERSION` so the next kit bump fails loudly instead of rotting. New test layer wired into **`scripts/test.sh`**.

## Out of scope

- **The AGENT_ISSUE-for-HEREDOC heads-up in the other flow docs.** `INIT_FLOW.md`, `RESET_FLOW.md`, `UNINSTALL_FLOW.md`, and `DIRECTIVE_AMEND_FLOW.md` all instruct HEREDOC commits without the `AGENT_ISSUE='#N'` note that finding C adds to `UPDATE_FLOW.md`. The same gap applies, but this issue is scoped to the `kit update` flow; the systemic doc sweep is a separate change.
- **A monolithic `kit update` apply driver.** Finding B's broadest reading is a single entry point that also performs the diff-before-exec, the per-file confirmation, and the apply (`cp` + stamp + hook-regen + manifest write). That contradicts the kit's architecture (granular pure helpers + prose orchestration, as in `packverb.py`) and would re-implement a large interactive surface. The apply primitives already exist as helpers; only the *plan* computation was fragile, so that is what `kit-plan` covers.
- **Auto-fetch-and-apply of a newer kit inside `kit update`.** `--check-upstream` is signal-only. Pulling a newer kit onto the machine stays the skill manager's job (`npx skills update governance --global`): a self-fetching verb would make the running flow apply assets/manifest contracts it predates (silent version skew) and bypass the skill manager's pinned, lock-verified install path.

## Verification

- `bash packs/core/directives/version-consistency/evals/test.sh` → all cases pass, including the new "single-quoted pin" case. Confirmed the case fails against the pre-fix parser.
- Parser checked directly on both GNU `sed` and macOS BSD `/usr/bin/sed` under bash 3.2 for single-quoted, double-quoted, and unquoted `kit_version` (all yield the bare value).
- `bash scripts/test.sh` clean — all kit-internal layers pass, including the new `test-kitverb.py` (16 cases: kit-plan delta/reconstruction/inventory, the upstream tag-parse/status helpers, and the up-to-date-fixture drift guard).
- `kit-plan` run against all six `governance/evals/kit-update/files/*` fixtures yields the expected `delta` for each (forward / up-to-date / downgrade / pre-tracking / no-recoverable-pin / reconstructed).
- `kit-upstream` smoke against the live repo returns `current` (latest published `kit/v0.3.5` == installed); a bad `--repo` degrades to `unknown` without blocking.

## Decisions

- **(C) is a misdiagnosis, fixed as documentation, not code.** The issue claims the steering populator's anchor regex disagrees with `commit-message-format`. It does not: `\(#([1-9][0-9]*)\)` matches `… (+packs) (#232)` on bash 3.2 (verified empirically), and `commit-message-format`'s `HEADER_RE` accepts the same subject. The real cause is that the accounting pre-commit hooks recover the subject from `git`'s argv, and a HEREDOC/`-F` commit puts no subject there — so inference legitimately can't see it and asks for `AGENT_ISSUE`. So the fix is to document `AGENT_ISSUE='#N'` in Step 7 and correct the framing, not to touch any regex.
- **Re-pinning the `up-to-date-repo` fixture is a necessary, in-scope side effect.** `scripts/release.sh` deliberately skips `governance/evals/*`, so the kit's 0.3 → 0.3.5 bump silently left that fixture pinned at 0.3 (its README even said 0.2). Eval 2's "up-to-date" case had therefore become a forward update — incoherent with finding 1, which targets the up-to-date branch. Re-pinned to track `KIT_VERSION`, made the narrative version-agnostic, and added a `test-kitverb.py` drift guard so the next bump fails loudly instead of rotting.
