# Community extensions

This directory holds everything governance-kit ships that follows the
**community pack contract** — packs authored with scoped `<author>/<slug>`
ids, capability declarations, and the install flow exercised by
`governance pack *`.

## Layout

```
extensions/
├── catalog.community.json   # Advisory index of known community packs.
├── catalog.schema.json      # JSON Schema for catalog entries.
└── packs/                   # In-repo home for community-shaped packs.
    └── agent-governance/    # Authored as `duaility/agent-governance`.
```

`packs/` is a **monorepo** of community-shaped packs that ship alongside
the kit. The kit's bundled-in `core` pack lives elsewhere
(`governance/assets/packs/core/`) because it is a non-negotiable
part of the bootstrap surface, not a community extension. Everything in
`extensions/packs/` is authored, validated, and consumed as if it were an
independently published community pack — the monorepo layout is a
publishing convenience, not a contract difference.

## The catalog

`catalog.community.json` is an advisory index of known community packs —
their scoped ids, summaries, and source references. It is consumed by
`governance pack search`. Presence in the catalog is not required:
`governance pack add gh:<owner>/<repo>` works against any GitHub ref,
with or without a matching catalog entry.

Packs that live in this monorepo point at the governance-kit repo itself
and use `source.path` to address their subdirectory:

```json
{
  "id": "duaility/agent-governance",
  "source": {
    "type": "github",
    "ref": "Duaility/governance-kit",
    "path": "extensions/packs/agent-governance"
  }
}
```

External packs hosted in their own repo drop the `path` field and point
`ref` at the pack repo directly.

## Adding a pack to the monorepo

1. Create `extensions/packs/<slug>/` with a `pack.yaml` that declares
   `id: <author>/<slug>`, `min_governance_kit`, and presets.
2. Populate `directives/<directive-id>/` folders as described in
   [governance/references/AUTHORING_PACKS.md](../governance/references/AUTHORING_PACKS.md).
3. Append a catalog entry to `catalog.community.json` pointing at the
   monorepo path.
4. Run `bash scripts/test-packs.sh` — it validates every pack under both
   roots and runs every eval.

## Adding an external community pack to the catalog

Open a PR that appends an entry to `catalog.community.json`:

- Scoped `id` of the form `<author>/<slug>`.
- One-line `summary`.
- `source` reference — `type: github`, `ref: <owner>/<repo>`, optional `path`.
- `min_governance_kit` — mirrored from the pack's own `pack.yaml`.

Catalog changes are advisory and do not affect already-installed repos.
