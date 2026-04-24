# Community extensions

This directory is the home of the governance-kit **community pack
catalog**.

`catalog.community.json` is an advisory index of known community packs —
their scoped ids, summaries, and source references. The catalog is
consumed by the `governance pack search` verb (see issue #31). Presence
in the catalog is not required: `governance pack add gh:<owner>/<repo>`
works against any GitHub ref, with or without a matching catalog entry.

`catalog.schema.json` is the JSON Schema for catalog entries.

The catalog seeds with one forward-looking entry: `duaility/agent-governance`.
That is the target id for the `agent-governance` pack once it moves
out-of-tree to its own repo (issue #31, step 5). The in-tree copy at
`governance-bootstrap/assets/packs/agent-governance/` remains the
installation source until the external repo is published; after that,
`governance init` will point users at `governance pack add
gh:Duaility/governance-pack-agent-governance` instead.

## Adding a community pack

Open a PR that appends an entry to `catalog.community.json`. Each entry
needs:

- A scoped `id` of the form `<author>/<slug>`.
- A one-line `summary`.
- A `source` reference (today: `type: github`, `ref: <owner>/<repo>`).
- `min_governance_kit` — mirrored from the pack's own `pack.yaml`.

The catalog PR does not need to bump `governance-kit` itself. Catalog
changes are advisory and do not affect already-installed repos.
