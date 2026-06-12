# issue-214 — pre-waive doc-integrity on chore(release) commits

Closes [#214](https://github.com/Duaility/governance-kit/issues/214).

## Checklist

- [x] release.sh writes a third `allow-doc-integrity CONSTITUTION.md` pre-waiver
- [x] Comment explains why the pre-waiver is sound

## What changed

`scripts/release.sh` writes a `chore(release)` commit with two in-body waivers
(`allow-commit-message-format`, `allow-commit-issue-receipt-match`) because a
mechanical version bump has no feature issue and no receipt. But the commit was
also blocked by `doc-integrity`: a release commit re-stamps only managed files
(`kit.yaml`, `install.yaml`, the `kit-version=` markers, `CHANGELOG.md`) and
never edits `CONSTITUTION.md`, yet on macOS the frozen-section `grep` OOMs on
`CONSTITUTION.md`'s huge single-line Evolution Log entries
(`grep: out of memory`) and false-reports removed frozen lines, blocking every
release commit.

- **release.sh writes a third `allow-doc-integrity CONSTITUTION.md` pre-waiver**
  in the `chore(release)` commit body. A release commit by construction touches
  no `CONSTITUTION.md`, so there is never a legitimate frozen-section violation
  to suppress — the pre-waiver is as sound as the two it sits beside — and it
  neutralizes the macOS OOM false-positive for all future releases.
- **Comment explains why the pre-waiver is sound** — the block above the
  `git commit` now records that release commits re-stamp managed files only and
  never edit `CONSTITUTION.md`, and notes the macOS grep-OOM neutralization.

## Verification

```sh
# A real kit release now commits cleanly past doc-integrity on macOS:
bash scripts/release.sh kit 0.6.0 --push   # (run as part of the release batch)
```

## Out of scope

- The root cause — `doc-integrity`'s frozen-section grep loading multi-megabyte
  single lines — is left for a separate issue. Streaming the diff would remove
  the need for the macOS waiver entirely; the pre-waiver is correct regardless.

## Decisions

- **Pre-waive in the tool, not via the doc-integrity check.** Fixing the OOM at
  the source (stream the grep) is the deeper fix but is out of scope for cutting
  the in-flight release batch. The pre-waiver is independently correct — release
  commits never legitimately edit `CONSTITUTION.md` — so it stands on its own
  merits, not merely as a macOS workaround.
- **Scope the waiver to `CONSTITUTION.md`.** `doc-integrity` covers more than
  the frozen section; scoping to the one file a release commit provably never
  touches keeps the waiver narrow.
