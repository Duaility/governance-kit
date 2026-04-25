#!/usr/bin/env python3
"""Commit-trailer parsing for agent-steering-accounting.

Steer-Key trailers stamped onto agent-authored commits with detected
steering events. Multiple `Steer-Key:` trailers per commit — one per row
in STEERING.md keyed by the same id.

    Steer-Key: steer-<session-short>-<epoch>-1
    Steer-Key: steer-<session-short>-<epoch>-2
    ...

A commit with zero detected events carries no `Steer-Key:` trailer; the
directive is satisfied by the absence.

CLI:

    python3 trailers.py extract [msg_file | -]
        → prints every Steer-Key trailer value, one per line.

    python3 trailers.py validate <label> <ledger> <commit-prefix> [msg_file | -]
        → cross-checks: every Steer-Key trailer on the commit message has
          a row in <ledger> with that exact steer-key, AND every row whose
          steer-key starts with <commit-prefix> has a Steer-Key trailer
          (i.e. row-trailer symmetry for this commit). <commit-prefix> is
          `steer-<session-short>-<epoch>` (no row index). When commit-prefix
          is the literal string `-`, only the trailer→row direction is
          checked (used by Mode B for historical commits where deriving the
          prefix is ambiguous).
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

# ledger.py sits next to this file; relative import works under
# `python3 trailers.py …` because the parent dir is on sys.path.
try:
    from ledger import parse as parse_ledger, find_by_steer_key  # type: ignore
except ModuleNotFoundError:  # pragma: no cover
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from ledger import parse as parse_ledger, find_by_steer_key  # type: ignore


_STEER_KEY_TRAILER_RE = re.compile(r"^Steer-Key:[ \t]*(.+?)[ \t]*$")


def extract_steer_keys(msg: str) -> list[str]:
    """Return every value of `Steer-Key:` trailers on the message, in order.

    Unlike most git trailers (last-wins), Steer-Key is naturally repeated —
    one trailer per ledger row. We keep all occurrences."""
    keys: list[str] = []
    for line in msg.splitlines():
        m = _STEER_KEY_TRAILER_RE.match(line)
        if m:
            keys.append(m.group(1).strip())
    return keys


def validate(
    msg: str,
    label: str,
    ledger_path: str | Path,
    commit_prefix: str | None,
) -> list[str]:
    """Cross-check trailers ↔ ledger rows for a single commit.

    `commit_prefix` is `steer-<session-short>-<epoch>` — every row in the
    ledger whose steer-key starts with this prefix is associated with this
    commit. None / "-" disables the row→trailer direction (Mode B).
    """
    violations: list[str] = []
    trailer_keys = extract_steer_keys(msg)

    # Reject duplicates within a single commit's trailers — the directive
    # contract is one trailer per row, no double-stamps.
    seen: dict[str, int] = {}
    for k in trailer_keys:
        seen[k] = seen.get(k, 0) + 1
    for k, count in seen.items():
        if count > 1:
            violations.append(
                f"{label} — Steer-Key '{k}' appears {count} times in trailers (one per row)"
            )

    rows = parse_ledger(ledger_path)
    keys_in_ledger = {r.steer_key for r in rows}

    # Trailer → row direction: every Steer-Key has a row.
    for k in trailer_keys:
        hits = find_by_steer_key(rows, k)
        if len(hits) == 0:
            violations.append(
                f"{label} — Steer-Key '{k}' has no matching row in STEERING.md"
            )
        elif len(hits) > 1:
            violations.append(
                f"{label} — Steer-Key '{k}' has {len(hits)} matching rows (must be unique)"
            )

    # Row → trailer direction: every row whose key starts with this commit's
    # prefix has a corresponding trailer. Skipped for Mode B (commit_prefix
    # is None / "-") because we can't recover the prefix for historical
    # commits without already trusting the trailers.
    if commit_prefix and commit_prefix != "-":
        trailer_set = set(trailer_keys)
        for k in keys_in_ledger:
            if k.startswith(commit_prefix + "-") and k not in trailer_set:
                violations.append(
                    f"{label} — STEERING.md has row '{k}' for this commit but "
                    f"no matching Steer-Key: trailer"
                )

    return violations


# ── CLI ───────────────────────────────────────────────────────────────────


def _read_msg(path_or_dash: str) -> str:
    if path_or_dash == "-":
        return sys.stdin.read()
    return Path(path_or_dash).read_text()


def _cmd_extract(argv: list[str]) -> int:
    src = argv[0] if argv else "-"
    for k in extract_steer_keys(_read_msg(src)):
        print(k)
    return 0


def _cmd_validate(argv: list[str]) -> int:
    if len(argv) < 3:
        print(
            "trailers validate: <label> <ledger> <commit-prefix|-> [msg_file | -]",
            file=sys.stderr,
        )
        return 2
    label, ledger, commit_prefix = argv[0], argv[1], argv[2]
    msg_src = argv[3] if len(argv) > 3 else "-"
    msg = _read_msg(msg_src)
    prefix = None if commit_prefix in ("", "-") else commit_prefix
    violations = validate(msg, label, ledger, prefix)
    for v in violations:
        print(v)
    return 1 if violations else 0


def main(argv: list[str]) -> int:
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        return 0 if argv else 2
    cmd, rest = argv[0], argv[1:]
    if cmd == "extract":
        return _cmd_extract(rest)
    if cmd == "validate":
        return _cmd_validate(rest)
    print(f"trailers: unknown command {cmd!r}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
