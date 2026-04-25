#!/usr/bin/env python3
"""Steering-event extractor for Claude Code session JSONL.

Two-tier detection — both run by default. The directive itself is opt-in
at install time; no additional internal gates.

    Tier 1 — structural (runtime sentinels)
        tool-denial — tool_result content starts with the canonical phrase
            ``The user doesn't want to proceed with this tool use``.
            The corresponding tool_use is found via tool_use_id to recover
            the proposed action's tool name and a short ``proposed`` summary.
            If the user typed a reason, the verbatim text after
            ``To tell you how to proceed, the user said:\\n`` is captured.
        interrupt — user message with text matching
            ``[Request interrupted by user`` (with or without ``for tool use``).
            No reason text by construction.

    Tier 2 — semantic correction
        correction — a user message immediately following an assistant turn,
            classified as a redirect. Primary classifier: shells out to the
            coding-agent CLI (``claude -p`` for Claude Code; future Codex
            adapter takes the same shape). The CLI is by definition installed
            in any session that wrote this transcript, so it's a free
            dependency. Fallback when the CLI is unreachable or returns a
            malformed response: a regex pre-filter (high-precision,
            high-FN — covers the obvious cases). Tier label on the emitted
            row reflects which classifier actually ran (``classifier`` or
            ``lexical``).

Output: one TSV row per detected event on stdout. Columns:

    timestamp_iso \\t type \\t tier \\t tool \\t proposed \\t user_reason

Empty cells are emitted as the literal string ``-``. The bash caller
splits on TAB and reads cells.

Determinism: tier-2 verdicts are cached by message-pair hash in
``$GIT_DIR/agent-steering-classify-cache.json`` so re-runs (amend, retry)
return the same result and the count-based dedup in the pre-commit hook
stays exact.

CLI:

    python3 extract.py <session_jsonl> [--no-tier2] [--cache <path>]

Stdlib-only.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path

# classifier.py sits next to this file; the relative import works under
# `python3 extract.py …` because the parent dir is on sys.path.
try:
    from classifier import Candidate, classify_candidates  # type: ignore
except ModuleNotFoundError:  # pragma: no cover
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from classifier import Candidate, classify_candidates  # type: ignore


DENIAL_PHRASE = "The user doesn't want to proceed with this tool use"
REASON_MARKER = "To tell you how to proceed, the user said:"
INTERRUPT_PHRASE_RE = re.compile(r"^\[Request interrupted by user\b")

# Heuristic guards on tier-2 candidate messages. We only ask the classifier
# about user messages that *could* be redirects — skip empty bodies and
# obvious tool-result wrappers. Long messages are clipped before classification.
CANDIDATE_MIN_LEN = 2
CANDIDATE_MAX_LEN = 2000


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


# ── Main extractor ───────────────────────────────────────────────────────


def extract(
    path: str | Path,
    *,
    tier2: bool = True,
    cache_path: Path | None = None,
) -> list[Event]:
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

    # Pre-pass keeps tier-1 events temporally ordered; we append tier-2 events
    # in their original timestamp positions afterwards. Each list element is
    # (insertion_idx, Event) — the insertion_idx ties tier-2 events to the
    # JSONL line they were detected on so the final ordering matches the
    # transcript's chronology.
    timeline: list[tuple[int, Event]] = []
    candidates: list[Candidate] = []
    candidate_origin: list[int] = []  # insertion index per candidate
    last_assistant_idx = -1
    last_assistant_text = ""

    for idx, d in enumerate(lines):
        ts = d.get("timestamp", "") or ""
        msg = d.get("message") if isinstance(d.get("message"), dict) else None
        if not msg:
            continue
        role = msg.get("role")
        content = msg.get("content")

        if role == "assistant":
            # Capture text for tier-2 context (assistant turn the user is
            # responding to). Tool-use parts contribute their tool name +
            # input summary so the classifier can see what was proposed.
            assistant_chunks = [_extract_text(content)]
            if isinstance(content, list):
                for part in content:
                    if isinstance(part, dict) and part.get("type") == "tool_use":
                        name = part.get("name", "") or ""
                        summary = _summary_for_tool(name, part.get("input") or {})
                        assistant_chunks.append(f"[tool_use {name}: {summary}]")
            last_assistant_idx = idx
            last_assistant_text = "\n".join(c for c in assistant_chunks if c)
            continue

        if role != "user":
            continue

        text = _extract_text(content)
        is_tool_result = False

        # Tool-denial: tool_result payload with the canonical phrase.
        if isinstance(content, list):
            for part in content:
                if not isinstance(part, dict):
                    continue
                if part.get("type") != "tool_result":
                    continue
                is_tool_result = True
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
                timeline.append((
                    idx,
                    Event(
                        timestamp=ts,
                        type="tool-denial",
                        tier="structural",
                        tool=tool,
                        proposed=proposed,
                        user_reason=reason,
                    ),
                ))

        # Interrupt: user message containing `[Request interrupted by user`.
        if INTERRUPT_PHRASE_RE.search(text):
            timeline.append((
                idx,
                Event(
                    timestamp=ts,
                    type="interrupt",
                    tier="structural",
                    tool="",
                    proposed="",
                    user_reason="",
                ),
            ))

        # Tier-2 candidate: a user message that immediately follows an
        # assistant turn, isn't a tool-result wrapper, and clears the
        # length floor. Classification happens in a single batched call
        # after the walk completes.
        if (
            tier2
            and not is_tool_result
            and last_assistant_idx >= 0
            and last_assistant_idx == idx - 1
        ):
            stripped = text.strip()
            if (
                CANDIDATE_MIN_LEN <= len(stripped) <= CANDIDATE_MAX_LEN
                and not INTERRUPT_PHRASE_RE.search(stripped)
            ):
                candidates.append(
                    Candidate(
                        timestamp=ts,
                        assistant_text=last_assistant_text,
                        user_text=stripped,
                    )
                )
                candidate_origin.append(idx)

    # Run the tier-2 classifier on candidates (CLI primary, regex fallback).
    if candidates:
        verdicts = classify_candidates(candidates, cache_path=cache_path)
        for cand_idx, (tier, reason) in verdicts.items():
            c = candidates[cand_idx]
            timeline.append((
                candidate_origin[cand_idx],
                Event(
                    timestamp=c.timestamp,
                    type="correction",
                    tier=tier,
                    tool="",
                    proposed="",
                    user_reason=reason or c.user_text[:240],
                ),
            ))

    # Sort by JSONL line index so tier-2 events slot back into chronological
    # order alongside tier-1 events.
    timeline.sort(key=lambda x: x[0])
    return [ev for _, ev in timeline]


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
    parser.add_argument(
        "--no-tier2",
        action="store_true",
        help="Skip tier-2 (correction) detection. Tier-1 still runs.",
    )
    parser.add_argument(
        "--cache",
        type=Path,
        default=None,
        help="Path to a JSON cache for tier-2 classifier verdicts.",
    )
    args = parser.parse_args(argv)
    events = extract(
        args.transcript,
        tier2=not args.no_tier2,
        cache_path=args.cache,
    )
    for ev in events:
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
