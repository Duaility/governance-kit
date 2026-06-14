# Eval fixtures — `governance kit update`

Each subdirectory is a seed repo state for one eval case. Before running an eval, copy the fixture into a fresh temp directory, run `git init && git add -A && git commit -m "seed"` inside it, and point the skill at that directory.

`kit update` follows the **repo-pinned model** (issue #177): `install.yaml`'s `kit_ref`/`kit_sha` pin which kit the repo runs. The verb **resolves a target** (default: latest published `kit/vX.Y.Z` tag; `--to X.Y.Z` for an exact version; offline falls back through the cached pin → installed skill), **fetches** that tree into `~/.governance/cache/kits/`, **delegates** `kit-plan`/`kit-apply` to the target's own engine, and **records the pin** (`kit-pin`). It re-syncs the kit-runtime files `init` seeded (`run.sh`, `lib.sh`, `governance.yml`, hook dispatchers) and is **disjoint** from `pack update` — see [UPDATE_FLOW.md](../../../references/UPDATE_FLOW.md). The fixtures exercise the verb's branching points: forward delegated update, `--to` pin, no-op short-circuit, downgrade with/without `--allow-downgrade`, the delegation floor, offline fallback, version-skew byte-identity, and the missing-manifest / pre-tracking cases.

The kit's `KIT_VERSION` is `"0.4.0"` ([packctl.py](../../../assets/packs/lib/packctl.py) → [kit.yaml](../../../assets/kit.yaml)) at the time these fixtures were authored — `0.4.0` is the **delegation floor** (the first kit shipping `kitverb.py kit-plan`/`kit-apply`). Fixtures stamped `kit_version: "0.1"` are deliberately stale (pre-pin, exercising backfill), `"0.4.0"` is current, `"9.9"` is a future version newer than anything published (exercising downgrade).

The marker shape is `# governance-kit:managed kit-version=<v>`. The marker is the per-file version pin; `install.yaml.kit_version` mirrors it, and `kit_ref`/`kit_sha` are the content-addressed pin the verb fetches and re-records. When the manifest is missing, the verb reconstructs the pin from runtime markers (min `kit-version=`); only if no versioned marker is found does it refuse.

| Fixture | `kit_version` | Pin (`kit_ref`/`kit_sha`) | What it exercises |
|---|---|---|---|
| `stale-repo/` | `"0.1"` | absent (pre-#177) | Forward delegated update + pin backfill; `--to 0.4.0` (explicit); floor refusal (`--to 0.3.5`); version-skew byte-identity. Backs eval cases 1, 7, 10, 11. |
| `up-to-date-repo/` | `"0.4.0"` | present | No-op short-circuit (`direction: same`); offline fallback. Backs eval cases 2, 9. |
| `no-manifest-repo/` | (manifest deleted) | n/a | Reconstruction-then-refuse: only the bare marker, `no-recoverable-pin`, route to `uninstall` + `init`. Backs eval case 3. |
| `future-kit-repo/` | `"9.9"` | absent | Downgrade: refused without `--allow-downgrade` (eval 4), rolled back with it via the newer-engine / older-assets path (eval 8). |
| `pre-tracking-repo/` | (field absent within v3) | absent | Pre-tracking install: records the resolved target, proceeds; unmarked runtime files surface as `Skipped (unmanaged)`. Backs eval case 5. |
| `reconstructable-repo/` | (manifest deleted) | n/a | Reconstruction-then-proceed: rebuild the pin from versioned markers (`kit-version=0.1`), forward delegated update, fresh `install.yaml` + pin. Backs eval case 6. |

The runtime stubs (`.governance/run.sh`, `.governance/lib.sh`) are intentionally minimal — for fixtures that hit the direction short-circuit, byte equality with the target's templates is not required, and for fixtures that proceed to the apply the per-file diff is graded behaviorally (the agent shows a diff and asks) rather than against fixed bytes. The `kit_sha` in `up-to-date-repo/` is a placeholder (all-zero); the eval grades the *flow* (resolve → delegate → pin), not a live fetch.
