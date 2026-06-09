# Versioning & release policy

governance-kit is a monorepo that ships two independently-versioned things from
one tree, plus a set of wire-format schema versions. This document defines what
each version means, how the two semantic axes relate, the tag scheme consumers
pin against, and the release procedure.

> Mechanics live in [`scripts/release.sh`](../../scripts/release.sh) and
> [RELEASE_FLOW.md](RELEASE_FLOW.md). Drift between the stamps below is caught by
> the `version-consistency` directive — these are not honour-system fields.

## The two semantic axes

| Axis | Question it answers | Source of truth | Derived copies (never hand-edit) |
|---|---|---|---|
| **Kit** | What version of the *framework* is this? (run.sh, lib.sh, hook generators, the `governance` skill, schemas) | [`governance/assets/kit.yaml`](../assets/kit.yaml) `version` | `governance/SKILL.md` frontmatter `version`; `.governance/install.yaml` `kit_version`; the `# governance-kit:managed kit-version=<v>` markers stamped into every managed runtime file |
| **Pack** | What version of this *directive content* is this? | each pack's `pack.yaml` `version` (the bundled one: [`packs/core/pack.yaml`](../../packs/core/pack.yaml)) | the consumer's `.governance/packs.lock` entry, written at `pack add`/`pack update` time |

The axes move **independently**. A pack can ship a patch (a `check.sh` bug fix)
on a stable kit — the `core` 0.3.1 → 0.3.2 → 0.3.3 sequence did exactly that
without the kit moving off 0.3. This is the Helm model (`Chart.version` vs
`appVersion`): don't collapse them.

### The axis contract

A pack declares the **floor** kit it needs via `min_governance_kit`. The
invariant the kit's own core pack must satisfy:

```
core.min_governance_kit  ≤  kit.yaml.version
```

`packctl validate-pack` already refuses any pack whose `min_governance_kit` is
newer than the installed `KIT_VERSION`. The `version-consistency` directive
additionally enforces the equation above for the bundled core pack, and that all
derived kit-version copies equal `kit.yaml`.

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
kit/vX.Y.Z      # a kit (framework) release
core/vX.Y.Z     # a governance-kit/core pack release
```

Community packs live in their own repos and tag plain `vX.Y.Z`.

Consumers then pin a **readable, immutable** ref instead of an opaque SHA:

```sh
governance pack add gh:duaility/governance-kit/packs/core@core/v0.3.4
```

A tag resolves to a SHA at `pack add`/`pack update` time and is recorded in the
lockfile, so the pin stays reproducible even though the tag name is human-legible.
Pinning `@main` (the current default) silently tracks latest — prefer a tag for
any repo that wants to choose its version.

## Release procedure (summary)

Bumps happen **only** in `chore(release)` commits cut by the release script —
feature and fix PRs never touch version lines. See [RELEASE_FLOW.md](RELEASE_FLOW.md)
for the full flow.

```sh
# Cut a core pack release (content change merged):
bash scripts/release.sh core 0.4.0

# Cut a kit release (framework change merged):
bash scripts/release.sh kit 0.4.0
```

`release.sh` validates a clean tree on `main` with a green suite, bumps the one
source of truth, re-derives every stamp, regenerates the `CHANGELOG.md` section
from the Conventional Commits since the last matching tag, makes the
`chore(release)` commit, and creates the prefixed annotated tag. Pushing the tag
triggers [`release.yml`](../../.github/workflows/release.yml), which cuts the
GitHub Release from the changelog section.
