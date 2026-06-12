# issue-213 — exclude docs/ from kit-version marker discovery

Closes [#213](https://github.com/Duaility/governance-kit/issues/213).

## Checklist

- [x] Added `:(exclude)docs/*` to the discovery `git grep`
- [x] Updated the explanatory comment
- [x] Dry-run lists 13 markers, schemas.mdx absent

## What changed

`scripts/release.sh`'s managed-marker auto-discovery
(`git grep -lE '^# governance-kit:managed'`) matched **any** tracked file whose
content begins a line with the marker string — including documentation that
quotes the marker format. The GitHub Pages site added in #180 carries exactly
such an illustrative example in `docs/reference/schemas.mdx` (inside a code
fence documenting the ownership marker, at column 0). The first kit release
since that site landed tried to stamp it as a managed runtime file and aborted:

```
stamp_managed_marker: marker on docs/reference/schemas.mdx is past line 3 (line 119)
```

This blocked every kit-axis release.

- **Added `:(exclude)docs/*` to the discovery `git grep`**, mirroring the
  existing `:(exclude)kit/references/*` exclusion — the flow docs quote the same
  marker literally for the same reason. `docs/` is the Pages site: entirely
  documentation, no managed runtime files, so excluding it wholesale is correct.
- **Updated the explanatory comment** to record that both `kit/references/` and
  `docs/` quote the marker at column 0 and so match the grep without being
  managed files.

## Verification

```sh
# Discovery now yields the 13 real managed files and NOT docs/reference/schemas.mdx
git grep -lE '^# governance-kit:managed' -- \
    ':(exclude)kit/evals/*' ':(exclude)kit/assets/packs/lib/*' \
    ':(exclude)kit/references/*' ':(exclude)docs/*' ':(exclude)scripts/test-*'

# Dry-run lists 13 markers, schemas.mdx absent
bash scripts/release.sh kit 0.6.0 --dry-run
```

## Out of scope

- The marker on `docs/reference/schemas.mdx` itself is left as-is — it is a
  correct, intentional documentation example of the marker format.

## Decisions

- **Exclude all of `docs/*`, not just the one offending file.** The entire
  `docs/` tree is the Pages site — documentation, never managed runtime files —
  so a wholesale exclusion matches the intent of the sibling
  `kit/references/*` rule and won't need revisiting when the docs site grows
  more marker examples.
- **Landed direct to main (governed), not via PR.** Maintainer-directed: the
  fix is a one-line, mechanically-verifiable unblock for the in-flight release
  batch; the issue + receipt + accounting trailers still apply.
