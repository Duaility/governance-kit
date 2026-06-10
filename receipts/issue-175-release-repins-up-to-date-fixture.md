# issue-175 — release.sh re-pins the up-to-date eval fixture on kit bump

Addresses [#175](https://github.com/Duaility/governance-kit/issues/175).

## Checklist

- [x] kit-axis apply block re-pins the up-to-date fixture
- [x] `--dry-run` plan lists the fixture re-pin
- [x] `future-kit-repo` / `stale-repo` fixtures are untouched
- [x] re-running on the same version is idempotent
- [x] `scripts/test-kitverb.py` stays green

## Problem

`scripts/release.sh kit X.Y.Z` re-stamps every managed kit-version copy but
deliberately excludes `governance/evals/*` from marker discovery (eval fixtures
pin chosen versions on purpose). The one exception is the `up-to-date-repo`
fixture, whose `.governance/install.yaml` `kit_version` **must** track
`KIT_VERSION` — `scripts/test-kitverb.py::test_up_to_date_fixture_pin_tracks_kit_version`
asserts it. So every kit release tripped its own pre-commit suite at the
`chore(release)` commit, forcing the operator to hand-edit the fixture. The pin
can't move in a separate commit (before mismatches the old kit, after leaves the
suite red between commits), so it must move atomically inside the bump.

## What changed

- **The kit-axis apply block re-pins the up-to-date fixture.** Added a
  `UP_TO_DATE_FIXTURE` constant
  (`governance/evals/kit-update/files/up-to-date-repo/.governance/install.yaml`)
  and a `set_quoted_field "$UP_TO_DATE_FIXTURE" '^kit_version: "' "$VERSION"`
  call alongside the existing `SKILL.md` / `install.yaml` re-stamps, so the
  fixture pin moves with the bump in the same `chore(release)` commit.
- **The `--dry-run` plan lists the fixture re-pin** under the kit re-stamps
  (`eval fixture:  <path>  kit_version → $VERSION`) so the preview stays
  truthful.
- Because the re-pin reuses the existing `set_quoted_field` helper,
  re-running on the same version is idempotent — a byte-identical no-op.

## Out of scope

- `future-kit-repo` / `stale-repo` fixtures are untouched — they deliberately
  pin different versions and broadening marker discovery would risk sweeping
  them in.
- The drift-guard test stays as-is — it remains valid and now passes
  automatically on release.
- The pre-existing `build_changelog_section` `set -e` edge case (it returns
  non-zero, aborting `--dry-run`, when there are no Conventional-Commit matches
  since the last tag) is left untouched.

## Decisions

- Reused the existing `set_quoted_field` helper rather than adding the fixture
  to marker discovery — the fixture is a YAML `kit_version` field, not a
  `# governance-kit:managed kit-version=` marker, and broadening the discovery
  glob would risk sweeping in the sibling fixtures that pin old versions on
  purpose.

## Verification

- `scripts/test-kitverb.py` stays green, including
  `test_up_to_date_fixture_pin_tracks_kit_version`
  (`uv run --with PyYAML python scripts/test-kitverb.py`).
- `bash .governance/run.sh` green (all 17 directives).
- `bash scripts/release.sh kit <next> --dry-run` shows the fixture re-pin under
  the kit re-stamps.
- `future-kit-repo` / `stale-repo` fixtures are untouched — `git diff` on a
  release touches only the up-to-date fixture's pin.
