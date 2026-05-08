# Eval fixtures — `governance kit update`

Each subdirectory is a seed repo state for one eval case. Before running an eval, copy the fixture into a fresh temp directory, run `git init && git add -A && git commit -m "seed"` inside it, and point the skill at that directory.

`kit update` re-syncs the kit-runtime files installed at `governance init` (`run.sh`, `lib.sh`, `setup-clone.sh`, `governance.yml`, hook dispatchers) when a newer kit is on PATH. It is **disjoint** from `pack update` — see [UPDATE_FLOW.md](../../../references/UPDATE_FLOW.md). The fixtures here exercise the verb's branching points: forward update, no-op short-circuit, no-downgrade refusal, missing-manifest refusal, and the pre-tracking-install opt-in.

The kit's `KIT_VERSION` constant is `"0.2"` ([packctl.py](../../../assets/packs/lib/packctl.py)) at the time these fixtures were authored — fixtures stamped `kit_version: "0.1"` are deliberately stale, `"0.2"` is current, `"9.9"` is a future version newer than any kit we'd run against.

| Fixture | `kit_version` | What it exercises |
|---|---|---|
| `stale-repo/` | `"0.1"` | Forward update: agent diffs, asks per file, applies, regenerates hooks, smoke-tests, commits. Backs eval case 1. |
| `up-to-date-repo/` | `"0.2"` | No-op short-circuit at Step 2 (`kit: up-to-date`). No commit, no file writes. Backs eval case 2. |
| `no-manifest-repo/` | (manifest deleted) | Refuse-to-run; recovery path is `governance uninstall` + `governance init`. Backs eval case 3. |
| `future-kit-repo/` | `"9.9"` | No-downgrade refusal at Step 2; recovery is to upgrade the kit on PATH. Backs eval case 4. |
| `pre-tracking-repo/` | (field absent within v3) | Pre-tracking install: agent records the current `KIT_VERSION` and proceeds through the normal flow. Runtime files lack the marker, so they surface as `Skipped (unmanaged)`. Backs eval case 5. |

The runtime stubs (`.governance/run.sh`, `.governance/lib.sh`) are intentionally minimal — for fixtures that hit the version-delta short-circuit at Step 2, byte equality with the kit's current templates is not required, and for fixtures that proceed to Step 3 the per-file diff itself is graded behaviorally (the agent shows a diff and asks) rather than against fixed bytes.
