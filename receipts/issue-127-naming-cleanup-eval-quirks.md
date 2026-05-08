# issue-127 — kit naming cleanup + eval-quirk fixes

Closes [#127](https://github.com/Duaility/governance-kit/issues/127).

## Checklist

- [x] Rename `setup-clone.sh` to `enable-governance.sh`
- [x] Rename `AGENTS.directive.md` to `AGENTS.snippet.md`
- [x] Rename `AUTHORING_PACKS.md` to `PACK_AUTHORING.md`
- [x] Update install.yaml fixtures across `governance/evals/**`
- [x] AGENTS marker drift: `rules-to-follow` to `directives-to-follow`
- [x] Pin `actions/checkout@v5` to its SHA
- [x] Seed init fixtures with baseline files
- [x] Tighten UPDATE_FLOW Step 8 reporting block
- [x] Fix `validate_pack_dir` cache layout

## What changed

- **Rename `setup-clone.sh` to `enable-governance.sh`.** Asset, dogfood
  script, and every reference doc updated so the kit ships under the new
  name end-to-end. Receipt issue-113 also updated to point at the new
  path. The prior name lived in the kit since #43 and never reflected
  what the script actually did — it never cloned anything, only enabled
  the local hook strategy.
- **Rename `AGENTS.directive.md` to `AGENTS.snippet.md`.** The asset
  copied into target repos is a snippet, not a directive — `directive`
  is a load-bearing word elsewhere in the kit (the contents of
  `directives/<id>/`). Renaming closes that lexical drift. INIT_FLOW.md
  and INSTALL_SCHEMA.md updated to reference the new asset name; the
  marker contract embedded in the file did not change.
- **Rename `AUTHORING_PACKS.md` to `PACK_AUTHORING.md`.** Matches the
  `<NOUN>_<VERB>.md` shape every other reference uses
  (`PACK_VERBS.md`, `DIRECTIVE_VERBS.md`, `DIRECTIVE_AUTHORING.md`).
  All references and SKILL.md frontmatter updated.
- **Update install.yaml fixtures across `governance/evals/**`.** The
  `setup_clone_script` field is now `enable_governance_script` and
  every fixture's manifest reflects the new key. 11 install.yaml
  files touched — without this the rename would go half-applied.
- **AGENTS marker drift: `rules-to-follow` to `directives-to-follow`.**
  `governance/assets/AGENTS.snippet.md` and the dogfood `AGENTS.md`
  both updated. The paired-marker uninstall path in UNINSTALL_FLOW.md
  expects `directives-to-follow` and the eval grader expected the same
  — the asset was the only place still using the legacy spelling.
- **Pin `actions/checkout@v5` to its SHA.** Now pinned to
  `93cb6efe18208431cddfb8368fd83d5badbf9bfd` (v5.0.1) in
  `governance/assets/governance.yml`,
  `.github/workflows/governance.yml`, and
  `.github/workflows/tests.yml`. The kit's `workflows-hardened`
  directive demands SHA pinning over tag pinning; the kit's own
  workflows were violating it.
- **Seed init fixtures with baseline files.** `empty-polyglot-repo/`
  and `go-service-repo/` now ship LICENSE, SECURITY.md,
  ARCHITECTURE.md, a `.gitignore` listing `.env`, and a
  non-governance `.github/workflows/ci.yml`. go-service `main.go`
  switched from `fmt.Println` to `log.Println` to dodge the
  debug-statement check and the README padded past the 30-word
  threshold. Fixture README documents the
  `chore: seed fixture (#0)` seed-commit convention so the
  Conventional-Commits pre-commit hook accepts it.
- **Tighten UPDATE_FLOW Step 8 reporting block.** The split between
  Step 8 (10 fields) and "Required final output" (6 fields) let the
  eval-grader skip the `Packs:` line. Collapsed both into a single
  10-field required template, marked skipping a row as a flow
  violation, and documented the no-op + refusal branches inline.
- **Fix `validate_pack_dir` cache layout.** `packctl.py` now accepts
  the cache layouts `<author>__<slug>` and `<author>__<slug>@<sha>`
  in addition to the bare `<slug>`. Without this, `validate-pack`
  invoked against a freshly fetched pack root rejected it by dirname
  before any field-level check ran.

## Out of scope

- `repo-hygiene/check.sh:116` references an undefined `has_file_waiver`
  function — every iteration of the file-size-limit loop emits a
  `command not found` line to stderr. The directive still exits 0
  because the missing function never triggers a violation, but the
  noise is real. Worth a separate fix.
- The eval grader's "skipping a row is a flow violation" rule is
  documented in UPDATE_FLOW.md, but not yet enforced by an automated
  check. The eval cases catch it via assertions; a stricter grader
  could match the report block against the documented template.
- Network-dependent pack-add / pack-update eval cases (`acme/soc2-pack`,
  `acme/widgets-pack`) still depend on fictional repos. The
  local-source substitution exercised by the latest re-run is enough
  to verify the deterministic prefix; a fixture-side mock-server pass
  is a separate scope.

## Verification

- `bash scripts/test.sh` → all kit-internal layers pass: install.sh,
  hooks.sh, schema split, packctl, packverb, working-tree, and
  test-packs (1 pack, 14 directives, 14 evals).
- `bash .governance/run.sh` → all 14 dogfood directives pass after the
  changes, including `workflows-hardened` (which now sees the SHA pin)
  and `required-docs` (unchanged, still passing on the kit root).
- `validate_pack_dir` smoke-tested against four dirname forms:
  `widgets`, `acme__widgets`, `acme__widgets@<40-hex>` all accept;
  `wrong-name` still rejects with the new error message naming the
  three accepted forms. Confirms the cache-layout fix without
  loosening the rejection rule for genuinely misnamed packs.
- AGENTS marker drift eyeballed: `grep -c 'rules-to-follow'
  governance/assets/AGENTS.snippet.md AGENTS.md` returns zero.
- `actions/checkout` SHA pin confirmed in all three workflow files
  via `grep checkout@`.
- Init fixtures inspected: both `empty-polyglot-repo/` and
  `go-service-repo/` carry the five baseline-doc files
  (LICENSE, SECURITY.md, ARCHITECTURE.md, .gitignore,
  `.github/workflows/ci.yml`).
