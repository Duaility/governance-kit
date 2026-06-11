# Receipt: harden CI supply-chain hygiene (issue-188)

Strengthen the repo's CI/supply-chain posture with GitHub-native hygiene,
layered on top of what the `workflows-hardened` directive already enforces
(third-party SHA-pinning + a `permissions:` block per workflow).

## Checklist

- [x] Pinned first-party actions to commit SHAs
- [x] `.github/dependabot.yml`
- [x] `CODEOWNERS`
- [x] `.github/workflows/scorecard.yml`
- [x] Live repo settings applied out-of-band

## What changed

- **Pinned first-party actions to commit SHAs** in `.github/workflows/docs.yml`:
  `actions/checkout` (v4.3.1), `actions/setup-node` (v4.4.0),
  `actions/upload-pages-artifact` (v3.0.1), `actions/deploy-pages` (v4.0.5).
  `workflows-hardened` allowlists the `actions/*` namespace, so these were not
  violations — but GitHub's hardening guidance recommends pinning even
  first-party actions, and `release.yml` already pins `checkout`. This makes
  SHA-pinning consistent across every workflow.
- **`.github/dependabot.yml`** — `github-actions` and `npm` (docs-site)
  ecosystems, weekly, grouped one-PR-per-ecosystem. Keeps the SHA pins current
  with an auditable bump trail instead of by-hand updates.
- **`CODEOWNERS`** — a default reviewer for every path, pairing with the new
  `main` branch-protection ruleset's require-review rule.
- **`.github/workflows/scorecard.yml`** — OpenSSF Scorecard analysis (weekly +
  on push to `main` + on branch-protection changes). Publishes to code scanning
  and the OpenSSF API. The third-party `ossf/scorecard-action` is SHA-pinned
  (v2.4.3) per `workflows-hardened`; `actions/*` and `github/*` steps are pinned
  too. Top-level `permissions: read-all`; the job elevates only
  `security-events: write` + `id-token: write`.
- **Live repo settings applied out-of-band** (branch-protection ruleset,
  squash-only merges, secret scanning + push protection, private vulnerability
  reporting, Dependabot alerts) are detailed in the next section for the audit
  trail.

## Applied out-of-band (live repo settings, not via this PR)

These are repository settings, applied through `gh api` / `gh repo edit`, and
are recorded here for the audit trail:

- **Branch-protection ruleset on `main`** (id 17540529, active): require a PR
  with at least one approval, passing status checks (`governance`, `tests`,
  `Analyze (python)`, `Analyze (javascript-typescript)`, `Analyze (go)`),
  linear history, no force-push or deletion. Admin role bypasses (`always`) so
  the direct-to-main release flow via `scripts/release.sh` still works.
- **Merge settings**: squash-only (merge-commit and rebase-merge disabled),
  delete-branch-on-merge enabled. Protects the accounting trailers that a
  merge-commit would strip.
- **Secret scanning + push protection**, **private vulnerability reporting**,
  and **Dependabot alerts** enabled.

## Out of scope

- **Build-provenance attestations** (`actions/attest-build-provenance`):
  `release.yml` only publishes release notes lifted from `CHANGELOG.md` via the
  `gh` CLI — it ships no built or uploaded artifact, so there is nothing to
  attest. Revisit if releases ever produce binaries.
- **Re-templating `scorecard.yml`/`dependabot.yml` into target repos**: these
  harden this repo only; shipping them as `governance` init assets is a separate
  feature, not this PR.

## Decisions

- **Pin first-party actions even though `workflows-hardened` allowlists them.**
  Defense-in-depth: GitHub's own hardening guide recommends pinning all actions,
  and the repo already half-did this. Consistency over a partial allowlist.
- **No build-provenance now.** Attesting a non-existent artifact would be
  ceremony, not provenance.
- **Admin bypass on the ruleset.** Keeps the sanctioned direct-to-main release
  path open while making green-PR-with-review the default for everyone else.

## Verification

```sh
bash .governance/run.sh   # dogfood suite green, incl. workflows-hardened on the
                          # pinned docs.yml + new scorecard.yml
```

GitHub Actions linting of the two new/edited workflows runs on this PR; the
Scorecard workflow itself first executes after merge to `main`.
