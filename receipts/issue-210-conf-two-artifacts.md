# issue-210 — collapse per-directive config to two artifacts (defaults.conf + overlay)

Closes [#210](https://github.com/Duaility/governance-kit/issues/210).

## Checklist

- [x] `conf_get` resolves `defaults.conf`
- [x] Scalar directives became `defaults.conf` rows
- [x] List/opt-in directives folded `config.conf` into `defaults.conf` comments
- [x] All nine `config.conf` templates deleted; the overlay seeds from one generic kit stub
- [x] `conf-knob-doc-sync` is now exact
- [x] Docs, templates, evals

## What changed

Configuration is now **two artifacts, one writer each** (the systemd/sysctl.d model), replacing the prior up-to-three-places story (code constant + `config.conf` prose + `defaults.conf`).

- **`conf_get` resolves `defaults.conf`.** `kit/assets/dot-governance/lib.sh` (mirrored to the committed `.governance/lib.sh`): `conf_get <id> <KEY> <defaults-file>` now resolves env `GOVERNANCE_<KEY>` > user overlay `KEY=` > pack-owned `defaults.conf` `KEY=` row. The in-code default constant is gone; a read knob whose `defaults.conf` is missing or lacks the row **fails loud** (stderr + non-zero), the broken-install precedent #206's `rates.py` set. A documented transitional branch keeps treating a bare-literal 3rd arg as an in-code default so directive folders vendored from a pre-#210 release (which still pass literal defaults) keep working against this newer `lib.sh` during the one-release dogfood lag.
- **Scalar directives became `defaults.conf` rows.** `repo-hygiene` (`MAX_FILE_SIZE_MB`, `FILE_SIZE_LIMIT`), `required-docs` (`AGENTS_MD_MIN`/`_MAX`/`_MIN_LINKS`, `ARCHITECTURE_MIN`), and `doc-freshness` (`FRESHNESS_DAYS`) each ship a `defaults.conf` with `KEY=value` rows + doc comments; their `check.sh` call sites pass `"$(dirname "$0")/defaults.conf"` and gained a one-line missing-file guard.
- **List/opt-in directives folded `config.conf` into `defaults.conf` comments.** `doc-integrity`, `toolchain-config-protection`, `commit-message-format`, and `agent-token-accounting` moved their overlay-syntax + worked-example prose into `defaults.conf` header comments. `internal-doc-links` (no scalar knob, purely opt-in) gained an all-comment `defaults.conf` documenting `root`/`exclude` — which, unlike the old `config.conf`, is refreshed on `pack update`. `agent-steering-accounting` folded its lexical-phrase + `CANDIDATE_MAX_LEN` docs in and added a live `CANDIDATE_MAX_LEN=2000` row that its Python `lib/conf.py` `get_int` now reads (env > overlay > `defaults.conf` row > the broken-install fallback arg).
- **All nine `config.conf` templates deleted; the overlay seeds from one generic kit stub.** New `kit/assets/conf-overlay.stub.conf` is a directive-agnostic header; `install.sh`'s `seed_directive_conf` interpolates the directive id and its `defaults.conf` path and writes it (gated on the directive shipping a `defaults.conf`, augment-only). `initapply.py`, `packapply.py`, `packplan.py` (`config_drift` now keys off `defaults.conf` only), and `resetapply.py` updated to match.
- **`conf-knob-doc-sync` is now exact.** The repo-local dogfood lint went from a heuristic prose match to the structural identity "every `conf_get <id> <KEY>` in a bundled `check.sh` has a `<KEY>=` row in its sibling `defaults.conf`". No value or prose matching, so both prior weaknesses (two-form text matching, cross-knob value-collision false-pass) vanish. `check.sh`, `directive.yaml`, `constitution.md`, the live `CONSTITUTION.md` subsection, and an Evolution Log entry all moved together.
- **Docs, templates, evals.** PACK_AUTHORING / DIRECTIVE_AUTHORING / DIRECTIVES_CATALOG / INIT_FLOW / INSTALL_SCHEMA / PACK_VERBS / DIRECTIVE_VERBS / UNINSTALL_MATRIX, the `directive.template.sh` authoring stub, AGENTS.md, and the kit-internal tests (`test-install-sh.sh`, `test-init.py`, `test-packverb-apply.py`, `test-runtime.sh`) all updated to the two-artifact model.

## Out of scope

- `agent-token-accounting`'s rates `defaults.conf` (#206) was already on this model and keeps its bespoke Python parser; only its now-deleted `config.conf` prose moved into `defaults.conf` comments.
- The committed Lane-1 consumed tree under `.governance/packs/` is left untouched — it catches up at release time via `governance pack update` (`consumed-tree-integrity` would reject a hand-edit). So during the lag the vendored directives still pass literal defaults to `conf_get`, which the transitional `lib.sh` branch serves.

## Verification

```sh
# new conf_get: defaults.conf resolution, env/overlay precedence, fail-loud, literal compat
bash scripts/test-runtime.sh            # 62 assertions

# seeding from the generic stub (augment-only; gated on defaults.conf)
bash scripts/test-install-sh.sh         # 78 assertions
uv run --with PyYAML python scripts/test-init.py
uv run --with PyYAML python scripts/test-packverb-apply.py

# every pack directive's evals pass on the migrated config
bash scripts/test-packs.sh              # 5 packs, 19 directives

# Lane 1 — the committed dogfood suite (new exact conf-knob-doc-sync green on packs/ HEAD;
# the new backward-compatible conf_get serves the OLD vendored check.sh)
bash .governance/run.sh                 # 21 directives

# Lane 2 — HEAD smoke: the NEW packs/ repo-state directives run against the NEW lib.sh
bash scripts/dogfood-smoke.sh
```

All green: 62 + 78 runtime/install assertions, the init/pack-apply engine suites, 19 pack-directive evals, the 21-directive Lane-1 suite, and the Lane-2 HEAD smoke.

## Decisions

- **`lib.sh` keeps a transitional literal-default branch.** Both dogfood lanes share the committed `.governance/lib.sh`: Lane 1 runs the still-vendored pre-#210 `check.sh` (which pass literal defaults like `conf_get repo-hygiene MAX_FILE_SIZE_MB 5`), Lane 2 runs the new `packs/` `check.sh` (which pass a `defaults.conf` path). A bivalent `conf_get` — `*/defaults.conf` ⇒ new fail-loud resolution, bare literal ⇒ pre-#210 default — is the only way to keep both green without bumping the kit version (release-only). The branch is documented as removable once no released directive passes a literal. The issue's "delete the code-constant fallback" is satisfied where it matters: every `packs/` call site and the `conf-knob-doc-sync` drift class.
- **Source and committed `lib.sh` stay byte-identical.** Rather than diverge a clean source from a compat-shimmed committed copy, both carry the same bivalent `conf_get`. Lane 1 must be an honest install of the kit, so the committed copy can't be a one-off frankenstein.
- **`conf-knob-doc-sync` stays a repo-local dogfood directive** (meaningful only in the kit source repo) and keeps its name — the check now asserts a knob-read ⇔ defaults-row identity, which the name still fits.
- **`agent-steering-accounting`'s `CANDIDATE_MAX_LEN` migrated to `defaults.conf`** even though it is read in Python, not bash `conf_get` (so `conf-knob-doc-sync` doesn't lint it). The value now lives once in `defaults.conf`; `get_int`'s `default` arg is a documented broken-install fallback.
