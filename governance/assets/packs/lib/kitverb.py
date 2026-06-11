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
produced a wrong plan (issue #170, finding B). `kit-plan` writes nothing.
With `--diff` it also emits the per-file unified diff, computed against the
source template *after* the new `kit-version=` stamp — the same noise-free
diff UPDATE_FLOW.md Step 4 shows the user.

`kit-apply <root>` is the deterministic execution half (issue #172; engine
in kitapply.py, dispatched from this CLI). It
recomputes the plan (never trusts a stale one), enforces the gates that used
to be prose — refuse on `downgrade` / `no-recoverable-pin`, refuse on
`pre-tracking` without `--record-pre-tracking`, refuse on a dirty working
tree without `--force` — then executes the whole apply in one call: writes
each managed file pre-stamped, honors per-file `--decisions` overrides
(`keep` / `apply` / `overwrite-with-backup`; managed files default to
`apply`, unmanaged ones to `keep`), regenerates the hook dispatchers through
hooks.sh
`generate_hooks_for_strategy`, writes `kit_version` through to
`install.yaml` (in-place edit when the manifest exists; a fresh v3 manifest
via install.sh `write_installed_manifest` when the pin was reconstructed —
that path requires `--owner`/`--repo`), smoke-tests `run.sh`, and prints a
JSON report. The operator (agent or human) keeps what is genuinely theirs:
eliciting the decisions, showing the diffs, and the commit. `--dry-run`
resolves every action and writes nothing.

`kit-resolve <root>` is the repo-pinned orchestration brain (issue #177). It
resolves a `kit update` target (default: the latest published `kit/vX.Y.Z` tag;
`--to X.Y.Z` for an exact version; offline falls back through the cached pin then
the installed skill), fetches that tree via `fetch_kit_ref` into the `kits/`
cache, gates the floor (target ≥ 0.4.0) and direction (`--allow-downgrade`), and
reports which engine the shim should delegate `kit-plan`/`kit-apply` to. Forward
and same-version updates exec the *fetched target's own* `kitverb.py` — so the
code that writes version X's files is version X's code, and markers never lie. A
downgrade runs the *local newer* engine against the fetched older target's
`assets/` + `lib/`. `kit-pin <root> --kit-ref --kit-sha` records the resulting
pin in install.yaml after a successful apply. `kit-resolve` writes nothing.

`kit-upstream [--repo <owner/repo>]` is the opt-in read-only staleness check
behind `governance kit update --check-upstream` (issue #170, option 2). It
resolves the latest published `kit/vX.Y.Z` tag via `git ls-remote` and compares
it to the installed `KIT_VERSION`, reporting `current` / `behind` (with a count
and the skill-manager refresh command) / `ahead` / `unknown` (offline). Since
#177 promoted published-tag resolution to the `kit update` default, this stays
as the lightweight signal that does not fetch.

Run via:
    uv run --with PyYAML python governance/assets/packs/lib/kitverb.py kit-resolve <root> [--to X.Y.Z] [--repo <owner/repo>] [--allow-downgrade] [--offline]
    uv run --with PyYAML python governance/assets/packs/lib/kitverb.py kit-plan <root> [--diff] [--assets-root <path>] [--stamp-version <v>]
    uv run --with PyYAML python governance/assets/packs/lib/kitverb.py kit-apply <root> [--decisions <json>] [--dry-run] [--force] [--record-pre-tracking] [--owner <o> --repo <r>] [--assets-root <path>] [--stamp-version <v>] [--hooks-lib <path>] [--allow-downgrade]
    uv run --with PyYAML python governance/assets/packs/lib/kitverb.py kit-pin <root> --kit-ref <ref> --kit-sha <sha>
    uv run --with PyYAML python governance/assets/packs/lib/kitverb.py fetch-kit <ref>
    uv run --with PyYAML python governance/assets/packs/lib/kitverb.py kit-upstream [--repo <owner/repo>]
"""

from __future__ import annotations

import argparse
import difflib
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

# The kit is published from its skill subdir, so a kit ref points at
# `<owner>/<repo>/governance@kit/vX.Y.Z` — the tree whose `assets/kit.yaml`
# carries the version and whose `assets/packs/lib/kitverb.py` is the engine.
KIT_SUBPATH = "governance"

# Delegated plan/apply requires the target to ship `kitverb.py kit-plan` /
# `kit-apply`, first present in kit/v0.4.0 (issue #172). A `kit update` to a
# target below this floor is refused — there is no engine to delegate to.
KIT_DELEGATION_FLOOR = "0.4.0"

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


def _status_for(marker: dict[str, Any], exists: bool, stamp_version: str) -> str:
    """Plan-status hint from the destination's marker state.

    A hint, not a verdict: the agent still computes the byte-diff (`diff -u`)
    before showing or applying anything. `apply` on a same-version stamp is a
    byte-identical no-op, so the diff is what ultimately decides. `stamp_version`
    is the version being written (this engine's own, or — on a delegated
    downgrade — the fetched older target's).
    """
    if not exists:
        return "add"
    if marker["state"] == "absent":
        return "unmanaged"          # user-owned — never silently overwritten
    if marker["state"] == "bare":
        return "apply"              # re-stamp brings it under per-file tracking
    # versioned
    if marker["version"] == stamp_version:
        return "skip"
    return "apply"


def _inventory(root: Path, manifest: dict[str, Any], assets_root: Path, stamp_version: str) -> list[dict[str, Any]]:
    """Managed kit-asset ↔ destination pairs, per UPDATE_FLOW.md Step 3.

    Derived from manifest fields so the set matches exactly what `init` wrote.
    The hook dispatchers are regenerated wholesale (hooks.sh), not copied from a
    static asset, so they are reported via `hook_strategy`, not as file pairs.
    `assets_root` is the source tree to copy from (this engine's own assets, or
    — on a delegated downgrade — the fetched older target's `assets/`).
    """
    tests_dir = scalar(manifest.get("tests_dir")) or ".governance"
    ci_workflow = scalar(manifest.get("ci_workflow"))
    enable_script = scalar(manifest.get("enable_governance_script"))

    pairs: list[tuple[str, str, str]] = [
        (str(assets_root / "dot-governance" / "run.sh"), f"{tests_dir}/run.sh", "run.sh"),
        (str(assets_root / "dot-governance" / "lib.sh"), f"{tests_dir}/lib.sh", "lib.sh"),
    ]
    if ci_workflow:
        pairs.append((str(assets_root / "governance.yml"), ci_workflow, "ci_workflow"))
    if enable_script:
        pairs.append((str(assets_root / "enable-governance.sh"), enable_script, "enable_governance_script"))

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
            "status": _status_for(marker, exists, stamp_version),
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


def _delta(installed: str | None, manifest_present: bool, stamp_version: str) -> str:
    """Version delta of the recorded pin vs `stamp_version` (the version being applied).

    `stamp_version` is normally this engine's own `KIT_VERSION`. On a delegated
    downgrade the local engine runs against a fetched older target, so it is the
    target's version — which is how the same code path classifies `downgrade`.

    When `installed` is unknown the distinction is whether a manifest exists at
    all: a manifest with no `kit_version` is a *pre-tracking* install (recover
    by recording the current version), whereas no manifest and no reconstructable
    marker is *no-recoverable-pin* (recover only via uninstall + init).
    """
    if installed is None:
        return "pre-tracking" if manifest_present else "no-recoverable-pin"
    inst, kit = _version_tuple(installed), _version_tuple(stamp_version)
    if inst < kit:
        return "forward"
    if inst > kit:
        return "downgrade"
    return "up-to-date"


def compute_plan(
    root: Path,
    assets_root: Path | None = None,
    stamp_version: str | None = None,
) -> dict[str, Any]:
    """The full `kit-plan` resolution as a pure computation.

    Shared by `kit-plan` (which prints it) and `kit-apply` (which recomputes
    it at execution time rather than trusting a possibly-stale plan file).

    `assets_root` / `stamp_version` default to this engine's own
    `KIT_ASSETS` / `KIT_VERSION` — the forward and same-version case, where the
    *fetched target's* engine runs the plan against its own tree (issue #177,
    decision 4). They are overridden only on a delegated downgrade, when the
    local (newer) engine plans against the fetched older target's assets and
    version (decision 5).
    """
    assets_root = assets_root if assets_root is not None else KIT_ASSETS
    stamp_version = stamp_version if stamp_version is not None else KIT_VERSION
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

    return {
        "kit_version": stamp_version,
        "installed_kit_version": installed,
        "manifest_source": manifest_source,
        "reconstructed_from": reconstructed_from,
        "delta": _delta(installed, manifest_present, stamp_version),
        "hook_strategy": scalar(manifest.get("hook_strategy")) or "githooks",
        "tests_dir": scalar(manifest.get("tests_dir")) or ".governance",
        "files": _inventory(root, manifest, assets_root, stamp_version),
    }


def stamped_text(src: Path, kit_version: str) -> str:
    """Source template text with the marker pre-stamped to `kit-version=<v>`.

    Python mirror of install.sh `stamp_managed_marker` (same contract: the
    bare-or-versioned `# governance-kit:managed` line within the first 3
    lines is rewritten; no wall-clock date, so re-stamping is byte-stable).
    Mirrored here so diffs and applies never show marker-line noise. Text
    without a marker in the first 3 lines is returned unchanged.
    """
    lines = src.read_text().splitlines(keepends=True)
    for i, line in enumerate(lines[:3]):
        if line.startswith("# governance-kit:managed"):
            lines[i] = f"# governance-kit:managed kit-version={kit_version}\n"
            break
    return "".join(lines)


def file_diff(dest: Path, dest_rel: str, new_text: str) -> str:
    """Unified diff from the current destination to the stamped source."""
    old = dest.read_text(errors="replace").splitlines(keepends=True) if dest.is_file() else []
    diff = difflib.unified_diff(
        old, new_text.splitlines(keepends=True),
        fromfile=f"a/{dest_rel}", tofile=f"b/{dest_rel}",
    )
    return "".join(diff)


def cmd_kit_plan(args: argparse.Namespace) -> int:
    root = Path(args.root).resolve()
    assets_root = Path(args.assets_root).resolve() if args.assets_root else KIT_ASSETS
    stamp_version = args.stamp_version or KIT_VERSION
    plan = compute_plan(root, assets_root=assets_root, stamp_version=stamp_version)
    if args.diff:
        for entry in plan["files"]:
            new_text = stamped_text(Path(entry["src"]), stamp_version)
            entry["diff"] = file_diff(root / entry["dest"], entry["dest"], new_text)
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


def fetch_published_tags(repo: str) -> tuple[list[str], str | None]:
    """`(kit versions, error)` from `git ls-remote --tags <repo>`.

    The single network read both `kit-upstream` (signal) and `kit-resolve`
    (default target resolution) share. `error` is non-None when offline / git is
    missing / the repo is unreachable — callers degrade rather than block.
    """
    try:
        proc = subprocess.run(
            ["git", "ls-remote", "--tags", f"https://github.com/{repo}"],
            check=False, text=True, capture_output=True, timeout=20,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        return [], str(exc)
    if proc.returncode != 0:
        return [], proc.stderr.strip() or f"git ls-remote exited {proc.returncode}"
    return parse_kit_tags(proc.stdout), None


def cmd_kit_upstream(args: argparse.Namespace) -> int:
    repo = args.repo or DEFAULT_KIT_REPO
    result: dict[str, Any] = {
        "installed_kit_version": KIT_VERSION,
        "repo": repo,
        "refresh_cmd": REFRESH_CMD,
    }
    published, error = fetch_published_tags(repo)
    if error is not None:
        # Offline / git missing / bad repo — degrade to `unknown`, never block.
        result.update(status="unknown", latest_published=None, releases_behind=0, error=error)
    else:
        result.update(upstream_status(published, KIT_VERSION), published=published)
    print(json.dumps(result, indent=2))
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("kit-plan")
    p.add_argument("root")
    p.add_argument("--diff", action="store_true",
                   help="include per-file unified diffs (dest vs stamped source)")
    p.add_argument("--assets-root", default=None,
                   help="source asset tree to plan against (default: this kit's own)")
    p.add_argument("--stamp-version", default=None,
                   help="version to stamp/compare (default: this kit's KIT_VERSION)")
    p.set_defaults(func=cmd_kit_plan)

    p = sub.add_parser("kit-apply")
    p.add_argument("root")
    p.add_argument("--decisions", default=None,
                   help="JSON of {dest: keep|apply|overwrite-with-backup} for unmanaged files — inline or a path to a JSON file")
    p.add_argument("--dry-run", action="store_true",
                   help="resolve every action and report; write nothing")
    p.add_argument("--force", action="store_true",
                   help="proceed over a dirty working tree")
    p.add_argument("--record-pre-tracking", action="store_true",
                   help="consent to recording kit_version on a pre-tracking install")
    p.add_argument("--owner", default=None,
                   help="github owner for the fresh manifest (reconstructed-pin path only)")
    p.add_argument("--repo", default=None,
                   help="repo name for the fresh manifest (reconstructed-pin path only)")
    p.add_argument("--assets-root", default=None,
                   help="source asset tree to apply from (default: this kit's own; a "
                        "delegated downgrade points it at the fetched older target)")
    p.add_argument("--stamp-version", default=None,
                   help="version to stamp/record (default: this kit's KIT_VERSION)")
    p.add_argument("--hooks-lib", default=None,
                   help="lib dir whose install.sh/hooks.sh generate the dispatchers "
                        "(default: this kit's own; the fetched target's on a downgrade)")
    p.add_argument("--allow-downgrade", action="store_true",
                   help="permit rolling the kit-runtime backward (target older than recorded)")
    # Local import: kitapply imports compute_plan/stamped_text from this
    # module, so a top-level import here would be a cycle. The engine lives
    # in its own module to keep each file a focused, reviewable unit.
    from kitapply import cmd_kit_apply
    p.set_defaults(func=cmd_kit_apply)

    # Network + pin orchestration lives in kitresolve.py (kept separate so each
    # module stays focused and under the file-size budget). Lazy-imported here
    # because kitresolve imports this module at top level — a top-level import
    # the other way would be a cycle. Issue #177.
    from kitresolve import cmd_fetch_kit, cmd_kit_current, cmd_kit_pin, cmd_kit_resolve

    p = sub.add_parser("kit-current")
    p.add_argument("root")
    p.add_argument("--offline", action="store_true",
                   help="skip the network; resolve from cache or the installed skill")
    p.set_defaults(func=cmd_kit_current)

    p = sub.add_parser("kit-resolve")
    p.add_argument("root")
    p.add_argument("--to", default=None,
                   help="resolve an exact published version X.Y.Z (default: latest tag)")
    p.add_argument("--repo", default=None,
                   help=f"owner/repo to resolve kit/v* tags from (default {DEFAULT_KIT_REPO})")
    p.add_argument("--allow-downgrade", action="store_true",
                   help="permit resolving a target older than the repo's recorded pin")
    p.add_argument("--offline", action="store_true",
                   help="skip the network; resolve from the cached pin or installed skill")
    p.set_defaults(func=cmd_kit_resolve)

    p = sub.add_parser("kit-pin")
    p.add_argument("root")
    p.add_argument("--kit-ref", required=True)
    p.add_argument("--kit-sha", required=True)
    p.set_defaults(func=cmd_kit_pin)

    p = sub.add_parser("fetch-kit")
    p.add_argument("ref")
    p.set_defaults(func=cmd_fetch_kit)

    p = sub.add_parser("kit-upstream")
    p.add_argument("--repo", default=None,
                   help=f"owner/repo to query for kit/v* tags (default {DEFAULT_KIT_REPO})")
    p.set_defaults(func=cmd_kit_upstream)

    args = parser.parse_args(argv)
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
