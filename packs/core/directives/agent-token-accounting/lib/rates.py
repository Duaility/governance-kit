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
minor release between directive updates — e.g. `gpt-5.5` or `claude-opus-4-8` —
resolves to the nearest family schedule rather than falling through to an
empty `cost-usd` cell. Families shift slowly; version numbers churn fast,
so an estimated-but-present cost beats silently-zero. When an older release
has its own pricing (Opus 4.0/4.1), keep a version-specific key alongside
the family key — longest-prefix matching picks the version first.

Unknown model → `lookup()` returns None. The `cost` CLI exits non-zero
and emits nothing on stdout, so the pre-commit caller can distinguish
a real failure from a "cost=0.0000" priced row. Cost-USD is mandatory
on new commits, so an unknown model blocks the commit — the operator
adds a `rate <model> ...` row to `.governance/conf/agent-token-accounting.conf`
(the user-owned override file, which survives `governance pack update`),
or for a built-in default a family-prefix row to `RATES` here, or waives
via `SKIP_GOVERNANCE=1` for a hot-fix. The directive script's ledger
validator still tolerates legacy rows with an empty `cost-usd` cell
(grandfathered — pre-mandate history).

Per-repo price overrides: `load_overrides()` reads
`.governance/conf/agent-token-accounting.conf` and MERGES its `rate` rows over
`RATES` (user rows win), so a repo with negotiated pricing or a brand-new model
never has to patch this pack-owned file. A malformed override row raises
`ValueError`; the CLI turns that into a non-zero exit that blocks the commit.

This module is stdlib-only.

CLI:

    python3 rates.py cost <model> <input> <cache_create> <cache_read> <output>
        → prints the 4-decimal dollar cost on stdout and exits 0 when the
          model resolves. When the model is unpriced (no family-prefix
          match either), exits 3 with a human-readable reason on stderr
          and no stdout — the pre-commit hook propagates that as a hard
          failure so the commit doesn't land with a missing Cost-USD.
"""

from __future__ import annotations

import os
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
    "claude-fable":  (10.00, 12.50, 1.00, 50.00),

    # ── Claude Fable — version-specific rows ───────────────────────────
    "claude-fable-5": (10.00, 12.50, 1.00, 50.00),

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

# User-owned per-repo price overrides live here, relative to the repo root.
# Each row is `rate <model> <base_input> <cache_create> <cache_read> <output>`
# (per-MTok USD). Overrides MERGE OVER the built-in RATES — a user adds a new
# model or corrects a price without patching this pack-owned file (which a
# `governance pack update` would clobber). See config.conf for the template.
_CONF_REL = os.path.join(".governance", "conf", "agent-token-accounting.conf")


def normalize(model: str) -> str:
    """`claude-opus-4-5-20250929` → `claude-opus-4-5`."""
    m = (model or "").lower().strip()
    return _DATE_SUFFIX_RE.sub("", m)


def _find_conf() -> str | None:
    """Walk up from the CWD to find `.governance/conf/agent-token-accounting.conf`.
    The pre-commit hook and run.sh both invoke with the repo root as CWD; the
    walk-up keeps it correct from a subdirectory too. None if not found."""
    d = os.path.abspath(os.getcwd())
    while True:
        candidate = os.path.join(d, _CONF_REL)
        if os.path.isfile(candidate):
            return candidate
        parent = os.path.dirname(d)
        if parent == d:
            return None
        d = parent


def load_overrides() -> dict[str, tuple[float, float, float, float]]:
    """Parse the user conf's `rate` rows into a model → rates map. Empty when no
    conf exists. Raises ValueError on a malformed row — a bad price table must
    fail loudly, never silently misprice a commit."""
    out: dict[str, tuple[float, float, float, float]] = {}
    conf = _find_conf()
    if conf is None:
        return out
    with open(conf, encoding="utf-8") as fh:
        for lineno, raw in enumerate(fh, 1):
            line = raw.split("#", 1)[0].strip()
            if not line:
                continue
            parts = line.split()
            if parts[0] != "rate":
                raise ValueError(
                    f"{conf}:{lineno}: unrecognized line {line!r} — override rows "
                    f"must start with `rate` (or be a `#` comment)"
                )
            if len(parts) != 6:
                raise ValueError(
                    f"{conf}:{lineno}: malformed rate row — expected "
                    f"`rate <model> <base_input> <cache_create> <cache_read> <output>`"
                )
            model = parts[1].lower().strip()
            try:
                nums = tuple(float(x) for x in parts[2:])
            except ValueError:
                raise ValueError(
                    f"{conf}:{lineno}: rate row for {model!r} has a non-numeric price"
                ) from None
            out[model] = nums  # type: ignore[assignment]
    return out


def _prefix_match(norm: str, table: dict[str, tuple[float, float, float, float]],
                  best_key: str) -> tuple[str, tuple[float, float, float, float] | None]:
    """Longest-prefix lookup within one table; only beats `best_key` on a strictly
    longer key, so a same-length override (searched first) wins ties."""
    best_val: tuple[float, float, float, float] | None = None
    for key in table:
        if norm.startswith(key) and len(key) > len(best_key):
            best_key, best_val = key, table[key]
    return best_key, best_val


def lookup(model: str) -> tuple[float, float, float, float] | None:
    """Return `(base, cache_create, cache_read, output)` per-MTok rates, or
    None if the model isn't priced. User overrides merge over the built-in
    RATES: an exact override wins outright, and on a prefix match the override
    wins ties (built-ins still win with a strictly longer, more-specific key)."""
    if not model:
        return None
    norm = normalize(model)
    overrides = load_overrides()
    # Exact match — override beats built-in.
    if norm in overrides:
        return overrides[norm]
    if norm in RATES:
        return RATES[norm]
    # Longest-prefix match across both tables — `claude-sonnet-4-5-custom-suffix`
    # finds the 4-5 row; `gpt-5.5` finds the `gpt-5` family row. Overrides are
    # searched first so an equal-length override prefix wins the tie.
    best_key, best_val = _prefix_match(norm, overrides, "")
    best_key, rates_val = _prefix_match(norm, RATES, best_key)
    if rates_val is not None:
        best_val = rates_val
    return best_val


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
    try:
        cost = compute_cost_usd(model, *tokens)
    except ValueError as exc:
        # A malformed price override must fail loudly — block the commit so the
        # operator fixes `.governance/conf/agent-token-accounting.conf`.
        print(f"rates cost: {exc}", file=sys.stderr)
        return 2
    if cost is None:
        # Unpriced → exit 3 so the pre-commit hook can distinguish this
        # from a priced row that happens to total $0. Stderr carries the
        # human-readable reason; stdout is empty.
        print(
            f"rates cost: model {model!r} has no entry in RATES and no "
            f"family-prefix fallback matches; add an entry to lib/rates.py",
            file=sys.stderr,
        )
        return 3
    print(f"{cost:.4f}")
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
