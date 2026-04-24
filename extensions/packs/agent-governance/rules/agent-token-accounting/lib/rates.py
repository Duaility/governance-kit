#!/usr/bin/env python3
"""Model → per-MTok USD rate table for cost-usd computation in COSTS.md.

Rates are per-million-tokens, split by usage mode:

    (base_input, cache_create_5m, cache_read, output)

Source: Anthropic pricing table (Opus 4.x / Sonnet 3.7-4.6) and OpenAI API
pricing table (GPT-5.4 family) as of 2026-04-23.
Cache writes assume the **5-minute** TTL for Anthropic models, which is
Claude Code's default. OpenAI models do not charge a separate cache-write
rate in this ledger, so their cache-create rate matches base input.

Model lookup is tolerant:
  - lowercase + strip whitespace
  - strip a trailing date suffix like `-20250929` that Anthropic APIs attach
  - exact match first, then prefix match (so `claude-sonnet-4-5-20250929`
    resolves to `claude-sonnet-4-5` even if the exact stamped key is
    missing from the table)

Unknown model → `lookup()` returns None → `cost_usd` in the ledger is
written as an empty cell, which `validate()` and the rule script treat
as "unpriced, don't cross-check."

This module is stdlib-only.
"""

from __future__ import annotations

import re


# (base_input, cache_create_5m, cache_read, output) per MTok, USD
RATES: dict[str, tuple[float, float, float, float]] = {
    # Claude Opus — premium tier
    "claude-opus-4-7": (5.00, 6.25, 0.50, 25.00),
    "claude-opus-4-6": (5.00, 6.25, 0.50, 25.00),
    "claude-opus-4-5": (5.00, 6.25, 0.50, 25.00),
    "claude-opus-4-1": (15.00, 18.75, 1.50, 75.00),
    "claude-opus-4":   (15.00, 18.75, 1.50, 75.00),
    # Claude Sonnet — mid tier
    "claude-sonnet-4-6": (3.00, 3.75, 0.30, 15.00),
    "claude-sonnet-4-5": (3.00, 3.75, 0.30, 15.00),
    "claude-sonnet-4":   (3.00, 3.75, 0.30, 15.00),
    "claude-sonnet-3-7": (3.00, 3.75, 0.30, 15.00),
    # OpenAI GPT-5.4 — standard processing, text tokens
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
    # Prefix match — `claude-sonnet-4-5-custom-suffix` still finds the Sonnet 4.5 row.
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
