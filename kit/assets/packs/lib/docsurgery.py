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

# A pack-group header is `## <owner>/<pack>` — a level-2 heading whose only token
# contains a slash. The other level-2 headings in CONSTITUTION.md (`## Directives`,
# `## Amendment process`, `## Evolution Log`, …) never do, so this discriminates a
# pack group from a major section without a hard-coded section list.
_PACK_HEADER_RE = re.compile(r"^##[ \t]+\S+/\S+[ \t]*$")
_DIRECTIVES_RE = re.compile(r"^##[ \t]+Directives[ \t]*$")
_L2_RE = re.compile(r"^##[ \t]+\S")


def _pack_header_re(pack_id: str) -> re.Pattern[str]:
    return re.compile(rf"^##[ \t]+{re.escape(pack_id)}[ \t]*$")


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


def _directives_region_end(lines: list[str]) -> int:
    """Index of the line that ends the Directives region — the first level-2
    heading after `## Directives` that is *not* a pack group (e.g. `## Amendment
    process`), or `len(lines)`. Pack-group headers live inside this region; a new
    one is created just before it."""
    dir_start = next((i for i, ln in enumerate(lines) if _DIRECTIVES_RE.match(ln)), None)
    if dir_start is None:
        return len(lines)
    for j in range(dir_start + 1, len(lines)):
        if _L2_RE.match(lines[j]) and not _PACK_HEADER_RE.match(lines[j]):
            return j
    return len(lines)


def render_pack_groups(groups: list[tuple[str, list[str]]]) -> str:
    """Render directive subsections grouped under `## <owner>/<pack>` headers.

    `groups` is `[(pack_id, [subsection, …]), …]` in display order. Each pack
    emits its `## <pack_id>` header followed by its directive subsections, one
    blank line between blocks. Shared by `init` assembly and the pack-aware
    upsert so both produce the same grouped structure.
    """
    out: list[str] = []
    for pack_id, subs in groups:
        out.append(f"## {pack_id}\n\n")
        for s in subs:
            out.append(s.rstrip("\n") + "\n\n")
    return "".join(out)


def upsert_directive_subsection(
    text: str, directive_id: str, subsection: str, pack_id: str | None = None
) -> tuple[str, str]:
    """Replace the directive's subsection with `subsection`, or insert it if absent.

    Returns `(new_text, action)` where action is `replaced` or `inserted`.
    `subsection` is normalized to end with exactly one trailing blank line so
    adjacent blocks stay one blank line apart.

    When `pack_id` is given (`<owner>/<pack>`), the subsection is homed under that
    pack's `## <owner>/<pack>` header — created at the end of the Directives region
    if absent — and any stray copy elsewhere in the document is first removed, so
    a re-pin relocates a previously-ungrouped subsection into its group. When
    `pack_id` is None, the legacy flat behaviour applies: replace in place, else
    append at the end of `## Directives`.
    """
    block = subsection.rstrip("\n") + "\n\n"

    if pack_id is None:
        lines = text.splitlines(keepends=True)
        span = find_subsection(text, directive_id)
        if span is not None:
            start, end = span
            lines[start:end] = [block]
            return "".join(lines), "replaced"
        dir_start = next((i for i, ln in enumerate(lines) if _DIRECTIVES_RE.match(ln)), None)
        if dir_start is None:
            # No Directives section — append at end of document.
            tail = "" if text.endswith("\n") else "\n"
            return text + tail + "\n" + block, "inserted"
        insert_at = len(lines)
        for j in range(dir_start + 1, len(lines)):
            if _L2_RE.match(lines[j]):
                insert_at = j
                break
        lines[insert_at:insert_at] = [block]
        return "".join(lines), "inserted"

    # Pack-group-aware: remove any existing copy (wherever it sits — this is what
    # relocates a previously-ungrouped subsection), then insert under the pack's
    # header. action reflects whether the directive already had an entry.
    text, removed = strip_directive_subsection(text, directive_id)
    action = "replaced" if removed else "inserted"
    lines = text.splitlines(keepends=True)
    header = _pack_header_re(pack_id)
    header_idx = next((i for i, ln in enumerate(lines) if header.match(ln)), None)
    if header_idx is not None:
        # Group spans from the header to the next level-2 heading (or EOF).
        group_end = len(lines)
        for j in range(header_idx + 1, len(lines)):
            if _L2_RE.match(lines[j]):
                group_end = j
                break
        # Insert in sorted position by directive id — init emits each pack's
        # directives `sorted`, so matching that keeps the two paths in lockstep
        # and makes a re-upsert idempotent rather than churning the order.
        insert_at = group_end
        for j in range(header_idx + 1, group_end):
            m = re.match(r"^###[ \t]+(\S+)", lines[j])
            if m and m.group(1) > directive_id:
                insert_at = j
                break
        lines[insert_at:insert_at] = [block]
        return "".join(lines), action
    # No header yet — create `## <pack_id>` at the end of the Directives region.
    region_end = _directives_region_end(lines)
    lines[region_end:region_end] = [f"## {pack_id}\n\n", block]
    return "".join(lines), action


def strip_marker_block(text: str, open_marker: str, close_marker: str) -> tuple[str, str, bool]:
    """Strip an HTML-comment-bounded block from `text` (the AGENTS.md directive
    block `uninstall` removes). Returns `(new_text, status, rest_unchanged)`:

      * Paired path — both markers present: delete the inclusive span plus one
        trailing blank line. status = `stripped`.
      * Opening-only path (pre-paired-marker installs): only `open_marker`
        present → strip from it up to (not including) the next `## ` heading or
        EOF. status = `unbounded-stripped`.
      * Neither present → status = `absent`, text unchanged.

    `rest_unchanged` reports whether every line outside the removed span is
    byte-identical pre/post — the caller aborts the uninstall if it is False
    (something other than the block would have changed).
    """
    lines = text.splitlines(keepends=True)
    open_i = next((i for i, ln in enumerate(lines) if open_marker in ln), None)
    if open_i is None:
        return text, "absent", True
    close_i = next((i for i, ln in enumerate(lines) if close_marker in ln), None)
    if close_i is not None and close_i >= open_i:
        end = close_i + 1
        if end < len(lines) and not lines[end].strip():
            end += 1
        status = "stripped"
    else:
        end = len(lines)
        for j in range(open_i + 1, len(lines)):
            if re.match(r"^##[ \t]+\S", lines[j]):
                end = j
                break
        status = "unbounded-stripped"
    new_text = "".join(lines[:open_i] + lines[end:])
    # Deterministic span removal concatenates the before/after lines verbatim,
    # so every line outside the removed block is byte-identical by construction
    # — the prose's byte-diff guard can never trip here.
    return new_text, status, True


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
