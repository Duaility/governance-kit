# Community extensions

This directory is the home of the governance-kit **community pack
catalog**.

`catalog.community.json` is an advisory index of known community packs —
their scoped ids, summaries, and source references. The catalog is
consumed by the `governance pack search` verb (see issue #31). Presence
in the catalog is not required: `governance pack add gh:<owner>/<repo>`
works against any GitHub ref, with or without a matching catalog entry.

`catalog.schema.json` is the JSON Schema for catalog entries.

The catalog ships empty today. It will be populated as community packs
appear in follow-up work — the first planned entry is the out-of-tree
form of the currently in-tree `agent-governance` pack.

## Adding a community pack

Open a PR that appends an entry to `catalog.community.json`. Each entry
needs:

- A scoped `id` of the form `<author>/<slug>`.
- A one-line `summary`.
- A `source` reference (today: `type: github`, `ref: <owner>/<repo>`).
- `min_governance_kit` — mirrored from the pack's own `pack.yaml`.

The catalog PR does not need to bump `governance-kit` itself. Catalog
changes are advisory and do not affect already-installed repos.
