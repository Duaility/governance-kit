# up-to-date-repo

Bootstrapped at the same kit version that's currently on PATH (`kit_version`
matches the kit's `KIT_VERSION`). `kit update` should short-circuit at Step 2
with `kit: up-to-date` and exit without writing anything. The pin must be kept
equal to `governance/assets/kit.yaml`'s `version` whenever the kit is released
— `scripts/release.sh` deliberately skips `governance/evals/*`, so a kit bump
that forgets this fixture turns the up-to-date case into a forward update.
`test-kitverb.py` guards against that drift.
