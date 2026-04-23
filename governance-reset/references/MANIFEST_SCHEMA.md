# Manifest schema

`governance-bootstrap` writes `.governance-kit/installed-packs.yaml` after installing rules. `governance-reset` reads it as the **authoritative** record of what the kit owns in this repo.

The manifest is not an auto-upgrade contract — installed rule folders are user-owned copies, and the user may have edited them. Reset uses the manifest only to learn *what paths to consider*, then confirms ownership via per-file evidence (ownership marker, byte match against the shipped template, etc. — see [UNINSTALL_MATRIX.md](UNINSTALL_MATRIX.md)).

## v1 shape (current)

This is what `write_installed_manifest` in `governance-bootstrap/assets/packs/lib/install.sh` actually emits today. Reset must parse this exact shape; regenerate the eval fixture whenever the emitter changes.

```yaml
version: "1"
generated_at: 2026-04-23T16:45:34Z
hook_strategy: githooks          # or: husky | pre-commit
stack: bash                      # or: python | node | go | rust
constitution: true               # CONSTITUTION.md was written at repo root
ci_workflow: .github/workflows/governance.yml
tests_dir: tests/governance
agents_md_directive: true        # true when the marker-bounded block was inserted
agents_md_created: false         # true only when bootstrap Step 4b Case 2 ran (stub)
setup_clone_script: scripts/setup-clone.sh  # Path A only; omitted under Path B
packs:
  - id: core
    version: "0.1"
    rules:
      - id: constitution-exists
        installed_path: tests/governance/rules/constitution-exists
      - id: no-secrets
        installed_path: tests/governance/rules/no-secrets
  - id: agent-governance
    version: "0.1"
    rules:
      - id: agent-token-accounting
        installed_path: tests/governance/rules/agent-token-accounting
install_assets_seeded:           # files seeded by rules' install-assets/
  - QUALITY.md
  - COSTS.md
collisions: []                   # empty list when Step 6 resolved nothing
# path_b: block below only present when hook_strategy != githooks
```

When `collisions` or `path_b` are non-empty, they look like:

```yaml
collisions:
  - path: .githooks/pre-commit
    resolution: wrap             # or: skip | overwrite
    extra: .githooks/pre-commit.userhook  # userhook path (wrap) or backup path (overwrite)
path_b:
  framework: husky               # or: pre-commit
  entries:
    - file: .husky/pre-commit
      fingerprint: bash tests/governance/run.sh
```

Notes on the emitted shape:

- `version` is a **quoted string** (`"1"`), not a bare integer. YAML treats both identically, but fixture byte-diffs depend on the exact form the emitter writes.
- Rule entries carry only `id` and `installed_path`. `hook` / `always_install` are intentionally **not** duplicated here — reset discovers those at execute time by reading the installed `rule.yaml` under `installed_path`.
- `collisions[*]` uses a flat `extra` field, not named `backup_path` / `userhook_path` sub-fields. Interpret `extra` based on `resolution`: `wrap` ⇒ userhook sibling path; `overwrite` ⇒ `.pre-governance.bak` backup path; `skip` ⇒ no extra.
- Keys appear in the emitter's fixed order (metadata → flags → `packs` → `install_assets_seeded` → `collisions` → optional `path_b`). Do not rely on order when parsing, but **do** preserve it when regenerating fixtures — byte-diffs matter for the eval harness.

## Fields reset relies on

| Field | Purpose in reset |
|---|---|
| `packs[*].rules[*].installed_path` | The list of `tests/governance/rules/<id>/` folders to remove. |
| `constitution` | Whether to remove `CONSTITUTION.md`. |
| `ci_workflow` | Path of the workflow file to delete. |
| `tests_dir` | Parent directory whose `run.sh`, `lib.sh`, and empty-after-cleanup shell are removed. |
| `install_assets_seeded` | The paths soft mode preserves and hard mode deletes. |
| `agents_md_created` | In hard mode, only delete `AGENTS.md` entirely if this is `true`. |
| `agents_md_directive` | Whether to attempt the marker-bounded-block strip. If `false`, skip the AGENTS.md step. |
| `hook_strategy` | Selects the reset branch (`.githooks/*` vs. `path_b.entries` editing). |
| `setup_clone_script` | Path A only — path of the one-time per-clone setup script to delete (bootstrap Step 6 Path A step 5). Omitted under Path B. |
| `path_b.framework` / `path_b.entries` | Which framework config to edit instead of `.githooks/`, and which entries to remove. |
| `collisions[*]` | Which hooks came from Path A wrap/overwrite resolution; drives *restore wrap* and *delete with backup* offers. |

Fields not listed here are reserved for future use; reset ignores them.

## Legacy fallback — v0.1 / pre-PR-#26 manifests

Repos bootstrapped before the v1 schema landed carry a flatter manifest. Shape is approximately:

```yaml
# (no version key, or version: "0.1")
packs:
  core:
    rules: [constitution-exists, no-secrets, ...]
  agent-governance:
    rules: [agent-token-accounting]
```

When reset reads a manifest whose top-level `version` field is absent or not `"1"`:

1. Log a one-line warning: *"manifest schema v<found>; falling back to heuristic detection for fields absent in this version"*.
2. Treat the `packs:` entries as an authoritative rule list (still trustworthy — this is what the repo actually has installed).
3. Fill every missing v1 field from **heuristic evidence** (see below), with each assumption called out in the Step 6 report's `Assumptions:` line.
4. Do **not** refuse the reset. The alternative is a repo the user cannot uninstall, which is worse than a partial clean-up they can finish by hand.

## When the manifest is missing entirely

A repo where the manifest was never written, or was deleted manually, is a **legitimate reset target** — we just have less evidence to work from. The fallback order:

1. **Heuristic detection.** Look for the artifacts in the uninstall matrix by exact path. For each one found, require independent ownership evidence before deleting:
   - Hooks: line-2 `governance-kit:managed` marker.
   - `CONSTITUTION.md`: the template's header sentinel line (look for the literal phrase from `assets/CONSTITUTION.template.md`'s lead paragraph).
   - `tests/governance/run.sh` / `lib.sh`: byte-for-byte match against the shipped copies in `governance-bootstrap/assets/tests-bash/`.
   - Rule folders under `tests/governance/rules/`: presence of a `check.sh` shebang line identical to the shipped one is a weak signal; absence of user-added sibling files is a stronger one.
   - `AGENTS.md`: see *opening-marker-only* heuristic below.
2. **Default mode = dry-run.** Present the plan and list each artifact with the evidence that classified it as kit-owned. Require explicit user confirmation to proceed in a destructive mode.
3. **No manifest, no artifacts ⇒ `none-detected`.** Report "nothing to remove" and exit.

### AGENTS.md opening-marker-only heuristic

The v1 directive template (`governance-bootstrap/assets/AGENTS.directive.md`) ships with **both** `<!-- governance: rules-to-follow -->` and `<!-- /governance: rules-to-follow -->` markers, so reset can strip the block by paired markers. Earlier bootstrap runs inserted only the opening marker.

When an AGENTS.md file contains the opening marker but **not** the closing one:

1. Classify as `directive-block-unbounded` at **lower confidence**.
2. Strip from the opening marker line up to (but not including) the next `^## ` heading, or to end-of-file if no such heading follows.
3. Require an **extra confirm** in Step 4 ("block boundary is inferred, not marker-bounded — proceed?"). A silent accept does not count.
4. Still run the byte-diff guard on everything outside the inferred block; abort if anything non-block-adjacent changed.
5. Record the heuristic in the Step 6 report's `Assumptions:` line.

The heuristic path must **never** guess. If evidence for a given path is ambiguous (e.g., `CONSTITUTION.md` exists but was rewritten by hand), surface it as a collision in the Step 4 confirmation and default to "leave alone".

## Forward compatibility

The manifest is versioned. `version: "1"` is the current shape. Reset accepts unknown fields silently and unknown `version` values with a warning ("manifest written by a newer bootstrap; proceeding with best-effort field mapping"). A `version` mismatch never causes reset to refuse — the alternative is a repo the user cannot uninstall, which is worse than a partial clean-up they can finish by hand.
