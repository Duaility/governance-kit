# issue-256 — release.sh stamps only kit/assets source, not the consumed tree

Closes [#256](https://github.com/Duaility/governance-kit/issues/256).

## Checklist

- [x] Scope kit-axis marker discovery to `kit/assets/` (exclude the consumed tree)
- [x] Stop bumping `.governance/install.yaml` kit_version in release.sh
- [x] A kit release leaves the consumed config untouched and the suite green

## What changed

- **Scope kit-axis marker discovery to `kit/assets/` (exclude the consumed tree).**
  `scripts/release.sh`'s `git grep` for `# governance-kit:managed` markers now
  scopes positively to `kit/assets/*` (minus `kit/assets/packs/lib/*` generator
  code), so it stamps only the six source templates
  (`dot-governance/{run.sh,lib.sh,sweep.py}`, `enable-governance.sh`,
  `governance.yml`, `governance-sweep.yml`). The dogfood's consumed surface —
  `.governance/{run.sh,lib.sh,sweep.py}`, `.github/workflows/*`, the installed
  `scripts/enable-governance.sh`, and `.githooks/*` — is no longer matched.
- **Stop bumping `.governance/install.yaml` kit_version in release.sh.** The
  consumed manifest is moved by `governance update`, not by the release. Bumping
  it (like stamping the consumed markers) advanced the marker past the runtime it
  pins, turning the post-release `governance update` into a marker-version no-op
  (`kit-plan` skips a file when `marker == target`) that never synced the new
  code — the dogfood then advertised the new version while running stale content.
- **A kit release leaves the consumed config untouched and the suite green.**
  The `chore(release)` commit now touches only `kit/assets/` + the up-to-date
  eval fixture + `CHANGELOG.md` + `kit/assets/kit.yaml`. The now-moot
  `allow-toolchain-config` waiver (which guarded `.github/workflows/` + `.githooks/`)
  was removed — those paths are no longer touched. Nothing couples
  `install.yaml.kit_version` to `kit.yaml`, so the dogfood's `.governance/`
  staying at its prior version keeps `kit-version-sync` (marker == manifest) green.

## Out of scope

- Re-syncing the dogfood that the buggy kit/v0.8.0 release already mis-stamped —
  handled by cutting kit/v0.8.1 (clean release.sh) and a forward `governance
  update`, tracked under the release issue #255 follow-up.
- The sweep-lane assets (`sweep.py`, `governance-sweep.yml`) are stamped as
  source under `kit/assets/`; their consumed copies update via the sweep install.

## Decisions

- **Positive scope (`kit/assets/*`) over more excludes.** Listing the consumed
  paths to exclude would silently miss any future consumed marker file; scoping
  to the source directory is exhaustive by construction. `release.sh` only ever
  runs in this source repo, so "consumed" always means this repo's own install.
- **Removed the toolchain-config waiver rather than keeping it moot.** A trust
  tool should not carry a waiver whose justification is false; the kit release no
  longer touches any `toolchain-config-protection`-guarded path.

## Verification

```sh
bash -n scripts/release.sh                                  # syntax OK
RELEASE_SKIP_SUITE=1 bash scripts/release.sh kit 0.8.1 --dry-run
#   markers (6, kit/assets source only) — no .governance / .githooks / .github
#   no `manifest: .governance/install.yaml` line
bash scripts/test.sh        # kit-internal layers green (incl. test-kitverb fixture pin)
bash .governance/run.sh     # dogfood suite green
```

## Accounting

<!-- Accounting rows are maintained by the agent-token-accounting and agent-steering-accounting pre-commit hooks. Keys are opaque — do not parse. -->

### Steering

| steer-key | session | issue | type | tier | user-reason | commit |
| --- | --- | --- | --- | --- | --- | --- |

### Costs

| cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| claude-code-30ab4f99-98f-1781369982-1 | claude-code | 30ab4f99-98f9-43e2-a227-36c3af4f8431 | #256 | claude-opus-4-8 | 0 | 0 | 0 | 0 | 0 | 0.0000 | 34399 | 212495 | 1550766 | 46082 | fix(governance): release.sh must not stamp the dogfood consumed tree (#256) |
