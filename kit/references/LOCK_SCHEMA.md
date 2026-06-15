# Lockfile schema (`.governance/packs.lock`)

`packs.lock` is the **pack pin record** — every pack installed in this repo, with the version, source, and (for community packs) the resolved upstream SHA. Following the npm/cargo/poetry convention, it carries both a human-readable version and a content hash; the hash is the trust unit, the version is for humans.

`packs.lock` is the single source of truth for `pack add` / `pack update` / `pack remove` / `reset`. Companion file: [`install.yaml`](INSTALL_SCHEMA.md), which carries the install receipt (init choices, side effects) but no pack pin state.

## v2 shape (current)

```yaml
version: "2"
packs:
  - id: governance-kit/docs
    version: "0.2"
    source: gh
    ref: gh:duaility/governance-kit/packs/docs@docs/v0.2.0
    sha: b33ec7a05be6c157a63b5f1a22d0102a1bf5a50c
    subpath: packs/docs
    min_governance_kit: ""
    installed_at: 2026-05-08T13:00:00Z
    directives:
      - internal-doc-links
      - doc-freshness

  - id: acme/soc2
    version: "0.3"
    source: gh
    ref: gh:acme/soc2-pack@main
    sha: 5f3c8b1a9d2e4c6f8a0b3d5e7f9a1c3e5d7f9a1b
    subpath: ""
    min_governance_kit: "0.2"
    installed_at: 2026-04-24T12:00:00Z
    directives:
      - soc2-audit-logs
      - soc2-retention

  - id: duaility/governance-kit
    version: "0.1"
    source: local
    directives:
      - pre-commit-test-gate
```

## Source discriminator

Every entry carries a `source` field. It controls which other fields are present and how `pack update` / `reset` treat the entry.

| `source` | Meaning | Required fields | Forbidden fields |
|---|---|---|---|
| `gh` | Pack fetched from `github.com/<owner>/<repo>` via `pack add`. Used for both community packs **and** the kit's own bundled concern packs (post-#117, phase 2 of #114 — e.g. `gh:duaility/governance-kit/packs/docs`). | `id`, `version`, `source`, `ref`, `sha`, `directives`, `installed_at` | — |
| `local` | Repo-local hand-authored pack (no `source:` in `pack.yaml`). | `id`, `version`, `directives` | `ref`, `sha`, `installed_at`, `subpath`, `min_governance_kit` |

The `builtin` source type was retired in #117. `governance-kit/core` is now fetched the same way community packs are, so `pack update` works uniformly across the entire pack set.

`min_governance_kit` and `subpath` are optional even on `gh` entries — empty strings are emitted when the source pack does not declare one.

## Field reference

| Field | Type | Notes |
|---|---|---|
| `id` | string | `<owner>/<name>`, lowercased. Matches the directory at `.governance/packs/<owner>/<name>/`. |
| `version` | string | Self-declared by the pack's `pack.yaml`. **Not** authoritative for trust — the SHA is. Recorded so a reviewer can read `core@0.2 (sha 5f3c…)` without resolving the SHA. |
| `source` | string | One of `gh`, `local`. See above. (`builtin` was retired in #117.) |
| `ref` | string | (`gh` only) The user's pin ref — e.g., `gh:acme/soc2-pack@main`. Resolved to a SHA at install time. |
| `sha` | 40-char hex | (`gh` only) The resolved commit SHA. The trust unit — `pack update` re-pins this. |
| `subpath` | string | (`gh` only) Subpath inside the repo where `pack.yaml` lives. Empty for monorepo-root packs. |
| `min_governance_kit` | string | (`gh` only) Minimum kit version the pack declares. Used by `pack update` to refuse pins that exceed the running kit. |
| `installed_at` | RFC 3339 | (`gh` only) When `lock-add` recorded this entry. Empty/absent for `local`. |
| `directives` | list[string] | Sorted list of directive ids the pack contributes. Used by `reset --pack` and `pack remove`. |
| `digest` | map[string,string] | (optional, issue #253) `{<directive-id>: <sha256-hex>}` — the content digest of each materialized directive folder under `.governance/packs/<id>/directives/<did>/` (git-tracked files, excluding `evals/`, `install-assets/`, `__pycache__/`, `*.pyc`), recorded by `init` / `pack-apply` via `digestlib.directory_digest`. The `managed-tree-integrity` directive recomputes these on every commit to verify the vendored tree **offline** (no upstream git objects). **Optional** — entries written before #253 omit it, and the directive skips a pack whose `digest` is absent (coverage is gained on the next `pack update`). |

Pack rows are written **sorted by `id`**, regardless of insert order. This keeps PR diffs minimal when a new pack lands ahead of existing ones.

## Helpers — `packverb.py`

The lockfile is exclusively written via `kit/assets/packs/lib/packverb.py`. Never hand-edit. The CLI:

```sh
# add or replace an entry
packverb lock-add <lockfile> <pack_id> \
    --source {gh|local} \
    --version <v> \
    [--ref <r>]            # gh only
    [--sha <sha40>]        # gh only
    [--subpath <p>]        # gh only
    [--min-kit <v>]        # gh only
    --directive <id> ...

# remove by pack id
packverb lock-remove <lockfile> <pack_id>

# emit JSON of the full lockfile
packverb lock-read <lockfile>

# tab-separated rows
packverb lock-list <lockfile>          # id\tsha\tref
packverb lock-list <lockfile> --long   # id\tsource\tversion\tsha\tref
```

Validation in `lock-add`:

- `--source gh` requires `--ref` and `--sha`.
- `--source local` rejects `--ref`/`--sha` (no upstream pin).
- `--source builtin` is rejected as a retired choice (#117).
- Pack rows are sorted by id on every write.

## Forward compatibility

`load_lockfile` raises on any `version` other than `"2"`. V0 — no migration shim. A repo carrying an older `packs.lock` (v1, the pre-split shape) must be re-installed via `governance init`. CI re-enforces every directive on every PR; there is no developer-side bypass.
