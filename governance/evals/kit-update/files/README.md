# Eval fixtures — `governance kit update`

Each subdirectory is a seed repo state for one eval case. Before running an eval, copy the fixture into a fresh temp directory, run `git init && git add -A && git commit -m "seed"` inside it, and point the skill at that directory.

`kit update` re-syncs the kit-runtime files installed at `governance init` (`run.sh`, `lib.sh`, `enable-governance.sh`, `governance.yml`, hook dispatchers) when a newer kit is on PATH. It is **disjoint** from `pack update` — see [UPDATE_FLOW.md](../../../references/UPDATE_FLOW.md). The fixtures here exercise the verb's branching points: forward update, no-op short-circuit, no-downgrade refusal, missing-manifest cases (both reconstructable and not), and the pre-tracking-install opt-in.

The kit's `KIT_VERSION` constant is `"0.3"` ([packctl.py](../../../assets/packs/lib/packctl.py)) at the time these fixtures were authored — fixtures stamped `kit_version: "0.1"` are deliberately stale, `"0.3"` is current, `"9.9"` is a future version newer than any kit we'd run against.

The marker shape is `# governance-kit:managed kit-version=<v> generated=<date>`. The marker is the per-file version pin; `install.yaml.kit_version` is a cache. When the manifest is missing, `kit update` reconstructs the pin from runtime markers (taking the min `kit-version=`); only if no versioned marker is found does the verb refuse.

| Fixture | `kit_version` | Markers | What it exercises |
|---|---|---|---|
| `stale-repo/` | `"0.1"` | bare | Forward update: agent diffs, asks per file, applies, regenerates hooks, smoke-tests, commits. Backs eval case 1. |
| `up-to-date-repo/` | `"0.3"` | bare | No-op short-circuit at Step 2 (`kit: up-to-date`). No commit, no file writes. Backs eval case 2. |
| `no-manifest-repo/` | (manifest deleted) | bare | Reconstruction-then-refuse: agent attempts marker reconstruction, finds only bare `# governance-kit:managed` (no `kit-version=`), refuses with the recovery path `governance uninstall` + `governance init`. Backs eval case 3. |
| `future-kit-repo/` | `"9.9"` | bare | No-downgrade refusal at Step 2; recovery is to upgrade the kit on PATH. Backs eval case 4. |
| `pre-tracking-repo/` | (field absent within v3) | none | Pre-tracking install: agent records the current `KIT_VERSION` and proceeds through the normal flow. Runtime files lack the marker, so they surface as `Skipped (unmanaged)`. Backs eval case 5. |
| `reconstructable-repo/` | (manifest deleted) | versioned (`kit-version=0.1`) | Reconstruction-then-proceed: agent rebuilds the pin from per-file markers, runs the forward-update flow, writes a fresh `install.yaml`, commits. Backs eval case 6. |

The runtime stubs (`.governance/run.sh`, `.governance/lib.sh`) are intentionally minimal — for fixtures that hit the version-delta short-circuit at Step 2, byte equality with the kit's current templates is not required, and for fixtures that proceed to Step 3 the per-file diff itself is graded behaviorally (the agent shows a diff and asks) rather than against fixed bytes.
