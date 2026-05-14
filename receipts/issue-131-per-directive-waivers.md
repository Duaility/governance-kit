# issue-131 — per-directive waiver mechanism across the kit

Closes [#131](https://github.com/Duaility/governance-kit/issues/131).

## Checklist

- [x] Revert the diff-dedup auto-exemption in `agent-steering-accounting/check.sh`
- [x] Add commit-body waiver to `agent-steering-accounting`
- [x] Add commit-body waiver to `commit-message-format`
- [x] Add file-level waiver to `doc-freshness`
- [x] Document the existing line-level waiver in `no-broken-internal-doc-links`
- [x] Add file-level waiver to `receipt-per-issue`
- [x] Add per-sub-check waiver to `required-docs`
- [x] Add whole-directive waivers to `issue-templates` and `issues-tracked`
- [x] Sync root `CONSTITUTION.md` Exceptions clauses to mirror each directive
- [x] Add eval coverage
- [x] Close the squash-merge gap in `agent-steering-accounting` Mode B

## What changed

- **Revert the diff-dedup auto-exemption in `agent-steering-accounting/check.sh`.** The initial fix for #131 silently treated verbatim row moves as non-additions inside the directive's diff parser. That was a one-off implicit exemption hidden inside one directive — the wrong shape for a kit that already has a uniform `governance: allow-<directive> [<scope>] <reason>` waiver vocabulary. The revert puts the directive back to the original new-row detection.
- **Add commit-body waiver to `agent-steering-accounting`.** `governance: allow-agent-steering-accounting <reason>` in the commit body bypasses the trailer + ledger cross-checks (Mode A) and Mode B's walk. Reason required; a bare token does not waive. This is the right shape for issue #131's ledger-repair scenario — the audit trail is `git log --grep='allow-agent-steering-accounting'`.
- **Add commit-body waiver to `commit-message-format`.** `governance: allow-commit-message-format <reason>` in the commit body bypasses the subject-format check. The waiver lives in the body because the subject itself is the check's target.
- **Add file-level waiver to `doc-freshness`.** `governance: allow-doc-freshness <reason>` anywhere in the checked doc (typically as an HTML comment alongside the `last-verified` marker) exempts that doc from the staleness check. HTML comment markers are stripped before matching so `<!-- ... -->` does not count as the reason.
- **Document the existing line-level waiver in `no-broken-internal-doc-links`.** The directive already supported `has_waiver` line-level exemptions via the kit-wide helper; the constitution claimed "none" exceptions. Updated the constitution and added an eval case.
- **Add file-level waiver to `receipt-per-issue`.** `governance: allow-receipt-per-issue <reason>` in the first 10 lines of a receipt exempts that receipt from all four shape rules (filename, sections, crosswalk). HTML comment markers stripped before matching.
- **Add per-sub-check waiver to `required-docs`.** `<!-- governance: allow-required-docs <sub-check> <reason> -->` in CONSTITUTION.md exempts a single sub-check (`constitution`, `agents`, `readme`, `license`, `security`, `architecture`, `ci-workflow`, `env-example`, `hooks`). The `constitution` sub-check is effectively un-waivable since the waiver host is CONSTITUTION.md itself.
- **Add whole-directive waivers to `issue-templates` and `issues-tracked`.** Both check repo-state files whose existence isn't guaranteed, so the waiver host is CONSTITUTION.md (the universal source-of-truth file). Format: `<!-- governance: allow-<directive> <reason> -->`. Use cases: repos that track issues / bugs in Linear or Jira and have no need for these files.
- **Sync root `CONSTITUTION.md` Exceptions clauses to mirror each directive.** Every directive's `constitution.md` and the corresponding `### <directive>` block in the root `CONSTITUTION.md` now carry the same Exceptions text, so a reader of the root constitution sees the same waiver mechanism the directive enforces.
- **Add eval coverage.** Each new waiver ships with two eval cases — a "valid waiver passes" assertion and a "bare token without a reason fails" assertion. 18 waiver-related eval cases now pass across the suite (existing 4 + 14 new).
- **Close the squash-merge gap in `agent-steering-accounting` Mode B.** A squash-merge produces a fresh commit on `main` on GitHub's server — the local `commit-msg` hook never fires on it, so without an active CI check the squash slips past the trailer contract. The pre-existing Mode B walk handles this on PR branches (the walk's tip is the merge commit) but on `main` itself `merge-base(HEAD, origin/main) == HEAD`, so the walk yields nothing. Added a HEAD-fallback inside the `[[ -z "$base" ]]` block: when no base ref is found, validate HEAD's trailers as a single commit. `git rev-parse --verify HEAD` is the existence guard (in an empty repo `git rev-parse HEAD` prints the literal string `HEAD` on stdout and exits 128, which would otherwise become a phantom `head_sha`). Two new eval cases — `mode-b-on-main-valid` (HEAD with valid trailers passes) and `mode-b-on-main-missing-triple` (HEAD without trailers fails). The kit-side fallback complements the user-side waiver: malformed squashes fail loudly; legitimate ledger-repair commits opt out via `governance: allow-agent-steering-accounting <reason>`.

## Out of scope

- **Tightening the kit-wide `has_waiver` / `has_file_waiver` helpers to require a reason.** The helpers in `governance/assets/dot-governance/lib.sh` currently only grep for the directive name; they don't enforce a non-empty reason. The newly-added waivers enforce the reason in their own regexes. Aligning the lib helpers to the same standard would tighten the existing waivers in `no-orphan-todos`, `workflows-hardened`, `repo-hygiene/debug-statements`, and `secrets-hygiene` — worth a follow-up but out of scope for this PR.
- **HEAD-fallback for `agent-token-accounting` and `commit-issue-receipt-match`.** Both directives have explicit comments saying they deliberately do NOT validate HEAD when `base..HEAD` is empty ("would re-flag historical commits already in main"). The same squash-merge gap exists for them, but reversing those explicit decisions is its own discussion and out of scope here — the change in this PR is targeted at #131's specific failure mode (`agent-steering-accounting` trailers).
- **Reworking the squash-merge workflow that creates ledger inversions in the first place.** The original #131 mentioned a follow-up to re-sort `STEERING.md` rows on PR merge. Out of scope here; the waiver mechanism is the local cliff-drop fix.
- **A meta-directive that asserts every directive ships a waiver.** Would be the right way to keep the property as the kit grows, but adding it is its own design exercise.

## Verification

- `bash scripts/test-packs.sh` → 14 directive eval suites pass; `grep -E "waiver|waived"` shows 18 passing waiver-related cases.
- `bash .governance/run.sh` → dogfood suite passes.
- For each new waiver: the "waiver works" case asserts the directive lets a violation through when the marker is present with a non-empty reason; the "waiver-without-reason" case asserts that a bare token (e.g. `<!-- governance: allow-foo -->`) does not waive.
- New Mode-B-on-main cases for `agent-steering-accounting`: `mode-b-on-main-valid` (HEAD with valid trailers passes the no-base path) and `mode-b-on-main-missing-triple` (HEAD without trailers fails it). Fresh-repo install contract still green (empty-repo `git rev-parse HEAD` edge case is handled by `--verify`).
- `CONSTITUTION.md` and each directive's `constitution.md` carry parallel Exceptions text for the directives modified in this PR.
