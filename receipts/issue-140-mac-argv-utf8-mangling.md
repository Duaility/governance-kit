# issue-140 — agent-steering-accounting / agent-token-accounting mangle non-ASCII commit subjects on macOS

Closes [#140](https://github.com/Duaility/governance-kit/issues/140).

The two accounting directives both recover the pending commit's subject by scraping the parent `git` process's argv. Linux reads `/proc/<pid>/cmdline` (exact bytes); macOS shells out to `ps -ww -p <pid> -o args=`. Under `LC_ALL=C` or `LC_ALL=POSIX` — the locale environment git hooks typically inherit — BSD `ps` **cat-v-escapes every byte ≥ 0x80**, so every UTF-8 multi-byte sequence in the commit subject (em-dash `—` = `0xE2 0x80 0x94`, arrow `→` = `0xE2 0x86 0x92`, accents, CJK, emoji, etc.) is rewritten into ASCII escape sequences (`M-bM^@M^T`) before the hook's regex extracts `-m <subject>` from `ARGV`. The mangled subject then lands in `STEERING.md`'s `commit |` cell and `COSTS.md`'s subject column. In 0.3.1 `agent-steering-accounting/check.sh`'s strict subject-match check reads the un-mangled subject from the commit-msg file and disagrees with what the hook just wrote — every commit with a non-ASCII subject is blocked.

Note: under the default UTF-8 locale (e.g. an interactive Terminal.app shell with `LANG=en_US.UTF-8`), macOS `ps` returns exact bytes — which is why the bug doesn't reproduce when poking at `ps` from a normal shell prompt. It reproduces inside the hook because git's environment + the shell scripts in the chain inherit `LC_ALL=C` from somewhere upstream.

## Checklist

- [x] Add stdlib-only `lib/argv.py` reader using `sysctl(KERN_PROCARGS2)` via ctypes
- [x] Wire it into `parent_argv_string()` on the macOS branch of both pre-commit hooks
- [x] Add round-trip eval covering UTF-8 argv under `LC_ALL=C`
- [x] Bump core pack version 0.3.1 → 0.3.2
- [x] Update agent-token-accounting hook's doc-comment about the macOS path
- [x] Add an entry to the **Evolution Log** in CONSTITUTION.md
- [x] `bash scripts/test-packs.sh` clean

## What changed

- **`packs/core/directives/agent-steering-accounting/lib/argv.py`** and **`packs/core/directives/agent-token-accounting/lib/argv.py`** (new, identical). Read the named pid's argv as a list of raw byte-strings via `sysctl(CTL_KERN, KERN_PROCARGS2, pid)` through ctypes. Returns `None` on non-Darwin platforms, libc-load failure, or any sysctl error. CLI prints argv to stdout NUL-separated; the bash side captures it via `python3 "$LIB/argv.py" "$pid" | tr '\0' ' '` so the existing consumers see a single space-separated string identical in shape to the Linux `/proc/<pid>/cmdline` path. Stdlib-only — no third-party deps. The helper validates `argc ≤ 4096` to reject corrupt buffers.
- **`packs/core/directives/agent-steering-accounting/hooks/pre-commit.sh`** and **`packs/core/directives/agent-token-accounting/hooks/pre-commit.sh`**: `parent_argv_string()` gains a Darwin branch that calls the new helper before falling through to `ps`. The `ps` branch is retained for non-Darwin BSDs but is unreachable on the platforms affected by this issue. Both hooks gained a one-paragraph comment pointing at #140 from the macOS branch so the next reader doesn't reach for `ps` again.
- **`packs/core/directives/agent-token-accounting/hooks/pre-commit.sh`** header docstring updated: the line that referenced `` `ps -ww -p $PPID -o args=` (macOS) `` now reads `sysctl(KERN_PROCARGS2) via lib/argv.py (macOS)` so the doc-string and the code agree.
- **`packs/core/directives/agent-steering-accounting/evals/test.sh`** gains **Case 0**, a sanity check that exercises the installed `lib/argv.py` directly. The case spawns a child shell holding a known UTF-8 argv (`/bin/sh -c '…' tag $'feat: em-dash \xe2\x80\x94 arrow \xe2\x86\x92 (#1)'`), invokes `LC_ALL=C python3 ".governance/packs/governance-kit/core/directives/agent-steering-accounting/lib/argv.py" "$PID"` (the same locale that triggers `ps`'s cat-v escaping), and asserts both UTF-8 byte sequences survive the round-trip. The case is skipped with a `⊘` line on non-Darwin platforms. The `agent-token-accounting` eval is not duplicated — the helper is byte-identical in both directives.
- **`packs/core/pack.yaml`**: `version: "0.3.1"` → `"0.3.2"`. `min_governance_kit` is unchanged (the fix uses only stdlib ctypes and existing pack-shape primitives).
- **`CONSTITUTION.md`**: evolution-log entry added describing the bug, the fix, the locale-dependent failure mode, and the pack-version bump. Inserted in chronological order (2026-05-28) ahead of the older 2026-05-16 entry the prior `f7c2163` commit appended out of order.

## Out of scope

- **Refactor to read the commit subject from the commit-msg file instead of argv.** The issue's suggested fix (2) would sidestep argv scraping entirely by moving the ledger-row write into `prepare-commit-msg.sh` (which receives the message file path as `$1`). It's a larger refactor — the existing code path is "pre-commit appends a row, `git add`s it, then `prepare-commit-msg` stamps trailers". Moving the row append to `prepare-commit-msg` requires re-validating that `git add` in `prepare-commit-msg` lands in the current commit's tree (the in-file comment claims it doesn't); restructuring the handoff env file; verifying retry-after-failed-commit-msg still works; and updating both directives in lockstep. Worth doing — argv scraping is also fragile against `git commit -F <file>`, `-t <template>`, `--amend`, and editor-mode commits, none of which match the `(-m|--message)` regex — but it's a 0.4 change, not a patch.
- **Retroactive `STEERING.md` / `COSTS.md` row rewrites.** Historical commits whose subjects landed mangled (e.g. the `M-bM^FM^R` artefacts in `COSTS.md` from 0.3.0-era commits, or the example in the issue) are not rewritten. The audit-log philosophy is "rows describe what was true at the time"; `agent-token-accounting` has no subject-equality invariant so the mangled rows there are cosmetic.
- **`__pycache__` exclusion in `repo-hygiene`.** `bash scripts/test-packs.sh` initially flagged a stray `argv.cpython-314.pyc` left behind by a sanity-check Python run during development. Cleaned up locally; not addressing the broader question of whether the directive script should learn to ignore `__pycache__` paths (it has bigger fish — pre-existing pyc artefacts have not been an issue and `git status` already shows them).
- **Defensive subject sanitization** (issue's suggested fix #3 — refuse to write a row when `SUBJECT` contains `M-` / `M^` escape patterns). With the sysctl path live the write side cannot emit those bytes; adding a check for them would be belt-and-braces against a regression the eval already catches.

## Verification

- `bash packs/core/directives/agent-steering-accounting/evals/test.sh` → 18/18 cases pass. Case 0 confirms `lib/argv.py` round-trips UTF-8 under `LC_ALL=C`; the existing 17 cases (subject-match, count, types, tiers, waiver, Mode B HEAD fallback, squash-merge stacking) still pass.
- `bash scripts/test-packs.sh` → 1 pack, 14 directives, 14 evals green. Includes the fresh-repo install contract (which exercises the hook generator wiring the new helper file into the installed directive folder).
- Manual macOS reproduction: ran the helper against a live child process holding a UTF-8 argv under both default and `LC_ALL=C` locales. `ps -ww -o args=` mangles `—` and `→` to `M-bM^@M^T` / `M-bM^FM^R` under `LC_ALL=C`; the helper returns the exact `0xE2 0x80 0x94` / `0xE2 0x86 0x92` byte sequences in both locales.
