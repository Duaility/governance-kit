#!/usr/bin/env python3
"""governance skill bootstrap — get a kit tree; never apply one.

The installer half of "the skill is an installer, the kit is the product"
(issues #194, #198). This is the ONLY code the published skill ships. It knows
how to:

  * `resolve`  — pick a published `kit/vX.Y.Z` tag (latest, or `--to`), fetch
    that tree into the shared cache, and report its paths;
  * `current`  — read the repo's recorded pin (`kit_ref` / `kit_sha` in
    `.governance/install.yaml`), locate that tree in the cache (fetching it
    once when absent), and report its paths.

Everything else — version gates, plan/apply engines, templates, flow docs —
lives in the kit tree this script fetches, and runs FROM that tree. When no
tree is reachable (offline and nothing cached) the answer is `result:
refused` with recovery guidance, never a partial fallback: the shim carries
nothing to fall back to.

Deliberately stdlib-only (no PyYAML, no kit imports) so `python3
bootstrap.py` works on a bare machine. The cache layout is the shared
contract with the kit's own engines (`packverb.cache_base` /
`kitresolve.cached_kit_path`):

    ${GOVERNANCE_KIT_HOME:-~/.governance/cache}/kits/<owner>__<repo>@<sha>/

`scripts/test-bootstrap.py` in the source repo locks the two sides together.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

DEFAULT_KIT_REPO = "duaility/governance-kit"
# Where the kit artifact lives inside the source repo for post-split releases.
# Pre-split tags (< the kit/ rename) keep their tree at `governance/`; repos
# pinned to such tags still resolve because `current` parses the subpath from
# the recorded ref rather than assuming this constant.
KIT_SUBPATH = "kit"

GH_REF_RE = re.compile(
    r"^gh:(?P<owner>[^/@]+)/(?P<repo>[^/@]+)(?:/(?P<subpath>[^@]+))?(?:@(?P<rev>.+))?$"
)
KIT_TAG_RE = re.compile(r"refs/tags/kit/v(\d+\.\d+\.\d+)(\^\{\})?$")


def cache_root() -> Path:
    override = os.environ.get("GOVERNANCE_KIT_HOME")
    base = Path(override) if override else Path.home() / ".governance" / "cache"
    return base / "kits"


def parse_ref(ref: str) -> dict:
    match = GH_REF_RE.match(ref)
    if not match:
        raise ValueError(f"unrecognized kit ref: {ref!r} (expected gh:owner/repo[/subpath][@rev])")
    return {
        "owner": match.group("owner"),
        "repo": match.group("repo"),
        "subpath": match.group("subpath") or "",
        "rev": match.group("rev") or "HEAD",
        "url": f"https://github.com/{match.group('owner')}/{match.group('repo')}.git",
    }


def kit_yaml_version(kit_dir: Path) -> str | None:
    """The `version:` scalar of `<kit_dir>/assets/kit.yaml`, or None."""
    kit_yaml = kit_dir / "assets" / "kit.yaml"
    if not kit_yaml.is_file():
        return None
    for line in kit_yaml.read_text().splitlines():
        m = re.match(r'^version:\s*"?([0-9][^"#\s]*)"?\s*(#.*)?$', line)
        if m:
            return m.group(1)
    return None


def tree_report(kit_dir: Path) -> dict:
    """The path fields every consumer of a resolved tree needs."""
    return {
        "version": kit_yaml_version(kit_dir),
        "kit_dir": str(kit_dir),
        "lib_dir": str(kit_dir / "assets" / "packs" / "lib"),
        "references_dir": str(kit_dir / "references"),
        "assets_dir": str(kit_dir / "assets"),
    }


def validate_kit_tree(kit_dir: Path) -> str | None:
    """None when `kit_dir` is a delegable kit tree, else the refusal reason.

    Structural, not version-policy: a tree the shim can hand over to must
    carry its own engine lib and flow docs. Pre-delegation kits (< 0.4.0) and
    pre-split subpaths fail here with a reason the caller surfaces verbatim.
    """
    if not (kit_dir / "assets" / "kit.yaml").is_file():
        return f"no assets/kit.yaml under {kit_dir} — not a kit tree (pre-split tags keep the kit at governance/, not kit/)"
    if not (kit_dir / "assets" / "packs" / "lib" / "kitverb.py").is_file():
        return f"kit at {kit_dir} ships no assets/packs/lib/kitverb.py — it predates delegated apply and cannot be driven by this installer"
    if not (kit_dir / "references").is_dir():
        return f"kit at {kit_dir} ships no references/ flow docs"
    return None


def list_published_versions(repo: str) -> tuple[list[str], str | None]:
    """(kit versions from `git ls-remote --tags`, error). Network read."""
    try:
        proc = subprocess.run(
            ["git", "ls-remote", "--tags", f"https://github.com/{repo}"],
            check=False, text=True, capture_output=True, timeout=20,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        return [], str(exc)
    if proc.returncode != 0:
        return [], proc.stderr.strip() or f"git ls-remote exited {proc.returncode}"
    versions = set()
    for line in proc.stdout.splitlines():
        m = KIT_TAG_RE.search(line)
        if m:
            versions.add(m.group(1))
    return sorted(versions, key=_version_tuple), None


def _version_tuple(v: str) -> tuple[int, ...]:
    return tuple(int(p) for p in v.split("."))


def fetch_ref(ref: str) -> dict:
    """Clone `ref` into the cache; return {sha, kit_dir, cache_dir}.

    Mirrors the kit's `clone_into_cache` contract: clone (or init+fetch when
    the rev is a 40-char sha) into a temp dir inside the cache root, resolve
    the concrete sha, move to `<owner>__<repo>@<sha>`. Idempotent on a repeat
    fetch of the same sha. Raises on network/validation failure — callers
    translate to a refusal.
    """
    parsed = parse_ref(ref)
    root = cache_root()
    root.mkdir(parents=True, exist_ok=True)
    rev = parsed["rev"]
    is_sha = bool(re.fullmatch(r"[0-9a-f]{40}", rev))

    with tempfile.TemporaryDirectory(prefix="gk-bootstrap-", dir=str(root)) as tmp:
        checkout = Path(tmp) / "checkout"
        if is_sha:
            checkout.mkdir(parents=True)
            run = lambda *a: subprocess.run(["git", "-C", str(checkout), *a], check=True, capture_output=True, text=True)
            run("init", "--quiet")
            run("remote", "add", "origin", parsed["url"])
            run("fetch", "--quiet", "--depth", "1", "origin", rev)
            run("checkout", "--quiet", "FETCH_HEAD")
            sha = rev
        else:
            cmd = ["git", "clone", "--quiet", "--depth", "1"]
            if rev != "HEAD":
                cmd += ["--branch", rev]
            subprocess.run([*cmd, parsed["url"], str(checkout)], check=True, capture_output=True, text=True)
            sha = subprocess.run(
                ["git", "-C", str(checkout), "rev-parse", "HEAD"],
                check=True, capture_output=True, text=True,
            ).stdout.strip()

        slug = f"{parsed['owner'].lower()}__{parsed['repo'].lower()}"
        cache_dir = root / f"{slug}@{sha}"
        kit_sub = checkout / parsed["subpath"] if parsed["subpath"] else checkout
        reason = validate_kit_tree(kit_sub)
        if reason:
            raise SystemExit(f"{ref}: {reason}")
        if not cache_dir.exists():
            shutil.rmtree(checkout / ".git", ignore_errors=True)
            shutil.move(str(checkout), str(cache_dir))

    kit_dir = cache_dir / parsed["subpath"] if parsed["subpath"] else cache_dir
    return {"sha": sha, "kit_dir": kit_dir, "cache_dir": str(cache_dir)}


def cached_tree(ref: str, sha: str) -> Path | None:
    """The cached kit dir for a (ref, sha) pin, or None. No network."""
    try:
        parsed = parse_ref(ref)
    except ValueError:
        return None
    cache_dir = cache_root() / f"{parsed['owner'].lower()}__{parsed['repo'].lower()}@{sha}"
    kit_dir = cache_dir / parsed["subpath"] if parsed["subpath"] else cache_dir
    return kit_dir if (kit_dir / "assets" / "kit.yaml").is_file() else None


def scan_cache_for_version(repo: str, version: str) -> tuple[Path, str] | None:
    """(kit_dir, sha) of a cached tree of `repo` at `version`, or None.

    The offline `--to` path: a version that was ever fetched on this machine
    is findable by content even when its sha isn't known up front.
    """
    slug_prefix = repo.lower().replace("/", "__") + "@"
    root = cache_root()
    if not root.is_dir():
        return None
    for entry in sorted(root.iterdir()):
        if not entry.name.startswith(slug_prefix) or not entry.is_dir():
            continue
        sha = entry.name.split("@", 1)[1]
        for sub in (KIT_SUBPATH, "governance", "."):
            kit_dir = (entry / sub).resolve() if sub != "." else entry
            if kit_yaml_version(kit_dir) == version and validate_kit_tree(kit_dir) is None:
                return kit_dir, sha
    return None


def read_pin(root: Path) -> tuple[str | None, str | None]:
    """(kit_ref, kit_sha) from `.governance/install.yaml`, line-parsed."""
    manifest = root / ".governance" / "install.yaml"
    if not manifest.is_file():
        return None, None
    ref = sha = None
    for line in manifest.read_text().splitlines():
        m = re.match(r'^(kit_ref|kit_sha):\s*"?([^"#\s]+)"?\s*(#.*)?$', line)
        if not m:
            continue
        if m.group(1) == "kit_ref":
            ref = m.group(2)
        else:
            sha = m.group(2)
    return ref, sha


def emit(report: dict) -> int:
    print(json.dumps(report, indent=2))
    return 0 if report["result"] == "ok" else 2


def refuse(report: dict, reason: str, recovery: str) -> int:
    report.update(result="refused", reason=reason, recovery=recovery)
    return emit(report)


def cmd_resolve(args: argparse.Namespace) -> int:
    """Fetch a published kit (latest tag, or --to X.Y.Z) and report its tree."""
    repo = (args.repo or DEFAULT_KIT_REPO).lower()
    report: dict = {"result": None, "provenance": None, "kit_ref": None, "kit_sha": None,
                    "assumptions": [], **{k: None for k in ("version", "kit_dir", "lib_dir", "references_dir", "assets_dir")}}

    target, resolve_error = args.to, None
    if not target and not args.offline:
        published, resolve_error = list_published_versions(repo)
        if published:
            target = published[-1]
    if not target:
        return refuse(
            report,
            "no target version: " + ("--offline was set" if args.offline else f"no published kit/vX.Y.Z tag reachable at {repo} ({resolve_error})"),
            "connect once so the latest release can be listed and fetched, or pass --to X.Y.Z for a version already in the cache",
        )

    ref = f"gh:{repo}/{KIT_SUBPATH}@kit/v{target}"
    report["kit_ref"] = ref
    if not args.offline:
        try:
            fetched = fetch_ref(ref)
            report.update(provenance="explicit" if args.to else "published-tag",
                          kit_sha=fetched["sha"], result="ok", **tree_report(fetched["kit_dir"]))
            return emit(report)
        except (SystemExit, subprocess.CalledProcessError, OSError) as exc:
            detail = exc.stderr.strip() if isinstance(exc, subprocess.CalledProcessError) and exc.stderr else str(exc)
            resolve_error = detail

    # Offline (or the fetch failed): a --to version may already be cached.
    cached = scan_cache_for_version(repo, target) if args.to else None
    if cached:
        kit_dir, sha = cached
        report["assumptions"].append(
            f"kit/v{target} served from the local cache; upstream was not consulted"
        )
        report.update(provenance="cache", kit_sha=sha, result="ok", **tree_report(kit_dir))
        return emit(report)

    return refuse(
        report,
        f"kit/v{target} could not be fetched and is not in the cache" + (f" ({resolve_error})" if resolve_error else ""),
        "connect once to fetch the release (it lands in the cache; later runs of the same version are network-free)",
    )


def cmd_current(args: argparse.Namespace) -> int:
    """Resolve the kit the repo already pins, for delegation. Writes nothing."""
    root = Path(args.root).resolve()
    kit_ref, kit_sha = read_pin(root)
    report: dict = {"result": None, "provenance": None, "kit_ref": kit_ref, "kit_sha": kit_sha,
                    "assumptions": [], **{k: None for k in ("version", "kit_dir", "lib_dir", "references_dir", "assets_dir")}}

    if not (kit_ref and kit_sha):
        return refuse(
            report,
            "no recorded kit pin (kit_ref/kit_sha) in .governance/install.yaml",
            "run `governance update` once (online) to record the pin; if governance was never installed here, run `governance install`",
        )

    cached = cached_tree(kit_ref, kit_sha)
    if cached is not None:
        report.update(provenance="cache", result="ok", **tree_report(cached))
        return emit(report)

    if args.offline:
        return refuse(
            report,
            f"pinned kit {kit_ref}@{kit_sha[:12]} is not in the cache and --offline was set",
            "re-run with network access; the fetch is cached, so every later run is network-free",
        )

    parsed = parse_ref(kit_ref)
    try:
        fetched = fetch_ref(f"gh:{parsed['owner']}/{parsed['repo']}" + (f"/{parsed['subpath']}" if parsed["subpath"] else "") + f"@{kit_sha}")
    except (SystemExit, subprocess.CalledProcessError, OSError, ValueError) as exc:
        detail = exc.stderr.strip() if isinstance(exc, subprocess.CalledProcessError) and exc.stderr else str(exc)
        return refuse(
            report,
            f"pinned kit {kit_ref}@{kit_sha[:12]} is not cached and could not be fetched ({detail})",
            "re-run with network access; the fetch is cached, so every later run is network-free",
        )
    report.update(provenance="fetch", result="ok", **tree_report(fetched["kit_dir"]))
    return emit(report)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="bootstrap.py", description=__doc__)
    sub = parser.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("resolve", help="fetch a published kit (latest tag or --to) and report its tree")
    p.add_argument("--to", metavar="X.Y.Z", help="exact published version instead of the latest tag")
    p.add_argument("--repo", help=f"owner/repo to resolve kit/v* tags from (default {DEFAULT_KIT_REPO})")
    p.add_argument("--offline", action="store_true", help="never touch the network (only a cached --to can succeed)")
    p.set_defaults(func=cmd_resolve)

    p = sub.add_parser("current", help="resolve the kit the repo pins in .governance/install.yaml")
    p.add_argument("root", help="repo root (the directory holding .governance/)")
    p.add_argument("--offline", action="store_true", help="never touch the network (cache hit or refuse)")
    p.set_defaults(func=cmd_current)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
