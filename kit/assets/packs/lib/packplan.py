#!/usr/bin/env python3
"""Pure plan computation for `governance pack {add,update,remove}` (issue #172).

`pack-plan add|update|remove …` resolves everything PACK_VERBS.md's flows need
before any file is written, as one side-effect-free computation printed as JSON
— the half consumers previously hand-assembled from prose (fetch → validate →
capability-check → per-directive diff → classify add/update/remove). The only
network it does is `packverb fetch`, which populates the SHA-addressed immutable
cache (never the working tree); that is the resolution step, analogous to a
terraform refresh, and is what lets the plan show the exact `check.sh` a pack
would start running before the operator approves it.

`pack-apply` (engine in packapply.py, dispatched from packverb.py) recomputes
the plan and executes it. With `--diff` the plan also carries the per-directive
folder diff PACK_VERBS.md's diff-before-exec step shows the user.

Run via `packverb.py pack-plan {add,update,remove} <root> [target] [--diff]`
(lifecycle_cli.py registers the subcommand).
"""

from __future__ import annotations

import argparse
import difflib
import json
from pathlib import Path
from typing import Any

from packctl import (
    directives_for_pack,
    load_yaml,
    pack_manifest,
    scalar,
    validate_pack_dir,
)
from packverb import capability_violations, fetch_ref, load_lockfile, parse_ref

# governance-kit/core is the bedrock of every setup; `pack remove` refuses it
# wholesale (individual directives go through `governance directive remove`).
CORE_PACK_ID = "governance-kit/core"

# Author-side / install-asset folders never copied into a consumer repo, so
# never part of an installed-vs-source directory diff.
_SKIP_DIR_ENTRIES = ("evals", "install-assets")


def _list_directive_files(directive_dir: Path) -> dict[str, Path]:
    """Relative-path → file map for a directive folder, minus author-side dirs."""
    out: dict[str, Path] = {}
    if not directive_dir.is_dir():
        return out
    for path in sorted(directive_dir.rglob("*")):
        if not path.is_file():
            continue
        rel_parts = path.relative_to(directive_dir).parts
        if rel_parts and rel_parts[0] in _SKIP_DIR_ENTRIES:
            continue
        out["/".join(rel_parts)] = path
    return out


def _dir_diff(installed_dir: Path, source_dir: Path, dest_rel: str) -> str:
    """Concatenated per-file unified diff from the installed folder to the source.

    Mirrors `diff -ruN <installed> <fetched>` over the files that actually ship
    (evals/ and install-assets/ excluded). New and deleted files render as full
    additions/removals — the same shape the agent used to produce by hand.
    """
    old_files = _list_directive_files(installed_dir)
    new_files = _list_directive_files(source_dir)
    chunks: list[str] = []
    for rel in sorted(set(old_files) | set(new_files)):
        old = old_files[rel].read_text(errors="replace").splitlines(keepends=True) if rel in old_files else []
        new = new_files[rel].read_text(errors="replace").splitlines(keepends=True) if rel in new_files else []
        if old == new:
            continue
        chunks.append("".join(difflib.unified_diff(
            old, new,
            fromfile=f"a/{dest_rel}/{rel}", tofile=f"b/{dest_rel}/{rel}",
        )))
    return "".join(chunks)


def _manifest_context(root: Path) -> dict[str, str]:
    manifest_path = root / ".governance" / "install.yaml"
    manifest = load_yaml(manifest_path) if manifest_path.is_file() else {}
    return {
        "hook_strategy": scalar(manifest.get("hook_strategy")) or "githooks",
        "tests_dir": scalar(manifest.get("tests_dir")) or ".governance",
    }


def _resolve_pack(root: Path, ref: str, with_diff: bool, from_sha: str | None) -> dict[str, Any]:
    """Fetch + validate + capability-check + classify one pack from a ref."""
    fetched = fetch_ref(ref)
    pack_dir = Path(fetched["pack_dir"])
    pack_id = fetched["id"]
    sha = fetched["sha"]
    parsed = parse_ref(ref)
    manifest = pack_manifest(pack_dir)

    entry: dict[str, Any] = {
        "id": pack_id,
        "action": "skip" if (from_sha and from_sha == sha) else ("update" if from_sha else "add"),
        "source": "gh",
        "version": scalar(manifest.get("version")),
        "ref": ref,
        "sha": sha,
        "from_sha": from_sha,
        "subpath": parsed["subpath"],
        "min_governance_kit": scalar(manifest.get("min_governance_kit")),
        "pack_dir": str(pack_dir),
        "validation_errors": validate_pack_dir(pack_dir),
        "capability_violations": [],
        "directives": [],
    }

    directives: list[dict[str, Any]] = []
    for did in directives_for_pack(pack_dir):
        src = pack_dir / "directives" / did
        entry["capability_violations"].extend(capability_violations(src))
        dest_rel = f".governance/packs/{pack_id}/directives/{did}"
        installed = root / dest_rel
        d: dict[str, Any] = {
            "id": did,
            "status": "update" if installed.is_dir() else "add",
            "dest": dest_rel,
        }
        # Surface per-directive config drift so the operator can be told to
        # reconcile their user overlay by hand — `pack update` refreshes the
        # pack-owned `defaults.conf` (the live defaults *and* their docs, issue
        # #210) in the installed tree but never rewrites the user-owned
        # `.governance/conf/<id>.conf`. A change to defaults.conf shifts what the
        # directive enforces by default, so it's the signal worth surfacing.
        if d["status"] == "update":
            def _bytes(p: Path) -> bytes:
                return p.read_bytes() if p.is_file() else b""
            d["config_drift"] = _bytes(installed / "defaults.conf") != _bytes(src / "defaults.conf")
            user_conf = f".governance/conf/{pack_id}/{did}.conf"
            d["user_conf"] = user_conf
            d["user_conf_present"] = (root / user_conf).is_file()
        if with_diff:
            d["diff"] = _dir_diff(installed, src, dest_rel)
        directives.append(d)
    entry["directives"] = directives
    return entry


def _plan_add(root: Path, ref: str, with_diff: bool) -> list[dict[str, Any]]:
    return [_resolve_pack(root, ref, with_diff, from_sha=None)]


def _plan_update(root: Path, pack_id: str | None, with_diff: bool) -> list[dict[str, Any]]:
    lock = load_lockfile(root / ".governance" / "packs.lock")
    out: list[dict[str, Any]] = []
    for pack in lock["packs"]:
        pid = scalar(pack.get("id"))
        if pack_id and pid != pack_id:
            continue
        if scalar(pack.get("source")) != "gh":
            out.append({"id": pid, "action": "skip", "source": "local",
                        "reason": "repo-local pack has no upstream to re-pin", "directives": []})
            continue
        entry = _resolve_pack(root, scalar(pack.get("ref")), with_diff, from_sha=scalar(pack.get("sha")))
        out.append(entry)
    return out


def _plan_remove(root: Path, pack_id: str) -> list[dict[str, Any]]:
    lock = load_lockfile(root / ".governance" / "packs.lock")
    pack = next((p for p in lock["packs"] if scalar(p.get("id")) == pack_id), None)
    if pack is None:
        return [{"id": pack_id, "action": "absent",
                 "reason": "pack id not present in .governance/packs.lock", "directives": []}]

    constitution = root / "CONSTITUTION.md"
    const_text = constitution.read_text() if constitution.is_file() else ""
    # Local import keeps docsurgery out of the import path for add/update.
    from docsurgery import find_subsection

    directive_ids = sorted(str(d) for d in (pack.get("directives") or []))
    directives = []
    subsections = []
    for did in directive_ids:
        directives.append({"id": did, "dest": f".governance/packs/{pack_id}/directives/{did}"})
        if const_text and find_subsection(const_text, did) is not None:
            subsections.append(did)

    # User conf files to delete with the pack — only those present on disk.
    conf_files = [f".governance/conf/{pack_id}/{did}.conf" for did in directive_ids
                  if (root / ".governance" / "conf" / pack_id / f"{did}.conf").is_file()]

    return [{
        "id": pack_id,
        "action": "remove",
        "source": scalar(pack.get("source")),
        "is_core": pack_id == CORE_PACK_ID,
        "pack_root": f".governance/packs/{pack_id}",
        "directive_dirs": [f".governance/packs/{pack_id}/directives/{did}" for did in directive_ids],
        "directives": directives,
        "constitution_subsections": subsections,
        "conf_files": conf_files,
    }]


def compute_pack_plan(root: Path, mode: str, target: str | None, with_diff: bool) -> dict[str, Any]:
    """The full `pack-plan` resolution as a (near-)pure computation.

    Shared by `pack-plan` (prints it) and `pack-apply` (recomputes at execution
    time). `add`/`update` populate the cache via fetch; `remove` is fully
    offline, reading only the lockfile and CONSTITUTION.md.
    """
    if mode == "add":
        packs = _plan_add(root, target or "", with_diff)
    elif mode == "update":
        packs = _plan_update(root, target, with_diff)
    elif mode == "remove":
        packs = _plan_remove(root, target or "")
    else:
        raise ValueError(f"unknown pack-plan mode: {mode!r}")

    ctx = _manifest_context(root)
    return {
        "mode": mode,
        "lockfile": ".governance/packs.lock",
        "hook_strategy": ctx["hook_strategy"],
        "tests_dir": ctx["tests_dir"],
        "packs": packs,
    }


def cmd_pack_plan(args: argparse.Namespace) -> int:
    root = Path(args.root).resolve()
    try:
        plan = compute_pack_plan(root, args.mode, args.target, args.diff)
    except (ValueError, SystemExit) as exc:
        print(json.dumps({"error": str(exc)}, indent=2))
        return 1
    print(json.dumps(plan, indent=2))
    return 0
