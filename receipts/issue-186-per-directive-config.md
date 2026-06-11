# Receipt: first-class per-directive configuration (issue-186)

Every directive can now ship configuration that target-repo users tweak per
repo, and pack updates never clobber those tweaks. Replaces the ad-hoc mix of
root-level `*.conf` files, kit-asset templates, and `GOVERNANCE_*` env vars with
a uniform layered model.

## Checklist

- [x] `conf_file` / `conf_get` / `conf_rule_lines` / `conf_list`
- [x] `seed_directive_conf`
- [x] `config_drift`
- [x] reported under a new `conf_seeded` key
- [x] move their default lists into `defaults.conf`
- [x] `agent-token-accounting`'s `lib/rates.py` merges `rate` rows
- [x] Dogfood
- [x] Docs

## Design

Two pack-owned files per configurable directive, plus a user overlay:

- `defaults.conf` (pack-owned, list directives only) — the live default list, in
  the directive folder, refreshed by `pack update`/`reset`. Never hand-edited.
- `config.conf` (pack-owned) — an all-comment template that seeds the overlay.
- `.governance/conf/<id>.conf` (user-owned) — the overlay; deltas only. Seeded
  once on fresh install; never rewritten by any lifecycle verb afterward.

Effective config = `defaults.conf` layered with the overlay: a bare line **adds**,
`!item` **removes** a default (gitignore-style negation; whitespace-normalized so
a single-spaced `!` line matches a column-aligned default), `KEY=value`
**overrides** a scalar (env `GOVERNANCE_<KEY>` still wins). This decouples
"keep receiving new pack defaults" from "customize" — no frozen fork.

## What changed

- **Runtime** (`governance/assets/dot-governance/lib.sh` + dogfood `.governance/lib.sh`):
  added `conf_file` / `conf_get` / `conf_rule_lines` / `conf_list` (+ `_conf_trim`/`_conf_norm`).
- **Installer** (`install.sh`): `seed_directive_conf` (augment-only, echoes seeded path).
- **Engines**: `initapply.py` seeds + deletes the hardcoded freshness/integrity
  special case; `packapply.py` seeds on fresh add only and deletes conf on remove;
  `packplan.py` adds `config_drift` / `user_conf` / `conf_files`; `resetapply.py`
  drops conf only under `--drop-handauthored`. Seeded paths reported under a new
  `conf_seeded` key — **not** `install_assets_seeded` (the deterministic path
  inside `.governance/` is its own ledger).
- **Directives** (`packs/core/directives/`): `doc-integrity`, `commit-message-format`,
  `toolchain-config-protection` move their default lists into `defaults.conf` and
  read via `conf_list`; `doc-freshness`, `internal-doc-links` move to overlay paths;
  `repo-hygiene`, `required-docs`, `doc-freshness` window read scalars via `conf_get`;
  `agent-token-accounting`'s `lib/rates.py` merges `rate` rows from its conf over the
  built-in table (malformed row blocks the commit). Each gets a `config.conf`.
  Deleted `governance/assets/{integrity,freshness}.conf`.
- **Dogfood**: removed `.governance/{integrity,freshness}.conf` (rules now ship in
  the consumed-tree `defaults.conf`), dual-edited the consumed core tree and lib.sh,
  updated the affected `CONSTITUTION.md` Directive subsections + appended an
  Evolution Log entry.
- **Docs**: INIT/UPDATE/RESET/UNINSTALL flows + matrix, PACK_VERBS, DIRECTIVE_VERBS,
  PACK_AUTHORING, DIRECTIVE_AUTHORING, DIRECTIVES_CATALOG, INSTALL_SCHEMA,
  RELEASE_FLOW, AGENT_TOKEN_ACCOUNTING, AGENTS.md tree, the amend template, the
  docs-site `.mdx` pages, and README.

## Decisions

- **Overlay over replace-or-freeze.** Seeding active defaults into the user file
  would freeze a fork; an all-comment template can't remove a baked default. The
  layered `defaults.conf` + overlay resolves both, uniformly.
- **`!` for removal, not `-`.** `!` is the established line-config negation
  convention (gitignore, dockerignore, ripgrep); `-` collides with YAML list-item
  syntax.
- **No legacy-path fallback.** V0 — this repo's own conf files are `git mv`'d in
  the same change; migrated directives read only `.governance/conf/<id>.conf`.
- **No version bumps.** Release-only policy; ships as a `feat`, versions on the
  next `chore(release)`.

## Out of scope

- Re-pinning the dogfood lock (`.governance/packs.lock`) onto this directive set —
  follows the next `core` release. The consumed tree drifts from the `core/v0.4.0`
  pin by design until then.

## Verification

```sh
bash scripts/test.sh        # ✓ all kit-internal layers (engines, install.sh, runtime, schema, 18 evals)
bash scripts/test-packs.sh  # ✓ 1 pack, 18 directives, 18 evals + fresh-repo init smoke
bash .governance/run.sh     # ✓ governance: all 17 directive(s) passed
```

Spot checks performed against throwaway git repos: `conf_list` add/`!`-remove with
whitespace-normalized matching; `rates.py cost` honoring an override row, a new
model, and failing on a malformed row; `seed_directive_conf` augment-only seeding.
