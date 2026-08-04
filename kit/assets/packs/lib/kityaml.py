#!/usr/bin/env python3
# governance: allow-repo-hygiene file-size-limit hand-rolled restricted-YAML load+dump (parser, flow-collection sub-parser, and a yaml.safe_dump-compatible writer) is one cohesive unit; splitting it across files would scatter the grammar it exists to keep in one place (issue #355).
"""kityaml — a stdlib-only, restricted-YAML load/dump pair for the kit's own
manifests (kit.yaml, pack.yaml, directive.yaml, install.yaml, packs.lock).

Issue #355: the kit's lifecycle tooling depended on PyYAML (`uv run --with
PyYAML`), which meant every consumer repo needed `uv` on PATH just to run
`governance install`/`pack *`/`directive *`. This module hand-parses exactly
the YAML subset the kit ever authors or reads — nothing more — so packctl.py
and packverb.py can drop `import yaml` entirely.

Supported grammar (see kit/references — the locked grammar for issue #355):
  - `#` comments to end of line, honored outside quotes only.
  - Block maps, arbitrarily nested, 2-space (or deeper) indentation.
  - Block sequences of scalars and of maps (`- id: x` + aligned continuation
    keys), either "indentless" (items at the same column as their key, the
    shape `yaml.safe_dump` produces) or indented further (the shape humans
    write by hand) — both are legal YAML and this parser accepts both.
  - Flow sequences `[a, b]` and flow maps `{k: v}` (single line only).
  - Single- and double-quoted scalars (`''` / `\\` escapes respectively) and
    unquoted plain scalars.
  - Scalar coercion matching `yaml.safe_load` for this corpus: `true`/`false`
    (plus the YAML 1.1 yes/no/on/off spellings) -> bool, `null`/`~`/`''` ->
    None, integer-looking -> int, float-looking (`0.8`) -> float, everything
    else stays str (so a three-segment version like `0.8.1` stays str).

Explicitly UNSUPPORTED, and loud (raises YAMLError naming file + line) the
moment one is seen: anchors (`&`), aliases (`*`), tags (`!`), block scalars
(`|` / `>`), and multi-line flow collections. None of these appear anywhere
in the kit's own shipped YAML.

    python3 kit/assets/packs/lib/kityaml.py <file>   # smoke: parse + re-dump
"""

from __future__ import annotations

import collections
import math
import re
import sys
from pathlib import Path
from typing import Any


class YAMLError(ValueError):
    """Raised on anything outside the restricted grammar. Message carries
    `<source>:<line>: ...` so callers get the same file+line signal a real
    YAML parser would."""


_Line = collections.namedtuple("_Line", "no indent text")

# ---------------------------------------------------------------------------
# Tokenize: raw text -> non-blank, comment-stripped (indent, text, lineno)
# records. Everything downstream operates on this flat list.
# ---------------------------------------------------------------------------


def _strip_comment(s: str) -> str:
    """Remove a trailing `# ...` comment, honoring quote state. A `#` starts a
    comment only outside a quote AND only when it is the first character or
    is preceded by whitespace — matching real YAML (and `yaml.safe_load`):
    a `#` glued onto a plain scalar (e.g. a URL fragment or, as it happens,
    an unquoted directive summary with `` `#N` `` issue refs) is not a
    comment start."""
    out: list[str] = []
    in_sq = in_dq = False
    i, n = 0, len(s)
    while i < n:
        c = s[i]
        if in_sq:
            out.append(c)
            if c == "'":
                if i + 1 < n and s[i + 1] == "'":
                    out.append(s[i + 1])
                    i += 2
                    continue
                in_sq = False
            i += 1
            continue
        if in_dq:
            out.append(c)
            if c == "\\" and i + 1 < n:
                out.append(s[i + 1])
                i += 2
                continue
            if c == '"':
                in_dq = False
            i += 1
            continue
        if c == "'":
            in_sq = True
            out.append(c)
            i += 1
            continue
        if c == '"':
            in_dq = True
            out.append(c)
            i += 1
            continue
        if c == "#" and (i == 0 or s[i - 1] in " \t"):
            break
        out.append(c)
        i += 1
    return "".join(out)


def _tokenize(text: str, source: str) -> list[_Line]:
    lines: list[_Line] = []
    for lineno, raw in enumerate(text.splitlines(), start=1):
        i = 0
        while i < len(raw) and raw[i] == " ":
            i += 1
        if i < len(raw) and raw[i] == "\t":
            raise YAMLError(f"{source}:{lineno}: tabs are not allowed for indentation")
        rest = _strip_comment(raw[i:]).rstrip()
        if rest == "":
            continue
        lines.append(_Line(lineno, i, rest))
    return lines


def _is_seq_item(text: str) -> bool:
    return text == "-" or text.startswith("- ")


# ---------------------------------------------------------------------------
# Scalar scanning: quoted, flow, and plain scalars, plus coercion.
# ---------------------------------------------------------------------------

_BANNED_LEADING = ("&", "*", "!", "|", ">")


def _reject_unsupported(raw: str, lineno: int, source: str) -> None:
    if raw and raw[0] in _BANNED_LEADING:
        raise YAMLError(
            f"{source}:{lineno}: unsupported YAML construct starting with "
            f"{raw[0]!r} (anchors/aliases/tags/block-scalars are outside the "
            f"restricted grammar): {raw!r}"
        )


_DQ_ESCAPES = {"n": "\n", "t": "\t", '"': '"', "\\": "\\", "/": "/", "r": "\r", "0": "\0"}


def _scan_squoted(text: str, pos: int, lineno: int, source: str) -> tuple[str, int]:
    assert text[pos] == "'"
    i, n = pos + 1, len(text)
    out: list[str] = []
    while i < n:
        c = text[i]
        if c == "'":
            if i + 1 < n and text[i + 1] == "'":
                out.append("'")
                i += 2
                continue
            return "".join(out), i + 1
        out.append(c)
        i += 1
    raise YAMLError(f"{source}:{lineno}: unterminated single-quoted scalar")


def _scan_dquoted(text: str, pos: int, lineno: int, source: str) -> tuple[str, int]:
    assert text[pos] == '"'
    i, n = pos + 1, len(text)
    out: list[str] = []
    while i < n:
        c = text[i]
        if c == "\\":
            if i + 1 >= n:
                raise YAMLError(f"{source}:{lineno}: unterminated escape in double-quoted scalar")
            nc = text[i + 1]
            if nc not in _DQ_ESCAPES:
                raise YAMLError(f"{source}:{lineno}: unsupported escape \\{nc} in double-quoted scalar")
            out.append(_DQ_ESCAPES[nc])
            i += 2
            continue
        if c == '"':
            return "".join(out), i + 1
        out.append(c)
        i += 1
    raise YAMLError(f"{source}:{lineno}: unterminated double-quoted scalar")


_NULL_TOKENS = {"~", "null", "Null", "NULL", ""}
_BOOL_TRUE = {"true", "True", "TRUE", "yes", "Yes", "YES", "on", "On", "ON"}
_BOOL_FALSE = {"false", "False", "FALSE", "no", "No", "NO", "off", "Off", "OFF"}
_INT_RE = re.compile(r"^[-+]?(0|[1-9][0-9_]*)$")
_INT_HEX_RE = re.compile(r"^[-+]?0x[0-9a-fA-F_]+$")
_INT_OCT_RE = re.compile(r"^[-+]?0o[0-7_]+$")
_FLOAT_RE = re.compile(r"^[-+]?(\.[0-9][0-9_]*|[0-9][0-9_]*(\.[0-9_]*)?)([eE][-+]?[0-9]+)?$")


def _coerce_plain(text: str) -> Any:
    """Coerce a plain (unquoted) scalar. Matches yaml.safe_load for this
    corpus: bool / None / int / float, else str (so `0.8.1` — two dots —
    never matches the float grammar and stays str)."""
    if text in _NULL_TOKENS:
        return None
    if text in _BOOL_TRUE:
        return True
    if text in _BOOL_FALSE:
        return False
    if text in (".inf", ".Inf", ".INF", "+.inf", "+.Inf", "+.INF"):
        return float("inf")
    if text in ("-.inf", "-.Inf", "-.INF"):
        return float("-inf")
    if text in (".nan", ".NaN", ".NAN"):
        return float("nan")
    if _INT_RE.match(text):
        return int(text.replace("_", ""))
    if _INT_HEX_RE.match(text):
        return int(text.replace("_", ""), 16)
    if _INT_OCT_RE.match(text):
        sign = -1 if text.startswith("-") else 1
        return sign * int(text.replace("_", "").lstrip("+-").replace("0o", ""), 8)
    if _FLOAT_RE.match(text) and ("." in text or "e" in text or "E" in text):
        return float(text.replace("_", ""))
    return text


def _flow_skip_ws(text: str, pos: int) -> int:
    while pos < len(text) and text[pos] in " \t":
        pos += 1
    return pos


def _flow_parse(text: str, pos: int, lineno: int, source: str) -> tuple[Any, int]:
    pos = _flow_skip_ws(text, pos)
    if pos >= len(text):
        raise YAMLError(f"{source}:{lineno}: unexpected end of flow collection")
    c = text[pos]
    if c == "[":
        return _flow_parse_seq(text, pos, lineno, source)
    if c == "{":
        return _flow_parse_map(text, pos, lineno, source)
    if c == "'":
        return _scan_squoted(text, pos, lineno, source)
    if c == '"':
        return _scan_dquoted(text, pos, lineno, source)
    return _flow_parse_plain(text, pos, lineno, source)


def _flow_parse_seq(text: str, pos: int, lineno: int, source: str) -> tuple[list[Any], int]:
    assert text[pos] == "["
    pos += 1
    items: list[Any] = []
    pos = _flow_skip_ws(text, pos)
    if pos < len(text) and text[pos] == "]":
        return items, pos + 1
    while True:
        value, pos = _flow_parse(text, pos, lineno, source)
        items.append(value)
        pos = _flow_skip_ws(text, pos)
        if pos >= len(text):
            raise YAMLError(f"{source}:{lineno}: unterminated flow sequence")
        if text[pos] == ",":
            pos = _flow_skip_ws(text, pos + 1)
            if pos < len(text) and text[pos] == "]":
                return items, pos + 1
            continue
        if text[pos] == "]":
            return items, pos + 1
        raise YAMLError(f"{source}:{lineno}: expected ',' or ']' in flow sequence, got {text[pos]!r}")


def _flow_parse_map(text: str, pos: int, lineno: int, source: str) -> tuple[dict[str, Any], int]:
    assert text[pos] == "{"
    pos += 1
    result: dict[str, Any] = {}
    pos = _flow_skip_ws(text, pos)
    if pos < len(text) and text[pos] == "}":
        return result, pos + 1
    while True:
        pos = _flow_skip_ws(text, pos)
        key, pos = _flow_parse_key(text, pos, lineno, source)
        pos = _flow_skip_ws(text, pos)
        if pos >= len(text) or text[pos] != ":":
            raise YAMLError(f"{source}:{lineno}: expected ':' after flow map key {key!r}")
        pos = _flow_skip_ws(text, pos + 1)
        value, pos = _flow_parse(text, pos, lineno, source)
        result[key] = value
        pos = _flow_skip_ws(text, pos)
        if pos >= len(text):
            raise YAMLError(f"{source}:{lineno}: unterminated flow map")
        if text[pos] == ",":
            pos += 1
            continue
        if text[pos] == "}":
            return result, pos + 1
        raise YAMLError(f"{source}:{lineno}: expected ',' or '}}' in flow map, got {text[pos]!r}")


def _flow_parse_key(text: str, pos: int, lineno: int, source: str) -> tuple[str, int]:
    if pos < len(text) and text[pos] == "'":
        return _scan_squoted(text, pos, lineno, source)
    if pos < len(text) and text[pos] == '"':
        return _scan_dquoted(text, pos, lineno, source)
    start = pos
    while pos < len(text) and text[pos] not in ",:{}[]":
        pos += 1
    raw = text[start:pos].strip()
    if raw == "":
        raise YAMLError(f"{source}:{lineno}: empty flow map key")
    return raw, pos


def _flow_parse_plain(text: str, pos: int, lineno: int, source: str) -> tuple[Any, int]:
    start = pos
    while pos < len(text) and text[pos] not in ",:{}[]":
        pos += 1
    raw = text[start:pos].strip()
    if raw == "":
        raise YAMLError(f"{source}:{lineno}: empty flow scalar")
    _reject_unsupported(raw, lineno, source)
    return _coerce_plain(raw), pos


def _parse_scalar(text: str, lineno: int, source: str) -> Any:
    text = text.strip()
    if text.startswith("'") or text.startswith('"'):
        scan = _scan_squoted if text[0] == "'" else _scan_dquoted
        value, pos = scan(text, 0, lineno, source)
        rest = text[pos:].strip()
        if rest:
            raise YAMLError(f"{source}:{lineno}: unexpected content after quoted scalar: {rest!r}")
        return value
    if text.startswith("[") or text.startswith("{"):
        value, pos = _flow_parse(text, 0, lineno, source)
        rest = text[pos:].strip()
        if rest:
            raise YAMLError(f"{source}:{lineno}: unexpected trailing content after flow collection: {rest!r}")
        return value
    _reject_unsupported(text, lineno, source)
    return _coerce_plain(text)


def _find_key_colon(text: str) -> int | None:
    in_sq = in_dq = False
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if in_sq:
            if c == "'":
                if i + 1 < n and text[i + 1] == "'":
                    i += 2
                    continue
                in_sq = False
            i += 1
            continue
        if in_dq:
            if c == "\\" and i + 1 < n:
                i += 2
                continue
            if c == '"':
                in_dq = False
            i += 1
            continue
        if c == "'":
            in_sq = True
            i += 1
            continue
        if c == '"':
            in_dq = True
            i += 1
            continue
        if c == ":" and (i + 1 == n or text[i + 1] == " "):
            return i
        i += 1
    return None


def _parse_key_scalar(text: str, lineno: int, source: str) -> str:
    if text.startswith("'") or text.startswith('"'):
        scan = _scan_squoted if text[0] == "'" else _scan_dquoted
        value, pos = scan(text, 0, lineno, source)
        rest = text[pos:].strip()
        if rest:
            raise YAMLError(f"{source}:{lineno}: unexpected content after quoted key: {rest!r}")
        return value
    _reject_unsupported(text, lineno, source)
    return text


def _split_map_line(text: str, lineno: int, source: str) -> tuple[str, str | None]:
    idx = _find_key_colon(text)
    if idx is None:
        raise YAMLError(f"{source}:{lineno}: expected 'key: value' mapping entry, got {text!r}")
    key = _parse_key_scalar(text[:idx].strip(), lineno, source)
    value_raw = text[idx + 1 :].strip()
    return key, (value_raw if value_raw != "" else None)


def _looks_like_map_entry(rest: str) -> bool:
    if rest[:1] in ("'", '"', "[", "{"):
        return False
    return _find_key_colon(rest) is not None


# ---------------------------------------------------------------------------
# Block structure: indentation-driven recursive descent.
# ---------------------------------------------------------------------------


def _parse_block(lines: list[_Line], i: int, indent: int, source: str) -> tuple[Any, int]:
    if i >= len(lines) or lines[i].indent != indent:
        return None, i
    if _is_seq_item(lines[i].text):
        return _parse_sequence(lines, i, indent, source)
    return _parse_mapping(lines, i, indent, source)


def _parse_value_after_key(lines: list[_Line], i: int, indent: int, source: str) -> tuple[Any, int]:
    """The value of a `key:` line with nothing inline. Its children are
    either a sequence at the SAME indent as the key (the "indentless" style
    `yaml.safe_dump` produces) or any block indented further (the style
    humans write by hand) — both are legal YAML; a sibling key at the same
    indent means the value is empty (None)."""
    if i < len(lines) and lines[i].indent == indent and _is_seq_item(lines[i].text):
        return _parse_sequence(lines, i, indent, source)
    if i < len(lines) and lines[i].indent > indent:
        return _parse_block(lines, i, lines[i].indent, source)
    return None, i


def _mapping_loop(
    lines: list[_Line], i: int, indent: int, source: str, result: dict[str, Any]
) -> tuple[dict[str, Any], int]:
    while i < len(lines) and lines[i].indent == indent and not _is_seq_item(lines[i].text):
        line = lines[i]
        key, inline_val = _split_map_line(line.text, line.no, source)
        i += 1
        if inline_val is None:
            value, i = _parse_value_after_key(lines, i, indent, source)
        else:
            value = _parse_scalar(inline_val, line.no, source)
        if key in result:
            raise YAMLError(f"{source}:{line.no}: duplicate key {key!r}")
        result[key] = value
    return result, i


def _parse_mapping(lines: list[_Line], i: int, indent: int, source: str) -> tuple[dict[str, Any], int]:
    return _mapping_loop(lines, i, indent, source, {})


def _parse_sequence(lines: list[_Line], i: int, indent: int, source: str) -> tuple[list[Any], int]:
    items: list[Any] = []
    while i < len(lines) and lines[i].indent == indent and _is_seq_item(lines[i].text):
        line = lines[i]
        rest = "" if line.text == "-" else line.text[2:]
        i += 1
        if rest == "":
            if i < len(lines) and lines[i].indent > indent:
                value, i = _parse_block(lines, i, lines[i].indent, source)
            else:
                value = None
        elif _looks_like_map_entry(rest):
            map_indent = indent + 2
            key, inline_val = _split_map_line(rest, line.no, source)
            if inline_val is None:
                first_value, i = _parse_value_after_key(lines, i, map_indent, source)
            else:
                first_value = _parse_scalar(inline_val, line.no, source)
            value, i = _mapping_loop(lines, i, map_indent, source, {key: first_value})
        else:
            value = _parse_scalar(rest, line.no, source)
        items.append(value)
    return items, i


def loads(text: str, source: str = "<string>") -> Any:
    """Parse restricted-YAML text directly (no file access)."""
    lines = _tokenize(text, source)
    if not lines:
        return None
    if len(lines) == 1 and not _is_seq_item(lines[0].text) and _find_key_colon(lines[0].text) is None:
        return _parse_scalar(lines[0].text, lines[0].no, source)
    value, i = _parse_block(lines, 0, lines[0].indent, source)
    if i != len(lines):
        extra = lines[i]
        raise YAMLError(f"{source}:{extra.no}: unexpected indentation or content at top level")
    return value


def load(path_or_text: Path | str) -> Any:
    """Parse restricted-YAML. Accepts a `Path` (reads the file), a `str` that
    names an existing file on disk (reads it), or raw YAML text (parsed
    directly, source label `<string>`)."""
    if isinstance(path_or_text, Path):
        return loads(path_or_text.read_text(), str(path_or_text))
    if isinstance(path_or_text, str) and path_or_text and Path(path_or_text).is_file():
        return loads(Path(path_or_text).read_text(), path_or_text)
    return loads(path_or_text, "<string>")


# ---------------------------------------------------------------------------
# Writer: block style, insertion order, 2-space indents — mirrors
# `yaml.safe_dump(sort_keys=False, default_flow_style=False)` closely enough
# to reproduce this repo's `.governance/packs.lock` byte-for-byte (see
# scripts/test-kityaml.py). One extra quoting rule beyond the locked grammar's
# stated bool/int/float/null lookalikes is required for that: PyYAML's
# SafeLoader also implicitly resolves bare ISO-8601-shaped strings (the
# lockfile's `installed_at` values) to timestamps, so its dumper quotes them
# to keep them strings on the next load — kityaml's own loader never coerces
# timestamps (the locked grammar's coercion set is bool/None/int/float/str
# only), but the quoting *decision* still has to account for it to match what
# real `yaml.safe_dump` already wrote to disk.
# ---------------------------------------------------------------------------

_TIMESTAMP_RE = re.compile(
    r"^[0-9]{4}-[0-9]{2}-[0-9]{2}"
    r"([Tt ][0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]*)?"
    r"([ \t]*(Z|[-+][0-9]{2}:?[0-9]{2}?))?)?$"
)


def _looks_like_timestamp(s: str) -> bool:
    return bool(_TIMESTAMP_RE.match(s))


def _needs_quoting(s: str) -> bool:
    if s == "":
        return True
    if s != s.strip():
        return True
    if s == "-" or s.startswith("- "):
        return True
    if ": " in s or s.endswith(":"):
        return True
    if s.startswith("#") or " #" in s:
        return True
    if s[0] in "'\"[{":
        return True
    if _coerce_plain(s) != s:
        return True
    return _looks_like_timestamp(s)


def _quote_single(s: str) -> str:
    return "'" + s.replace("'", "''") + "'"


def _scalar_repr(value: Any) -> str:
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        if math.isnan(value):
            return ".nan"
        if value == float("inf"):
            return ".inf"
        if value == float("-inf"):
            return "-.inf"
        return repr(value)
    s = str(value)
    return _quote_single(s) if _needs_quoting(s) else s


def _emit_kv(key: Any, value: Any, indent: int, lines: list[str], prefix: str | None = None) -> None:
    pad = prefix if prefix is not None else " " * indent
    key_str = _scalar_repr(key)
    if isinstance(value, dict) and value:
        lines.append(f"{pad}{key_str}:")
        _emit_mapping(value, indent + 2, lines)
    elif isinstance(value, dict):
        lines.append(f"{pad}{key_str}: {{}}")
    elif isinstance(value, list) and value:
        lines.append(f"{pad}{key_str}:")
        _emit_sequence(value, indent, lines)  # indentless, matches yaml.safe_dump
    elif isinstance(value, list):
        lines.append(f"{pad}{key_str}: []")
    else:
        lines.append(f"{pad}{key_str}: {_scalar_repr(value)}")


def _emit_mapping(mapping: dict[str, Any], indent: int, lines: list[str]) -> None:
    for key, value in mapping.items():
        _emit_kv(key, value, indent, lines)


def _emit_sequence(items: list[Any], indent: int, lines: list[str]) -> None:
    pad = " " * indent
    for item in items:
        if isinstance(item, dict) and item:
            it = iter(item.items())
            first_key, first_value = next(it)
            _emit_kv(first_key, first_value, indent + 2, lines, prefix=f"{pad}- ")
            for key, value in it:
                _emit_kv(key, value, indent + 2, lines)
        elif isinstance(item, dict):
            lines.append(f"{pad}- {{}}")
        elif isinstance(item, list) and item:
            lines.append(f"{pad}-")
            _emit_sequence(item, indent + 2, lines)
        elif isinstance(item, list):
            lines.append(f"{pad}- []")
        else:
            lines.append(f"{pad}- {_scalar_repr(item)}")


def dump(obj: Any) -> str:
    """Serialize `obj` (dict/list/scalar tree) to restricted-YAML text."""
    lines: list[str] = []
    if isinstance(obj, dict):
        _emit_mapping(obj, 0, lines)
    elif isinstance(obj, list):
        _emit_sequence(obj, 0, lines)
    else:
        lines.append(_scalar_repr(obj))
    return "\n".join(lines) + "\n" if lines else ""


def main(argv: list[str]) -> int:
    if not argv:
        print("usage: kityaml.py <file>  # parse + re-dump smoke test", file=sys.stderr)
        return 2
    data = load(Path(argv[0]))
    sys.stdout.write(dump(data))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
