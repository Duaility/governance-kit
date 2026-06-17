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

Grouped by job. **Since** is the kit source line the helper was authored
against — see [Version-floor obligation](#version-floor-obligation) below for why
that column is load-bearing, not trivia.

### Lifecycle — every `check.sh` uses these

| Function | Signature | What it does | Since |
|---|---|---|---|
| `directive_start` | `directive_start <directive-id>` | Open a directive. Resets the violation counter; the id must match the directive folder name. Pair with `directive_end`. | 0.3 |
| `violation` | `violation <message>` | Record one violation. The message must carry the location and the fix — `"path:line — what's wrong"`, never `"bad code"`. Call once per problem found; they are batched and printed by `directive_end`. | 0.3 |
| `directive_end` | `directive_end` | Print the `✓`/`✗` summary (and, on failure, the directive's `**Rationale**:` pulled from its sibling `constitution.md`) and **exit** `0` (clean) or `1` (violations). Owns the exit status — never call `exit` yourself. | 0.3 |

### Git / repo state

| Function | Signature | What it does | Since |
|---|---|---|---|
| `require_git` | `require_git` | Skip the directive (print `⊘` and exit `0`) when not inside a git work tree. Call it before any `git ls-files` / `git grep`, so a check sourced outside a repo no-ops instead of erroring. | 0.3 |
| `tracked_files` | `tracked_files [<pathspec>...]` | Emit git-tracked files (respects `.gitignore`), optionally filtered by a pathspec — `tracked_files '*.py'`, `tracked_files ':!vendor/**'`. **Use this instead of `ls`, `find`, or a hand-rolled `git ls-files` loop** — those pull in gitignored files and directories. | 0.3 |

### Waivers

| Function | Signature | What it does | Since |
|---|---|---|---|
| `has_waiver` | `has_waiver <file> <line_no> <directive-id>` | True when that line carries `governance: allow-<directive-id>`. The per-line escape hatch — `has_waiver "$file" "$line" "<id>" && continue` inside a per-line scan. | 0.3 |
| `has_file_waiver` | `has_file_waiver <file> <directive-id> <subcheck>` | True when the file's first 10 lines carry `governance: allow-<directive-id> <subcheck>`. The **whole-file** waiver, for sub-checks whose violation is the file itself rather than a line. The `<subcheck>` name lets several file-level sub-checks share one `allow-<directive-id>` prefix without colliding. | 0.3 |

### Sub-agent attestation

The independent-auditor pattern — a section a fresh-context sub-agent must
populate against ground truth (the diff, the linked issue) the hook itself
cannot read. Full design in
[SUBAGENT_ATTESTATION.md](SUBAGENT_ATTESTATION.md); the attestation
[pattern-class in DIRECTIVE_AUTHORING.md](DIRECTIVE_AUTHORING.md#attestation--sub-agent-verdict-checks)
shows when to reach for it.

| Function | Signature | What it does | Since |
|---|---|---|---|
| `extract_md_section` | `extract_md_section <file> <heading>` | Print the body of the `## <heading>` section (case-insensitive), stopping at the next `## `. The generic markdown-section reader. | 0.9 |
| `attestation_prompt` | `attestation_prompt <section> <inputs> <check-1> [<check-2> ...]` | Print the canonical fresh-context sub-agent authoring instruction. One envelope so every attestation-backed directive emits the same recognizable prompt; you supply only the section name, the `<inputs>` the sub-agent must be handed, and the numbered checks it must adjudicate. | 0.9 |
| `require_attestation` | `require_attestation <file> <section> <why> <inputs> <check-1> [...]` | The deterministic gate. Records a `violation` when `<file>` lacks a well-formed `## <section>`: absent → `<why>` plus the `attestation_prompt` instruction; present but carrying no `PASS`/`REFUTED` token → a "fill in the verdict" message. Returns `0` on a well-formed section, `1` otherwise (callers may branch). Purely mechanical: presence + a verdict token, **never** the verdict's truth. | 0.9 |

### Per-directive configuration

Two artifacts, one writer each (issue #210): the pack-owned `defaults.conf` next
to `check.sh` (live defaults + their docs) and the user overlay
`.governance/conf/<owner>/<pack>/<id>.conf`. Both resolve the qualified overlay
path from the running `check.sh` location automatically. Layout and the
add/remove/override grammar: [PACK_AUTHORING.md](PACK_AUTHORING.md#per-directive-configuration).

| Function | Signature | What it does | Since |
|---|---|---|---|
| `conf_file` | `conf_file <directive-id>` | Print the directive's user-overlay path and return `0` if it exists; return `1` (printing nothing) otherwise. Conf-driven directives typically treat a missing overlay as "nothing opted in" and no-op. | 0.5 |
| `conf_get` | `conf_get <directive-id> <KEY> <defaults-file>` | Resolve a scalar knob. Precedence: env `GOVERNANCE_<KEY>` > the overlay's `KEY=` line > the `defaults.conf` `KEY=` row. Pass `"$(dirname "$0")/defaults.conf"` as `<defaults-file>` — the `defaults.conf` row **is** the default (there is no in-code constant), so a read knob with no row fails loud. | 0.5 |
| `conf_rule_lines` | `conf_rule_lines <directive-id>` | Emit the user overlay's directive-defined rule lines — trimmed, with `#` comments, blank lines, and `KEY=value` scalar lines stripped. Emits nothing when no overlay exists. | 0.5 |
| `conf_list` | `conf_list <directive-id> <defaults-file>` | Emit the effective list: the `defaults.conf` items with the overlay layered on top — a bare line **adds**, `!<item>` **removes** a default (gitignore-style negation), `KEY=value` is ignored (read scalars with `conf_get`). Pass `"$(dirname "$0")/defaults.conf"`. | 0.5 |

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
siblings landed on the kit's `0.9` source line (issue #272), which is exactly
why the `governance-kit/audit` pack declares `min_governance_kit: "0.9.0"`. A
community pack that calls `require_attestation` while flooring at, say, `0.5`
installs cleanly into a `0.5`–`0.8` kit and then fails at commit time with
`require_attestation: command not found` — a silent breakage the floor exists to
prevent. (This bites arbitrary consumers, not the dogfood, which always runs the
latest kit.)

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
