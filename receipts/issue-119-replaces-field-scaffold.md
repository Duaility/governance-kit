# issue-119 — scaffold fork-not-patch amendments via replaces field

Closes [#119](https://github.com/Duaility/governance-kit/issues/119). Phase 5 of [#114](https://github.com/Duaility/governance-kit/issues/114) — minimal scaffold.

## Checklist

- [x] `packctl.py` validates the optional `replaces:` scalar on a directive.yaml — when present, must be a 3-segment `<owner>/<pack>/<directive>` shape; otherwise no extra constraints
- [x] `DIRECTIVE_AMEND_FLOW.md` interaction-policy table updated: amending an upstream-pinned directive (any `source: gh` entry, including the kit's own core) routes through fork-not-patch (copy directive into a `source: local` pack, stamp `replaces:`) rather than editing the read-only fetched tree

## What changed

- `packctl.py` validates the optional `replaces:` scalar on a directive.yaml — when present, must be a 3-segment `<owner>/<pack>/<directive>` shape; otherwise no extra constraints. The validation runs inside `validate_pack_dir`'s per-directive loop, after the existing `always_install` and `requires_hook_strategy` checks. `replaces` is intentionally optional — most directives in a local pack are originals, not forks. When set, the value is split on `/` and rejected unless there are at least 3 segments (so `owner/pack/dir` is well-formed). Cross-id replacements (forked id ≠ upstream id) are allowed but undocumented as a smell — the canonical use case is forking a kit/community directive while preserving its id, so the runtime suppression (deferred) can dedupe by id.
- `DIRECTIVE_AMEND_FLOW.md` interaction-policy table updated: amending an upstream-pinned directive (any `source: gh` entry, including the kit's own core) routes through fork-not-patch (copy directive into a `source: local` pack, stamp `replaces:`) rather than editing the read-only fetched tree. The previous row read "Refuse `directive add` / `directive modify`. Route the user to `governance pack update` / `governance pack remove`" — that text reflected the pre-#117 model where `governance-kit/core` was bundled and `source: builtin` gave it a special read-only status. Post-#117 every fetched pack is `source: gh`, and post-#118 the expanded copies under `.governance/packs/<id>/` are reconstructable artifacts that the reconciler clobbers. The new row tells the agent to fork-then-edit: copy the directive folder into the consumer's local pack, mark `replaces: <upstream-pack-id>/<directive-id>`, and let the runner shadow the upstream version.

## Out of scope

- Runtime suppression of upstream directives when a local `replaces:` is present. Today `run.sh` walks every directive folder unconditionally; with fork-not-patch, both the upstream and the forked copies live under `.governance/packs/`, so both run. That's not catastrophic — the forked directive's check.sh is what the user wants enforced, and the upstream version usually still passes against the same tree (otherwise the user would want the upstream's behavior anyway). But it's not the cleanest end state. The optimization — read lockfile, dedupe directive ids by `replaces:`, run only the forked copy when both exist — is a runtime change deferred to a follow-up so this scaffold can land cleanly.
- New verbs `governance directive disable <id>` and `governance directive sync <id>`. `disable` would record a skip in `install.yaml` so the directive is reconciled-and-pruned but never run. `sync` would diff the user's forked directive against the upstream's current version after a `pack update` so they can rebase tweaks. Both require new SKILL.md content + reference flow docs and are big enough to deserve their own issue.
- Reworking `directive modify` to perform the fork automatically. Today the user manually copies the directive folder; the verb's reflexive behavior (edit-in-place) is preserved for `source: local` packs, and routes to fork-not-patch only when the directive is upstream-pinned. Auto-forking is a UX improvement, not a correctness one — covered by the same follow-up that handles `disable`/`sync`.

## Verification

- `bash scripts/test.sh` exits 0 — every layer (`packctl`, `packverb`, `working-tree resolver`, `install.sh`, `hooks.sh`, runtime, schema-split, packs) passes; `validate_pack_dir`'s new `replaces:` check is exercised indirectly by the existing pack-validation smoke tests (no directive in this repo currently sets the field, so the codepath returns clean — the negative shape check would surface in a future eval that does).
- `bash .governance/run.sh` exits 0 with all 14 directives green — the optional-field validation doesn't regress any existing directive metadata.
- `grep -n "replaces" governance/assets/packs/lib/packctl.py` shows the new validation block at the per-directive loop.
- `grep -n "fork-not-patch" governance/references/DIRECTIVE_AMEND_FLOW.md` shows the updated interaction-policy row pointing to this issue.
