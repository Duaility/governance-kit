#!/usr/bin/env python3
"""Deterministic CONSTITUTION.md text surgery shared by the lifecycle engines.

A directive's subsection in CONSTITUTION.md is exactly its `directives/<id>/
constitution.md` payload: a Markdown block that opens with `### <directive-id>`
and runs until the next `### ` / `## ` heading. `pack remove`, `reset`, and
`init` all add, replace, or strip these blocks; doing it by prose `Edit` is the
drift surface this module removes. Every function is a pure string→string
transform — the apply engines own the file I/O — so they are trivially testable
and never depend on the working tree.

The heading text is matched exactly (`### secrets-hygiene` with nothing but
optional trailing whitespace after the id), so a directive id that is a prefix
of another (`doc-freshness` vs `doc-freshness-extra`) never aliases.
"""

from __future__ import annotations

import re


def _heading_re(directive_id: str) -> re.Pattern[str]:
    return re.compile(rf"^###[ \t]+{re.escape(directive_id)}[ \t]*$")


_ANY_HEADING_RE = re.compile(r"^(#{2,3})[ \t]+\S")


def find_subsection(text: str, directive_id: str) -> tuple[int, int] | None:
    """Return the `[start, end)` line-index span of the directive's `### <id>`
    subsection (including trailing blank lines up to the next heading), or None
    when the subsection is absent."""
    lines = text.splitlines(keepends=True)
    head = _heading_re(directive_id)
    start = next((i for i, ln in enumerate(lines) if head.match(ln)), None)
    if start is None:
        return None
    end = len(lines)
    for j in range(start + 1, len(lines)):
        if _ANY_HEADING_RE.match(lines[j]):
            end = j
            break
    return start, end


def strip_directive_subsection(text: str, directive_id: str) -> tuple[str, bool]:
    """Remove the directive's subsection. Returns `(new_text, removed?)`.

    Removes the `### <id>` heading through everything up to (not including) the
    next heading — i.e. the trailing blank line(s) that separated it from the
    following subsection go too, so no double blank is left behind. A no-op
    (text unchanged, `removed=False`) when the subsection is absent.
    """
    span = find_subsection(text, directive_id)
    if span is None:
        return text, False
    start, end = span
    lines = text.splitlines(keepends=True)
    del lines[start:end]
    return "".join(lines), True


def upsert_directive_subsection(text: str, directive_id: str, subsection: str) -> tuple[str, str]:
    """Replace the directive's subsection with `subsection`, or insert it if absent.

    Returns `(new_text, action)` where action is `replaced` or `inserted`.
    Insertion lands at the end of the `## Directives` section (before the next
    `## ` heading), matching where init appends new directive blocks. `subsection`
    is normalized to end with exactly one trailing blank line so adjacent blocks
    stay one blank line apart.
    """
    block = subsection.rstrip("\n") + "\n\n"
    lines = text.splitlines(keepends=True)
    span = find_subsection(text, directive_id)
    if span is not None:
        start, end = span
        lines[start:end] = [block]
        return "".join(lines), "replaced"

    # Insert at the end of the `## Directives` section.
    dir_start = next(
        (i for i, ln in enumerate(lines) if re.match(r"^##[ \t]+Directives[ \t]*$", ln)),
        None,
    )
    if dir_start is None:
        # No Directives section — append at end of document.
        tail = "" if text.endswith("\n") else "\n"
        return text + tail + "\n" + block, "inserted"
    insert_at = len(lines)
    for j in range(dir_start + 1, len(lines)):
        if re.match(r"^##[ \t]+\S", lines[j]):
            insert_at = j
            break
    lines[insert_at:insert_at] = [block]
    return "".join(lines), "inserted"


def append_evolution_log(text: str, entry: str) -> str:
    """Append a one-line entry under the `## Evolution Log` section.

    The entry is added after the last existing log line (or right after the
    section's HTML-comment format hint when the log is empty), preserving the
    append-only discipline the doc-integrity directive enforces. `entry` should
    be the full bullet line without a trailing newline.
    """
    lines = text.splitlines(keepends=True)
    log_start = next(
        (i for i, ln in enumerate(lines) if re.match(r"^##[ \t]+Evolution Log[ \t]*$", ln)),
        None,
    )
    bullet = entry.rstrip("\n") + "\n"
    if log_start is None:
        tail = "" if text.endswith("\n") else "\n"
        return text + tail + "\n## Evolution Log\n\n" + bullet
    # End of the Evolution Log section = next `## ` heading or EOF.
    section_end = len(lines)
    for j in range(log_start + 1, len(lines)):
        if re.match(r"^##[ \t]+\S", lines[j]):
            section_end = j
            break
    # Insert after the last non-blank line within the section.
    insert_at = log_start + 1
    for j in range(log_start + 1, section_end):
        if lines[j].strip():
            insert_at = j + 1
    lines[insert_at:insert_at] = [bullet]
    return "".join(lines)
