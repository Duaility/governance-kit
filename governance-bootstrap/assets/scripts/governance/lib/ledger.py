#!/usr/bin/env python3
"""Agent token accounting ledger — parse, sum, append, validate COSTS.md rows.

This module is the data-processing half of agent-token-accounting. The bash
hooks and rule scripts still do git plumbing and env detection; anything that
manipulates COSTS.md rows by name rather than by column index lives here.

Schema (v2 — cache columns split out):

    | cost-key | agent | session | issue | input | cache-create | cache-read | output | total | note |

Where:
    input         = usage.input_tokens            (truly new tokens this turn)
    cache-create  = usage.cache_creation_input_tokens
    cache-read    = usage.cache_read_input_tokens
    output        = usage.output_tokens
    total         = input + cache-create + cache-read + output
                    (total billable tokens — self-checking invariant)

Trailer invariant (not enforced here, enforced by the rule script):
    Token-Input  = input + cache-create            (new work worth showing reviewers)
    Token-Output = output
    Token-Total  = Token-Input + Token-Output

This module is stdlib-only and has no runtime dependencies.

CLI shims (called from bash):

    python3 -m ledger sum-by-session <ledger> <session_id>
        → prints  "<input> <cache_create> <cache_read> <output>"
          (zeros if no matching rows or ledger is missing)

    python3 -m ledger append-row <ledger> <cost_key> <agent> <session> \\
                                 <issue> <input> <cache_create> <cache_read> \\
                                 <output> <note>
        → appends the row (formatted), creating the file with the header
          template if needed. Prints nothing on success.

    python3 -m ledger validate <ledger>
        → prints one violation per line to stdout; exits non-zero if any.
          Checks: row shape, total invariant, issue anchor shape, cost-key
          uniqueness.

    python3 -m ledger find-by-cost-key <ledger> <cost_key>
        → prints the matching row's columns space-separated:
          "<input> <cache_create> <cache_read> <output> <total>"
          or exits with code 2 if zero/multiple matches.
"""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterator


# ── Schema ────────────────────────────────────────────────────────────────

# Columns as they appear in a ledger row, left to right. Used by both the
# parser (index → field) and the writer (field → cell order).
COLUMNS = (
    "cost_key",
    "agent",
    "session",
    "issue",
    "input",
    "cache_create",
    "cache_read",
    "output",
    "total",
    "note",
)

# Numeric columns that get summed for per-commit deltas.
NUMERIC_COLUMNS = ("input", "cache_create", "cache_read", "output")

LEDGER_TEMPLATE = """\
<!-- COSTS.md — append-only agent token-accounting ledger -->
<!-- governance: allow-plan-captured -->

# COSTS.md

Append-only ledger of token consumption for agent-authored commits. Rows are
keyed by `Cost-Key`, which is mirrored into the commit trailers so the ledger
survives squash merges that strip the original commit history.

**Do not** rewrite or reorder rows. This file is the durable system-of-record
that the `agent-token-accounting` governance rule validates.

The pre-commit hook (`scripts/governance/agent-accounting.sh`) appends a row
before git snapshots the tree; the `prepare-commit-msg` hook stamps the
matching trailers. See
[governance-bootstrap/references/AGENT_TOKEN_ACCOUNTING.md](governance-bootstrap/references/AGENT_TOKEN_ACCOUNTING.md)
for wiring instructions.

## Ledger

| cost-key | agent | session | issue | input | cache-create | cache-read | output | total | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
"""


# ── Row model ─────────────────────────────────────────────────────────────


@dataclass
class LedgerRow:
    cost_key: str = ""
    agent: str = ""
    session: str = ""
    issue: str = ""
    input: int = 0
    cache_create: int = 0
    cache_read: int = 0
    output: int = 0
    total: int = 0
    note: str = ""

    @property
    def expected_total(self) -> int:
        return self.input + self.cache_create + self.cache_read + self.output

    def to_cells(self) -> list[str]:
        """Return the row as a list of ten string cells, pipe-separator-ready."""
        return [
            self.cost_key,
            self.agent,
            self.session,
            self.issue,
            str(self.input),
            str(self.cache_create),
            str(self.cache_read),
            str(self.output),
            str(self.total),
            self.note,
        ]


# ── Parse ─────────────────────────────────────────────────────────────────


_INT_RE = re.compile(r"^-?\d+$")
_ISSUE_RE = re.compile(r"^#[1-9][0-9]*$")


def _parse_cells(line: str) -> list[str] | None:
    """Split a `| a | b | c |` line into cell strings with whitespace stripped.

    Returns None if the line is not a table row (no leading `|` or not enough
    cells). The header row and separator row are *not* filtered here — callers
    filter by inspecting cell contents.
    """
    stripped = line.strip()
    if not stripped.startswith("|"):
        return None
    # `| a | b |`.split("|") → ["", " a ", " b ", ""] — drop the two sentinel empties.
    parts = [c.strip() for c in stripped.split("|")[1:-1]]
    return parts or None


def _is_header_or_separator(cells: list[str]) -> bool:
    if not cells:
        return True
    first = cells[0]
    if first == "cost-key":
        return True
    if first == "" or re.fullmatch(r"-+", first or ""):
        return True
    # Separator rows like `| --- | --- | ... |` have all cells as dashes.
    if all(c == "" or re.fullmatch(r"-+", c) for c in cells):
        return True
    return False


def parse(path: str | Path) -> list[LedgerRow]:
    """Parse all data rows from a COSTS.md ledger file.

    Returns an empty list if the file doesn't exist. Rows with the *legacy*
    8-column shape (input, output, total, note — pre-cache-split) are accepted
    and upgraded to the new shape with cache_create/cache_read defaulted to 0.
    Rows with fewer than 8 cells or non-integer token fields are skipped
    silently here; validate() surfaces them as violations.
    """
    p = Path(path)
    if not p.is_file():
        return []
    rows: list[LedgerRow] = []
    for line in p.read_text().splitlines():
        cells = _parse_cells(line)
        if cells is None:
            continue
        if _is_header_or_separator(cells):
            continue

        # v2 (10 columns, cache split): cost-key agent session issue input cache_create cache_read output total note
        # v1 legacy (8 columns):        cost-key agent session issue input                           output total note
        if len(cells) == 10:
            cost_key, agent, session, issue, i, cc, cr, o, t, note = cells
        elif len(cells) == 8:
            cost_key, agent, session, issue, i, o, t, note = cells
            cc, cr = "0", "0"
        else:
            # Unknown shape — skip in parse; validate() reports the file-level issue.
            continue

        def to_int(s: str) -> int:
            return int(s) if _INT_RE.match(s or "") else 0

        rows.append(
            LedgerRow(
                cost_key=cost_key,
                agent=agent,
                session=session,
                issue=issue,
                input=to_int(i),
                cache_create=to_int(cc),
                cache_read=to_int(cr),
                output=to_int(o),
                total=to_int(t),
                note=note,
            )
        )
    return rows


# ── Queries ───────────────────────────────────────────────────────────────


def sum_by_session(rows: list[LedgerRow], session_id: str) -> LedgerRow:
    """Return a synthetic LedgerRow whose numeric fields are sums across all
    rows matching `session_id`. Non-numeric fields are left default. Used to
    compute per-commit delta = cumulative - priors."""
    agg = LedgerRow(session=session_id)
    for r in rows:
        if r.session == session_id:
            agg.input += r.input
            agg.cache_create += r.cache_create
            agg.cache_read += r.cache_read
            agg.output += r.output
    agg.total = agg.expected_total
    return agg


def find_by_cost_key(rows: list[LedgerRow], cost_key: str) -> list[LedgerRow]:
    """All rows matching a cost-key. Expected to be exactly 1; the rule
    surfaces 0-or-more-than-1 as violations."""
    return [r for r in rows if r.cost_key == cost_key]


# ── Append ────────────────────────────────────────────────────────────────


def append_row(path: str | Path, row: LedgerRow) -> None:
    """Append `row` to the ledger. Creates the file with the header template
    if it doesn't exist yet. `row.total` is recomputed from its components so
    callers don't have to keep it in sync."""
    row.total = row.expected_total
    p = Path(path)
    if not p.exists():
        p.write_text(LEDGER_TEMPLATE)
    cells = row.to_cells()
    # Strip pipes and control chars from `note` so the row stays well-formed.
    cells[-1] = _safe_cell(cells[-1])[:80]
    line = "| " + " | ".join(cells) + " |\n"
    with p.open("a") as f:
        f.write(line)


def _safe_cell(s: str) -> str:
    """Strip pipes and ASCII control characters from a cell. BSD `ps` escapes
    embedded newlines in argv as literal `\\012`; truncate at the first
    backslash too so those escapes don't contaminate the note column."""
    # Drop control chars (0x00-0x1F, 0x7F) and pipes.
    cleaned = "".join(ch for ch in s if ch.isprintable() and ch != "|")
    # Truncate at first backslash (ps escape boundary).
    if "\\" in cleaned:
        cleaned = cleaned.split("\\", 1)[0]
    return cleaned.strip()


# ── Validate ──────────────────────────────────────────────────────────────


def validate(path: str | Path) -> list[str]:
    """Walk the ledger and return a list of violation strings.

    Checks:
        - Every non-header, non-separator `|...|` line has 8 (legacy) or 10 cells.
        - All token columns are non-negative integers.
        - row.total == sum of the four token columns.
        - issue matches `#N`.
        - agent / session / issue are non-empty.
        - cost-key is unique across the file.

    Returns [] if the ledger is clean. A missing file is not a violation.
    """
    p = Path(path)
    if not p.is_file():
        return []

    violations: list[str] = []
    cost_keys: dict[str, int] = {}

    for line_no, line in enumerate(p.read_text().splitlines(), start=1):
        cells = _parse_cells(line)
        if cells is None:
            continue
        if _is_header_or_separator(cells):
            continue
        if len(cells) not in (8, 10):
            violations.append(
                f"COSTS.md:{line_no} — row has {len(cells)} cells, expected 8 (legacy) or 10"
            )
            continue

        if len(cells) == 10:
            cost_key, agent, session, issue, i, cc, cr, o, t, _note = cells
        else:
            cost_key, agent, session, issue, i, o, t, _note = cells
            cc, cr = "0", "0"

        # Shape of all required string fields.
        if not cost_key:
            violations.append(f"COSTS.md:{line_no} — empty cost-key")
            continue
        if not agent or not session or not issue:
            violations.append(
                f"COSTS.md — row '{cost_key}' has empty agent/session/issue field"
            )
        if issue and not _ISSUE_RE.match(issue):
            violations.append(
                f"COSTS.md — row '{cost_key}' issue '{issue}' must look like '#123'"
            )

        # Token columns.
        token_cells = {"input": i, "cache_create": cc, "cache_read": cr, "output": o, "total": t}
        if not all(_INT_RE.match(v or "") and int(v) >= 0 for v in token_cells.values()):
            violations.append(
                f"COSTS.md — row '{cost_key}' has non-integer or negative token counts "
                f"(input={i}, cache_create={cc}, cache_read={cr}, output={o}, total={t})"
            )
            continue

        actual_total = int(i) + int(cc) + int(cr) + int(o)
        if int(t) != actual_total:
            violations.append(
                f"COSTS.md — row '{cost_key}' has total={t} but "
                f"input+cache_create+cache_read+output={actual_total}"
            )

        cost_keys[cost_key] = cost_keys.get(cost_key, 0) + 1

    for key, count in cost_keys.items():
        if count > 1:
            violations.append(
                f"COSTS.md — cost-key '{key}' appears {count} times (must be unique, append-only)"
            )

    return violations


# ── CLI ───────────────────────────────────────────────────────────────────


def _cmd_sum_by_session(args: list[str]) -> int:
    if len(args) != 2:
        _die("sum-by-session takes: <ledger> <session_id>")
    rows = parse(args[0])
    agg = sum_by_session(rows, args[1])
    print(f"{agg.input} {agg.cache_create} {agg.cache_read} {agg.output}")
    return 0


def _cmd_append_row(args: list[str]) -> int:
    # ledger cost_key agent session issue input cache_create cache_read output note
    if len(args) != 10:
        _die(
            "append-row takes: <ledger> <cost_key> <agent> <session> <issue> "
            "<input> <cache_create> <cache_read> <output> <note>"
        )
    (
        ledger,
        cost_key,
        agent,
        session,
        issue,
        inp,
        cc,
        cr,
        out,
        note,
    ) = args

    def to_int(s: str, label: str) -> int:
        if not _INT_RE.match(s) or int(s) < 0:
            _die(f"{label} must be a non-negative integer (got {s!r})")
        return int(s)

    row = LedgerRow(
        cost_key=cost_key,
        agent=agent,
        session=session,
        issue=issue,
        input=to_int(inp, "input"),
        cache_create=to_int(cc, "cache_create"),
        cache_read=to_int(cr, "cache_read"),
        output=to_int(out, "output"),
        note=note,
    )
    append_row(ledger, row)
    return 0


def _cmd_validate(args: list[str]) -> int:
    if len(args) != 1:
        _die("validate takes: <ledger>")
    violations = validate(args[0])
    for v in violations:
        print(v)
    return 1 if violations else 0


def _cmd_find_by_cost_key(args: list[str]) -> int:
    if len(args) != 2:
        _die("find-by-cost-key takes: <ledger> <cost_key>")
    rows = parse(args[0])
    hits = find_by_cost_key(rows, args[1])
    if len(hits) != 1:
        print(f"expected 1 row for cost-key '{args[1]}', found {len(hits)}", file=sys.stderr)
        return 2
    r = hits[0]
    print(f"{r.input} {r.cache_create} {r.cache_read} {r.output} {r.total}")
    return 0


def _die(msg: str) -> None:
    print(f"ledger: {msg}", file=sys.stderr)
    sys.exit(2)


_COMMANDS = {
    "sum-by-session": _cmd_sum_by_session,
    "append-row": _cmd_append_row,
    "validate": _cmd_validate,
    "find-by-cost-key": _cmd_find_by_cost_key,
}


def main(argv: list[str]) -> int:
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        return 0 if argv else 2
    cmd, rest = argv[0], argv[1:]
    if cmd not in _COMMANDS:
        _die(f"unknown command {cmd!r}; try one of: {', '.join(sorted(_COMMANDS))}")
    return _COMMANDS[cmd](rest)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
