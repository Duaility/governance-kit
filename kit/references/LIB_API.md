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

The independent-auditor pattern — a section a fresh-context sub-agent must
populate against ground truth (the diff, the linked issue, the session
transcript) the hook itself cannot read. Since issue #325 the task is declared
once in the directive's `directive.yaml` `subagent:` block and the commit-time
orchestrator **batches** every `isolation: shared` section into one sub-agent.
Since issue #355 the block also declares what the commit path *does* with the
verdict — `gate: record` (presence) or `gate: verdict` (the verdict decides the
commit, bound to the tree by a stamp).
Full design in [SUBAGENT_ATTESTATION.md](SUBAGENT_ATTESTATION.md); the attestation
[pattern-class in DIRECTIVE_AUTHORING.md](DIRECTIVE_AUTHORING.md#attestation--sub-agent-verdict-checks)
shows when to reach for it.

| Function | Signature | What it does | Since |
|---|---|---|---|
| `extract_md_section` | `extract_md_section <file> <heading>` | Print the body of the `## <heading>` section (case-insensitive), stopping at the next `## `. The generic markdown-section reader. | 0.10.0 |
| `attestation_prompt` | `attestation_prompt <section> <inputs> <check-1> [<check-2> ...]` | Print the canonical single-section fresh-context sub-agent authoring instruction. One envelope so every attestation-backed directive emits the same recognizable prompt; you supply only the section name, the `<inputs>` the sub-agent must be handed, and the numbered checks it must adjudicate. | 0.10.0 |
| `require_attestation` | `require_attestation <file> <section> <why> <inputs> <check-1> [...]` | The original per-directive gate. Records a `violation` when `<file>` lacks a well-formed `## <section>`: absent → `<why>` plus the `attestation_prompt` instruction; present but carrying no `PASS`/`REFUTED` token → a "fill in the verdict" message. Returns `0` on a well-formed section, `1` otherwise. Purely mechanical: presence + a verdict token, **never** the verdict's truth. Still the fallback when a directive can't declare a `subagent:` block. | 0.10.0 |
| `subagent_attest` | `subagent_attest <receipt>` | The declaration-driven gate. Reads the sibling `directive.yaml`'s `subagent:` block (section, isolation, inputs, checks, and — since #355 — `gate`, `sink`, `contest`) and runs the gate it declares: `gate: record` is presence + a `PASS`/`REFUTED` token, `gate: verdict` is the adjudication gate (append-only log, latest round `PASS`, fresh stamp). `sink: none` returns `0` immediately — a sweep-only declaration the commit lane ignores. When the section is pending it registers into the shared ledger so `attestation_remediation` can batch it. Returns `0`/`1` like `require_attestation`. | 0.11.0 |
| `attestation_remediation` | `attestation_remediation [<ledger>]` | The run-level orchestrator. Reads the pending-attestation ledger and emits **one** grouped remediation instruction: a single sub-agent for all `isolation: shared` sections (handed the union of inputs), plus one isolated sub-agent per `isolation: isolated` section. For `gate: verdict` sections it renders the escalation ladder — attest tier, then a `high`-tier escalation round, then a terminal STALLED instruction — plus the exact round-line format and the `_adjudication_stamp` invocation. Invoked once by `run.sh` and the pre-commit dispatcher; silent no-op when nothing is pending. | 0.11.0 |
| `resolve_subagent_input` | `resolve_subagent_input <token> <receipt>` | Map a typed input token (`diff`, `receipt`, `issue`, `transcript`, `layer-map`) to the concrete handle phrase the sub-agent is handed; unknown tokens pass through verbatim. | 0.11.0 |

Operator knobs these read, all through the standard `conf_get` ladder (env
`GOVERNANCE_<KEY>` > user overlay > pack `defaults.conf`): `SUBAGENT_ISOLATION`,
`SUBAGENT_TIERS_ATTEST` / `_SWEEP`, `SUBAGENT_ROUNDS`, and — since issue #355 —
`SUBAGENT_EXECUTOR` plus `SUBAGENT_MODELS_LOW` / `_MEDIUM` / `_HIGH`. See
[SUBAGENT_ATTESTATION.md](SUBAGENT_ATTESTATION.md) for what each one changes.

These helpers are **pure bash + awk + git** since issue #355 — the commit path
invokes no python. Several private helpers landed with the adjudication gate and
the executor dispatch in the same release; they are `_`-prefixed and may change,
but these are worth knowing:

| Private helper | Signature | What it does | Since |
|---|---|---|---|
| `_adjudication_stamp` | `_adjudication_stamp <receipt>` | Print the 12-hex freshness stamp binding a verdict to the tree it judged: `sha256("<git write-tree over the index minus the receipt> <sha256 of the receipt with its round lines stripped>")`, truncated. Appending round lines never moves it; changing any other byte of the receipt or any other file in the commit does. Callable standalone (`bash -c 'source .governance/lib.sh; _adjudication_stamp <path>'`) so an adjudicator can record it. | the release carrying #355 |
| `_change_set_base` | `_change_set_base` | Print the commit the change set is measured against — the merge-base with the first resolvable default branch (`origin/main`, `origin/master`, `main`, `master`), falling back to `HEAD`. The `doc-integrity` candidate ladder, factored out. `GOVERNANCE_CHANGE_SET_BASE` overrides. | the release carrying #355 |
| `_subagent_rounds_resolve` | `_subagent_rounds_resolve <id> <defaults-file> <directive.yaml>` | Resolve the adjudication round ceiling *K* through the usual `conf_get` ladder (`SUBAGENT_ROUNDS`), default `3`, clamped up to a floor of `2`. | the release carrying #355 |
| `_subagent_executor_resolve` | `_subagent_executor_resolve <id> <defaults-file>` | Resolve **who renders the verdict** through the `conf_get` ladder (`SUBAGENT_EXECUTOR`): `harness` (default — the sub-agent the calling agent spawns) or `cli:<adapter>` (a separate command-line agent this hook invokes). Anything unrecognized degrades to `harness`, so a typo in a conf file can never wedge a commit. | the release carrying #355 |
| `_subagent_model_resolve` | `_subagent_model_resolve <id> <defaults-file> <tier>` | The `SUBAGENT_MODELS_LOW` / `_MEDIUM` / `_HIGH` override a `cli:` executor should run this tier at. Empty (the default) means the adapter picks — the kit ships no model catalog for someone else's CLI. | the release carrying #355 |
| `_subagent_adapter` | `_subagent_adapter <name>` | Path to the kit-level runtime adapter `.governance/runtimes/<name>.sh`, or nothing (return `1`). `GOVERNANCE_RUNTIMES_DIR` overrides the registry location. | the release carrying #355 |
| `_subagent_cli_adjudicate` | `_subagent_cli_adjudicate <adapter> <tier> <model> <receipt> <section> <checks-US> <directive.yaml> <ceiling>` | Run **one** cli adjudication round: build the prompt from the declaration + git ground truth (`_subagent_cli_prompt`), pipe it to `<adapter> judge`, append the returned round line with a fresh stamp, and stage the receipt. Returns `0` when a round landed (the caller re-evaluates the gate once), `1` on any failure — with a one-line stderr note, because a silent degrade reads as the executor working. | the release carrying #355 |

### Per-directive configuration

Two artifacts, one writer each (issue #210): the pack-owned `defaults.conf` next
to `check.sh` (live defaults + their docs) and the user overlay
`.governance/conf/<owner>/<pack>/<id>.conf`. Both resolve the qualified overlay
path from the running `check.sh` location automatically. Layout and the
add/remove/override grammar: [PACK_AUTHORING.md](PACK_AUTHORING.md#per-directive-configuration).

| Function | Signature | What it does | Since |
|---|---|---|---|
| `conf_file` | `conf_file <directive-id>` | Print the directive's user-overlay path and return `0` if it exists; return `1` (printing nothing) otherwise. Conf-driven directives typically treat a missing overlay as "nothing opted in" and no-op. | 0.6.0 |
| `conf_get` | `conf_get <directive-id> <KEY> <defaults-file>` | Resolve a scalar knob. Precedence: env `GOVERNANCE_<KEY>` > the overlay's `KEY=` line > the `defaults.conf` `KEY=` row. Pass `"$(dirname "$0")/defaults.conf"` as `<defaults-file>` — the `defaults.conf` row **is** the default (there is no in-code constant), so a read knob with no row fails loud. | 0.6.0 |
| `conf_rule_lines` | `conf_rule_lines <directive-id>` | Emit the user overlay's directive-defined rule lines — trimmed, with `#` comments, blank lines, and `KEY=value` scalar lines stripped. Emits nothing when no overlay exists. | 0.6.0 |
| `conf_list` | `conf_list <directive-id> <defaults-file>` | Emit the effective list: the `defaults.conf` items with the overlay layered on top — a bare line **adds**, `!<item>` **removes** a default (gitignore-style negation), `KEY=value` is ignored (read scalars with `conf_get`). Pass `"$(dirname "$0")/defaults.conf"`. | 0.6.0 |

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
- **Reading config** — `conf_get` / `conf_list` already implement the
  env → overlay → `defaults.conf` precedence and the add/remove grammar. Don't
  re-parse the conf files by hand.

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
- [SUBAGENT_ATTESTATION.md](SUBAGENT_ATTESTATION.md) — the attestation pattern
  the three attestation helpers implement.
