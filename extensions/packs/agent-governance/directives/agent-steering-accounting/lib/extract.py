#!/usr/bin/env python3
"""Steering-event extractor for Claude Code session JSONL.

Two-tier detection:

    Tier 1 (structural, default-on)
        tool-denial — tool_result content starts with the canonical phrase
            ``The user doesn't want to proceed with this tool use``.
            The corresponding tool_use is found via tool_use_id to recover
            the proposed action's tool name and a short ``proposed`` summary.
            If the user typed a reason, the verbatim text after
            ``To tell you how to proceed, the user said:\\n`` is captured.
        interrupt — user message with text matching
            ``[Request interrupted by user`` (with or without ``for tool use``).
            No reason text by construction.

    Tier 2 (lexical, gated by STEERING_LEXICAL=1)
        correction — a user message immediately following an assistant turn
            whose first non-whitespace text matches the correction regex
            from issue #53. Verbatim user text becomes ``user-reason``.

Output: one TSV row per detected event on stdout. Columns:

    timestamp_iso \\t type \\t tier \\t tool \\t proposed \\t user_reason

Empty cells are emitted as the literal string ``-``. The bash caller
splits on TAB and reads cells.

CLI:

    python3 extract.py <session_jsonl> [--lexical]

Stdlib-only.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path


DENIAL_PHRASE = "The user doesn't want to proceed with this tool use"
REASON_MARKER = "To tell you how to proceed, the user said:"
INTERRUPT_PHRASE_RE = re.compile(r"^\[Request interrupted by user\b")

CORRECTION_RE = re.compile(
    r"^(no|stop|wait|actually|instead|don't|hold on|back up|undo|revert|"
    r"that's wrong|you're wrong)\b",
    re.IGNORECASE,
)


@dataclass
class Event:
    timestamp: str
    type: str
    tier: str
    tool: str
    proposed: str
    user_reason: str


def _summary_for_tool(tool: str, tool_input: dict) -> str:
    """One-line, ledger-friendly description of what the agent proposed.

    Truncation happens in lib/ledger.py — here we just pull the most
    informative single field and leave the rest to the cell sanitizer.
    """
    if not isinstance(tool_input, dict):
        return ""
    if tool == "Bash":
        cmd = tool_input.get("command", "")
        if isinstance(cmd, str):
            return cmd.splitlines()[0] if cmd else ""
    for key in ("file_path", "path", "url", "pattern", "query"):
        v = tool_input.get(key)
        if isinstance(v, str) and v:
            return v
    # Fall back to the first scalar input field, whatever it is.
    for v in tool_input.values():
        if isinstance(v, str) and v:
            return v.splitlines()[0]
    return ""


def _extract_text(content) -> str:
    """Pull the canonical text out of a message.content block.

    Claude Code stores content as either a plain string or a list of typed
    parts; we only care about ``text`` and ``tool_result`` payloads here.
    """
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        chunks: list[str] = []
        for part in content:
            if not isinstance(part, dict):
                continue
            if part.get("type") == "text" and isinstance(part.get("text"), str):
                chunks.append(part["text"])
            elif part.get("type") == "tool_result":
                inner = part.get("content")
                if isinstance(inner, str):
                    chunks.append(inner)
                elif isinstance(inner, list):
                    for sub in inner:
                        if isinstance(sub, dict) and isinstance(sub.get("text"), str):
                            chunks.append(sub["text"])
        return "\n".join(chunks)
    return ""


def _parse_reason(content_str: str) -> str:
    """Recover the verbatim user-typed reason from a denial tool_result.

    Format (literal):
        The user doesn't want to proceed with this tool use. ...
        To tell you how to proceed, the user said:
        <verbatim multi-line text>
    """
    idx = content_str.find(REASON_MARKER)
    if idx < 0:
        return ""
    tail = content_str[idx + len(REASON_MARKER):]
    # Skip a single leading newline; preserve the rest.
    if tail.startswith("\n"):
        tail = tail[1:]
    return tail.strip()


def extract(path: str | Path, *, lexical: bool = False) -> list[Event]:
    """Walk a Claude Code JSONL transcript, return detected events in order."""
    p = Path(path)
    if not p.is_file():
        return []

    # First pass: index tool_use blocks by their id so denials/interrupts
    # can be resolved back to the proposed action.
    tool_uses: dict[str, tuple[str, str]] = {}
    # Buffer the parsed lines for the second pass — JSONL is small enough
    # that two passes is cheaper than the bookkeeping needed for one.
    lines: list[dict] = []
    with p.open() as f:
        for line in f:
            try:
                d = json.loads(line)
            except Exception:
                continue
            lines.append(d)
            msg = d.get("message") if isinstance(d.get("message"), dict) else None
            if not msg:
                continue
            content = msg.get("content")
            if not isinstance(content, list):
                continue
            for part in content:
                if not isinstance(part, dict):
                    continue
                if part.get("type") == "tool_use":
                    tu_id = part.get("id")
                    name = part.get("name", "") or ""
                    tu_input = part.get("input")
                    if isinstance(tu_id, str) and tu_id:
                        tool_uses[tu_id] = (name, _summary_for_tool(name, tu_input or {}))

    events: list[Event] = []
    last_assistant_idx = -1

    for idx, d in enumerate(lines):
        ts = d.get("timestamp", "") or ""
        msg = d.get("message") if isinstance(d.get("message"), dict) else None
        if not msg:
            continue
        role = msg.get("role")
        content = msg.get("content")

        if role == "assistant":
            last_assistant_idx = idx
            continue

        if role != "user":
            continue

        # Tool-denial: tool_result payload with the canonical phrase.
        if isinstance(content, list):
            for part in content:
                if not isinstance(part, dict):
                    continue
                if part.get("type") != "tool_result":
                    continue
                payload = part.get("content")
                if isinstance(payload, list):
                    payload = "\n".join(
                        sub.get("text", "")
                        for sub in payload
                        if isinstance(sub, dict)
                    )
                if not isinstance(payload, str):
                    continue
                if DENIAL_PHRASE not in payload:
                    continue
                tool_use_id = part.get("tool_use_id", "") or ""
                tool, proposed = tool_uses.get(tool_use_id, ("", ""))
                reason = _parse_reason(payload)
                events.append(
                    Event(
                        timestamp=ts,
                        type="tool-denial",
                        tier="structural",
                        tool=tool,
                        proposed=proposed,
                        user_reason=reason,
                    )
                )

        # Interrupt: user message containing `[Request interrupted by user`.
        text = _extract_text(content)
        if INTERRUPT_PHRASE_RE.search(text):
            events.append(
                Event(
                    timestamp=ts,
                    type="interrupt",
                    tier="structural",
                    tool="",
                    proposed="",
                    user_reason="",
                )
            )

        # Lexical correction: user message whose first non-whitespace text
        # matches the correction regex AND that immediately follows an
        # assistant turn (i.e. it's a reactive redirect, not a fresh task).
        if lexical and last_assistant_idx >= 0 and last_assistant_idx == idx - 1:
            stripped = text.lstrip()
            # Skip messages that are tool_results or empty bookkeeping.
            if stripped and CORRECTION_RE.match(stripped):
                events.append(
                    Event(
                        timestamp=ts,
                        type="correction",
                        tier="lexical",
                        tool="",
                        proposed="",
                        user_reason=stripped,
                    )
                )

    return events


# ── CLI ───────────────────────────────────────────────────────────────────


def _emit(field: str) -> str:
    # Emit empty cells as `-` so naive `read -r` in bash doesn't collapse
    # adjacent tabs.
    if not field:
        return "-"
    # Guard against literal tabs in the source destroying the TSV.
    return field.replace("\t", " ").replace("\n", " ")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("transcript")
    parser.add_argument("--lexical", action="store_true")
    args = parser.parse_args(argv)
    for ev in extract(args.transcript, lexical=args.lexical):
        print(
            "\t".join(
                _emit(x)
                for x in (
                    ev.timestamp,
                    ev.type,
                    ev.tier,
                    ev.tool,
                    ev.proposed,
                    ev.user_reason,
                )
            )
        )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
