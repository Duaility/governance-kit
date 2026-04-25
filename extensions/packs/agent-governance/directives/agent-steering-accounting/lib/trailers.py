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
_SCALAR_TRAILER_RE = re.compile(r"^([A-Za-z][A-Za-z0-9-]*):[ \t]*(.*)$")
_COUNT_BREAKDOWN_RE = re.compile(r"^([a-z][a-z-]*=\d+)(,[a-z][a-z-]*=\d+)*$")


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


def extract_scalar_trailers(msg: str) -> dict[str, str]:
    """Last-wins parse for non-repeated trailers (Steer-Count / Types / Tiers)."""
    out: dict[str, str] = {}
    for line in msg.splitlines():
        m = _SCALAR_TRAILER_RE.match(line)
        if m:
            out[m.group(1)] = m.group(2).strip()
    return out


def _parse_count_breakdown(value: str) -> dict[str, int] | None:
    """Parse `key=N,key=N` into a dict, or `none` → {}. None on malformed."""
    if value == "none" or value == "":
        return {}
    if not _COUNT_BREAKDOWN_RE.match(value):
        return None
    out: dict[str, int] = {}
    for chunk in value.split(","):
        k, _, v = chunk.partition("=")
        out[k] = int(v)
    return out


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

    # Trailer → row direction: every Steer-Key has a row. Build a per-key
    # type/tier index for the summary cross-check below.
    matched_rows = []
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
        else:
            matched_rows.append(hits[0])

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

    # Summary trailers (Steer-Count / Steer-Types / Steer-Tiers) must agree
    # with the per-event Steer-Key count and the matched rows' types/tiers.
    # When no Steer-Key trailers are present, summary trailers are also
    # expected to be absent — both shapes equal "this commit had no events".
    scalars = extract_scalar_trailers(msg)
    has_count = "Steer-Count" in scalars
    has_types = "Steer-Types" in scalars
    has_tiers = "Steer-Tiers" in scalars

    if trailer_keys:
        if not (has_count and has_types and has_tiers):
            missing = [
                name for name, present in (
                    ("Steer-Count", has_count),
                    ("Steer-Types", has_types),
                    ("Steer-Tiers", has_tiers),
                ) if not present
            ]
            violations.append(
                f"{label} — Steer-Key trailers present but missing summary "
                f"trailer(s): {', '.join(missing)}"
            )
        else:
            count_val = scalars["Steer-Count"]
            if not count_val.isdigit():
                violations.append(
                    f"{label} — Steer-Count '{count_val}' must be a non-negative integer"
                )
            elif int(count_val) != len(trailer_keys):
                violations.append(
                    f"{label} — Steer-Count ({count_val}) != number of Steer-Key "
                    f"trailers ({len(trailer_keys)})"
                )

            types_parsed = _parse_count_breakdown(scalars["Steer-Types"])
            tiers_parsed = _parse_count_breakdown(scalars["Steer-Tiers"])
            if types_parsed is None:
                violations.append(
                    f"{label} — Steer-Types '{scalars['Steer-Types']}' is malformed "
                    f"(expected `key=N,key=N` or `none`)"
                )
            if tiers_parsed is None:
                violations.append(
                    f"{label} — Steer-Tiers '{scalars['Steer-Tiers']}' is malformed "
                    f"(expected `key=N,key=N` or `none`)"
                )

            # Cross-check breakdowns against matched rows when we have them.
            if matched_rows and types_parsed is not None:
                actual_types: dict[str, int] = {}
                for r in matched_rows:
                    actual_types[r.type] = actual_types.get(r.type, 0) + 1
                if types_parsed != actual_types:
                    violations.append(
                        f"{label} — Steer-Types {scalars['Steer-Types']} disagrees "
                        f"with matched rows' types {actual_types}"
                    )
            if matched_rows and tiers_parsed is not None:
                actual_tiers: dict[str, int] = {}
                for r in matched_rows:
                    actual_tiers[r.tier] = actual_tiers.get(r.tier, 0) + 1
                if tiers_parsed != actual_tiers:
                    violations.append(
                        f"{label} — Steer-Tiers {scalars['Steer-Tiers']} disagrees "
                        f"with matched rows' tiers {actual_tiers}"
                    )
    else:
        # No Steer-Key trailers — summary trailers must also be absent.
        for name in ("Steer-Count", "Steer-Types", "Steer-Tiers"):
            if name in scalars:
                violations.append(
                    f"{label} — {name} trailer present without any Steer-Key trailers"
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
