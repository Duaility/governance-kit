#!/usr/bin/env python3
"""Pack-verb helpers: ref parsing, fetch/resolve, lockfile I/O, capability
enforcement. Consumed by the `governance pack *` verbs.

Run via:
    uv run --with PyYAML python governance/assets/packs/lib/packverb.py ...
"""

from __future__ import annotations

import argparse
import fnmatch
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import yaml

from packctl import load_yaml, pack_manifest, scalar, validate_pack_dir

LOCK_VERSION = "1"

# Scoped pack id pattern: `<author>/<slug>` — both segments start with an
# alphanumeric and allow `.`, `_`, `-` after that. Kept in sync with
# extensions/catalog.schema.json.
PACK_ID_RE = re.compile(r"^[a-z0-9][a-z0-9._-]*/[a-z0-9][a-z0-9._-]*$")

# Pack refs look like:
#   gh:<owner>/<repo>[/<subpath>][@<rev>]
GH_REF_RE = re.compile(
    r"^gh:(?P<owner>[^/@\s]+)/(?P<repo>[^/@\s]+)"
    r"(?:/(?P<subpath>[^@\s]+))?"
    r"(?:@(?P<rev>[^\s]+))?$"
)


def _utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_ref(ref: str) -> dict[str, str]:
    """Parse a pack ref → structured fields. Raises ValueError on invalid input."""
    match = GH_REF_RE.match(ref)
    if not match:
        raise ValueError(f"unrecognized pack ref: {ref!r} (expected gh:owner/repo[/subpath][@rev])")
    owner = match.group("owner")
    repo = match.group("repo")
    subpath = match.group("subpath") or ""
    rev = match.group("rev") or "HEAD"
    return {
        "scheme": "gh",
        "owner": owner,
        "repo": repo,
        "subpath": subpath,
        "rev": rev,
        "url": f"https://github.com/{owner}/{repo}.git",
    }


def cache_root() -> Path:
    """Shared pack cache root. Honors `GOVERNANCE_KIT_HOME`; defaults to ~/.governance/cache/."""
    override = os.environ.get("GOVERNANCE_KIT_HOME")
    base = Path(override) if override else Path.home() / ".governance" / "cache"
    return base / "packs"


def _slugify_pack_id(pack_id: str) -> str:
    return pack_id.replace("/", "__")


def fetch_ref(ref: str, cache_dir: Path | None = None) -> dict[str, str]:
    """Clone `ref` into the shared cache, resolving HEAD to a concrete SHA.

    Idempotent: repeat calls with the same resolved SHA hit the cache.
    """
    parsed = parse_ref(ref)
    root = cache_dir if cache_dir else cache_root()
    root.mkdir(parents=True, exist_ok=True)

    rev = parsed["rev"]
    is_sha = bool(re.fullmatch(r"[0-9a-f]{40}", rev))

    with tempfile.TemporaryDirectory(prefix="gk-fetch-", dir=str(root)) as tmp:
        tmp_path = Path(tmp) / "checkout"
        if is_sha:
            # `git clone --branch` does not accept raw commit SHAs on most
            # servers; init + fetch a single commit by SHA instead. Requires
            # the remote to allow `uploadpack.allowReachableSHA1InWant`
            # (GitHub does).
            tmp_path.mkdir(parents=True)
            subprocess.run(
                ["git", "-C", str(tmp_path), "init", "--quiet"],
                check=True,
            )
            subprocess.run(
                ["git", "-C", str(tmp_path), "remote", "add", "origin", parsed["url"]],
                check=True,
            )
            subprocess.run(
                ["git", "-C", str(tmp_path), "fetch", "--depth", "1", "--quiet", "origin", rev],
                check=True,
            )
            subprocess.run(
                ["git", "-C", str(tmp_path), "checkout", "--quiet", "FETCH_HEAD"],
                check=True,
            )
        else:
            clone_cmd = ["git", "clone", "--depth", "1", "--quiet"]
            if rev != "HEAD":
                clone_cmd += ["--branch", rev]
            clone_cmd += [parsed["url"], str(tmp_path)]
            subprocess.run(clone_cmd, check=True)
        sha = subprocess.check_output(
            ["git", "-C", str(tmp_path), "rev-parse", "HEAD"], text=True
        ).strip()

        pack_sub = tmp_path / parsed["subpath"] if parsed["subpath"] else tmp_path
        if not (pack_sub / "pack.yaml").is_file():
            raise SystemExit(
                f"fetch: no pack.yaml at {parsed['subpath'] or '<root>'} in {ref}"
            )
        pack_id = scalar(pack_manifest(pack_sub).get("id"))
        if not pack_id or not PACK_ID_RE.match(pack_id):
            raise SystemExit(
                f"fetch: pack.yaml id {pack_id!r} is not a scoped id (pattern: author/slug)"
            )

        final_root = root / f"{_slugify_pack_id(pack_id)}@{sha}"
        pack_dir = final_root / parsed["subpath"] if parsed["subpath"] else final_root
        if final_root.exists():
            return {"sha": sha, "pack_dir": str(pack_dir), "cache_dir": str(final_root), "id": pack_id}

        shutil.rmtree(tmp_path / ".git", ignore_errors=True)
        shutil.move(str(tmp_path), str(final_root))
        return {"sha": sha, "pack_dir": str(pack_dir), "cache_dir": str(final_root), "id": pack_id}


# ---- Capability-glob enforcement ------------------------------------------

_PATH_TOKEN_RE = re.compile(r"""["']([A-Za-z0-9_./\-]{2,})["']""")


def _collect_referenced_paths(check_sh: Path) -> list[str]:
    """Extract quoted path-like tokens from a check.sh. Best-effort static sweep."""
    if not check_sh.is_file():
        return []
    text = check_sh.read_text()
    out: set[str] = set()
    for match in _PATH_TOKEN_RE.finditer(text):
        token = match.group(1)
        if "://" in token or token.startswith("-"):
            continue
        if "/" not in token:
            continue
        out.add(token)
    return sorted(out)


def _matches_any(path: str, globs: list[str]) -> bool:
    for pattern in globs:
        flat = pattern.replace("**", "*")
        if fnmatch.fnmatch(path, flat):
            return True
        if flat.endswith("/*") and path.startswith(flat[:-2] + "/"):
            return True
    return False


def capability_violations(directive_dir: Path) -> list[str]:
    """Return [] when the directive's check.sh stays within declared reads/writes globs.

    Directives that declare neither reads: nor writes: opt out of the check.
    """
    directive_yaml = directive_dir / "directive.yaml"
    if not directive_yaml.is_file():
        return [f"{directive_dir}: directive.yaml missing"]
    manifest = load_yaml(directive_yaml)
    reads = manifest.get("reads") or []
    writes = manifest.get("writes") or []
    if not isinstance(reads, list) or not isinstance(writes, list):
        return [f"{directive_dir}: reads/writes must be lists of globs"]
    if not reads and not writes:
        return []

    allowed = [str(g) for g in (*reads, *writes)]
    violations: list[str] = []
    for token in _collect_referenced_paths(directive_dir / "check.sh"):
        if not _matches_any(token, allowed):
            violations.append(
                f"{directive_dir}: check.sh references {token!r} outside declared reads/writes globs"
            )
    return violations


# ---- Lockfile I/O ---------------------------------------------------------


def load_lockfile(path: Path) -> dict[str, Any]:
    if not path.is_file():
        return {"version": LOCK_VERSION, "packs": []}
    data = load_yaml(path)
    if data.get("version") != LOCK_VERSION:
        raise SystemExit(f"{path}: unsupported lockfile version {data.get('version')!r}")
    packs = data.get("packs") or []
    if not isinstance(packs, list):
        raise SystemExit(f"{path}: packs must be a list")
    return {"version": LOCK_VERSION, "packs": packs}


def write_lockfile(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    packs = sorted(data.get("packs") or [], key=lambda p: str(p.get("id") or ""))
    out = {"version": data.get("version", LOCK_VERSION), "packs": packs}
    path.write_text(yaml.safe_dump(out, sort_keys=False, default_flow_style=False))


# ---- Subcommand plumbing --------------------------------------------------


def cmd_parse_ref(args: argparse.Namespace) -> int:
    try:
        parsed = parse_ref(args.ref)
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    for key in ("scheme", "owner", "repo", "subpath", "rev", "url"):
        print(f"{key}={parsed[key]}")
    return 0


def cmd_fetch(args: argparse.Namespace) -> int:
    try:
        print(json.dumps(fetch_ref(args.ref)))
    except (ValueError, subprocess.CalledProcessError, SystemExit) as exc:
        print(f"fetch failed: {exc}", file=sys.stderr)
        return 1
    return 0


def cmd_cache_root(_: argparse.Namespace) -> int:
    print(cache_root())
    return 0


def cmd_validate_pack(args: argparse.Namespace) -> int:
    errors = validate_pack_dir(Path(args.pack_dir))
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    return 0


def cmd_capability_check(args: argparse.Namespace) -> int:
    violations = capability_violations(Path(args.directive_dir))
    if violations:
        print("\n".join(violations))
        return 1
    return 0


def cmd_lock_read(args: argparse.Namespace) -> int:
    print(json.dumps(load_lockfile(Path(args.lockfile))))
    return 0


def cmd_lock_add(args: argparse.Namespace) -> int:
    path = Path(args.lockfile)
    data = load_lockfile(path)
    entry = {
        "id": args.pack_id,
        "ref": args.ref,
        "sha": args.sha,
        "subpath": args.subpath or "",
        "min_governance_kit": args.min_kit or "",
        "installed_at": _utc_now(),
        "directives": sorted(args.directives or []),
    }
    data["packs"] = [p for p in data["packs"] if p.get("id") != args.pack_id]
    data["packs"].append(entry)
    write_lockfile(path, data)
    print(json.dumps(entry))
    return 0


def cmd_lock_remove(args: argparse.Namespace) -> int:
    path = Path(args.lockfile)
    data = load_lockfile(path)
    before = len(data["packs"])
    data["packs"] = [p for p in data["packs"] if p.get("id") != args.pack_id]
    if len(data["packs"]) == before:
        print(f"lock-remove: pack {args.pack_id!r} not in lockfile", file=sys.stderr)
        return 1
    write_lockfile(path, data)
    return 0


def cmd_lock_list(args: argparse.Namespace) -> int:
    data = load_lockfile(Path(args.lockfile))
    for pack in data["packs"]:
        print(f"{pack.get('id')}\t{pack.get('sha')}\t{pack.get('ref')}")
    return 0


def cmd_catalog_search(args: argparse.Namespace) -> int:
    path = Path(args.catalog)
    if not path.is_file():
        print(f"catalog not found: {path}", file=sys.stderr)
        return 1
    data = json.loads(path.read_text())
    needle = (args.query or "").lower()
    for entry in data.get("packs", []) or []:
        haystack = " ".join(
            str(entry.get(k, "")) for k in ("id", "summary", "category", "tags")
        ).lower()
        if needle and needle not in haystack:
            continue
        source = entry.get("source", {}) or {}
        if source.get("type") == "github":
            ref = f"gh:{source.get('ref', '')}"
            subpath = source.get("path") or ""
            if subpath:
                ref = f"{ref}/{subpath.strip('/')}"
        else:
            ref = ""
        print(f"{entry.get('id', '')}\t{ref}\t{entry.get('summary', '')}")
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("parse-ref")
    p.add_argument("ref")
    p.set_defaults(func=cmd_parse_ref)

    p = sub.add_parser("cache-root")
    p.set_defaults(func=cmd_cache_root)

    p = sub.add_parser("fetch")
    p.add_argument("ref")
    p.set_defaults(func=cmd_fetch)

    p = sub.add_parser("validate-pack")
    p.add_argument("pack_dir")
    p.set_defaults(func=cmd_validate_pack)

    p = sub.add_parser("capability-check")
    p.add_argument("directive_dir")
    p.set_defaults(func=cmd_capability_check)

    p = sub.add_parser("lock-read")
    p.add_argument("lockfile")
    p.set_defaults(func=cmd_lock_read)

    p = sub.add_parser("lock-add")
    p.add_argument("lockfile")
    p.add_argument("pack_id")
    p.add_argument("ref")
    p.add_argument("sha")
    p.add_argument("--subpath", default="")
    p.add_argument("--min-kit", dest="min_kit", default="")
    p.add_argument("--directive", action="append", dest="directives", default=[])
    p.set_defaults(func=cmd_lock_add)

    p = sub.add_parser("lock-remove")
    p.add_argument("lockfile")
    p.add_argument("pack_id")
    p.set_defaults(func=cmd_lock_remove)

    p = sub.add_parser("lock-list")
    p.add_argument("lockfile")
    p.set_defaults(func=cmd_lock_list)

    p = sub.add_parser("catalog-search")
    p.add_argument("catalog")
    p.add_argument("query", nargs="?", default="")
    p.set_defaults(func=cmd_catalog_search)

    args = parser.parse_args(argv)
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
