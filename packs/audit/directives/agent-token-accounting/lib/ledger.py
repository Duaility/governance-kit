#!/usr/bin/env python3
"""Agent token accounting — parse, sum, append, validate cost rows.

Cost rows live in per-issue receipts (issue #201): each row is appended under
the `## Accounting` → `### Costs` sub-table of `receipts/issue-<N>.md`, not in a
central `COSTS.md`. The receipt is conflict-free (only its own PR branch writes
it) and naturally sealed (frozen on the trunk by doc-integrity). `COSTS.md` is
sealed history this flow no longer reads or writes.

Row schema (12 columns):

    | cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | note |

`new-work = input + cache_create + output` (cache_read tracked but excluded —
same bytes re-read, not new effort) and matches trailer `Token-Total` by
construction. `cost-usd` = `rates.lookup(model)` over all four token columns;
required when `model` is non-empty. `cost-key` is opaque
(`<agent>-<session-short>-<epoch>-<n>`) — a join token, not a parseable id.

Markdown section/table plumbing lives in sibling `receipt_io.py`; pricing in
`rates.py`. Stdlib-only. CLI shims (called from the bash hook / check):

    resolve-receipt <receipts_dir> <issue>    → receipt path for issue N
    sum-by-session  <receipts_dir> <session>  → "<in> <cc> <cr> <out>" summed
    next-cost-index <receipts_dir> <prefix>   → 1 + (#rows with that key prefix)
    append-row      <receipt> <cost_key> <agent> <session> <issue> <model> \\
                    <input> <cache_create> <cache_read> <output> <note>
    validate        <receipt>                 → one violation per line
    validate-dir    <receipts_dir>            → all receipts + global uniqueness
    find-by-cost-key <receipts_dir> <key>     → "<in> <cc> <cr> <out> <nw> <usd>"
"""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from pathlib import Path

# Don't write __pycache__ into the installed directive folder — it would
# litter the consumer's `.governance/packs/` and trip repo-hygiene.
sys.dont_write_bytecode = True

try:
    from rates import compute_cost_usd  # type: ignore
    import receipt_io as rio  # type: ignore
except ModuleNotFoundError:  # pragma: no cover — import fallback when run as a module
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from rates import compute_cost_usd  # type: ignore
    import receipt_io as rio  # type: ignore


COLUMNS = (
    "cost_key", "agent", "session", "issue", "model", "input",
    "cache_create", "cache_read", "output", "new_work", "cost_usd", "note",
)
NUMERIC_COLUMNS = ("input", "cache_create", "cache_read", "output")

COST_HEADER = (
    "| cost-key | agent | session | issue | model | input | cache-create "
    "| cache-read | output | new-work | cost-usd | note |"
)
COST_SEPARATOR = "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |"

_INT_RE = re.compile(r"^-?\d+$")
_FLOAT_RE = re.compile(r"^-?\d+(\.\d+)?$")
_ISSUE_RE = re.compile(r"^#[1-9][0-9]*$")
_RECEIPT_NAME_RE = re.compile(r"^issue-([1-9][0-9]*)(?:-[a-z0-9]+(?:-[a-z0-9]+)*)?\.md$")


@dataclass
class LedgerRow:
    cost_key: str = ""
    agent: str = ""
    session: str = ""
    issue: str = ""
    model: str = ""
    input: int = 0
    cache_create: int = 0
    cache_read: int = 0
    output: int = 0
    new_work: int = 0
    cost_usd: float | None = None
    note: str = ""

    @property
    def expected_new_work(self) -> int:
        return self.input + self.cache_create + self.output

    def to_cells(self) -> list[str]:
        cost_cell = "" if self.cost_usd is None else f"{self.cost_usd:.4f}"
        return [
            self.cost_key, self.agent, self.session, self.issue, self.model,
            str(self.input), str(self.cache_create), str(self.cache_read),
            str(self.output), str(self.new_work), cost_cell, self.note,
        ]


# ── Parse ─────────────────────────────────────────────────────────────────


def _to_int(s: str) -> int:
    return int(s) if _INT_RE.match(s or "") else 0


def _to_cost(s: str) -> float | None:
    s = (s or "").strip()
    if not s:
        return None
    return float(s) if _FLOAT_RE.match(s) else None


def _issue_from_name(name: str) -> str | None:
    m = _RECEIPT_NAME_RE.match(name)
    return f"#{m.group(1)}" if m else None


def _row_from_cells(cells: list[str]) -> LedgerRow | None:
    if len(cells) != 12:
        return None
    (cost_key, agent, session, issue, model, i, cc, cr, o, nw, cost, note) = cells
    return LedgerRow(
        cost_key=cost_key, agent=agent, session=session, issue=issue, model=model,
        input=_to_int(i), cache_create=_to_int(cc), cache_read=_to_int(cr),
        output=_to_int(o), new_work=_to_int(nw), cost_usd=_to_cost(cost), note=note,
    )


def parse_costs(path: str | Path) -> list[LedgerRow]:
    """Parse the cost rows from one receipt's `### Costs` sub-table."""
    p = Path(path)
    if not p.is_file():
        return []
    lines = p.read_text().splitlines()
    region = rio.subtable_region(lines, rio.COSTS_SUBHEADING)
    if region is None:
        return []
    rows: list[LedgerRow] = []
    for idx in range(*region):
        cells = rio.parse_cells(lines[idx])
        if cells is None or rio.is_header_or_separator(cells, "cost-key"):
            continue
        row = _row_from_cells(cells)
        if row is not None:
            rows.append(row)
    return rows


parse = parse_costs  # alias for callers importing `parse`


def parse_all_costs(receipts_dir: str | Path) -> list[LedgerRow]:
    d = Path(receipts_dir)
    rows: list[LedgerRow] = []
    if d.is_dir():
        for f in sorted(d.glob("issue-*.md")):
            rows.extend(parse_costs(f))
    return rows


# ── Queries ───────────────────────────────────────────────────────────────


def sum_by_session(rows: list[LedgerRow], session_id: str) -> LedgerRow:
    agg = LedgerRow(session=session_id)
    for r in rows:
        if r.session == session_id:
            agg.input += r.input
            agg.cache_create += r.cache_create
            agg.cache_read += r.cache_read
            agg.output += r.output
    agg.new_work = agg.expected_new_work
    return agg


def find_by_cost_key(rows: list[LedgerRow], cost_key: str) -> list[LedgerRow]:
    return [r for r in rows if r.cost_key == cost_key]


def resolve_receipt(receipts_dir: str | Path, issue_number: str) -> str:
    """The receipt path a cost row for issue N belongs in: an existing
    `issue-N.md` / `issue-N-<slug>.md` (first, deterministically, if several),
    else the slugless `issue-N.md` create-if-absent default."""
    n = issue_number.lstrip("#")
    d = Path(receipts_dir)
    pat = re.compile(rf"^issue-{re.escape(n)}(?:-[a-z0-9]+(?:-[a-z0-9]+)*)?\.md$")
    if d.is_dir():
        matches = sorted(p.name for p in d.iterdir() if p.is_file() and pat.match(p.name))
        if matches:
            return str(d / matches[0])
    return str(d / f"issue-{n}.md")


# ── Append ────────────────────────────────────────────────────────────────


def _safe_cell(s: str) -> str:
    cleaned = "".join(ch for ch in s if ch.isprintable() and ch != "|")
    if "\\" in cleaned:
        cleaned = cleaned.split("\\", 1)[0]
    return cleaned.strip()


def append_row(path: str | Path, row: LedgerRow) -> None:
    """Append `row` to <path>'s Costs sub-table. Recomputes `new_work` and
    looks up `cost_usd`; creates the receipt / section if needed."""
    row.new_work = row.expected_new_work
    if row.cost_usd is None:
        row.cost_usd = compute_cost_usd(
            row.model, row.input, row.cache_create, row.cache_read, row.output
        )
    cells = row.to_cells()
    cells[-1] = _safe_cell(cells[-1])[:80]
    row_line = "| " + " | ".join(cells) + " |"
    rio.write_row(path, rio.COSTS_SUBHEADING, COST_HEADER, COST_SEPARATOR, row_line)


# ── Validate ──────────────────────────────────────────────────────────────


def _validate_row_cells(
    cells: list[str], line_no: int, name: str, issue_n: str | None
) -> tuple[list[str], str | None]:
    violations: list[str] = []
    if len(cells) != 12:
        violations.append(f"{name}:{line_no} — row has {len(cells)} cells, expected 12")
        return violations, None
    cost_key, agent, session, issue, model, i, cc, cr, o, nw, cost, _note = cells

    if not cost_key:
        violations.append(f"{name}:{line_no} — empty cost-key")
        return violations, None
    if not agent or not session or not issue:
        violations.append(f"{name} — row '{cost_key}' has empty agent/session/issue field")
    if issue and not _ISSUE_RE.match(issue):
        violations.append(f"{name} — row '{cost_key}' issue '{issue}' must look like '#123'")
    elif issue and issue_n is not None and issue != issue_n:
        violations.append(
            f"{name} — row '{cost_key}' issue '{issue}' does not match this receipt's "
            f"issue '{issue_n}' (a cost row lives in the receipt for its own issue)"
        )

    token_cells = {"input": i, "cache_create": cc, "cache_read": cr, "output": o, "new_work": nw}
    if not all(_INT_RE.match(v or "") and int(v) >= 0 for v in token_cells.values()):
        violations.append(
            f"{name} — row '{cost_key}' has non-integer or negative token counts "
            f"(input={i}, cache_create={cc}, cache_read={cr}, output={o}, new_work={nw})"
        )
        return violations, cost_key

    expected_nw = int(i) + int(cc) + int(o)
    if int(nw) != expected_nw:
        violations.append(
            f"{name} — row '{cost_key}' has new_work={nw} but "
            f"input+cache_create+output={expected_nw} "
            f"(cache_read={cr} is tracked but excluded from new_work)"
        )

    if cost and not _FLOAT_RE.match(cost):
        violations.append(f"{name} — row '{cost_key}' has non-numeric cost_usd '{cost}'")
    elif cost and float(cost) < 0:
        violations.append(f"{name} — row '{cost_key}' has negative cost_usd '{cost}'")
    elif not cost and model:
        violations.append(
            f"{name} — row '{cost_key}' names model '{model}' but has empty cost_usd "
            f"(add a `rate {model} ...` row to "
            f".governance/conf/governance-kit/audit/agent-token-accounting.conf or backfill the cell)"
        )

    return violations, cost_key


def validate(path: str | Path) -> list[str]:
    """Validate one receipt's `### Costs` sub-table."""
    p = Path(path)
    if not p.is_file():
        return []
    name = p.name
    lines = p.read_text().splitlines()
    region = rio.subtable_region(lines, rio.COSTS_SUBHEADING)
    if region is None:
        return []
    issue_n = _issue_from_name(name)

    violations: list[str] = []
    cost_keys: dict[str, int] = {}
    for idx in range(*region):
        cells = rio.parse_cells(lines[idx])
        if cells is None or rio.is_header_or_separator(cells, "cost-key"):
            continue
        v, key = _validate_row_cells(cells, idx + 1, name, issue_n)
        violations.extend(v)
        if key:
            cost_keys[key] = cost_keys.get(key, 0) + 1

    for key, count in cost_keys.items():
        if count > 1:
            violations.append(f"{name} — cost-key '{key}' appears {count} times (must be unique)")
    return violations


def validate_dir(receipts_dir: str | Path) -> list[str]:
    """Validate every receipt's Costs sub-table plus global cost-key uniqueness."""
    d = Path(receipts_dir)
    if not d.is_dir():
        return []
    violations: list[str] = []
    seen: dict[str, str] = {}
    for f in sorted(d.glob("issue-*.md")):
        violations.extend(validate(f))
        for row in parse_costs(f):
            if not row.cost_key:
                continue
            if row.cost_key in seen and seen[row.cost_key] != f.name:
                violations.append(
                    f"receipts — cost-key '{row.cost_key}' appears in both "
                    f"{seen[row.cost_key]} and {f.name} (must be globally unique)"
                )
            else:
                seen.setdefault(row.cost_key, f.name)
    return violations


# ── CLI ───────────────────────────────────────────────────────────────────


def _die(msg: str) -> None:
    print(f"ledger: {msg}", file=sys.stderr)
    sys.exit(2)


def _cmd_resolve_receipt(args: list[str]) -> int:
    if len(args) != 2:
        _die("resolve-receipt takes: <receipts_dir> <issue_number>")
    print(resolve_receipt(args[0], args[1]))
    return 0


def _cmd_sum_by_session(args: list[str]) -> int:
    if len(args) != 2:
        _die("sum-by-session takes: <receipts_dir> <session_id>")
    agg = sum_by_session(parse_all_costs(args[0]), args[1])
    print(f"{agg.input} {agg.cache_create} {agg.cache_read} {agg.output}")
    return 0


def _cmd_next_cost_index(args: list[str]) -> int:
    if len(args) != 2:
        _die("next-cost-index takes: <receipts_dir> <key_prefix>")
    rows = parse_all_costs(args[0])
    print(sum(1 for r in rows if r.cost_key.startswith(args[1])) + 1)
    return 0


def _cmd_append_row(args: list[str]) -> int:
    if len(args) != 11:
        _die(
            "append-row takes: <receipt> <cost_key> <agent> <session> <issue> "
            "<model> <input> <cache_create> <cache_read> <output> <note>"
        )
    (receipt, cost_key, agent, session, issue, model, inp, cc, cr, out, note) = args

    def to_int(s: str, label: str) -> int:
        if not _INT_RE.match(s) or int(s) < 0:
            _die(f"{label} must be a non-negative integer (got {s!r})")
        return int(s)

    append_row(receipt, LedgerRow(
        cost_key=cost_key, agent=agent, session=session, issue=issue, model=model,
        input=to_int(inp, "input"), cache_create=to_int(cc, "cache_create"),
        cache_read=to_int(cr, "cache_read"), output=to_int(out, "output"), note=note,
    ))
    return 0


def _cmd_validate(args: list[str]) -> int:
    if len(args) != 1:
        _die("validate takes: <receipt>")
    violations = validate(args[0])
    for v in violations:
        print(v)
    return 1 if violations else 0


def _cmd_validate_dir(args: list[str]) -> int:
    if len(args) != 1:
        _die("validate-dir takes: <receipts_dir>")
    violations = validate_dir(args[0])
    for v in violations:
        print(v)
    return 1 if violations else 0


def _cmd_find_by_cost_key(args: list[str]) -> int:
    if len(args) != 2:
        _die("find-by-cost-key takes: <receipts_dir> <cost_key>")
    hits = find_by_cost_key(parse_all_costs(args[0]), args[1])
    if len(hits) != 1:
        print(f"expected 1 row for cost-key '{args[1]}', found {len(hits)}", file=sys.stderr)
        return 2
    r = hits[0]
    cost = "-" if r.cost_usd is None else f"{r.cost_usd:.4f}"
    print(f"{r.input} {r.cache_create} {r.cache_read} {r.output} {r.new_work} {cost}")
    return 0


_COMMANDS = {
    "resolve-receipt": _cmd_resolve_receipt,
    "sum-by-session": _cmd_sum_by_session,
    "next-cost-index": _cmd_next_cost_index,
    "append-row": _cmd_append_row,
    "validate": _cmd_validate,
    "validate-dir": _cmd_validate_dir,
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
