#!/usr/bin/env python3
"""Working-tree resolver for `packverb fetch`.

When a pack ref points at the very repo we're currently inside (origin URL
matches), `resolve_from_working_tree` short-circuits the network clone:
the pack subtree is read from the live working tree and copied into the
shared cache, mirroring the shape `fetch_ref` produces from a real clone.

Rationale: dogfood and inner-loop dev. A monorepo that owns a pack also
consumes it (e.g. governance-kit hosting `packs/core/` and consuming it
via `gh:duaility/governance-kit/packs/core`). Forcing every edit through
commit + tag + bump just to re-fetch is hostile; reading working tree
makes the loop instant. Uncommitted edits are reflected by design.
"""

from __future__ import annotations

import re
import shutil
import subprocess
from pathlib import Path


def origin_matches_target(origin_url: str, owner: str, repo: str) -> bool:
    """True when `origin_url` points at github.com:<owner>/<repo>(.git)?.

    Accepts both https (`https://github.com/o/r.git`) and ssh
    (`git@github.com:o/r.git`) shapes. GitHub treats owner/repo as
    case-insensitive, so the comparison is too. The leading `/` or `:`
    anchors the path-segment boundary, so substring matches like
    `xacme/repo` against owner `acme` correctly fail.
    """
    cleaned = origin_url.strip().rstrip("/").lower()
    if cleaned.endswith(".git"):
        cleaned = cleaned[:-4]
    target = f"{owner}/{repo}".lower()
    return cleaned.endswith(f"/{target}") or cleaned.endswith(f":{target}")


def resolve_from_working_tree(
    parsed: dict[str, str],
    cache_root_path: Path,
    *,
    slugify: callable,
    pack_id_re: re.Pattern,
    read_pack_id: callable,
) -> dict[str, str] | None:
    """Short-circuit `fetch_ref` when `parsed` points at the repo we're inside.

    Walks up from cwd to find a git toplevel, checks `origin` against the
    parsed owner/repo, and — on a match — copies the pack subtree into the
    same cache shape that a real clone would produce. The SHA pin is the
    working tree's HEAD; uncommitted edits are reflected in the cached copy
    (intentional — this is the dogfood / inner-loop dev path).

    Returns None when we are not in a git repo, the origin does not match,
    the subpath does not contain a pack.yaml, or any git invocation fails.
    Callers fall through to the network clone in that case.

    The `slugify`, `pack_id_re`, and `read_pack_id` injections keep this
    module free of import cycles with `packverb.py` and `packctl.py`.
    """
    try:
        toplevel = subprocess.check_output(
            ["git", "rev-parse", "--show-toplevel"],
            stderr=subprocess.DEVNULL,
            text=True,
        ).strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None
    root_dir = Path(toplevel)
    if not root_dir.is_dir():
        return None

    try:
        origin = subprocess.check_output(
            ["git", "-C", str(root_dir), "remote", "get-url", "origin"],
            stderr=subprocess.DEVNULL,
            text=True,
        ).strip()
    except subprocess.CalledProcessError:
        return None
    if not origin_matches_target(origin, parsed["owner"], parsed["repo"]):
        return None

    pack_sub = root_dir / parsed["subpath"] if parsed["subpath"] else root_dir
    if not (pack_sub / "pack.yaml").is_file():
        return None

    try:
        sha = subprocess.check_output(
            ["git", "-C", str(root_dir), "rev-parse", "HEAD"],
            stderr=subprocess.DEVNULL,
            text=True,
        ).strip()
    except subprocess.CalledProcessError:
        return None
    if not re.fullmatch(r"[0-9a-f]{40}", sha):
        return None

    pack_id = read_pack_id(pack_sub)
    if not pack_id or not pack_id_re.match(pack_id):
        raise SystemExit(
            f"working-tree fetch: pack.yaml id {pack_id!r} is not a scoped id (pattern: author/slug)"
        )

    cache_root_path.mkdir(parents=True, exist_ok=True)
    final_root = cache_root_path / f"{slugify(pack_id)}@{sha}"
    pack_dir = final_root / parsed["subpath"] if parsed["subpath"] else final_root
    if final_root.exists():
        return {"sha": sha, "pack_dir": str(pack_dir), "cache_dir": str(final_root), "id": pack_id}

    # Mirror what the clone path leaves behind: the full repo tree minus .git.
    # Subpath consumers may reference sibling files (shared `lib/`, etc.), so
    # we copy the whole working tree, not just the pack subdir.
    shutil.copytree(
        root_dir,
        final_root,
        ignore=shutil.ignore_patterns(".git"),
        symlinks=False,
    )
    return {"sha": sha, "pack_dir": str(pack_dir), "cache_dir": str(final_root), "id": pack_id}
