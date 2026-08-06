# `lib.sh` helper API

The canonical reference for every author-facing function in the shared
`lib.sh` that each directive's `check.sh` sources. **Read this before reaching
into `lib.sh` source** — if a function is here, it is a supported helper you
should call rather than reinvent; if it is not (anything `_`-prefixed), it is
private and may change without notice.

`lib.sh` is materialized into every consumer at `.governance/lib.sh` and sourced
from each directive at the top of its `check.sh`. A directive lives two pack
levels deep, so the canonical source line is five `..` segments:

```bash
source "$(dirname "$0")/../../../../../lib.sh"
```

(`.governance/packs/<owner>/<name>/directives/<id>/check.sh` → `.governance/lib.sh`.)

## The functions

Grouped by job. **Since** is the first released kit version that **ships** the
helper to consumers (`kit/vX.Y.Z`) — not the in-development source line it was
authored on, which is one release lower and would under-floor a pack. See
[Version-floor obligation](#version-floor-obligation) below for why that column
is load-bearing, not trivia.

### Lifecycle — every `check.sh` uses these

| Function | Signature | What it does | Since |
|---|---|---|---|
| `directive_start` | `directive_start <directive-id>` | Open a directive. Resets the violation counter; the id must match the directive folder name. Pair with `directive_end`. | 0.3.5 |
| `violation` | `violation <message>` | Record one violation. The message must carry the location and the fix — `"path:line — what's wrong"`, never `"bad code"`. Call once per problem found; they are batched and printed by `directive_end`. | 0.3.5 |
| `directive_end` | `directive_end` | Print the `✓`/`✗` summary (and, on failure, the directive's `**Rationale**:` pulled from its sibling `constitution.md`) and **exit** `0` (clean) or `1` (violations). Owns the exit status — never call `exit` yourself. | 0.3.5 |

### Git / repo state

| Function | Signature | What it does | Since |
|---|---|---|---|
| `require_git` | `require_git` | Skip the directive (print `⊘` and exit `0`) when not inside a git work tree. Call it before any `git ls-files` / `git grep`, so a check sourced outside a repo no-ops instead of erroring. | 0.3.5 |
| `tracked_files` | `tracked_files [<pathspec>...]` | Emit git-tracked files (respects `.gitignore`), optionally filtered by a pathspec — `tracked_files '*.py'`, `tracked_files ':!vendor/**'`. **Use this instead of `ls`, `find`, or a hand-rolled `git ls-files` loop** — those pull in gitignored files and directories. | 0.3.5 |

### Waivers

| Function | Signature | What it does | Since |
|---|---|---|---|
| `has_waiver` | `has_waiver <file> <line_no> <directive-id>` | True when that line carries `governance: allow-<directive-id>`. The per-line escape hatch — `has_waiver "$file" "$line" "<id>" && continue` inside a per-line scan. | 0.3.5 |
| `has_file_waiver` | `has_file_waiver <file> <directive-id> <subcheck>` | True when the file's first 10 lines carry `governance: allow-<directive-id> <subcheck>`. The **whole-file** waiver, for sub-checks whose violation is the file itself rather than a line. The `<subcheck>` name lets several file-level sub-checks share one `allow-<directive-id>` prefix without colliding. | 0.3.5 |

### Sub-agent judgment (attest)

The independent-auditor pattern — a section a fresh-context sub-agent (or a
detached CLI judge) must populate against ground truth (the diff and linked
issue) the hook itself cannot read. Since issue #325
the task is declared once in the directive's `directive.yaml` `judge:`
block and the commit-time orchestrator **batches** every section sharing a
`group` label into one judge invocation. Since issue #355 the block also
declares what the commit path *does* with the verdict — `gate: record`
(presence) or `gate: verdict` (the verdict decides the commit, bound to the
tree by a stamp) — and who renders it, via `cmd`.
Full design in [JUDGE.md](JUDGE.md); the attestation
[pattern-class in DIRECTIVE_AUTHORING.md](DIRECTIVE_AUTHORING.md#attestation--sub-agent-verdict-checks)
shows when to reach for it.

| Function | Signature | What it does | Since |
|---|---|---|---|
| `extract_md_section` | `extract_md_section <file> <heading>` | Print the body of the `## <heading>` section (case-insensitive), stopping at the next `## `. The generic markdown-section reader. | 0.10.0 |
| `attestation_prompt` | `attestation_prompt <section> <inputs> <check-1> [<check-2> ...]` | Print the canonical single-section fresh-context sub-agent authoring instruction. One envelope so every attestation-backed directive emits the same recognizable prompt; you supply only the section name, the `<inputs>` the sub-agent must be handed, and the numbered checks it must adjudicate. | 0.10.0 |
| `require_attestation` | `require_attestation <file> <section> <why> <inputs> <check-1> [...]` | The original per-directive gate. Records a `violation` when `<file>` lacks a well-formed `## <section>`: absent → `<why>` plus the `attestation_prompt` instruction; present but carrying no `PASS`/`REFUTED` token → a "fill in the verdict" message. Returns `0` on a well-formed section, `1` otherwise. Purely mechanical: presence + a verdict token, **never** the verdict's truth. Still the fallback when a directive can't declare a `judge:` block. | 0.10.0 |
| `judge_attest` | `judge_attest <receipt>` | Reads judgment semantics (`inputs`, `checks`, `gate`) from `judge:` and live-lane placement/command/group/rounds from typed `config:`. Without `ATTEST_SECTION` the live lane no-ops. Pending sections enter the shared remediation ledger. | release carrying issue #366 |
| `attestation_remediation` | `attestation_remediation [<ledger>]` | The run-level orchestrator. Reads the pending-attestation ledger and emits **one** grouped remediation instruction per `group` label present (a single sub-agent handed the union of that group's sections' inputs, demuxed by `DIRECTIVE:`-tagged blocks), plus one solo sub-agent per section declaring no `group`. For `gate: verdict` sections it renders the escalation ladder through fixed `ATTEST_CMD`, then a terminal STALLED instruction, plus the exact round-line format and `_adjudication_stamp` invocation. Invoked once by `run.sh` and the pre-commit dispatcher; silent no-op when nothing is pending. | 0.11.0 |
| `resolve_judge_input` | `resolve_judge_input <token> <receipt>` | Map a typed input token (`diff`, `receipt`, `issue`, `layer-map`) to the concrete handle phrase the sub-agent is handed; unknown tokens pass through verbatim. Chat transcripts and harness-private session files are not supported inputs. | 0.11.0 |

Execution settings use ordinary config entries such as `ATTEST_SECTION`,
`ATTEST_CMD`, `SCHEDULE_CMD`, `JUDGE_GROUP`, and `JUDGE_ROUNDS`. The manifest
fixes command and artifact-contract entries; environment values never override
or supply them.

These helpers are **pure bash + awk + git** since issue #355 — the commit path
invokes no python. Several private helpers landed with the adjudication gate and
the `cmd` judge dispatch in the same era; they are `_`-prefixed and may change,
but these are worth knowing:

| Private helper | Signature | What it does | Since |
|---|---|---|---|
| `_adjudication_stamp` | `_adjudication_stamp <receipt>` | Print the 12-hex freshness stamp binding a verdict to the tree it judged: `sha256("<git write-tree over the index minus the receipt> <sha256 of the receipt with its round lines stripped>")`, truncated. Appending round lines never moves it; changing any other byte of the receipt or any other file in the commit does. Callable standalone (`bash -c 'source .governance/lib.sh; _adjudication_stamp <path>'`) so an adjudicator can record it. | the release carrying #355 |
| `_change_set_base` | `_change_set_base` | Print the commit the change set is measured against — the merge-base with the first resolvable default branch (`origin/main`, `origin/master`, `main`, `master`), falling back to `HEAD`. The `doc-integrity` candidate ladder, factored out. `GOVERNANCE_CHANGE_SET_BASE` overrides. | the release carrying #355 |
| `_judge_rounds_resolve` | `_judge_rounds_resolve <id> <directive.yaml>` | Resolve `JUDGE_ROUNDS` through the config registry, defaulting to `3` only when undeclared and clamping to a floor of `2`. | release carrying issue #366 |
| `_judge_cmd_resolve` | `_judge_cmd_resolve <yaml> <lane>` | Resolve `ATTEST_CMD` or `SCHEDULE_CMD` through the config registry; returns `1` when absent or empty. | release carrying issue #366 |
| `_judge_cmd_run` | `_judge_cmd_run <cmd>` | Run **one** judge round against a detached CLI: prompt on stdin, normalized verdict on stdout. `command -v` on `<cmd>`'s first word first — missing → return `2`, no output, one stderr line, never a guess. Strips harness session identity from the environment before exec'ing (`CLAUDECODE`, `CLAUDE_CODE_*`, `CODEX_*`, `CURSOR_*`, `PI_*`, `OPENCODE*`) so the spawned CLI is a fresh context, not a nested harness session. Wraps the call in `timeout`/`gtimeout ${AGENT_JUDGE_TIMEOUT:-120}` when available. Runs `bash -c "$cmd"` with the prompt on stdin; a nonzero exit returns `2`. Pipes stdout through `_judge_emit_verdict`; no well-formed `VERDICT:` line returns `2`. | the release carrying #355 |
| `_judge_emit_verdict` | `_judge_emit_verdict` | The awk grammar filter every judge's raw output is piped through, once, instead of duplicated per adapter: CR-strip, printable-ASCII only, length cap, passes only `VERDICT:`/`REASON:`/`FINDING:`/`DIRECTIVE:` lines. A `DIRECTIVE:` line re-arms the verdict matcher (the `blk` flag) so a batched `group` invocation's answer demuxes back into one verdict per member directive. | the release carrying #355 |
| `_judge_cli_prompt` | `_judge_cli_prompt <receipt> <section> <checks-US> <directive.yaml> [<range>] [<mode>]` | Build the whole prompt piped into `_judge_cmd_run` (or handed to the harness sub-agent instruction), from the declaration and git ground truth — never from the agent under audit's own context. `<mode>` selects the **moment**, not the judgment: `verdict` (default) is the commit lane, where a gate is waiting; `schedule` is the at-rest lane, where the answer is recorded as a round or filed as findings (the renamed `sweep` mode). `<range>` is the judged commit range the `range-diff` input token renders (falls back to `$GOVERNANCE_SCHEDULE_RANGE`, the renamed `GOVERNANCE_SWEEP_RANGE`). The batch-spec 7th arg (record-separator `\x1e`-joined members) is unchanged. One builder, one prompt shape, two moments — `schedule.sh` never builds its own prompt. | the release carrying #355 |
| `_judge_group_resolve` | `_judge_group_resolve <full-id> <bare-id> <yaml>` | Resolve `JUDGE_GROUP` through the config registry; empty or absent becomes solo (`-`). | release carrying issue #366 |
| `_directive_triggers_resolve` | `_directive_triggers_resolve <full-id> <bare-id> <yaml> <hook>` | Read author-owned explicit `triggers:` or derive the hook-only default. Overlays cannot change eligibility. | release carrying issue #366 |

### The `FINDING` grammar (schedule lane, issue #355)

`_judge_cmd_run`'s normalized output — `VERDICT: PASS|REFUTED` then zero
or more `REASON:` lines — grows one optional, repeatable line, only ever
emitted after `VERDICT`/`REASON`:

```
VERDICT: PASS|REFUTED
REASON: <one line>
FINDING: <path>:<line> — <short quote> — <why>
```

`_judge_emit_verdict` passes `FINDING:` lines through with the same
treatment as everything else it emits — carriage returns stripped, printable
ASCII only, length-capped. `_judge_cli_prompt` emits the `FINDING:` line
instruction only in `schedule` mode; the commit-lane prompt never asks for
one, and the commit-lane caller ignores any `FINDING:` lines a judge emits
anyway — no commit-path behavior changes because the grammar grew.

### Per-directive configuration

The author-owned `directive.yaml config:` registry holds typed defaults, docs,
and tunability. The optional user overlay lives at
`.governance/conf/<owner>/<pack>/<id>.conf`. Helpers resolve the qualified
overlay from the running `check.sh`; only entries declared `tunable: true`
consume it. See [PACK_AUTHORING.md](PACK_AUTHORING.md#per-directive-configuration).

| Function | Signature | What it does | Since |
|---|---|---|---|
| `conf_file` | `conf_file <directive-id>` | Print the directive's user-overlay path and return `0` if it exists; return `1` (printing nothing) otherwise. Conf-driven directives typically treat a missing overlay as "nothing opted in" and no-op. | 0.6.0 |
| `conf_get` | `conf_get <directive-id> <KEY> <directive.yaml>` | Resolve a declared scalar. A tunable overlay `KEY=` row wins; otherwise the manifest default is final. There is no environment tier or undeclared fallback. | release carrying issue #366 |
| `conf_rule_lines` | `conf_rule_lines <directive-id>` | Emit the user overlay's directive-defined rule lines — trimmed, with `#` comments, blank lines, and `KEY=value` scalar lines stripped. Emits nothing when no overlay exists. | 0.6.0 |
| `conf_list` | `conf_list <directive-id> <directive.yaml> [KEY]` | Emit a declared list default. For tunable entries, `KEY+=<item>` adds and `KEY-=<item>` removes; bare/`!item` shorthand is accepted only when the manifest declares one list key. `KEY` defaults to `RULES`. | release carrying issue #366 |

## Use these, don't reinvent

Roughly half this surface is missing from a casual read of the authoring docs,
so authors routinely hand-roll what already ships. The recurring foot-guns:

- **Iterating files** — reach for `tracked_files`, never `ls` / `find` / a
  `while read … < <(git ls-files)` loop. The helper respects `.gitignore` and
  skips directories; the loops don't.
- **Whole-file waivers** — `has_file_waiver` exists for the "the violation is
  the file, not a line" case. Don't fall back to a per-line `has_waiver` against
  line 1.
- **Correspondence-to-reality checks** — when the real question is "does this
  artifact match the diff / the issue / the running system," that is the
  attestation class (`require_attestation`), not a cleverer grep. A hook cannot
  read ground truth; stop trying to approximate it.
- **Reading config** — `conf_get` / `conf_list` already enforce the manifest's
  type and tunability policy plus the list add/remove grammar. Don't re-parse
  manifests or overlay files by hand.

## Version-floor obligation

Every helper above ships inside kit-owned `lib.sh`. A directive that calls one
is only correct on a kit new enough to define it — so a pack whose directive
uses a helper introduced at kit v*X* **must floor `min_governance_kit` at *X***
(the **Since** column). Read the floor straight off the table.

The worked example is the attestation trio: `require_attestation` and its
siblings were authored on the kit's `0.9` source line (issue #272) but first
**shipped** to consumers in `kit/v0.10.0`, so the floor is `0.10.0` — which is
why the `governance-kit/audit` pack declares `min_governance_kit: "0.10.0"`. The
distinction matters: a community pack that calls `require_attestation` while
flooring at `0.9` (the source line) installs cleanly into a `0.9.x` kit — which
predates the tag that ships the helper — and then fails at commit time with
`require_attestation: command not found`. Always read the floor off the **Since**
column (first-shipped), never off the source-line marker. (This bites arbitrary
consumers, not the dogfood, which always runs the latest kit.)

See [VERSIONING.md](VERSIONING.md) for the kit-vs-pack version axes and
[PACK_AUTHORING.md](PACK_AUTHORING.md#versioning) for where `min_governance_kit`
is declared.

## See also

- [DIRECTIVE_AUTHORING.md](DIRECTIVE_AUTHORING.md) — the craft guide: qualities to
  aim for, anti-patterns, and patterns by directive class (each pattern points
  back here for the helper it leans on).
- [PACK_AUTHORING.md](PACK_AUTHORING.md) — the pack layout, `directive.yaml`
  schema, the configuration contract, and the eval mandate.
- [JUDGE.md](JUDGE.md) — the attestation pattern
  the three attestation helpers implement.
