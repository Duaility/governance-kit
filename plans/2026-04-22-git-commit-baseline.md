# Make `git commit` the baseline entry point for agent token accounting

## Goal

Agents and humans both use plain `git commit -m "…"`. There is no wrapper
script to remember, no IDE integration to rebuild, no onboarding step
beyond "install the hooks." If the commit is agent-authored, accounting
happens transparently via the pre-commit hook.

This replaces the earlier wrapper-based design
([2026-04-22-runtime-agnostic-wrapper.md](2026-04-22-runtime-agnostic-wrapper.md),
[2026-04-22-claude-code-commit-wrapper.md](2026-04-22-claude-code-commit-wrapper.md),
[2026-04-22-ledger-append-before-commit.md](2026-04-22-ledger-append-before-commit.md)),
which required agents (and humans reviewing agent commits) to remember to
run `scripts/claude-code-commit.sh` or `scripts/codex-commit.sh` instead
of `git commit`. Wrappers are a footgun: easy to forget, invisible to
IDE commit flows, and require per-runtime teaching.

## Steps

1. **Runtime detection moves into pre-commit.** `scripts/governance/agent-accounting.sh`
   detects the runtime from environment (`CLAUDECODE=1`, `CODEX_THREAD_ID`,
   or manual `AGENT_NAME`). Human commits hit the no-op branch and exit 0.

2. **Parent-process argv parsing recovers the `-m` subject.** Pre-commit
   cannot read `COMMIT_EDITMSG` (not populated yet), but it *can* read the
   parent git's argv via `/proc/$PPID/cmdline` (Linux) or `ps -ww -p $PPID
   -o args=` (macOS). That gives us the `(#N)` issue anchor without a
   wrapper. `AGENT_ISSUE='#N'` remains an explicit override for editor-mode
   commits.

3. **Per-runtime transcript readers under `scripts/governance/runtimes/`.**
   Each reader (`claude-code.sh`, `codex.sh`) prints
   `<session_id> <cum_input> <cum_output>` on stdout. Nothing else.
   Adding a runtime means adding one ~60-line file and one `case` branch.

4. **`COSTS.md` append happens in pre-commit, not prepare-commit-msg.** This
   is load-bearing. `git add` during pre-commit lands in the tree git is
   about to snapshot; `git add` during prepare-commit-msg lands in the
   *next* commit's index. The earlier wrapper worked around this by
   appending *before* invoking `git commit`. The pre-commit layer gets
   the same effect with no wrapper.

5. **`prepare-commit-msg` shrinks to a trailer stamper.** It sources the
   handoff file `.git/governance-pending.env` written by pre-commit, emits
   the seven trailers, and deletes the handoff file. Idempotent on amends
   (skips if `Agent:` is already present). Silent no-op if no handoff
   file exists.

6. **Delete the wrappers.** `scripts/claude-code-commit.sh`,
   `scripts/codex-commit.sh`, `scripts/governance-commit.sh` — and their
   mirrors under `governance-bootstrap/assets/scripts/` — are gone.

7. **Update docs.** `governance-bootstrap/references/AGENT_TOKEN_ACCOUNTING.md`
   now describes the pre-commit pipeline. The `agent-token-accounting`
   Invariants subsection in `CONSTITUTION.md` and its Evolution Log entry
   reflect the new architecture. Bootstrap asset mirrors stay in sync with
   the live scripts.

8. **Dogfood.** This commit itself goes through the new path: plain
   `git commit -m "…"` from a Claude Code session, pre-commit detects
   `CLAUDECODE=1`, reads the transcript, appends the ledger row, and
   prepare-commit-msg stamps the trailers. If CI passes on this PR, the
   refactor is validated end-to-end.
