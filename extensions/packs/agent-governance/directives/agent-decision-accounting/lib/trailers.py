#!/usr/bin/env python3
"""Commit-trailer parsing for agent-decision-accounting.

Trailers stamped onto commits that reference load-bearing decisions:

    Decision-Key:      comma-separated list of decision-keys, each
                       resolving to exactly one DECISIONS.md row.
    Decision-Diverged: "<M>/<N>" where N == count of listed keys and
                       M == count of listed rows whose `diverged` value
                       is not `agreed`.

Both trailers are optional (a commit that recorded no load-bearing
decisions omits them). They are mutually required — if one is present,
the other must be too.

This module is the data-processing side of the directive script's
Mode A / Mode B validators — bash feeds a commit message on stdin and
a snapshot of the matching ledger rows on argv; Python returns one
violation per line.

CLI:

    python3 trailers.py validate <label> <ledger_snapshot_path> [msg_file | -]

        <ledger_snapshot_path>: path to a small TSV emitted by the bash
        caller. One line per Decision-Key listed in the trailer:

            <decision_key>\\t<diverged_or_MISSING>\\t<cost_key_or_->

        `MISSING` in column 2 signals "key was in the trailer but not
        found in DECISIONS.md" (or found more than once) — bash caller
        reports the presence count separately; trailers.py just flags
        the missing cross-ref.

        Stdin or file → commit message. Prints one violation per line;
        exits 1 if any, 0 if clean.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


_DIVERGED_COUNTER_RE = re.compile(r"^(\d+)/(\d+)$")
_DECISION_KEY_RE = re.compile(r"^[A-Za-z0-9._-]+$")


def parse(msg: str) -> dict[str, str]:
    """Return a dict of trailer key → value. Last-write-wins per key to
    match git-interpret-trailers semantics."""
    out: dict[str, str] = {}
    for line in msg.splitlines():
        m = re.match(r"^([A-Za-z][A-Za-z0-9-]*):[ \t]*(.*)$", line)
        if m:
            out[m.group(1)] = m.group(2).strip()
    return out


def _split_keys(raw: str) -> list[str]:
    return [k.strip() for k in raw.split(",") if k.strip()]


def validate(
    msg: str,
    label: str,
    snapshot: list[tuple[str, str, str]],
) -> list[str]:
    """Validate Decision-Key + Decision-Diverged trailers.

    Args:
        msg: the full commit message.
        label: prefix for violation strings (e.g. "pending commit" or SHA).
        snapshot: one tuple per key listed in the Decision-Key trailer,
            in order: (decision_key, diverged_or_MISSING, cost_key_or_-).

    Returns a list of violation strings (empty if clean).
    """
    trailers = parse(msg)
    dkey_raw = trailers.get("Decision-Key", "")
    dcounter = trailers.get("Decision-Diverged", "")

    # Both absent → commit recorded no load-bearing decisions. Clean.
    if not dkey_raw and not dcounter:
        return []

    violations: list[str] = []

    # One present, other absent → inconsistent.
    if dkey_raw and not dcounter:
        violations.append(
            f"{label} — has Decision-Key: trailer but missing Decision-Diverged: trailer"
        )
        return violations
    if dcounter and not dkey_raw:
        violations.append(
            f"{label} — has Decision-Diverged: trailer but missing Decision-Key: trailer"
        )
        return violations

    keys = _split_keys(dkey_raw)
    if not keys:
        violations.append(f"{label} — Decision-Key: trailer is empty")
        return violations

    # Shape-check each key id.
    for k in keys:
        if not _DECISION_KEY_RE.match(k):
            violations.append(
                f"{label} — Decision-Key '{k}' has invalid characters "
                f"(expected [A-Za-z0-9._-]+)"
            )

    # Duplicate keys inside the same trailer are a bug — each row is
    # supposed to be referenced once.
    seen: dict[str, int] = {}
    for k in keys:
        seen[k] = seen.get(k, 0) + 1
    for k, count in seen.items():
        if count > 1:
            violations.append(
                f"{label} — Decision-Key '{k}' listed {count} times in trailer "
                f"(each key must be unique within a commit)"
            )

    # Parse Decision-Diverged counter.
    m = _DIVERGED_COUNTER_RE.match(dcounter)
    if not m:
        violations.append(
            f"{label} — Decision-Diverged '{dcounter}' must look like 'M/N' "
            f"(e.g. '2/5')"
        )
        return violations
    declared_M = int(m.group(1))
    declared_N = int(m.group(2))

    unique_keys = list(seen.keys())
    if declared_N != len(unique_keys):
        violations.append(
            f"{label} — Decision-Diverged denominator is {declared_N} but "
            f"Decision-Key lists {len(unique_keys)} unique key(s)"
        )

    # Snapshot has one entry per *listed* key order from bash — dedupe here.
    snapshot_by_key = {row[0]: row for row in snapshot}

    actual_diverged_count = 0
    for k in unique_keys:
        entry = snapshot_by_key.get(k)
        if entry is None or entry[1] == "MISSING":
            violations.append(
                f"{label} — Decision-Key '{k}' has no matching row in DECISIONS.md"
            )
            continue
        diverged_value = entry[1]
        if diverged_value != "agreed":
            actual_diverged_count += 1

    # Only cross-check the numerator when every key actually resolved —
    # otherwise the count is meaningless and the MISSING violations above
    # are the real issue.
    resolved_all = all(
        snapshot_by_key.get(k) is not None
        and snapshot_by_key[k][1] != "MISSING"
        for k in unique_keys
    )
    if resolved_all and declared_M != actual_diverged_count:
        violations.append(
            f"{label} — Decision-Diverged numerator is {declared_M} but "
            f"{actual_diverged_count} of the listed rows are non-'agreed'"
        )

    return violations


# ── CLI ───────────────────────────────────────────────────────────────────


def _read_snapshot(path: str) -> list[tuple[str, str, str]]:
    p = Path(path)
    if not p.is_file():
        return []
    out: list[tuple[str, str, str]] = []
    for line in p.read_text().splitlines():
        parts = line.split("\t")
        if len(parts) != 3:
            continue
        out.append((parts[0], parts[1], parts[2]))
    return out


def _cmd_validate(args: list[str]) -> int:
    if len(args) < 2:
        _die("validate takes: <label> <snapshot_path> [msg_file | -]")
    label = args[0]
    snapshot_path = args[1]
    snapshot = _read_snapshot(snapshot_path)

    if len(args) >= 3 and args[2] != "-":
        msg = Path(args[2]).read_text()
    else:
        msg = sys.stdin.read()

    violations = validate(msg, label, snapshot)
    for v in violations:
        print(v)
    return 1 if violations else 0


def _die(msg: str) -> None:
    print(f"trailers: {msg}", file=sys.stderr)
    sys.exit(2)


_COMMANDS = {"validate": _cmd_validate}


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
