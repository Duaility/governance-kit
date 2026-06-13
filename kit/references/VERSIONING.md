# Versioning & release policy

governance-kit is a monorepo that ships a framework plus a set of
independently-versioned concern packs from one tree, plus a set of wire-format
schema versions. This document defines what each version means, how the semantic
axes relate, the tag scheme consumers pin against, and the release procedure.

> Mechanics live in [`scripts/release.sh`](../../scripts/release.sh) and
> [RELEASE_FLOW.md](RELEASE_FLOW.md). Drift between the stamps below is caught by
> the `managed-tree-integrity` directive — these are not honour-system fields.

## The two semantic axes

| Axis | Question it answers | Source of truth | Derived copies (never hand-edit) |
|---|---|---|---|
| **Kit** | What version of the *framework* is this? (run.sh, lib.sh, hook generators, engines, schemas) | [`kit/assets/kit.yaml`](../assets/kit.yaml) `version` | `.governance/install.yaml` `kit_version`; the `# governance-kit:managed kit-version=<v>` markers stamped into every managed runtime file |
| **Pack** | What version of this *directive content* is this? | each pack's `pack.yaml` `version` (the bundled concern packs live under [`packs/`](../../packs), e.g. [`packs/security/pack.yaml`](../../packs/security/pack.yaml)) | the consumer's `.governance/packs.lock` entry, written at `pack add`/`pack update` time |

The published **skill** (`skill/`) is *not* on the kit axis (issue #198): it is
a fetch-only installer carrying no kit code and no kit version, and its
`SKILL.md` frontmatter `version` is the installer's own, bumped by hand when
the shim itself changes. Kit releases do not touch `skill/`.

The axes move **independently** — and, since the decomposition, each pack moves
independently of its sibling packs too. A pack can ship a patch (a `check.sh`
bug fix) on a stable kit and without disturbing any other pack — the historical
`core` 0.3.1 → 0.3.2 → 0.3.3 sequence did exactly that against the kit, and the
per-pack axes now give every concern pack the same freedom relative to its
siblings. This is the Helm model (`Chart.version` vs `appVersion`): don't
collapse them.

### The axis contract

A pack declares the **floor** kit it needs via `min_governance_kit`. The
invariant every bundled `governance-kit/*` pack must satisfy:

```
pack.min_governance_kit  ≤  kit.yaml.version
```

`packctl validate-pack` already refuses any pack whose `min_governance_kit` is
newer than the installed `KIT_VERSION`. The kit-internal
`test-kit-version-consistency` test layer additionally enforces the equation
above for the bundled packs (`min_governance_kit <= KIT_VERSION`); in an
installed repo, `managed-tree-integrity` enforces that every managed-file
kit-version marker equals the manifest's `kit_version`.

## SemVer policy

Both axes are [SemVer 2.0.0](https://semver.org). While the project is pre-1.0
(see governance-kit is V0), we still apply the boundaries below so the numbers
stay *meaningful* — the move to 1.0 is when we additionally promise not to break
MAJOR-class things without a deprecation window.

### Pack version (directive content)

| Bump | When |
|---|---|
| **MAJOR** | A change that makes a previously-passing repo **fail**: removing/renaming a directive, or tightening a `check.sh` so existing commits/state are now rejected. Breaking. |
| **MINOR** | Additive: a new directive, a new preset, a new opt-in capability, or relaxing a check so strictly fewer things fail. |
| **PATCH** | A `check.sh`/lib bug fix with no intended change in which repos pass. |

> Worked example of the old, policy-less behaviour: #145 *added* the
> `doc-integrity` directive but bumped PATCH (0.3.3 → 0.3.4). Under this policy
> that is a **MINOR**. We do not renumber history; correct semver applies going
> forward.

### Kit version (framework)

| Bump | When |
|---|---|
| **MAJOR** | A break in the managed-file contract or a schema (`install.yaml`/`packs.lock` shape), or a removed/renamed verb or flag — anything that makes an existing installed repo's `kit update` unsafe without manual migration. |
| **MINOR** | A new verb, flag, hook kind, or marker-format change that `kit update` migrates cleanly. |
| **PATCH** | A framework bug fix with no contract change. |

Schema versions (`install.yaml` `version: "3"`, `packs.lock` `version: "2"`) are
a **separate, orthogonal** axis — they gate *format* compatibility, not feature
compatibility, and step independently when a wire format changes.

## Tag scheme

The monorepo ships more than one artifact, so tags are **prefixed** (the
Go-submodule / Lerna convention):

```
kit/vX.Y.Z       # a kit (framework) release
<pack>/vX.Y.Z    # a bundled-pack release — one axis per pack
```

Each bundled `governance-kit/*` concern pack carries its own `pack.yaml`
`version` and tags on its **own axis** — `foundation/vX.Y.Z`, `security/vX.Y.Z`,
`docs/vX.Y.Z`, `commits/vX.Y.Z`, `audit/vX.Y.Z` — all starting at `0.1.0` and
stepping independently. Tag
**lazily**: a release cuts a tag only for the pack(s) whose subtree actually
changed since their last tag, so a `security`-only fix ships `security/v0.1.1`
and touches nothing else — the six unchanged packs keep their existing tags and
versions. This is the Go-multi-module / Changesets model: per-unit tags, cut on
demand, never a flat bump across packs that did not change. Community packs live
in their own repos and tag plain `vX.Y.Z`.

> The retired `core/vX.Y.Z` axis (a single tag for the old catch-all `core`
> pack) is historical: `core/v0.4.0` and earlier stay as immutable history, but
> no new `core/*` tags are cut and `release.sh core …` now errors. The
> [`release.yml`](../../.github/workflows/release.yml) trigger is `'*/v*'`, so
> it still cuts a Release from any legacy `core/*` tag that is re-pushed.

Consumers then pin a **readable, immutable** ref instead of an opaque SHA:

```sh
governance pack add gh:duaility/governance-kit/packs/security@<tag>
```

A tag resolves to a SHA at `pack add`/`pack update` time and is recorded in the
lockfile, so the pin stays reproducible even though the tag name is human-legible.
Pinning `@main` (the current default) silently tracks latest — prefer a tag for
any repo that wants to choose its version.

The **kit axis pins the same way** since issue #177. `.governance/install.yaml`
records `kit_ref` (a `gh:duaility/governance-kit/kit@kit/vX.Y.Z` ref) and
the resolved `kit_sha`, and `governance kit update` fetches that tree into
`~/.governance/cache/kits/` and delegates plan/apply to *its* engine — the
gradle-wrapper / rustup model, where the repo's manifest is the authoritative
statement of which kit it runs and the machine honours it rather than deciding.
`kit update` resolves the latest published `kit/vX.Y.Z` tag by default, or an
exact version with `--to X.Y.Z`. **Subpath epoch (issue #198):** newly
constructed refs use the `kit/` subpath; tags cut before the skill≠kit split
keep their tree at `governance/`, so `resolve --to` a pre-split version refuses
with a clear no-`assets/kit.yaml` epoch error (repos already pinned to such a tag keep
working — the recorded `…/governance@…` ref stays valid). `--allow-downgrade`
is required to move
backward. This pin is **content state, not a derived version line** — it is
written by `init` / `kit update`, never by `release.sh`, and `managed-tree-integrity`
validates the managed-file markers against `kit_version` (alongside each file's
content digest). Delegated
apply requires the target to ship the `kitverb.py` engine, first present in
`kit/v0.4.0`; that is the delegation floor.

## Release procedure (summary)

Bumps happen **only** in `chore(release)` commits cut by the release script —
feature and fix PRs never touch version lines. See [RELEASE_FLOW.md](RELEASE_FLOW.md)
for the full flow.

```sh
# Cut a pack release (content change merged) — one invocation per changed pack:
bash scripts/release.sh security 0.2.0

# Cut a kit release (framework change merged):
bash scripts/release.sh kit 0.6.0
```

The axis argument is `kit` or any bundled pack name (validated against
`packs/<name>/pack.yaml`). `release.sh` validates a clean tree on `main` with a
green suite, bumps the one source of truth, re-derives every stamp, regenerates
the `CHANGELOG.md` section from the Conventional Commits since the last matching
tag — **path-scoped to the axis's own subtree** (`packs/<pack>` for a pack,
everything outside `packs/` for the kit), so each changelog lists only its own
commits — makes the `chore(release)` commit, and creates the prefixed annotated
tag. Pushing the tag triggers [`release.yml`](../../.github/workflows/release.yml),
which cuts the GitHub Release from the changelog section.
