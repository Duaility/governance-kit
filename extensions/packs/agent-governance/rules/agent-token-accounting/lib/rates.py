#!/usr/bin/env python3
"""Model → per-MTok USD rate table for cost-usd computation in COSTS.md.

Rates are per-million-tokens, split by usage mode:

    (base_input, cache_create_5m, cache_read, output)

Source: Anthropic pricing table (Opus 4.x / Sonnet 3.7-4.6 / Haiku 4.x) and
OpenAI API pricing table (GPT-5.4 family) as of 2026-04-23.
Cache writes assume the **5-minute** TTL for Anthropic models, which is
Claude Code's default. OpenAI models do not charge a separate cache-write
rate in this ledger, so their cache-create rate matches base input.

Model lookup is tolerant:
  - lowercase + strip whitespace
  - strip a trailing date suffix like `-20250929` that Anthropic APIs attach
  - exact match first, then longest-prefix match (so `claude-sonnet-4-5-custom`
    still resolves to `claude-sonnet-4-5`)

Family-prefix fallbacks (`claude-opus`, `claude-sonnet`, `claude-haiku`,
`gpt-5`) are seeded from the current production rate card so that a new
minor release between rule updates — e.g. `gpt-5.5` or `claude-opus-4-8` —
resolves to the nearest family schedule rather than falling through to an
empty `cost-usd` cell. Families shift slowly; version numbers churn fast,
so an estimated-but-present cost beats silently-zero. When an older release
has its own pricing (Opus 4.0/4.1), keep a version-specific key alongside
the family key — longest-prefix matching picks the version first.

Unknown model → `lookup()` returns None → `cost_usd` in the ledger is
written as an empty cell, which `validate()` and the rule script treat
as "unpriced, don't cross-check." The pre-commit hook prints a visible
warning in that case so the gap doesn't stay silent.

This module is stdlib-only.

CLI:

    python3 rates.py cost <model> <input> <cache_create> <cache_read> <output>
        → prints the 4-decimal dollar cost on stdout, or an empty line
          if the model isn't priced. Called from the pre-commit hook to
          keep the ledger row and the Cost-USD trailer in lock-step.
"""

from __future__ import annotations

import re
import sys


# (base_input, cache_create_5m, cache_read, output) per MTok, USD
RATES: dict[str, tuple[float, float, float, float]] = {
    # ── Claude family fallbacks ────────────────────────────────────────
    # Seeded from the current (4-6 / 4-7) production rate card. A new
    # minor release lands on these rates until a version-specific row
    # is added. Kept deliberately coarse — 5 chars shorter than any
    # version key so longest-prefix matching picks a specific version
    # whenever one exists.
    "claude-opus":   (5.00, 6.25, 0.50, 25.00),
    "claude-sonnet": (3.00, 3.75, 0.30, 15.00),
    "claude-haiku":  (1.00, 1.25, 0.10,  5.00),

    # ── Claude Opus — version-specific rows ────────────────────────────
    "claude-opus-4-7": (5.00, 6.25, 0.50, 25.00),
    "claude-opus-4-6": (5.00, 6.25, 0.50, 25.00),
    "claude-opus-4-5": (5.00, 6.25, 0.50, 25.00),
    "claude-opus-4-1": (15.00, 18.75, 1.50, 75.00),
    "claude-opus-4-0": (15.00, 18.75, 1.50, 75.00),

    # ── Claude Sonnet — version-specific rows ──────────────────────────
    "claude-sonnet-4-6": (3.00, 3.75, 0.30, 15.00),
    "claude-sonnet-4-5": (3.00, 3.75, 0.30, 15.00),
    "claude-sonnet-4-0": (3.00, 3.75, 0.30, 15.00),
    "claude-sonnet-3-7": (3.00, 3.75, 0.30, 15.00),

    # ── OpenAI GPT-5 family ────────────────────────────────────────────
    # `gpt-5` acts as the family fallback for `gpt-5.5`, `gpt-5.6`, etc.
    # Specific variants override — `gpt-5.4-mini`/`-nano` win by length.
    "gpt-5":        (2.50, 2.50, 0.25, 15.00),
    "gpt-5.4":      (2.50, 2.50, 0.25, 15.00),
    "gpt-5.4-mini": (0.75, 0.75, 0.075, 4.50),
    "gpt-5.4-nano": (0.20, 0.20, 0.02, 1.25),
}

_DATE_SUFFIX_RE = re.compile(r"-\d{8}$")


def normalize(model: str) -> str:
    """`claude-opus-4-5-20250929` → `claude-opus-4-5`."""
    m = (model or "").lower().strip()
    return _DATE_SUFFIX_RE.sub("", m)


def lookup(model: str) -> tuple[float, float, float, float] | None:
    """Return `(base, cache_create, cache_read, output)` per-MTok rates, or
    None if the model isn't in the table."""
    if not model:
        return None
    norm = normalize(model)
    if norm in RATES:
        return RATES[norm]
    # Longest-prefix match — `claude-sonnet-4-5-custom-suffix` finds the
    # 4-5 row; `gpt-5.5` finds the `gpt-5` family row.
    best_key = ""
    for key in RATES:
        if norm.startswith(key) and len(key) > len(best_key):
            best_key = key
    return RATES[best_key] if best_key else None


def compute_cost_usd(
    model: str,
    input_tok: int,
    cache_create_tok: int,
    cache_read_tok: int,
    output_tok: int,
) -> float | None:
    """Return the USD cost of one row's token usage, rounded to 4 decimals.
    None if the model isn't priced."""
    rates = lookup(model)
    if rates is None:
        return None
    r_base, r_cc, r_cr, r_out = rates
    cost = (
        input_tok * r_base
        + cache_create_tok * r_cc
        + cache_read_tok * r_cr
        + output_tok * r_out
    ) / 1_000_000.0
    return round(cost, 4)


# ── CLI ───────────────────────────────────────────────────────────────────


def _cmd_cost(argv: list[str]) -> int:
    if len(argv) != 5:
        print(
            "rates cost: <model> <input> <cache_create> <cache_read> <output>",
            file=sys.stderr,
        )
        return 2
    model = argv[0]
    try:
        tokens = [int(x) for x in argv[1:]]
    except ValueError:
        print("rates cost: token counts must be integers", file=sys.stderr)
        return 2
    cost = compute_cost_usd(model, *tokens)
    # Empty line = unpriced. Callers treat this as "leave the cell blank,
    # don't stamp Cost-USD, and optionally warn."
    print("" if cost is None else f"{cost:.4f}")
    return 0


def main(argv: list[str]) -> int:
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        return 0 if argv else 2
    cmd, rest = argv[0], argv[1:]
    if cmd == "cost":
        return _cmd_cost(rest)
    print(f"rates: unknown command {cmd!r}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
