# issue-216 — advance .governance kit pin v0.4.0 → v0.6.0

Closes #216.

## Checklist

- [x] Record corrected kit pin in install.yaml at kit/v0.6.0
- [x] Confirm same-version up-to-date delta (no runtime file rewrites)
- [x] Verify governance suite passes

## What changed

Ran `governance update` against the repo's pinned kit (the thin-shim →
`bootstrap.py` → delegated-engine path). Resolution reported
`direction: same` / `delta: up-to-date`: the runtime managed files
(`run.sh`, `lib.sh`, the hook dispatcher) and `install.yaml`'s
`kit_version` were already stamped `0.6.0` by the `kit/v0.6.0` release
commits, so `kit-apply` rewrote nothing.

The one stale value was the orchestration pin, corrected by the delegated
`kit-pin` engine — **Record corrected kit pin in install.yaml at
kit/v0.6.0**:

- `kit_ref`: `gh:duaility/governance-kit/governance@kit/v0.4.0` →
  `gh:duaility/governance-kit/kit@kit/v0.6.0` (also drops the
  pre-thin-shim `governance@` path for the current `kit@` layout)
- `kit_sha`: `c2680e0c15f222a26bde6a073ae9a1d541a828f7` →
  `adf959096dff0855c4743141d6c004453619277f`

`.governance/install.yaml` is the only file touched.

## Out of scope

Pack pins. `packs.lock` stays at `v0.2.0` for every bundled pack — the
by-design Lane-1 one-release lag (foundation/docs/commits `v0.2.1`,
audit `v0.3.0` were just published). A separate post-release
`governance pack update` catches those up and re-materializes the
vendored consumed tree; this change is the **kit axis only**.

## Verification

**Confirm same-version up-to-date delta (no runtime file rewrites)** — the
delegated engine reported `up-to-date` and listed all four managed files
under `skipped`:

```sh
uv run --quiet --isolated --with PyYAML python \
  "$KIT_LIB/kitverb.py" kit-plan "$(pwd)"
# delta: up-to-date; run.sh/lib.sh/ci_workflow/enable_governance_script → skip
```

**Verify governance suite passes** with the re-pinned manifest:

```sh
bash .governance/run.sh
# ✓ governance: all 21 directive(s) passed
```

## Decisions

- **Kit-axis only, by user direction.** Offered kit-pin-only vs.
  `--with-packs`; the user chose kit pin only, so pack pins were left at
  the Lane-1 lag rather than advanced in the same change.
- **Same-version pin correction, not a forward update.** Because the
  release commits had already re-stamped the runtime files to `0.6.0`,
  the kit move resolved as `direction: same`. The fix is purely the
  `kit_ref`/`kit_sha` record (`kit-pin`); no managed file changed, so no
  `kit-version=` marker moved.
