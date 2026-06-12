# issue-206 — move agent-token-accounting's default rate card into a pack-owned defaults.conf

Closes [#206](https://github.com/Duaility/governance-kit/issues/206).

## Checklist

- [x] Add defaults.conf with the rate card as `rate` rows
- [x] Refactor rates.py: shared parser, load_defaults / load_overrides, drop RATES literal
- [x] Missing defaults.conf fails loudly
- [x] Update config.conf + README
- [x] Add eval assertions locking defaults.conf as the price source

## What changed

- **Add defaults.conf with the rate card as `rate` rows.** New `packs/audit/directives/agent-token-accounting/defaults.conf` (directive root, sibling of `check.sh`) holds the full model price table as `rate <model> <base_input> <cache_create> <cache_read> <output>` rows — the same row format as the per-repo override file. Every price from the old `RATES` dict is preserved verbatim (Claude family fallbacks, Opus/Sonnet/Fable version rows, GPT-5 family). It carries the family-fallback and longest-prefix explanation as `#` comments.
- **Refactor rates.py: shared parser, load_defaults / load_overrides, drop RATES literal.** The hardcoded `RATES` dict is gone. A single `_parse_rate_rows(path)` parses the `rate`-row format (raising `ValueError` on any malformed row); `load_defaults()` reads the pack-owned `defaults.conf` (resolved from `__file__`, so it travels with the directive folder) and `load_overrides()` reuses the same parser on the user overlay. `lookup()` merges defaults + overrides with the identical precedence as before (exact override > exact default > longest-prefix, overrides winning ties). The module docstring and the unpriced-model CLI error now point at `defaults.conf`.
- **Missing defaults.conf fails loudly.** `load_defaults()` raises a clear `ValueError` ("pack-owned rate card not found — reinstall or `governance pack update`") if the file is absent, surfaced as CLI exit 2. A broken install blocks with a named cause rather than silently emptying the table and rejecting every commit as "unpriced model".
- **Update config.conf + README.** The override template (`config.conf`) and the directive `README.md` (the cost-usd prose, the family-fallback paragraph, the file-map table, and the invoice-reconciliation note) now reference `defaults.conf` instead of `RATES` / "the rate table in lib/rates.py". Added a `defaults.conf` row to the README file map.
- **Add eval assertions locking defaults.conf as the price source.** `evals/test.sh` Case 15 gains two assertions that, with no overlay present, an exact default model (`claude-sonnet-4-5` → $18.00) and a family-prefix fallback (`claude-opus-4-99` → $5.00) price from `defaults.conf`. The existing override-merge and malformed-row cases are unchanged and still pass.

## Out of scope

- The user-overlay format and path — unchanged (`.governance/conf/<owner>/<pack>/agent-token-accounting.conf`, same `rate` rows).
- The directive triple (`directive.yaml`, `check.sh`, `constitution.md`) — untouched. The enforced behavior and the `rates.py cost` CLI contract are identical; this is a pure data-location refactor, so no constitution amendment or evolution-log entry is required.
- Migrating the `defaults.conf` to lib.sh `conf_list` — deliberately not done; the rate table needs normalize + longest-prefix + 4-tuple values that `conf_list` can't express, so `rates.py` parses it (symmetric with how it already parses the overlay).
- The committed consumed tree under `.governance/packs/` — Lane 1, materialized from release tags by `pack update`, never hand-edited. This PR touches `packs/` only.

## Decisions

- **Reused one parser for both files rather than two.** The defaults and the overlay are now byte-identical in format, so a single `_parse_rate_rows` serves both. This is the concrete win the refactor buys: previously the defaults were a Python dict literal and the overrides were `rate` text rows — two formats for one concept.
- **defaults.conf is parsed by rates.py, not lib.sh `conf_list`.** Accepted deviation from the generic `defaults.conf` contract: the rate card's 4-tuple values and prefix-matching lookup can't be expressed as a flat `conf_list`. Since the directive already had bespoke Python conf parsing for overrides, this makes the two halves symmetric rather than introducing a new parser. The primary value of `defaults.conf` (pack-owned, `pack update`-refreshed, separate from the survive-update overlay) is fully realized.
- **Missing defaults.conf raises rather than degrading to empty.** Unlike `conf_get`'s graceful-default behavior for scalars, an absent pack-owned rate card is a broken install, not a normal state — failing loud with a named cause beats silently blocking every commit as "unpriced".

## Verification

```sh
# Direct lookup paths from defaults.conf (no overlay):
python3 packs/audit/directives/agent-token-accounting/lib/rates.py cost claude-sonnet-4-5 1000000 0 0 1000000  # 18.0000 (exact default)
python3 packs/audit/directives/agent-token-accounting/lib/rates.py cost claude-opus-4-7-20250929 1000000 0 0 0 # 5.0000 (date-suffix strip)
python3 packs/audit/directives/agent-token-accounting/lib/rates.py cost claude-opus-4-99 1000000 0 0 0          # 5.0000 (family fallback)
python3 packs/audit/directives/agent-token-accounting/lib/rates.py cost claude-opus-4-1 1000000 0 0 0           # 15.0000 (version beats family)
python3 packs/audit/directives/agent-token-accounting/lib/rates.py cost totally-unknown 1000000 0 0 0; echo $?  # exit 3, unpriced

# Directive eval suite (materializes the directive fresh from packs/ source):
bash scripts/test-packs.sh    # 5 packs, 19 directives, 19 evals — all pass, incl. the 2 new defaults.conf assertions

# Full kit-internal test umbrella (the pre-commit gate) and the dogfood suite:
bash scripts/test.sh          # exit 0
bash .governance/run.sh       # all 21 directives pass
```
