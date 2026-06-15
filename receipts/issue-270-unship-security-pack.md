# issue-270 — Unship the security pack from v0

Drops the `governance-kit/security` concern pack from the kit's bundled offering for v0. This supersedes the issue's original proposal (migrate `secrets-hygiene` / `pinned-dependencies` / `token-permissions` to gitleaks / actionlint / scorecard backends): rather than re-back the bash checks with dedicated tools, security governance is removed from the v0 surface entirely. Scope is **unship only** — the source pack and every surface that claims it ships are removed; the dogfood (`.governance/`) and `CONSTITUTION.md` are left to catch up at the next release via the normal `governance update` flow.

## Checklist

- [x] Delete the `governance-kit/security` pack from the kit source (`packs/security/`)
- [x] Scrub security from every source surface that enumerates the bundled packs (README, AGENTS, ARCHITECTURE, docs site, kit references)
- [x] Repoint the live `validate-pack` test fixture and the one broken doc link off the deleted pack
- [x] Update the `init` eval that assumed the security selection
- [x] Leave `.governance/` and `CONSTITUTION.md` to catch up at the next release (dogfood lag by design)

## What changed

- **Deleted the source pack.** `git rm -r packs/security/` removed the pack root, its `pack.yaml`, and the three directives (`secrets-hygiene`, `token-permissions`, `pinned-dependencies`) with their checks, constitution snippets, and evals. `packs/` now holds five concern packs (`foundation`, `docs`, `commits`, `audit`, `architecture`).
- **Scrubbed the bundled-set enumerations.** Every source surface that listed security as a bundled pack was updated to the new five-pack set: `README.md` (pack table + "Compared to" coverage row), `AGENTS.md` (dogfood paragraph, repo-layout comment, "Adding a new directive" count), `ARCHITECTURE.md` (pack list — corrected to five and added the previously-missing `architecture` bullet), `docs/concepts/packs.mdx`, `docs/reference/directive-catalog.mdx` (frontmatter, intro count, `minimal` preset row, and the whole `## governance-kit/security` section), `docs/guide/quickstart.mdx` (`minimal` preset blurb), `docs/concepts/versioning.mdx` (example tag + release command), and the kit references `DIRECTIVES_CATALOG.md` (count, table row, consolidated-directive list, preset union, and the security section), `INIT_FLOW.md`, `PACK_AUTHORING.md`, `PACK_VERBS.md`, `LOCK_SCHEMA.md`, `VERSIONING.md`, `RELEASE_FLOW.md`, plus the example comments in `kit/assets/dot-governance/run.sh` and `scripts/release.sh`. Illustrative example pack ids that pointed at `security` were swapped to a surviving pack (`docs` / `foundation`).
- **Repointed the live test fixture and the one broken doc link off the deleted pack.** `scripts/test-packverb.py`'s `validate-pack` public-command test ran against `packs/security`; it now runs against `packs/foundation`. `kit/references/VERSIONING.md` had the only tracked markdown link into the deleted tree (`[packs/security/pack.yaml]`); it now points at `packs/foundation/pack.yaml`.
- **Updated the init eval that assumed the security selection.** `kit/evals/init/evals.json` eval #3 was premised on "make sure security rules are included"; it is rewritten to a security-free tight-Go-selection scenario (foundation-leaning directives, Go-relevant over Python/JS-specific, stylistic excluded) so the eval no longer asserts a pack the kit does not ship.
- **Left `.governance/` and `CONSTITUTION.md` to catch up at the next release.** The dogfood lock still pins `governance-kit/security@security/v0.2.0` and `CONSTITUTION.md` still carries the security subsections; both move only through the post-release `governance update` flow, by design — `.governance/` lags `packs/` by one release. No `.governance/` file and no `CONSTITUTION.md` directive section was hand-edited.

## Out of scope

- **Migrating the security checks to gitleaks/actionlint/scorecard** — the issue's original proposal, now superseded by the decision to drop security from v0 rather than re-back it.
- **The release catch-up** — re-pinning `.governance/packs.lock` off `governance-kit/security` and removing the security subsections from `CONSTITUTION.md` happen at the next release via `governance update`, not in this PR. Until then the dogfood continues to enforce the three security directives on this repo (the documented one-release lag).
- **Eval/fixture `CONSTITUTION.md` files** under `kit/evals/*/files/*/` that mention security — self-contained test fixtures, left per the standing convention (see the #200 Evolution Log entry).

## Decisions

- **Unship, not migrate.** The maintainer chose to remove security from the v0 surface rather than do the tool-backend migration #270 originally proposed. The issue was repurposed (title + acceptance checklist) and the original proposal preserved under a collapsed section for history.
- **Source-only, dogfood lags by design.** Per the two-lane dogfood model, directive/pack PRs touch `packs/` only; the consumed `.governance/` tree is regenerated by the real `governance update` verb in a post-release PR. So this PR deliberately leaves `.governance/` and `CONSTITUTION.md` carrying security — `consumed-tree-integrity` / `managed-tree-integrity` stay green because the pins still resolve to the real `security/v0.2.0` tag.
- **Reverted the `release.yml` comment edit.** A parallel one-word comment tidy in `.github/workflows/release.yml` would have tripped `toolchain-config-protection` (which guards `.github/workflows/`) and forced an `allow-toolchain-config` waiver for no real benefit — the comment is an ellipsis-guarded example and not wrong. Left untouched.
- **Counts made honest, not just decremented.** `ARCHITECTURE.md` and `INIT_FLOW.md` previously under-counted (omitted the `architecture` pack); while fixing the count I added the missing `architecture` bullet so each enumeration reflects the true five-pack set rather than introducing a new off-by-one.

## Verification

Each acceptance item, confirmed:

- **Delete the `governance-kit/security` pack from the kit source (`packs/security/`)** — the directory is gone and the kit-internal suite now reports five packs / 18 directives (was six / 21).
- **Scrub security from every source surface that enumerates the bundled packs (README, AGENTS, ARCHITECTURE, docs site, kit references)** — a scoped grep finds no remaining `governance-kit/security` or `packs/security` reference outside frozen history (`CONSTITUTION.md` Evolution Log) and the generic `SECURITY.md` advisory link.
- **Repoint the live `validate-pack` test fixture and the one broken doc link off the deleted pack** — `test-packverb.py` validates `packs/foundation`; `VERSIONING.md`'s link targets `packs/foundation/pack.yaml`. Both confirmed by the green `scripts/test.sh` run and the link grep.
- **Update the `init` eval that assumed the security selection** — `evals.json` eval #3 no longer names a security directive or `governance-kit/security`.
- **Leave `.governance/` and `CONSTITUTION.md` to catch up at the next release (dogfood lag by design)** — `git status` shows no change under `.governance/` and no change to `CONSTITUTION.md`; the dogfood suite stays green against the still-pinned `security/v0.2.0`.

Kit-internal test umbrella green (security pack gone, fixture repointed):

```
$ bash scripts/test.sh
…
✓ test-packs: 5 pack(s), 18 directive(s), 18 eval(s) passed
…
✓ all kit-internal test layers passed
```

No security-pack references remain in active source surfaces:

```
$ git grep -nI -e 'governance-kit/security' -e 'packs/security' \
    -- ':!CONSTITUTION.md' ':!receipts/**' ':!plans/**' ':!.governance/**' ':!kit/evals/**/files/**'
# (no output)
```

Dogfood and `CONSTITUTION.md` untouched (the deliberate one-release lag):

```
$ git status --porcelain -- .governance/ CONSTITUTION.md
# (no output)
```

## Accounting

<!-- Accounting rows are maintained by the agent-token-accounting and agent-steering-accounting pre-commit hooks. Keys are opaque — do not parse. -->

### Costs

| cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | cum-input | cum-cache-create | cum-cache-read | cum-output | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| claude-code-cbab4e97-f8c-1781534772-1 | claude-code | cbab4e97-f8c8-4287-b4b3-e21a89094037 | #270 | claude-opus-4-8 | 41329 | 488220 | 30629044 | 223398 | 752947 | 24.1575 | 41329 | 488220 | 30629044 | 223398 |  |
