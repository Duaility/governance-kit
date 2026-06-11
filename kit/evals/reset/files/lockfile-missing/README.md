# lockfile-missing

Post-init repo missing `.governance/packs.lock`. The lockfile is the single source of truth for pack provenance — without it, reset cannot tell which directive came from which pack, and there is no safe heuristic fallback. This fixture exercises the refuse-to-run path: reset must stop and direct the user to `governance uninstall` + `governance init`.

`.governance/install.yaml` is present (so the repo isn't classified as `none-detected`) but the lockfile is intentionally absent.
