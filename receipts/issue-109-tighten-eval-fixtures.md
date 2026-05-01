# issue-109 — tighten two eval fixtures surfaced during eval-run dogfood

Closes [#109](https://github.com/Duaility/governance-kit/issues/109).

## Checklist

- [x] Loosen `reset` eval 3 (`--all --dry-run`) so it doesn't implicitly require cache state for the `acme/widgets` `gh`-source pin
- [x] Rewrite `init` eval 3's Go fixture so post-init `bash .governance/run.sh` exits 0 without an inline waiver

## What changed

- **Loosen `reset` eval 3 (`--all --dry-run`) so it doesn't implicitly require cache state for the `acme/widgets` `gh`-source pin.** Eval 3's assertion 6 read "Per-directive diffs were printed for the user to review", which for the `acme/widgets::widget-naming` directive means a diff against the pinned-SHA pack contents that `RESET_FLOW.md` Step 2 sources from `${GOVERNANCE_KIT_HOME:-$HOME/.governance/cache}/packs/<slug>@<sha>/`. The fixture pins `acme/widgets@5f3c0a1b…` as `source: gh` but doesn't seed that cache directory — and the LLM-graded eval workflow (`scripts/eval-report.sh` describes it: copy the fixture into a fresh tmp dir + `git init` + paste the prompt) doesn't set `GOVERNANCE_KIT_HOME`, so a faithful dry-run can only surface "fetch required" as a plan item rather than the diff itself unless it crosses into network territory. This is the same scope-line that issue #105's receipt drew when it punted cache-seeding ("cache-state seeding for the pack/ evals … punted because cache-seeding is a harness concern"); the reset eval inherited that concern silently. Fix is option B from issue #109: rewrite assertion 6 to accept both paths — diffs printed where the pristine source is offline-available (i.e., for `governance-kit/core` builtin directives), and a `fetch required` plan note for `gh`-source directives whose pin isn't cached locally. `expected_output` is updated in lockstep so the prose and the assertion stay aligned. Option A (seed `${GOVERNANCE_KIT_HOME}/packs/acme__widgets@<sha>/` inside the fixture) was rejected because the grading workflow doesn't set the env var per case, and threading env-setup into eval prompts contaminates them.
- **Rewrite `init` eval 3's Go fixture so post-init `bash .governance/run.sh` exits 0 without an inline waiver.** The eval's prompt asks for a tight, security-leaning ruleset, which routes to `minimal`, which installs `repo-hygiene`, which includes a Go debug-statement check that flags `^[[:space:]]*fmt\.Println\s*\(` (`governance/assets/packs/core/directives/repo-hygiene/check.sh:78`). The fixture's prior `main.go` was exactly that pattern (`fmt.Println("hello from fixture go service")` inside `main()`), so assertion 6 ("`bash .governance/run.sh` exits 0 on the seeded clean Go repo") was structurally unreachable — a real grader either had to add `// governance: allow-repo-hygiene <reason>` or restructure, neither of which the assertion implies. Fix is option A from issue #109: replace `main.go` with a realistic Go service entrypoint — `net/http` mux with a `/healthz` handler, served via `log.Fatal(srv.ListenAndServe())`. No `fmt.Println` at line-start, no debug pattern, well under any size limit, and modelling what a "Go service" actually looks like (the fixture's purpose per its README).

## Out of scope

- **Re-running the other 24 evals end-to-end.** Issue #109 explicitly defers this; the 5-eval sample from #107's session was enough signal that these two fixtures needed attention. A full grade pass should land separately once an automated harness exists.
- **Building an automated eval harness.** The current model is "manually run via Claude Code session"; codifying that into a runner is a separate piece of work and intentionally not in this scope.
- **Touching the assertions on the other three evals from the same session (uninstall #2, pack #6, directive #4).** All three passed cleanly per the #107 receipt, so no edit is warranted.
- **Updating `RESET_FLOW.md` to formally describe a "deferred fetch under dry-run" mode.** The eval assertion now accepts both behaviors, but tightening the flow doc to specify when a dry-run should fetch vs. note `fetch required` is a separate refinement and would expand scope into the skill's behavior, not the eval fixtures.

## Verification

- `jq -e . governance/evals/reset/evals.json` and `jq -e . governance/evals/init/evals.json` → both parse as valid JSON after the assertion + `expected_output` rewrite.
- Spot-check on the rewritten Go fixture: `git grep -InE '^[[:space:]]*fmt\.Println\s*\(' main.go` against `governance/evals/init/files/go-service-repo/main.go` returns no matches, so `repo-hygiene`'s Go debug-statement rule no longer fires on the seeded clean Go repo and the post-init `bash .governance/run.sh` can reach exit 0 as assertion 6 demands.
- `bash .governance/run.sh` → 14/14 dogfood directives green; the JSON edits and fixture rewrite don't break any constitutional check on this repo.
- `bash scripts/eval-report.sh` → still emits 5 verbs ready, 29 cases / 203 assertions, no missing or placeholder fixtures (the assertion-count total is unchanged because the change rewrites one assertion in place rather than adding/removing one).
