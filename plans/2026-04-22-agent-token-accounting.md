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
  runtime detection, issue parsing, ledger append.
- `governance-bootstrap/assets/scripts/governance/runtimes/claude-code.sh`
  and `runtimes/codex.sh` — transcript readers.
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
- **No cost computation.** The rule tracks tokens, not dollars. A
  downstream report can join `COSTS.md` to billing data if needed.
- **No modification to the runtimes themselves.** If Claude Code or Codex
  later export session id / token counts as env vars natively, the
  per-runtime readers become strictly simpler. The contract stays put.
