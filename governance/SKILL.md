---
name: governance
description: Single entry point for governance-kit's lifecycle verbs — `governance init` (bootstrap a repo), `governance uninstall` (clean tear-down), and the forthcoming `governance pack` and `governance rule` verbs. Use when the user says "governance init", "set up governance", "bootstrap governance", "governance uninstall", "reset governance", "tear down governance", "uninstall governance-kit", or asks to manage governance-kit lifecycle without naming a specific verb. Do not use for reviewing an existing setup (governance-gardener) or for amending a single rule in a governance-amend-installed repo (governance-amend) — those skills still own their surfaces until parity is reached.
license: MIT
metadata:
  author: governance-kit
  version: "0.1"
  supersedes: governance-bootstrap, governance-reset
---

# governance

This skill is the **unified lifecycle entry point** for governance-kit. It exposes a verb surface inspired by [spec-kit](https://github.com/github/spec-kit) — a single writer for the governance surface rather than three skills that each mutate `CONSTITUTION.md`, `tests/governance/rules/`, hooks, and ownership markers.

Tracking issue: [Duaility/governance-kit#31](https://github.com/Duaility/governance-kit/issues/31).

## Verb surface

```
governance init                                    # bootstrap a repo
governance pack search [query]                     # (coming) search community catalog
governance pack add <ref>                          # (coming) e.g. gh:acme/soc2@<sha>
governance pack update [<pack-id>]                 # (coming)
governance pack remove <pack-id>                   # (coming)
governance pack list                               # (coming)
governance rule add|modify|remove <rule-id>        # (coming) hand-authored rules
governance uninstall [--dry-run|--soft|--hard]     # tear-down
```

Today this skill implements `init` and `uninstall`. The `pack` and `rule` verbs are being ported in follow-up PRs on the same tracking issue; until those land, the legacy `governance-amend` skill remains the authoritative path for hand-authored rule changes. Redirect users there when they ask for rule amendments.

## Verb dispatch

Infer the intended verb from the user's request:

| User says | Verb |
|---|---|
| "governance init", "set up governance", "bootstrap governance", "install governance-kit" | `init` |
| "governance uninstall", "reset governance", "tear down governance", "uninstall governance-kit", "clean slate" | `uninstall` |
| "add / modify / remove rule X", "amend the constitution" | Route to `governance-amend` for now; say so explicitly. |
| "pack search / add / update / remove / list" | Not yet implemented. Tell the user the verb is tracked under issue #31 and stop. Do **not** fall back to editing the pack tree by hand. |
| "is my governance healthy?", "audit governance", "find dead rules" | Route to `governance-gardener`. |

If the user's intent is ambiguous between `init` and `uninstall`, look at the repo state: `CONSTITUTION.md` + `tests/governance/` both present → `uninstall` is more likely; both absent → `init`. Ask once when still ambiguous.

## `governance init`

Bootstraps governance-driven development in the current repo:

1. `CONSTITUTION.md` at the root — the evolving source of truth.
2. Machine-enforced tests under `tests/governance/`, one folder per rule.
3. A pre-commit hook (and `commit-msg` / `prepare-commit-msg` dispatchers when selected rules need them) honoring `SKIP_GOVERNANCE=1` and `git commit --no-verify`.
4. A GitHub Actions workflow at `.github/workflows/governance.yml`.

**Activation flow, pack discovery, preset resolution, rule selection, constitution composition, AGENTS.md directive injection, hook generation, and install manifest bookkeeping are unchanged from the legacy `governance-bootstrap` skill.** This skill delegates to that flow verbatim:

> Follow the 8-step activation flow documented in [../governance-bootstrap/SKILL.md](../governance-bootstrap/SKILL.md), starting at Step 1 ("Survey the repository"). The assets under `../governance-bootstrap/assets/` (template constitution, packs, hook lib, tests-bash runner, CI workflow) are still the source of truth for this verb.

The only semantic addition under this new skill is that pack manifests are now validated against the built-in `KIT_VERSION` constant in `governance-bootstrap/assets/packs/lib/packctl.py`. Packs whose `min_governance_kit` is newer than `KIT_VERSION` are rejected during discovery with a clear error.

### When to skip the flow

- Repo is not a git repo → stop, tell the user governance requires git.
- Repo already has `CONSTITUTION.md` + `tests/governance/` and the user asked a question (not a setup request) → answer the question; do not bootstrap.
- Repo already has governance and the user asked for one targeted rule change → route to `governance-amend`.

## `governance uninstall`

Cleanly tears down a previously-bootstrapped governance-kit setup. Reverses every side-effect `init` can produce, honoring the three-layer source-of-truth model (manifest → ownership marker → heuristic fallback that defaults to dry-run).

**Activation flow, classification, mode selection (dry-run / soft / hard), confirmation preview, execution ordering, and AGENTS.md surgical edit are unchanged from the legacy `governance-reset` skill.** This skill delegates to that flow verbatim:

> Follow the 6-step activation flow documented in [../governance-reset/SKILL.md](../governance-reset/SKILL.md), starting at Step 1 ("Survey the repository"). The uninstall matrix and manifest schema references in `../governance-reset/references/` still apply.

Key invariants preserved:

- Never delete a file without ownership evidence (manifest entry or line-2 `governance-kit:managed` marker).
- Dry-run is the default when the manifest is missing but artifacts are detected.
- No destructive git ops — no `git clean`, no `git reset --hard`, no stash.
- Leave changes unstaged; the user's first post-uninstall commit is intentional.

## Pack and rule verbs (coming soon)

`governance pack *` and `governance rule *` are tracked under [issue #31](https://github.com/Duaility/governance-kit/issues/31) and not yet implemented in this skill. Until they land:

- **Rule add / modify / remove** → use the `governance-amend` skill. It already enforces the atomic triple (test + constitution subsection + evolution-log entry).
- **Pack add from a community source** → not yet supported. Tell the user the feature is in-flight and do not attempt to bolt it on by hand-copying a pack folder into `governance-bootstrap/assets/packs/`.

When those verbs land they will own `.governance/packs.lock` (SHA-pinned community packs), diff-before-exec UX for `check.sh`, and the capability-declaration enforcement scheduled against the schema in this PR.

## Key design rules

- **One writer.** Mutations to the governance surface (`CONSTITUTION.md`, `tests/governance/`, hooks, `.governance-kit/installed-packs.yaml`, AGENTS.md directive block) flow through this skill. Legacy skills remain in-tree until verb parity is reached; do not invent a fourth writer.
- **Verb dispatch before flow.** Confirm the verb before running any flow. A user who said "uninstall" is not asking for a fresh bootstrap because the repo looks unsetup.
- **Delegate, do not duplicate.** Until the legacy skills are retired, `init` and `uninstall` follow the existing `governance-bootstrap` / `governance-reset` SKILL.md instructions verbatim. Duplicating that prose now would create drift; the retirement PR can delete the legacy SKILL.md once the verbs are self-contained.
- **Pack-contract forward-compatibility.** New community packs will declare `reads:` / `writes:` capabilities and may depend on a specific `min_governance_kit`. Both are validated by `packctl.py` today; semantic enforcement of capabilities lands with `governance pack add`.
- **No network at commit time.** All pack fetching happens inside user-invoked verbs. Commit hooks must not reach the network — this is enforced implicitly by keeping fetch logic out of rule `check.sh` scripts.

## References

- [../CONSTITUTION.md](../CONSTITUTION.md) — the live rule set for this repo.
- [../GOVERNANCE_VOCABULARY.md](../GOVERNANCE_VOCABULARY.md) — shared terms across the governance skills.
- [../governance-bootstrap/SKILL.md](../governance-bootstrap/SKILL.md) — authoritative `init` flow (until retired).
- [../governance-reset/SKILL.md](../governance-reset/SKILL.md) — authoritative `uninstall` flow (until retired).
- [../governance-bootstrap/references/AUTHORING_PACKS.md](../governance-bootstrap/references/AUTHORING_PACKS.md) — pack + rule schemas, capability declarations, and scoped pack ids.
- [../extensions/catalog.community.json](../extensions/catalog.community.json) — community pack catalog (target of the forthcoming `governance pack search` verb).
