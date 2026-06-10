#!/usr/bin/env python3
"""Kit-resolution orchestration: the network + pin half of `governance kit update`.

Companion to kitverb.py (the pure plan/stamp core) — split out so each module
stays under the repo's file-size budget and keeps a single focus. This module
owns everything that reaches the network or writes the pin (issue #177):

  * `fetch_kit_ref` / `cached_kit_path` / `ls_remote_sha` — the kit twin of the
    pack fetch machinery (`~/.governance/cache/kits/<owner>__<repo>@<sha>/`);
  * `kit-resolve` — resolve a target (published tag / `--to` / cache / installed
    skill), fetch it, gate the floor + direction, and name the engine the shim
    delegates `kit-plan`/`kit-apply` to;
  * `kit-pin` — record `kit_ref`/`kit_sha` in install.yaml after a successful
    apply, so the manifest is the authoritative statement of which kit runs;
  * `fetch-kit` — a debug wrapper over `fetch_kit_ref`.

Subcommands are registered from kitverb.py `main` (lazy import, to avoid a cycle
since this module imports kitverb at top level).
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
from packverb import cache_base, clone_into_cache, parse_ref
from kitverb import (
    DEFAULT_KIT_REPO,
    KIT_ASSETS,
    KIT_DELEGATION_FLOOR,
    KIT_SUBPATH,
    REFRESH_CMD,
    compute_plan,
    fetch_published_tags,
)

# This engine's own location — the local fallback when the target tree is the
# installed skill (offline, no cache) or when a delegated downgrade runs the
# newer engine against fetched older assets. Points at the *plan/apply* engine
# (kitverb.py), not this orchestration module.
KITVERB_SELF = Path(__file__).resolve().parent / "kitverb.py"


def ls_remote_sha(repo: str, tag: str) -> str | None:
    """Resolve a single tag to its commit SHA via `git ls-remote` (no clone).

    Prefers the `^{}` peeled line (the commit an annotated tag points at — what
    a clone of the tag would check out). Returns None offline or when the tag is
    absent. Used by `init` to record `kit_sha` cheaply, without a full fetch.
    """
    try:
        proc = subprocess.run(
            ["git", "ls-remote", f"https://github.com/{repo}", f"refs/tags/{tag}"],
            check=False, text=True, capture_output=True, timeout=20,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if proc.returncode != 0 or not proc.stdout.strip():
        return None
    lines = proc.stdout.splitlines()
    peeled = [ln for ln in lines if ln.rstrip().endswith("^{}")]
    chosen = peeled[0] if peeled else lines[0]
    return chosen.split()[0]


def fetch_kit_ref(ref: str) -> dict[str, str]:
    """Clone a kit `ref` into `~/.governance/cache/kits/<owner>__<repo>@<sha>/`.

    The kit-axis twin of `packverb.fetch_ref`: it reuses the same content-
    addressed clone primitive but validates `assets/kit.yaml` (version field)
    instead of `pack.yaml` (id), and caches under the `kits/` namespace. Returns
    `{sha, kit_dir, cache_dir, version}` — `kit_dir` is the cached skill tree
    whose `assets/packs/lib/kitverb.py` is the delegated engine.
    """
    def identity(target: Path, parsed: dict[str, str]) -> tuple[str, dict[str, str]]:
        kit_yaml = target / "assets" / "kit.yaml"
        if not kit_yaml.is_file():
            raise SystemExit(
                f"fetch-kit: no assets/kit.yaml at {parsed['subpath'] or '<root>'} in {ref}"
            )
        version = scalar(load_yaml(kit_yaml).get("version"))
        if not version:
            raise SystemExit(f"fetch-kit: assets/kit.yaml carries no version in {ref}")
        slug = f"{parsed['owner'].lower()}__{parsed['repo'].lower()}"
        return slug, {"version": version}

    res = clone_into_cache(ref, "kits", identity)
    return {"sha": res["sha"], "kit_dir": res["target_dir"], "cache_dir": res["cache_dir"], "version": res["version"]}


def cached_kit_path(ref: str, sha: str) -> dict[str, str] | None:
    """The on-disk cache entry for a (ref, sha) pair, or None if not cached.

    The offline fallback's first hop: a repo pinned by `kit_ref`/`kit_sha` whose
    tree is already in `~/.governance/cache/kits/` can be re-applied with no
    network. Validates `assets/kit.yaml` is present before claiming a hit.
    """
    try:
        parsed = parse_ref(ref)
    except ValueError:
        return None
    slug = f"{parsed['owner'].lower()}__{parsed['repo'].lower()}"
    cache_dir = cache_base() / "kits" / f"{slug}@{sha}"
    kit_dir = cache_dir / parsed["subpath"] if parsed["subpath"] else cache_dir
    kit_yaml = kit_dir / "assets" / "kit.yaml"
    if not kit_yaml.is_file():
        return None
    return {
        "cache_dir": str(cache_dir),
        "kit_dir": str(kit_dir),
        "version": scalar(load_yaml(kit_yaml).get("version")),
    }


def build_kit_ref(repo: str, version: str) -> str:
    """The canonical kit ref for `repo` at `version`: gh:<repo>/governance@kit/vX.Y.Z."""
    return f"gh:{repo}/{KIT_SUBPATH}@kit/v{version}"


def _direction(current: str | None, target: str) -> str:
    """`forward` / `same` / `downgrade` of `target` vs the repo's recorded pin.

    `unknown` when there is no recorded pin (pre-tracking / reconstructed /
    no-manifest) — the delegated engine classifies and gates those cases itself.
    """
    if current is None:
        return "unknown"
    c, t = _version_tuple(current), _version_tuple(target)
    if t > c:
        return "forward"
    if t < c:
        return "downgrade"
    return "same"


def cmd_kit_resolve(args: argparse.Namespace) -> int:
    """Resolve a `kit update` target, fetch its tree, and plan the delegation.

    The orchestration brain of the repo-pinned model (issue #177). It resolves
    the target version (default: the latest published `kit/vX.Y.Z` tag; `--to`
    selects an exact version; offline falls back through the cached pin then the
    installed skill), fetches that tree into the `kits/` cache, then reports
    which engine the shim should delegate to and with what flags:

      * forward / same-version → the *fetched target's own* `kitverb.py`, so the
        code that writes version X's files is version X's code (decision 4);
      * downgrade → the *local newer* engine against the fetched older target's
        `assets/` + `lib/` (decisions 5 + open-Q1-b), gated by --allow-downgrade;
      * installed-skill fallback (offline, no cache) → the local engine, no fetch.

    Writes nothing to the repo. The shim runs the named engine's `kit-plan` /
    `kit-apply`, then `kit-pin` to record `kit_ref`/`kit_sha`.
    """
    root = Path(args.root).resolve()
    repo = (args.repo or DEFAULT_KIT_REPO).lower()
    self_plan = compute_plan(root)
    current = self_plan["installed_kit_version"]

    report: dict[str, Any] = {
        "result": None,
        "current_version": current,
        "manifest_source": self_plan["manifest_source"],
        "target_version": None,
        "kit_ref": None,
        "kit_sha": None,
        "cache_dir": None,
        "kit_dir": None,
        "engine_path": None,
        "assets_root": None,
        "hooks_lib": None,
        "direction": None,
        "provenance": None,
        "floor_ok": None,
        "delegate": None,
        "assumptions": [],
    }

    manifest = self_plan_manifest(root)
    target = ref = sha = kit_dir = cache_dir = provenance = None
    resolve_error: str | None = None

    # --- choose a ref + version to fetch ---
    if args.to:
        target, provenance = args.to, "explicit"
        ref = build_kit_ref(repo, target)
    elif not args.offline:
        published, resolve_error = fetch_published_tags(repo)
        if published:
            target, provenance = max(published, key=_version_tuple), "published-tag"
            ref = build_kit_ref(repo, target)

    # --- fetch (network) unless we are already forced offline ---
    if ref and not args.offline:
        try:
            fetched = fetch_kit_ref(ref)
            target = fetched["version"]
            sha, kit_dir, cache_dir = fetched["sha"], fetched["kit_dir"], fetched["cache_dir"]
        except (SystemExit, subprocess.CalledProcessError, OSError) as exc:
            resolve_error, ref, target = str(exc), None, None

    # --- fallback chain: cached pin → installed skill ---
    if kit_dir is None:
        m_ref, m_sha = scalar(manifest.get("kit_ref")), scalar(manifest.get("kit_sha"))
        cached = cached_kit_path(m_ref, m_sha) if (m_ref and m_sha) else None
        if cached:
            target, ref, sha, provenance = cached["version"], m_ref, m_sha, "cache"
            kit_dir, cache_dir = cached["kit_dir"], cached["cache_dir"]
            report["assumptions"].append(
                "offline / upstream unreachable — applied the cached pin "
                f"({m_ref}@{m_sha[:12]}); not checked for a newer release"
            )
        else:
            target, provenance, ref, sha = KIT_VERSION, "installed-skill", None, None
            report["assumptions"].append(
                "offline / upstream unreachable and no cached pin — fell back to the "
                f"installed skill (kit {KIT_VERSION}); refresh the skill "
                f"({REFRESH_CMD}) and re-run to pick up a published release"
            )
        if resolve_error:
            report["assumptions"].append(f"resolution note: {resolve_error}")

    report.update(target_version=target, kit_ref=ref, kit_sha=sha,
                  cache_dir=cache_dir, kit_dir=kit_dir, provenance=provenance)

    # --- floor gate: a target below the delegation floor has no engine ---
    floor_ok = _version_tuple(target) >= _version_tuple(KIT_DELEGATION_FLOOR)
    report["floor_ok"] = floor_ok
    if not floor_ok:
        return _resolve_refuse(
            report,
            f"target kit {target} predates delegated apply (floor {KIT_DELEGATION_FLOOR}); "
            "it ships no kitverb.py to delegate to",
            f"to install a kit older than {KIT_DELEGATION_FLOOR}, use the legacy "
            f"skill-reinstall path: npx skills add Duaility/governance-kit#kit/v{target} "
            "--global --skill governance --agent claude-code, then run kit update from that skill",
        )

    # --- direction + downgrade gate ---
    direction = _direction(current, target)
    report["direction"] = direction
    if direction == "downgrade" and not args.allow_downgrade:
        return _resolve_refuse(
            report,
            f"target kit {target} is older than the repo's recorded {current} (downgrade)",
            "re-run with --allow-downgrade to roll the kit-runtime backward",
        )

    # --- name the engine the shim should delegate to ---
    local_lib = str(KITVERB_SELF.parent)
    if provenance == "installed-skill":
        report.update(delegate=False, engine_path=str(KITVERB_SELF),
                      assets_root=str(KIT_ASSETS), hooks_lib=local_lib)
    elif direction == "downgrade":
        # Newer (local) engine, older fetched assets + lib (open Q1, option b).
        report.update(delegate=True, engine_path=str(KITVERB_SELF),
                      assets_root=str(Path(kit_dir) / "assets"),
                      hooks_lib=str(Path(kit_dir) / "assets" / "packs" / "lib"))
    else:
        # forward / same / unknown — the fetched target's own engine.
        report.update(delegate=True,
                      engine_path=str(Path(kit_dir) / "assets" / "packs" / "lib" / "kitverb.py"),
                      assets_root=str(Path(kit_dir) / "assets"),
                      hooks_lib=str(Path(kit_dir) / "assets" / "packs" / "lib"))

    report["result"] = "ok"
    print(json.dumps(report, indent=2))
    return 0


def self_plan_manifest(root: Path) -> dict[str, Any]:
    """The repo's install.yaml as a dict (empty when absent) — for reading the pin."""
    manifest_path = root / ".governance" / "install.yaml"
    return load_yaml(manifest_path) if manifest_path.is_file() else {}


def _resolve_refuse(report: dict[str, Any], reason: str, recovery: str) -> int:
    report.update(result="refused", reason=reason, recovery=recovery)
    print(json.dumps(report, indent=2))
    return 2


def set_manifest_pin(manifest_path: Path, kit_ref: str, kit_sha: str) -> None:
    """Idempotently set `kit_ref` / `kit_sha` in install.yaml, preserving the rest.

    Updates the lines in place when present; otherwise inserts them right after
    `kit_version:` (or after `repo:`, or appends). A line edit can't lose fields
    it never touches — the same discipline as kitapply's kit_version write-through.
    """
    lines = manifest_path.read_text().splitlines(keepends=True)

    def upsert(key: str, value: str) -> None:
        new_line = f"{key}: {value}\n"
        for i, line in enumerate(lines):
            if re.match(rf"{key}\s*:", line):
                lines[i] = new_line
                return
        for anchor in (r"kit_version\s*:", r"repo\s*:"):
            for i, line in enumerate(lines):
                if re.match(anchor, line):
                    lines.insert(i + 1, new_line)
                    return
        lines.append(new_line)

    upsert("kit_ref", kit_ref)
    upsert("kit_sha", kit_sha)
    manifest_path.write_text("".join(lines))


def cmd_kit_pin(args: argparse.Namespace) -> int:
    """Record `kit_ref` / `kit_sha` in the repo's install.yaml (issue #177).

    The shim runs this after a successful delegated apply, so the repo's manifest
    becomes the authoritative statement of which kit it runs. Kept separate from
    `kit-apply` so the value-write is identical regardless of which (possibly
    older) target engine performed the file apply — the byte-identity contract.
    """
    manifest_path = Path(args.root).resolve() / ".governance" / "install.yaml"
    result: dict[str, Any] = {"kit_ref": args.kit_ref, "kit_sha": args.kit_sha}
    if not manifest_path.is_file():
        result.update(result="error", reason="no .governance/install.yaml to pin")
        print(json.dumps(result, indent=2))
        return 1
    set_manifest_pin(manifest_path, args.kit_ref, args.kit_sha)
    result["result"] = "pinned"
    print(json.dumps(result, indent=2))
    return 0


def cmd_fetch_kit(args: argparse.Namespace) -> int:
    try:
        print(json.dumps(fetch_kit_ref(args.ref)))
    except (ValueError, subprocess.CalledProcessError, SystemExit, OSError) as exc:
        print(f"fetch-kit failed: {exc}", file=sys.stderr)
        return 1
    return 0
