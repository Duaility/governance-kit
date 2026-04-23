# Agent Token Accounting

## Goal

Ship a governance rule `agent-token-accounting` that gives repositories a
durable, auditable ledger of token consumption for agent-authored commits
— generic across runtimes (Claude Code, Codex, anything else). Tracks
[governance-kit#13](https://github.com/Duaility/governance-kit/issues/13)
and lands in [#14](https://github.com/Duaility/governance-kit/pull/14).

## Design decisions resolved in the issue

1. **Opt-in in bootstrap, not default.** Most repos don't need token
   accounting; shipping in the default menu would add noise. Lives in
   `references/RULES_CATALOG.md` under "Also available".
2. **No squash-merge trailer on the base-branch commit.** `COSTS.md` is
   the durable source of truth; a squash trailer requires PR-platform
   tooling we don't control.
3. **Reuse the `(#123)` issue anchor from `conventional-commits`.** One
   canonical form across the kit.
4. **Multi-runtime from day one.** The `Agent:` trailer is a free-form
   string (`codex`, `claude-code`, etc.); shared accounting machinery
   consumes a generic env-var contract, with per-runtime transcript
   readers behind it.
5. **`Cost-Key` shape: `<agent>-<session-short>-<unix-epoch>`.** Stable,
   human-readable, collision-safe in practice.

## Architecture (final shape)

```
git commit -m "feat: x (#13)"
      │
      ▼
.githooks/pre-commit
      │
      └─► scripts/governance/agent-accounting.sh
             1. Detect runtime (CLAUDECODE / CODEX_THREAD_ID / manual AGENT_NAME)
             2. Read parent git's argv → parse (#N) issue anchor
             3. Dispatch to scripts/governance/runtimes/<runtime>.sh
                (prints "<session_id> <cum_input> <cum_output>")
             4. Subtract prior ledger rows for this session → per-commit delta
             5. Compute Cost-Key, append COSTS.md row, `git add` it
             6. Write handoff env file at `git rev-parse --git-path governance-pending.env`
      │
      ▼
.githooks/prepare-commit-msg
      │
      └─► Source handoff file → stamp seven trailers → delete handoff
      │
      ▼
git snapshots the tree (COSTS.md row is already in the index) → commit
      │
      ▼
CI: tests/governance/rules/agent-token-accounting.sh walks base..HEAD,
    cross-checks every Agent:-trailer commit against its COSTS.md row.
```

## Steps

1. **Rule + assets into bootstrap (opt-in).** Ship the rule script, the
   `prepare-commit-msg` and `pre-commit` hook templates, `COSTS.template.md`,
   the `scripts/governance/` tree (accounting + per-runtime readers), the
   reference doc, and a `RULES_CATALOG.md` "Also available" entry.
2. **Dogfood in this repo.** Copy the assets into `tests/governance/rules/`,
   `.githooks/`, `scripts/governance/`, `COSTS.md`. Add the matching
   Invariants subsection and Evolution Log entry to `CONSTITUTION.md`
   atomically (cardinal rule: test + constitution + log in one commit).
3. **Detect runtime in pre-commit, not in a wrapper.** `scripts/governance/
   agent-accounting.sh` branches on `CLAUDECODE=1` / `CODEX_THREAD_ID` /
   manual `AGENT_NAME`, hands off to the matching reader under
   `scripts/governance/runtimes/`, and exits 0 on human commits.
4. **Append `COSTS.md` in pre-commit, stamp trailers in prepare-commit-msg.**
   Pre-commit writes the row and `git add`s it (lands in the current
   tree); it also writes a handoff env file. `prepare-commit-msg` sources
   the handoff and stamps the seven trailers.
5. **Resolve worktree / argv / ps edge cases.** Handoff path via
   `git rev-parse --git-path`; parent git argv via
   `/proc/$PPID/cmdline` or `ps -ww -p <pid> -o args=` walking up two
   levels; NOTE truncation at first `\` to survive BSD `ps` newline
   escaping.
6. **Mirror every live asset under `governance-bootstrap/assets/`** so
   bootstrapped repos get the same behavior. Keep mirrors in sync on
   every subsequent edit.

## Iteration — what we tried and why the final shape

The issue proposed a layered model (trailers + ledger + rule); the *where*
each piece runs took four tries to get right. Capturing what each one
taught so the final shape reads with its reasoning intact.

1. **Append ledger row in `prepare-commit-msg`** (initial ship).
   CI failed with `Cost-Key X should have exactly 1 row in COSTS.md, found 0`.
   **Learned:** git snapshots the index *before* `prepare-commit-msg` runs;
   a `git add` there lands in the *next* commit's index. The ledger write
   has to happen earlier in the pipeline.

2. **Move append into a `scripts/claude-code-commit.sh` wrapper run before
   `git commit`.** Fixed the timing bug.
   **Learned:** Claude Code doesn't export session id or token counts as
   env vars — the wrapper has to read them from
   `~/.claude/projects/<encoded-cwd>/<session>.jsonl`. Input must count
   `input_tokens + cache_creation_input_tokens + cache_read_input_tokens`
   so the number matches billed usage. Per-commit delta = cumulative tally
   minus sum of prior `COSTS.md` rows for the session.

3. **Split wrapper into `governance-commit.sh` + per-runtime shims
   (`claude-code-commit.sh`, `codex-commit.sh`).** Gave Codex first-class
   support without duplicating 60 lines.
   **Learned:** Codex transcript schema varies — top-level `usage`,
   `message.usage`, `response.usage`; `input_tokens`/`output_tokens` or
   `prompt_tokens`/`completion_tokens`. Reader has to try the common
   shapes.

4. **Delete wrappers, detect runtime in `pre-commit`.** User objection:
   wrappers are a footgun — easy to forget, invisible to IDE commit flows,
   require per-runtime teaching. `git commit` should be the baseline for
   agents and humans alike.
   **Learned — three load-bearing implementation notes:**
   - `pre-commit` runs *before* git snapshots the index, so staging
     `COSTS.md` there lands it in the current commit's tree. That's
     exactly the window the wrapper was stretching to open; it existed
     for free all along.
   - Pre-commit can recover `git commit`'s `-m` argv by walking up two
     process levels (`$PPID` is the hook bash, its parent is git) and
     reading `/proc/<pid>/cmdline` or `ps -ww -p <pid> -o args=`. No
     wrapper needed to capture the issue anchor.
   - In a git worktree, `.git` is a pointer file, not a directory. The
     handoff file between `pre-commit` and `prepare-commit-msg` must use
     `git rev-parse --git-path governance-pending.env` — same call on
     both sides — to resolve to the real per-worktree git dir.
   - BSD `ps` escapes embedded newlines in a process's argv as literal
     `\012`. The subject captured for `COSTS.md`'s NOTE column must be
     truncated at the first `\` to avoid contaminating the row.

5. **Split cache tokens into their own columns; move ledger logic to Python.**
   A review of the single `input` column revealed it was summing
   `input_tokens + cache_creation + cache_read` — matching the billing
   dashboard's gross number but inflating what most readers would call
   "how much input did this commit consume," since `cache_read` is the
   same bytes re-read each turn.
   **Learned:**
   - The ledger should be lossless: once cache components are summed
     away they're gone, and billing dollars / cache-hit-rate cannot be
     recovered. Splitting to four token columns (`input`, `cache-create`,
     `cache-read`, `output`) keeps all information.
   - Trailers stay narrow on purpose. `Token-Input = input + cache-create`
     surfaces new work; `cache-read` is cache rent, not effort, and doesn't
     belong in commit messages reviewers skim.
   - `awk -F'|'` over a widening schema is the exact shape of bug we've
     already eaten once (column-index off by one). Moving ledger parse /
     sum-by-session / append / validate into
     `scripts/governance/lib/ledger.py` — stdlib only, named fields on a
     dataclass — makes the schema change a single-field edit and
     eliminates positional fragility. Same treatment for trailer parsing
     in `lib/trailers.py`.
   - Bash stays in charge of git plumbing, env detection, `ps` argv
     walking, and the env-file handoff; it shells out to the Python libs
     for anything that touches rows by semantics. Rule script calls the
     same libs, sharing the one parser.
   - Legacy 8-column rows (pre-split) stay readable: `ledger.py.parse`
     accepts them with `cache_create` and `cache_read` defaulted to 0,
     so old trailer-vs-row cross-checks still pass. Migration is a
     one-time edit of `COSTS.md` to insert two zero columns per row —
     all invariants hold because `old_input == new_input + 0 + 0` and
     `old_total == new_total`.

6. **Exclude `cache_read` from the ledger's `total` column.** The first
   commit under the new split-column schema landed with
   `total = 49,312,314` — dwarfed by a 48M `cache_read` that represented
   re-reads of the same bytes, not new work. The headline number for a
   commit was now mostly cache rent, and `row.total` no longer matched
   `Token-Total` in the trailer (since the trailer already excluded
   cache traffic).
   **Learned:**
   - A lossless ledger doesn't mean every column sums into the headline.
     `cache_read` belongs in `COSTS.md` (billing-dollar and cache-hit-rate
     reconstructability) but *not* in `total`. Keeping it out makes
     `row.total == input + cache_create + output == Token-Total` a
     single identity across ledger and trailer.
   - With `total` and `Token-Total` now *by construction* equal,
     `trailers.py` gained an explicit `Token-Total == row.total`
     cross-check. Tightening the invariant was a net add: the rule
     gets a new equality to enforce for free.
   - Migration cost was trivial because only commits with non-zero
     `cache_read` needed their `total` recomputed — every earlier row
     had `cache_read = 0` (Codex wasn't reporting cache, and the
     claude-code reader only started splitting cache columns in
     iteration 5).

7. **Add `model` + `cost-usd` columns; rename `total` → `new-work`.**
   Iteration 6 tightened the invariant but left one hole: the "headline"
   token sum is still meaningless across commits with different cache
   mixes. Output tokens cost ~50× cache-read tokens per MTok, so a
   `new-work`-heavy commit and a `cache-read`-heavy commit with the same
   headline can bill 10× differently. Raw token sums are the wrong
   comparable.
   **Learned:**
   - The fix isn't a smarter token formula — it's a dollar column. Added
     `scripts/governance/lib/rates.py` with a per-MTok rate table keyed
     by model string (Opus / Sonnet tiers, 5-minute cache TTL assumed)
     and tolerant lookup (lowercase, strip date suffix, prefix match).
     `compute_cost_usd(model, i, cc, cr, o)` multiplies each of the four
     token columns by its own rate — `cache_read` finally appears in the
     headline where it actually matters: billing.
   - `cost-usd` is the only number that lines up across commits with
     different cache mixes. `new-work` stays as the token-side headline
     — stable, denominator-free, matches `Token-Total` by construction —
     but reviewers comparing cost across PRs read the dollar column.
   - The schema needs a `model` column to make `cost-usd` reproducible
     and to survive future rate changes. Runtime readers now emit 6
     values (`session_id input cache_create cache_read output model`);
     `claude-code.sh` reads `.message.model` (latest-wins so mid-session
     `/model` switches propagate); `codex.sh` checks the same field
     across the container shapes it already handles. Unknown model →
     `cost-usd` empty, no cross-check failure — the rate table is a
     best-effort lookup, not an invariant.
   - Renaming `total` → `new-work` in v3 stops pretending the raw token
     sum is a comparable headline. The semantic is unchanged from v2's
     tightened `total` (iteration 6), so migration is purely textual:
     insert empty `model` after `issue`, rename `total` → `new-work`,
     insert empty `cost-usd` before `note`. Every existing row already
     satisfied the new invariant. Legacy v2 (10 cols) and v1 (8 cols)
     shapes continue to parse under the same `new_work` invariant.
   - `trailers.py` cross-check renamed `row.total` → `row.new_work`; the
     trailer shape (`Token-Input` / `Token-Output` / `Token-Total`) is
     unchanged — trailers stay token-only, dollars live only in the
     ledger.
   - Non-goal call-out: `cost-usd` is a commit-time *estimate*. Real
     invoices include promotional credits, per-workspace overrides, and
     enterprise pricing we can't see from a hook. Treat it as a
     prioritization signal; reconcile against the actual invoice
     monthly. Also: the rate table assumes the 5-minute cache TTL
     (Claude Code's default); a 1h-cache column will be needed if any
     runtime starts reporting that split.

## What shipped

**In the bootstrap (opt-in for downstream repos):**

- `governance-bootstrap/assets/tests-bash/rules/agent-token-accounting.sh`
  — the rule. Validates trailer math and `Cost-Key` ↔ `COSTS.md` agreement
  across `base..HEAD`.
- `governance-bootstrap/assets/githooks/pre-commit` — invokes
  `scripts/governance/agent-accounting.sh` before running governance tests.
- `governance-bootstrap/assets/githooks/prepare-commit-msg` — sources the
  handoff env file and stamps seven trailers.
- `governance-bootstrap/assets/scripts/governance/agent-accounting.sh` —
  runtime detection, issue parsing, shells out to `lib/ledger.py` for
  ledger append and delta math.
- `governance-bootstrap/assets/scripts/governance/lib/rates.py` —
  model → per-MTok USD rate table + `compute_cost_usd` helper with
  tolerant model-name lookup (strip date suffix, prefix match).
- `governance-bootstrap/assets/scripts/governance/lib/ledger.py` —
  stdlib-only Python: `LedgerRow` dataclass with `model`/`new_work`/`cost_usd`
  fields, `parse`, `sum_by_session`, `append_row` (recomputes `new_work`,
  looks up `cost_usd`), `validate`, `find_by_cost_key`. Handles v3
  (12 cols), v2 (10 cols), and v1 (8 cols) shapes.
- `governance-bootstrap/assets/scripts/governance/lib/trailers.py` —
  parses commit trailers and cross-checks them against a ledger row
  (`Token-Total == row.new_work`).
- `governance-bootstrap/assets/scripts/governance/runtimes/claude-code.sh`
  and `runtimes/codex.sh` — transcript readers emitting six
  whitespace-separated values (`session_id input cache_create cache_read output model`).
- `governance-bootstrap/assets/COSTS.template.md` — starter ledger with
  the append-only header and a `governance: allow-plan-captured` waiver.
- `governance-bootstrap/references/AGENT_TOKEN_ACCOUNTING.md` — install
  steps, the flow diagram, per-runtime wiring notes, and the enforcement
  table.
- `governance-bootstrap/references/RULES_CATALOG.md` — listed under
  "Also available" with a pointer to the reference doc.

**In this repo (dogfood):**

- Same assets copied to `tests/governance/rules/`, `.githooks/`,
  `scripts/governance/`, `COSTS.md`.
- `CONSTITUTION.md` gained an `agent-token-accounting` Invariants
  subsection and matching Evolution Log entries (initial adoption plus
  the pre-commit refactor).

## Non-goals

- **No authentication of token counts.** A runtime reader that fabricates
  numbers will pass the math check. The rule makes tampering *visible*
  (git blame on `COSTS.md`), not impossible.
- **No squash-merge trailer** on the base-branch commit — covered above.
- **No invoice reconciliation.** The `cost-usd` column uses the rate
  table in `scripts/governance/lib/rates.py` — a best-effort estimate
  from a commit hook with no network access. Real invoices include
  promotional credits, per-workspace overrides, and enterprise pricing
  we can't see. Treat `cost-usd` as a commit-time prioritization signal;
  reconcile monthly against the actual Anthropic invoice.
- **No 1-hour cache pricing.** The rate table assumes the 5-minute TTL
  (Claude Code's default). If a runtime ever reports 1h cache writes
  separately, `rates.py` needs a second cache-create column.
- **No modification to the runtimes themselves.** If Claude Code or Codex
  later export session id / token counts as env vars natively, the
  per-runtime readers become strictly simpler. The contract stays put.

## Side quest — prerequisite: `hooks-configured` worktree tolerance

Not strictly part of agent-token-accounting, but a blocker we had to clear in
the same PR because the dogfood branch lives in a git worktree.

**Problem.** `hooks-configured` was comparing `git config core.hooksPath`
against the literal string `.githooks`. In a worktree the config is shared
with the main checkout and resolves to an absolute path like
`/abs/path/to/main/.githooks` — functionally correct (hooks fire) but fails
the literal-string check. Every local run of the suite was reporting a false
positive.

**Fix.** Replace the literal comparison in both the live rule
(`tests/governance/rules/hooks-configured.sh`) and the bootstrap asset
(`governance-bootstrap/assets/tests-bash/rules/hooks-configured.sh`) with a
tolerant check:

- Empty → still a violation (the user hasn't run `git config core.hooksPath`
  yet).
- Absolute or relative → resolve the path, then require that (a) the
  basename is `.githooks`, (b) the path is a directory, and (c) that
  directory contains an executable `pre-commit`.

The separate tracked-and-executable checks for `.githooks/pre-commit` and
`.githooks/commit-msg` stayed unchanged — they already covered the
worktree's own hook scripts.

**Why this is a proxy swap, not a rewrite.** The rule's intent was always
"hooks are configured and fire." The literal-string comparison was right in
the 99% case but spuriously failed in worktrees; the fix swaps the proxy
for a check that actually expresses the intent.

## Side quest — follow-on: `governance-amend` skill pivot

Emerged from iterating on this PR with `governance-amend`. Not about
agent-token-accounting at all — it's about how the skill itself behaves —
but landed in the same PR because the friction surfaced here.

**Problem.** The skill's default flow staged the three amendment artifacts,
then asked the user to review-and-commit. That duplicates the PR review
surface imperfectly: inline approval in a skill transcript has no diff view,
no comment threads, no reviewer context. And staging-without-committing is a
footgun — state gets lost in worktrees, collides with other work, and is
easy to forget about.

**Pivot.** The skill now drafts → smoke-tests → **commits** in one pass.
Review happens on the PR. Four concrete edits to `governance-amend/SKILL.md`:

1. **Interaction policy.** Dropped the Fast/Interactive dual mode. Fast path
   is the only mode. Ask a *blocking* clarifying question only when
   rationale or check shape is genuinely missing.
2. **Step 3 (draft).** Removed "show the draft and ask whether it's the
   check they want." Write once syntax-check passes.
3. **Step 4 (smoke test Exit-1).** One targeted three-choice question before
   commit — **Loosen / Grandfather / Block** — because the resolution
   branches on user intent in a way the skill cannot pick mechanically.
   Committing a red-CI amendment and punting the triage to the PR reviewer
   would make them debug the rule's collateral damage instead of reviewing
   the rule.
4. **Step 6 (commit).** Skill runs `git commit` with a conventional-commit
   subject (add / update / remove variants), includes violators in the body
   when Step 4 was grandfather/block, and stops there. Pushing stays with
   the user.

Key design rules updated: "Don't commit" → "Commit, don't push"; added "PR
review is the review layer, not the skill" and "Block only on genuinely
missing inputs."

Evals #1–#3 assertions updated to verify the single-commit outcome and the
no-draft-approval pause. Evals #4–#5 untouched — they don't depend on the
approval-loop behavior.

**Why the Exit-1 exception.** "PR review is the gate" does not mean "let
every rule-amendment PR open with red CI from pre-existing violators." The
reviewer's job is to decide whether the rule is right, not to reverse-engineer
why bumping `max-file-size` to 800 suddenly flags three data-pipeline files.
Exit-1 is the one genuine branching decision the skill cannot make without
user intent, so it earns one question.

**Non-goals for this side quest.**

- Not automating `git push`. Pushing is a user decision (wrong branch,
  force-push risk). The skill commits; the user pushes.
- Not changing skill scope. Still one amendment, three artifacts, one
  commit. Did not expand to PR creation or CI setup.
- Not touching `governance-bootstrap` or `governance-gardener`. Bootstrap
  already behaves this way; gardener is read-only.
