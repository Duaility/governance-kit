#!/usr/bin/env python3
"""Agent decision accounting ledger — parse, validate, find DECISIONS.md rows.

This module is the data-processing half of agent-decision-accounting. The
bash check.sh does commit walking and env plumbing; anything that
manipulates DECISIONS.md rows by name rather than by column index lives
here.

Schema:

    | decision-key | agent | session | issue | phase | question | lean | choice | diverged | cost-key | note |

- `decision-key` is unique within the file (append-only).
- `diverged` is one of `{agreed, overrode, reframed, deferred}`.
- `phase` is one of `{scoping, plan-review, pr-review, post-merge}`.
- `cost-key` is optional (empty or `-` means not linked); if present it
  should resolve to a row in COSTS.md (cross-check is the check.sh job,
  not this module's — it doesn't know COSTS.md's schema).

Stdlib-only. Runtime-agnostic: rows are authored by the agent at
question-time, so there is no per-runtime transcript reader.

CLI shims (called from bash):

    python3 ledger.py validate <ledger>
        → prints one violation per line; exits non-zero if any.

    python3 ledger.py find-by-decision-key <ledger> <decision_key>
        → prints "<diverged> <cost_key>"  (cost_key printed as "-" if empty)
          exits 2 on miss or duplicate (with count reported on stderr).
"""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from pathlib import Path


# ── Schema ────────────────────────────────────────────────────────────────

COLUMNS = (
    "decision_key",
    "agent",
    "session",
    "issue",
    "phase",
    "question",
    "lean",
    "choice",
    "diverged",
    "cost_key",
    "note",
)

DIVERGED_VOCAB = frozenset({"agreed", "overrode", "reframed", "deferred"})
PHASE_VOCAB = frozenset({"scoping", "plan-review", "pr-review", "post-merge"})

LEDGER_TEMPLATE = """\
<!-- DECISIONS.md — append-only human-vs-agent decision ledger -->
<!-- governance: allow-plan-captured -->

# DECISIONS.md

Append-only ledger of load-bearing human decisions during agent-driven
development. Rows are keyed by `decision-key`, mirrored into the
`Decision-Key:` commit trailer so the ledger survives squash merges.

**Do not** rewrite or reorder rows. Validated by the
`agent-decision-accounting` governance directive.

## Ledger

| decision-key | agent | session | issue | phase | question | lean | choice | diverged | cost-key | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
"""


# ── Row model ─────────────────────────────────────────────────────────────


@dataclass
class LedgerRow:
    decision_key: str = ""
    agent: str = ""
    session: str = ""
    issue: str = ""
    phase: str = ""
    question: str = ""
    lean: str = ""
    choice: str = ""
    diverged: str = ""
    cost_key: str = ""
    note: str = ""


# ── Parse ─────────────────────────────────────────────────────────────────


_ISSUE_RE = re.compile(r"^#[1-9][0-9]*$")


def _parse_cells(line: str) -> list[str] | None:
    stripped = line.strip()
    if not stripped.startswith("|"):
        return None
    parts = [c.strip() for c in stripped.split("|")[1:-1]]
    return parts or None


def _is_header_or_separator(cells: list[str]) -> bool:
    if not cells:
        return True
    first = cells[0]
    if first == "decision-key":
        return True
    if first == "" or re.fullmatch(r"-+", first or ""):
        return True
    if all(c == "" or re.fullmatch(r"-+", c) for c in cells):
        return True
    return False


def parse(path: str | Path) -> list[LedgerRow]:
    """Parse all data rows. Strict on column count — 11 columns required."""
    p = Path(path)
    if not p.is_file():
        return []
    rows: list[LedgerRow] = []
    for line in p.read_text().splitlines():
        cells = _parse_cells(line)
        if cells is None or _is_header_or_separator(cells):
            continue
        if len(cells) != 11:
            # Parser is tolerant — validator reports the shape error.
            continue
        (dkey, agent, session, issue, phase, question, lean, choice,
         diverged, cost_key, note) = cells
        rows.append(
            LedgerRow(
                decision_key=dkey,
                agent=agent,
                session=session,
                issue=issue,
                phase=phase,
                question=question,
                lean=lean,
                choice=choice,
                diverged=diverged,
                cost_key=cost_key,
                note=note,
            )
        )
    return rows


# ── Queries ───────────────────────────────────────────────────────────────


def find_by_decision_key(rows: list[LedgerRow], decision_key: str) -> list[LedgerRow]:
    return [r for r in rows if r.decision_key == decision_key]


# ── Validate ──────────────────────────────────────────────────────────────


def validate(path: str | Path) -> list[str]:
    """Walk the ledger, return violation strings.

    Checks:
        - Every data row has exactly 11 cells.
        - decision-key non-empty and unique across the file.
        - agent / session / issue non-empty; issue matches `#N`.
        - phase ∈ PHASE_VOCAB.
        - diverged ∈ DIVERGED_VOCAB.
    """
    p = Path(path)
    if not p.is_file():
        return []

    violations: list[str] = []
    decision_keys: dict[str, int] = {}

    for line_no, line in enumerate(p.read_text().splitlines(), start=1):
        cells = _parse_cells(line)
        if cells is None or _is_header_or_separator(cells):
            continue
        if len(cells) != 11:
            violations.append(
                f"DECISIONS.md:{line_no} — row has {len(cells)} cells, expected 11"
            )
            continue

        (dkey, agent, session, issue, phase, _q, _lean, _choice,
         diverged, _cost_key, _note) = cells

        if not dkey:
            violations.append(f"DECISIONS.md:{line_no} — empty decision-key")
            continue
        if not agent or not session or not issue:
            violations.append(
                f"DECISIONS.md — row '{dkey}' has empty agent/session/issue field"
            )
        if issue and not _ISSUE_RE.match(issue):
            violations.append(
                f"DECISIONS.md — row '{dkey}' issue '{issue}' must look like '#123'"
            )
        if phase and phase not in PHASE_VOCAB:
            violations.append(
                f"DECISIONS.md — row '{dkey}' phase '{phase}' not in "
                f"{{{', '.join(sorted(PHASE_VOCAB))}}}"
            )
        if not diverged:
            violations.append(
                f"DECISIONS.md — row '{dkey}' has empty diverged (must be one of "
                f"{{{', '.join(sorted(DIVERGED_VOCAB))}}})"
            )
        elif diverged not in DIVERGED_VOCAB:
            violations.append(
                f"DECISIONS.md — row '{dkey}' diverged '{diverged}' not in "
                f"{{{', '.join(sorted(DIVERGED_VOCAB))}}}"
            )

        decision_keys[dkey] = decision_keys.get(dkey, 0) + 1

    for key, count in decision_keys.items():
        if count > 1:
            violations.append(
                f"DECISIONS.md — decision-key '{key}' appears {count} times "
                f"(must be unique, append-only)"
            )

    return violations


# ── CLI ───────────────────────────────────────────────────────────────────


def _cmd_validate(args: list[str]) -> int:
    if len(args) != 1:
        _die("validate takes: <ledger>")
    violations = validate(args[0])
    for v in violations:
        print(v)
    return 1 if violations else 0


def _cmd_find_by_decision_key(args: list[str]) -> int:
    if len(args) != 2:
        _die("find-by-decision-key takes: <ledger> <decision_key>")
    rows = parse(args[0])
    hits = find_by_decision_key(rows, args[1])
    if len(hits) != 1:
        print(
            f"expected 1 row for decision-key '{args[1]}', found {len(hits)}",
            file=sys.stderr,
        )
        return 2
    r = hits[0]
    cost_key = r.cost_key if r.cost_key and r.cost_key != "-" else "-"
    print(f"{r.diverged} {cost_key}")
    return 0


def _die(msg: str) -> None:
    print(f"ledger: {msg}", file=sys.stderr)
    sys.exit(2)


_COMMANDS = {
    "validate": _cmd_validate,
    "find-by-decision-key": _cmd_find_by_decision_key,
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
