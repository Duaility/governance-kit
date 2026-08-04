#!/usr/bin/env python3
"""Read-only accounting report across per-issue receipts (issue #201).

Accounting rows live in each issue's `receipts/issue-<N>.md` under an
`## Accounting` section rather than a central COSTS.md / STEERING.md. That keeps
the write path conflict-free, but cross-issue questions ("what did we spend in
total?", "which issues cost the most?") no longer have one file to read. This
script answers them by walking every receipt's `### Costs` / `### Steering`
sub-tables and aggregating — so nobody is tempted to reintroduce a central
ledger just to run a sum.

**Off the commit path.** Issue #355 rewrote the directive's commit-time stack in
bash + POSIX awk; this reporter is the one piece that stayed python, because it
is a human-invoked query tool that no hook, check, or adapter calls. It is
stdlib-only and self-contained (it carries its own row parser rather than
importing one, since the modules it used to import are gone).

Row versions it reads, dispatched on cell count:

    v5 = 17 columns (…, cum-*, source, note) — `cost-usd` is whatever the
         harness reported, and is frequently EMPTY. A blank cost contributes
         nothing to the totals; the row still counts as an accounted commit.
    v4 = 16 columns (…, cum-*, note)
    v3 = 12 columns (no cum-*)

CLI:

    python3 report.py <receipts_dir> [--json]

        Default: a human-readable per-issue table plus grand totals.
        --json:  the same data as a JSON object, for piping into other tools.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

sys.dont_write_bytecode = True  # don't litter the consumer repo with __pycache__

ACCOUNTING_HEADING = "## Accounting"
COSTS_SUBHEADING = "### Costs"
STEERING_SUBHEADING = "### Steering"

_RECEIPT_RE = re.compile(r"^issue-([1-9][0-9]*)(?:-[a-z0-9]+(?:-[a-z0-9]+)*)?\.md$")
_INT_RE = re.compile(r"^-?\d+$")
_FLOAT_RE = re.compile(r"^-?\d+(\.\d+)?$")


# ── Markdown region / row plumbing (mirrors lib/receipt.sh) ────────────────


def _parse_cells(line: str) -> list[str] | None:
    stripped = line.strip()
    if not stripped.startswith("|"):
        return None
    parts = [c.strip() for c in stripped.split("|")[1:-1]]
    return parts or None


def _is_header_or_separator(cells: list[str], first: str) -> bool:
    if not cells:
        return True
    if cells[0] in (first, ""):
        return True
    if re.fullmatch(r"-+", cells[0] or ""):
        return True
    return all(c == "" or re.fullmatch(r"-+", c) for c in cells)


def _subtable_rows(path: Path, subheading: str) -> list[list[str]]:
    """Cell-lists for the data rows of `## Accounting` → <subheading>."""
    lines = path.read_text().splitlines()
    in_acc = False
    in_sub = False
    out: list[list[str]] = []
    for line in lines:
        t = line.strip()
        if t == ACCOUNTING_HEADING:
            in_acc, in_sub = True, False
            continue
        if in_acc and (line.startswith("## ") or line.startswith("# ")):
            in_acc, in_sub = False, False
            continue
        if in_acc and line.startswith("### "):
            in_sub = t == subheading
            continue
        if in_acc and in_sub and t.startswith("|"):
            cells = _parse_cells(line)
            if cells is not None:
                out.append(cells)
    return out


def _to_int(s: str) -> int:
    return int(s) if _INT_RE.match(s or "") else 0


def _to_cost(s: str) -> float | None:
    s = (s or "").strip()
    if not s or not _FLOAT_RE.match(s):
        return None
    return float(s)


def cost_rows(path: Path) -> list[dict]:
    """The receipt's cost rows as dicts: new_work + cost_usd (None when blank)."""
    rows: list[dict] = []
    for cells in _subtable_rows(path, COSTS_SUBHEADING):
        if _is_header_or_separator(cells, "cost-key"):
            continue
        if len(cells) not in (12, 16, 17):
            continue
        rows.append({"new_work": _to_int(cells[9]), "cost_usd": _to_cost(cells[10])})
    return rows


def steering_rows(path: Path) -> list[list[str]]:
    """The receipt's steering rows — 7 = legacy v1, 9 = v2 (+ordinal/timestamp)."""
    return [
        cells
        for cells in _subtable_rows(path, STEERING_SUBHEADING)
        if not _is_header_or_separator(cells, "steer-key") and len(cells) in (7, 9)
    ]


# ── Aggregation ────────────────────────────────────────────────────────────


def collect(receipts_dir: str | Path) -> dict:
    d = Path(receipts_dir)
    per_issue: dict[str, dict] = {}
    if d.is_dir():
        for f in sorted(d.glob("issue-*.md")):
            m = _RECEIPT_RE.match(f.name)
            if not m:
                continue
            issue = f"#{m.group(1)}"
            entry = per_issue.setdefault(
                issue,
                {"receipt": f.name, "commits": 0, "new_work": 0,
                 "cost_usd": 0.0, "unpriced": 0, "steering": 0},
            )
            for row in cost_rows(f):
                entry["commits"] += 1
                entry["new_work"] += row["new_work"]
                if row["cost_usd"] is None:
                    entry["unpriced"] += 1
                else:
                    entry["cost_usd"] += row["cost_usd"]
            entry["steering"] += len(steering_rows(f))

    totals = {
        "issues": len(per_issue),
        "commits": sum(e["commits"] for e in per_issue.values()),
        "new_work": sum(e["new_work"] for e in per_issue.values()),
        "cost_usd": round(sum(e["cost_usd"] for e in per_issue.values()), 4),
        "unpriced": sum(e["unpriced"] for e in per_issue.values()),
        "steering": sum(e["steering"] for e in per_issue.values()),
    }
    for e in per_issue.values():
        e["cost_usd"] = round(e["cost_usd"], 4)
    return {"per_issue": per_issue, "totals": totals}


def _issue_sort_key(issue: str) -> int:
    return int(issue.lstrip("#"))


def render_text(data: dict) -> str:
    per_issue = data["per_issue"]
    totals = data["totals"]
    lines = []
    header = (
        f"{'issue':>7}  {'commits':>7}  {'new-work':>12}  {'cost-usd':>10}  "
        f"{'no-cost':>7}  {'steering':>8}"
    )
    lines.append(header)
    lines.append("-" * len(header))
    for issue in sorted(per_issue, key=_issue_sort_key):
        e = per_issue[issue]
        lines.append(
            f"{issue:>7}  {e['commits']:>7}  {e['new_work']:>12,}  "
            f"{e['cost_usd']:>10.4f}  {e['unpriced']:>7}  {e['steering']:>8}"
        )
    lines.append("-" * len(header))
    lines.append(
        f"{'TOTAL':>7}  {totals['commits']:>7}  {totals['new_work']:>12,}  "
        f"{totals['cost_usd']:>10.4f}  {totals['unpriced']:>7}  {totals['steering']:>8}"
    )
    lines.append("")
    lines.append(
        f"{totals['issues']} issue(s), {totals['commits']} accounted commit(s), "
        f"${totals['cost_usd']:.4f} reported."
    )
    if totals["unpriced"]:
        lines.append(
            f"{totals['unpriced']} row(s) carry no cost-usd — the harness reported "
            f"none and the kit does not estimate (issue #355)."
        )
    return "\n".join(lines)


def main(argv: list[str]) -> int:
    args = [a for a in argv if not a.startswith("--")]
    as_json = "--json" in argv
    if len(args) != 1 or argv[:1] in (["-h"], ["--help"]):
        print("report.py <receipts_dir> [--json]", file=sys.stderr)
        return 2
    data = collect(args[0])
    if as_json:
        print(json.dumps(data, indent=2, sort_keys=True))
    else:
        print(render_text(data))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
