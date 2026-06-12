# issue-204 — conf-knob-doc-sync: scalar conf_get knobs stay documented with matching defaults

Closes [#204](https://github.com/Duaility/governance-kit/issues/204).

## Checklist

- [x] Directive triple authored
- [x] Smoke tests pass and fail correctly
- [x] Constitution and Evolution Log updated
- [x] Lockfile synced

## What changed

- **Directive triple authored.** New repo-local directive `conf-knob-doc-sync` in the `duaility/governance-kit` pack (`.governance/packs/duaility/governance-kit/directives/conf-knob-doc-sync/` — `check.sh`, `directive.yaml`, `constitution.md`). The check scans every `packs/*/directives/*/check.sh` for literal `conf_get <id> <KEY> <default>` reads and requires (1) a sibling `config.conf` template exists, (2) the KEY is documented in it, and (3) the code's literal default appears in it — either as a commented `KEY=<default>` line (postgres-style) or as `Default <default>` / `default of <default>` prose, with value boundaries so `Default 5.` matches default `5` but `Default 50` and `Default 5.5` do not. Same-line waiver: `governance: allow-conf-knob-doc-sync <reason>`. The check no-ops in repos without a `packs/` tree, so it is inert anywhere but this source repo.
- **Constitution and Evolution Log updated.** New `### conf-knob-doc-sync` subsection appended to the `## duaility/governance-kit` section of `CONSTITUTION.md`, plus a dated Evolution Log entry. Rationale recorded: scalar defaults intentionally live as constants at the `conf_get` read site (only merge-semantics list directives ship a `defaults.conf`), so the `config.conf` comment is the only user-facing statement of the default — this lint is the mechanism that keeps it honest.
- **Lockfile synced.** `.governance/packs.lock` `duaility/governance-kit` entry upserted via the pinned kit's `packverb lock-add` to include the new directive id alongside the three existing local directives.

## Out of scope

- Scanning the repo-local pack itself (`.governance/packs/duaility/governance-kit/`) or vendored consumed-tree copies — the drift class lives where directives are authored, the `packs/` source tree. Vendored copies are materialized from release tags and lag by design.
- Knobs read through non-`conf_get` mechanisms (e.g. `agent-token-accounting`'s price table in `lib/rates.py`) — that table is pack-owned code refreshed on `pack update`, a different defaults channel.
- A kit-bundled (shipped-to-consumers) version of this lint — it is meaningful only in the kit source repo, so it stays a repo-local dogfood directive.

## Decisions

- **Heuristic doc-pattern matching.** The "documented default" test accepts two textual forms (`KEY=<default>` or `Default <default>` prose) rather than mandating one canonical format, because both already exist across the seven current knobs and forcing one form would churn templates for no behavioral gain.
- **Known weakness accepted: cross-knob false pass.** When one directive has two knobs (e.g. `repo-hygiene`), a `Default <n>` string belonging to knob A could satisfy knob B if their values collide after a drift. Tightening this needs per-key prose association, which the comment format does not reliably support; accepted as a best-effort lint.
- **Non-literal defaults skipped.** A `conf_get` call whose default is a variable or substitution is only checked for KEY documentation, not default equality — the value is not statically knowable in bash.

## Verification

Smoke tests pass and fail correctly:

```sh
# green on the current tree (all 7 existing knobs documented correctly)
bash .governance/run.sh conf-knob-doc-sync

# red on injected drift (verified during authoring, then reverted):
#   - changed `conf_get repo-hygiene MAX_FILE_SIZE_MB 5` -> 7 in packs/foundation/
#     directives/repo-hygiene/check.sh -> violation "does not document the code
#     default for MAX_FILE_SIZE_MB (code says 7)"
#   - added an undocumented `conf_get doc-freshness GRACE_DAYS 14` knob ->
#     violation "knob GRACE_DAYS is not documented in .../config.conf"
bash .governance/packs/duaility/governance-kit/directives/conf-knob-doc-sync/check.sh

# full suite
bash .governance/run.sh
```
