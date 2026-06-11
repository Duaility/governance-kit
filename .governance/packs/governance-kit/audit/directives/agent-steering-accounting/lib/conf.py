#!/usr/bin/env python3
"""Per-repo configuration overlay for the agent-steering-accounting directive.

Mirrors the bash `conf_list` / `conf_get` helpers in lib.sh so the Python
classifier honors the same config a target repo edits for every other
directive. Reads the user-owned overlay
`.governance/conf/agent-steering-accounting.conf` (never clobbered by
`governance pack update`) layered over the pack-owned `defaults.conf` that
ships beside this directive.

Effective list = defaults.conf, then the overlay applied:
  - a bare line ADDS an item,
  - `!item` REMOVES a default (gitignore-style negation; internal whitespace is
    normalized so a single-spaced overlay line matches a column-aligned
    default),
  - `KEY=value` overrides a scalar (env `GOVERNANCE_<KEY>` still wins; scalars
    are read from the overlay only — the code default is the baked fallback).

Stdlib-only.
"""

from __future__ import annotations

import os
import re

_DIRECTIVE = "agent-steering-accounting"
# User overlay, relative to the repo root. The pre-commit hook and run.sh both
# invoke with the repo root as CWD; the walk-up keeps it correct from a
# subdirectory too.
_OVERLAY_REL = os.path.join(".governance", "conf", _DIRECTIVE + ".conf")
# Pack-owned default list, shipped beside this directive (lib/ -> directive/).
_DEFAULTS = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), os.pardir, "defaults.conf"
)

_SCALAR_RE = re.compile(r"^[A-Z_]+=")


def _find_overlay() -> str | None:
    d = os.path.abspath(os.getcwd())
    while True:
        candidate = os.path.join(d, _OVERLAY_REL)
        if os.path.isfile(candidate):
            return candidate
        parent = os.path.dirname(d)
        if parent == d:
            return None
        d = parent


def _strip(raw: str) -> str:
    """Drop an inline `#` comment and trim surrounding whitespace."""
    return raw.split("#", 1)[0].strip()


def _norm(s: str) -> str:
    """Trim + collapse internal whitespace runs to one space (membership key)."""
    return " ".join(s.split())


def effective_list() -> list[str]:
    """Return the defaults.conf list with the overlay's adds/removals applied,
    in declared order (defaults first, then overlay additions), deduped by
    whitespace-normalized key. Mirrors `conf_list` in lib.sh."""
    removed: set[str] = set()
    adds: list[str] = []
    overlay = _find_overlay()
    if overlay is not None:
        with open(overlay, encoding="utf-8") as fh:
            for raw in fh:
                line = _strip(raw)
                if not line or _SCALAR_RE.match(line):
                    continue
                if line.startswith("!"):
                    item = _norm(line[1:])
                    if item:
                        removed.add(item)
                else:
                    if line.startswith("+"):  # optional explicit add marker
                        line = line[1:].strip()
                    if line:
                        adds.append(line)

    out: list[str] = []
    emitted: set[str] = set()

    def _consider(line: str) -> None:
        key = _norm(line)
        if key in removed or key in emitted:
            return
        emitted.add(key)
        out.append(line)

    if os.path.isfile(_DEFAULTS):
        with open(_DEFAULTS, encoding="utf-8") as fh:
            for raw in fh:
                line = _strip(raw)
                if not line or _SCALAR_RE.match(line):
                    continue
                _consider(line)
    for line in adds:
        _consider(line)
    return out


def get_int(key: str, default: int) -> int:
    """Scalar override: env `GOVERNANCE_<KEY>` > overlay `KEY=` line > default.
    Raises ValueError on a non-integer value — a bad knob fails loudly rather
    than silently reverting to the default. Mirrors `conf_get` + int parse."""
    env = os.environ.get("GOVERNANCE_" + key)
    raw = env
    if raw is None:
        overlay = _find_overlay()
        if overlay is not None:
            with open(overlay, encoding="utf-8") as fh:
                for line in fh:
                    if line.startswith(key + "="):
                        raw = line.split("=", 1)[1]
                        break
    if raw is None:
        return default
    raw = raw.split("#", 1)[0].strip()
    try:
        return int(raw)
    except ValueError:
        src = "GOVERNANCE_" + key if env is not None else key
        raise ValueError(
            f"{_DIRECTIVE}: {src} must be an integer, got {raw!r}"
        ) from None


def lexical_fallback_re() -> "re.Pattern[str]":
    """Compile the effective trigger-phrase list into the anchored, word-bounded,
    case-insensitive fallback regex. An empty list yields a never-match pattern
    so a fully-cleared overlay disables the lexical fallback rather than matching
    every message."""
    phrases = effective_list()
    if not phrases:
        return re.compile(r"(?!)")
    alt = "|".join(re.escape(p) for p in phrases)
    return re.compile(r"^(" + alt + r")\b", re.IGNORECASE)
