# Manifest schema

`governance-bootstrap` writes `.governance-kit/installed-packs.yaml` after installing rules. `governance-reset` reads it as the **authoritative** record of what the kit owns in this repo.

The manifest is not an auto-upgrade contract — installed rule folders are user-owned copies, and the user may have edited them. Reset uses the manifest only to learn *what paths to consider*, then confirms ownership via per-file evidence (ownership marker, byte match against the shipped template, etc. — see [UNINSTALL_MATRIX.md](UNINSTALL_MATRIX.md)).

## Expected shape

```yaml
# Written by governance-bootstrap v<version> on <YYYY-MM-DD>.
version: 1
generated_at: 2026-04-23T14:05:31Z
bootstrap_version: "0.2"

hook_strategy: githooks          # or: husky | pre-commit
stack: bash                      # or: python | node | go | rust

packs:
  - id: core
    version: "0.2"
    rules:
      - id: constitution-exists
        installed_path: tests/governance/rules/constitution-exists
        hook: none
      - id: no-merge-conflict-markers
        installed_path: tests/governance/rules/no-merge-conflict-markers
        hook: pre-commit
        always_install: true
      # ... one entry per installed rule ...
  - id: agent-governance
    version: "0.1"
    rules:
      - id: agent-token-accounting
        installed_path: tests/governance/rules/agent-token-accounting
        hook: pre-commit

constitution: true                # CONSTITUTION.md was written at repo root
ci_workflow: .github/workflows/governance.yml
tests_dir: tests/governance

install_assets_seeded:            # files seeded by rules' install-assets/
  - QUALITY.md
  - COSTS.md

agents_md_created: false          # true only when bootstrap Step 4b Case 2 ran
agents_md_directive: true         # true when the marker-bounded block was inserted

path_b:                           # present only when hook_strategy != githooks
  framework: husky
  entries:
    - file: .husky/pre-commit
      fingerprint: "bash tests/governance/run.sh"

collisions:                       # recorded from bootstrap Step 6 unmarked-hook flow
  - path: .githooks/pre-commit
    resolution: wrap              # or: skip | overwrite-with-backup
    backup_path: null             # set when resolution == overwrite-with-backup
    userhook_path: .githooks/pre-commit.userhook  # set when resolution == wrap
```

## Fields reset relies on

| Field | Purpose in reset |
|---|---|
| `packs[*].rules[*].installed_path` | The list of `tests/governance/rules/<id>/` folders to remove. |
| `packs[*].rules[*].hook` | Which dispatcher to regenerate if partial-reset were ever added (out of scope for v1; field is read defensively). |
| `constitution` | Whether to remove `CONSTITUTION.md`. |
| `ci_workflow` | Path of the workflow file to delete. |
| `tests_dir` | Parent directory whose `run.sh`, `lib.sh`, and empty-after-cleanup shell are removed. |
| `install_assets_seeded` | The paths soft mode preserves and hard mode deletes. |
| `agents_md_created` | In hard mode, only delete `AGENTS.md` entirely if this is `true`. |
| `agents_md_directive` | Whether to attempt the marker-bounded-block strip. If `false`, skip the AGENTS.md step. |
| `path_b.*` | Which framework config to edit instead of `.githooks/`. |
| `collisions[*]` | Which hooks came from Path A wrap/backup resolution; drives `restore wrap` and `delete with backup` offers. |

Fields not listed here are reserved for future use; reset ignores them.

## When the manifest is missing

A repo that was bootstrapped by an older version of the kit, or one where the manifest was deleted manually, is a **legitimate reset target** — we just have less evidence to work from. The fallback order:

1. **Heuristic detection.** Look for the artifacts in the uninstall matrix by exact path. For each one found, require independent ownership evidence before deleting:
   - Hooks: line-2 `governance-kit:managed` marker.
   - `CONSTITUTION.md`: the template's header sentinel line (look for the literal phrase from `assets/CONSTITUTION.template.md`'s lead paragraph).
   - `tests/governance/run.sh` / `lib.sh`: byte-for-byte match against the shipped copies in `governance-bootstrap/assets/tests-bash/`.
   - Rule folders under `tests/governance/rules/`: presence of a `check.sh` shebang line identical to the shipped one is a weak signal; absence of user-added sibling files is a stronger one.
2. **Default mode = dry-run.** Present the plan and list each artifact with the evidence that classified it as kit-owned. Require explicit user confirmation to proceed in a destructive mode.
3. **No manifest, no artifacts ⇒ `none-detected`.** Report "nothing to remove" and exit.

The heuristic path must **never** guess. If evidence for a given path is ambiguous (e.g., `CONSTITUTION.md` exists but was rewritten by hand), surface it as a collision in the Step 4 confirmation and default to "leave alone".

## Forward compatibility

The manifest is versioned. `version: 1` is the initial shape. Reset accepts unknown fields silently and unknown `version` values with a warning ("manifest written by a newer bootstrap; proceeding with best-effort field mapping"). A `version` mismatch never causes reset to refuse — the alternative is a repo the user cannot uninstall, which is worse than a partial clean-up they can finish by hand.
