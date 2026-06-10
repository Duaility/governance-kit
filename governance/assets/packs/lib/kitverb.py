#!/usr/bin/env python3
"""Kit-verb helper: the deterministic core of `governance kit update`.

`kit-plan <root>` resolves everything UPDATE_FLOW.md Steps 1–3 need as one
pure, side-effect-free computation and prints it as JSON:

  * the recorded `installed_kit_version` — read from
    `<root>/.governance/install.yaml`, or reconstructed from the
    `kit-version=` markers on the managed runtime files when the manifest is
    missing (mirrors install.sh `read_marker_kit_version`, taking the min);
  * the version `delta` vs the kit on PATH (`forward` / `up-to-date` /
    `downgrade` / `pre-tracking` / `no-recoverable-pin`);
  * the managed-file inventory — each kit asset paired with its install
    destination, the destination's current marker state, and a plan-status
    hint (`skip` / `apply` / `add` / `unmanaged`).

This is the piece consumers previously hand-assembled from prose — the bash
arrays, the marker scan, the min-reduction, the no-downgrade gate — i.e. the
exact surface where a missed `bash 3.2` quirk or a skipped phase silently
produced a wrong plan (issue #170, finding B). It writes nothing: the agent
still owns diff-before-exec, the per-file confirmation, and the apply itself
(`cp` + install.sh `stamp_managed_marker` + hooks.sh
`generate_hooks_for_strategy` + install.sh `write_installed_manifest`). The
plan is reproducible and unit-tested; the apply primitives already are.

`kit-upstream [--repo <owner/repo>]` is the opt-in read-only staleness check
behind `governance kit update --check-upstream` (issue #170, option 2). It
resolves the latest published `kit/vX.Y.Z` tag via `git ls-remote` and compares
it to the installed `KIT_VERSION`, reporting `current` / `behind` (with a count
and the skill-manager refresh command) / `ahead` / `unknown` (offline). It is
strictly a *signal*: it never fetches-and-applies the kit — that stays the
skill manager's job, so the running flow never applies a version it doesn't
understand and the skill manager's pinning is never bypassed.

Run via:
    uv run --with PyYAML python governance/assets/packs/lib/kitverb.py kit-plan <root>
    uv run --with PyYAML python governance/assets/packs/lib/kitverb.py kit-upstream [--repo <owner/repo>]
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

from packctl import KIT_VERSION, _version_tuple, load_yaml, scalar

# Default upstream the kit is published from. The installed skill records its
# real origin in the `skills` lockfile (`source: Duaility/governance-kit`);
# `--repo` overrides this for forks. GitHub owner/repo is case-insensitive.
DEFAULT_KIT_REPO = "duaility/governance-kit"

# Skill-manager refresh command — the one trusted, pinned channel for pulling a
# newer kit onto the machine. kit-upstream only ever points here; never applies.
REFRESH_CMD = "npx skills update governance --global"

# Kit releases are tagged `kit/vX.Y[.Z]`; annotated tags also emit a `^{}` deref
# line, which the dedupe below collapses.
_KIT_TAG_RE = re.compile(r"refs/tags/kit/v(\d+(?:\.\d+){1,2})(?:\^\{\})?$")

# Kit asset root — `<skill>/governance/assets`. kitverb.py lives at
# `governance/assets/packs/lib/kitverb.py`, so the assets dir is parents[2].
KIT_ASSETS = Path(__file__).resolve().parents[2]

_MARKER_RE = re.compile(r"^# governance-kit:managed", re.MULTILINE)
_KIT_VERSION_TOKEN_RE = re.compile(r"kit-version=(\S+)")


def read_marker(dest: Path) -> dict[str, Any]:
    """Marker state of a managed file, mirroring install.sh read_marker_kit_version.

    Returns {"state": versioned|bare|absent, "version": <v>|None}. Scans for the
    first `# governance-kit:managed` line; `bare` is the pre-kit-version form.
    """
    if not dest.is_file():
        return {"state": "absent", "version": None}
    try:
        text = dest.read_text(errors="replace")
    except OSError:
        return {"state": "absent", "version": None}
    m = _MARKER_RE.search(text)
    if not m:
        return {"state": "absent", "version": None}
    line = text[m.start():].splitlines()[0]
    token = _KIT_VERSION_TOKEN_RE.search(line)
    if token:
        return {"state": "versioned", "version": token.group(1)}
    return {"state": "bare", "version": None}


def _status_for(marker: dict[str, Any], exists: bool) -> str:
    """Plan-status hint from the destination's marker state.

    A hint, not a verdict: the agent still computes the byte-diff (`diff -u`)
    before showing or applying anything. `apply` on a same-version stamp is a
    byte-identical no-op, so the diff is what ultimately decides.
    """
    if not exists:
        return "add"
    if marker["state"] == "absent":
        return "unmanaged"          # user-owned — never silently overwritten
    if marker["state"] == "bare":
        return "apply"              # re-stamp brings it under per-file tracking
    # versioned
    if marker["version"] == KIT_VERSION:
        return "skip"
    return "apply"


def _inventory(root: Path, manifest: dict[str, Any]) -> list[dict[str, Any]]:
    """Managed kit-asset ↔ destination pairs, per UPDATE_FLOW.md Step 3.

    Derived from manifest fields so the set matches exactly what `init` wrote.
    The hook dispatchers are regenerated wholesale (hooks.sh), not copied from a
    static asset, so they are reported via `hook_strategy`, not as file pairs.
    """
    tests_dir = scalar(manifest.get("tests_dir")) or ".governance"
    ci_workflow = scalar(manifest.get("ci_workflow"))
    enable_script = scalar(manifest.get("enable_governance_script"))

    pairs: list[tuple[str, str, str]] = [
        (str(KIT_ASSETS / "dot-governance" / "run.sh"), f"{tests_dir}/run.sh", "run.sh"),
        (str(KIT_ASSETS / "dot-governance" / "lib.sh"), f"{tests_dir}/lib.sh", "lib.sh"),
    ]
    if ci_workflow:
        pairs.append((str(KIT_ASSETS / "governance.yml"), ci_workflow, "ci_workflow"))
    if enable_script:
        pairs.append((str(KIT_ASSETS / "enable-governance.sh"), enable_script, "enable_governance_script"))

    files: list[dict[str, Any]] = []
    for src, rel_dest, key in pairs:
        dest = root / rel_dest
        exists = dest.is_file()
        marker = read_marker(dest)
        files.append({
            "key": key,
            "src": src,
            "dest": rel_dest,
            "exists": exists,
            "marker": marker["state"],
            "dest_version": marker["version"],
            "status": _status_for(marker, exists),
        })
    return files


def _reconstruct(root: Path) -> dict[str, Any]:
    """Rebuild the version pin from per-file markers when the manifest is gone.

    Scans the default managed-file set for `kit-version=` tokens and takes the
    min (an update only lands when *every* file catches up). Returns the
    reconstructed version and the files that contributed, or version=None when
    nothing versioned is found (the no-recoverable-pin case).
    """
    candidates = [
        ".governance/run.sh",
        ".governance/lib.sh",
        ".github/workflows/governance.yml",
        "scripts/enable-governance.sh",
        ".githooks/pre-commit",
    ]
    found: list[tuple[str, str]] = []
    for rel in candidates:
        marker = read_marker(root / rel)
        if marker["state"] == "versioned":
            found.append((rel, marker["version"]))
    if not found:
        return {"version": None, "from": []}
    lowest = min((v for _, v in found), key=_version_tuple)
    return {"version": lowest, "from": [rel for rel, _ in found]}


def _delta(installed: str | None, manifest_present: bool) -> str:
    """Version delta vs the kit on PATH.

    When `installed` is unknown the distinction is whether a manifest exists at
    all: a manifest with no `kit_version` is a *pre-tracking* install (recover
    by recording the current version), whereas no manifest and no reconstructable
    marker is *no-recoverable-pin* (recover only via uninstall + init).
    """
    if installed is None:
        return "pre-tracking" if manifest_present else "no-recoverable-pin"
    inst, kit = _version_tuple(installed), _version_tuple(KIT_VERSION)
    if inst < kit:
        return "forward"
    if inst > kit:
        return "downgrade"
    return "up-to-date"


def cmd_kit_plan(args: argparse.Namespace) -> int:
    root = Path(args.root).resolve()
    manifest_path = root / ".governance" / "install.yaml"

    manifest: dict[str, Any] = {}
    reconstructed_from: list[str] = []
    manifest_present = manifest_path.is_file()

    if manifest_present:
        manifest = load_yaml(manifest_path)
        manifest_source = "install.yaml"
        installed = scalar(manifest.get("kit_version")) or None
    else:
        recon = _reconstruct(root)
        installed = recon["version"]
        reconstructed_from = recon["from"]
        manifest_source = "reconstructed" if installed is not None else "absent"

    plan = {
        "kit_version": KIT_VERSION,
        "installed_kit_version": installed,
        "manifest_source": manifest_source,
        "reconstructed_from": reconstructed_from,
        "delta": _delta(installed, manifest_present),
        "hook_strategy": scalar(manifest.get("hook_strategy")) or "githooks",
        "tests_dir": scalar(manifest.get("tests_dir")) or ".governance",
        "files": _inventory(root, manifest),
    }
    print(json.dumps(plan, indent=2))
    return 0


def parse_kit_tags(ls_remote_output: str) -> list[str]:
    """Distinct kit versions from `git ls-remote --tags` output, in encounter
    order. Matches `refs/tags/kit/vX.Y[.Z]`, ignores non-kit tags (e.g.
    `core/v*`) and the `^{}` annotated-tag deref duplicates."""
    versions: list[str] = []
    seen: set[str] = set()
    for line in ls_remote_output.splitlines():
        m = _KIT_TAG_RE.search(line.strip())
        if m and m.group(1) not in seen:
            seen.add(m.group(1))
            versions.append(m.group(1))
    return versions


def upstream_status(published: list[str], installed: str) -> dict[str, Any]:
    """Compare the installed kit to the published set. `releases_behind` counts
    distinct published versions strictly newer than the installed one."""
    if not published:
        return {"status": "unknown", "latest_published": None, "releases_behind": 0}
    latest = max(published, key=_version_tuple)
    behind = [v for v in published if _version_tuple(v) > _version_tuple(installed)]
    inst, lat = _version_tuple(installed), _version_tuple(latest)
    status = "current" if inst == lat else ("ahead" if inst > lat else "behind")
    return {"status": status, "latest_published": latest, "releases_behind": len(behind)}


def cmd_kit_upstream(args: argparse.Namespace) -> int:
    repo = args.repo or DEFAULT_KIT_REPO
    result: dict[str, Any] = {
        "installed_kit_version": KIT_VERSION,
        "repo": repo,
        "refresh_cmd": REFRESH_CMD,
    }
    error = None
    try:
        proc = subprocess.run(
            ["git", "ls-remote", "--tags", f"https://github.com/{repo}"],
            check=False, text=True, capture_output=True, timeout=20,
        )
        error = proc.stderr.strip() if proc.returncode != 0 else None
    except (OSError, subprocess.SubprocessError) as exc:
        error = str(exc)

    if error is not None:
        # Offline / git missing / bad repo — degrade to `unknown`, never block.
        result.update(status="unknown", latest_published=None, releases_behind=0, error=error)
    else:
        published = parse_kit_tags(proc.stdout)
        result.update(upstream_status(published, KIT_VERSION), published=published)
    print(json.dumps(result, indent=2))
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("kit-plan")
    p.add_argument("root")
    p.set_defaults(func=cmd_kit_plan)

    p = sub.add_parser("kit-upstream")
    p.add_argument("--repo", default=None,
                   help=f"owner/repo to query for kit/v* tags (default {DEFAULT_KIT_REPO})")
    p.set_defaults(func=cmd_kit_upstream)

    args = parser.parse_args(argv)
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
