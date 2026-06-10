#!/usr/bin/env python3
"""Pure plan computation for `governance reset` (issue #172).

`reset-plan {--directive <id> | --pack <id> | --all} <root> [--diff]` resolves
which pack-sourced directives are in scope, locates each one's **pinned**
pristine source (the SHA in `.governance/packs.lock`, re-fetched into the cache
if missing — never upstream HEAD; that is `pack update`'s job), classifies it
`restore` / `skip` (byte-identical to pinned) / `drop` (hand-authored, only
under `--drop-handauthored`), and — with `--diff` — emits the per-directive
`installed → pristine` folder diff. It writes nothing to the working tree.

`reset-apply` (engine in resetapply.py, dispatched from packverb.py) recomputes
this and executes the restore. The operator keeps the diff-before-exec `yes` and
the commit.

Run via `packverb.py reset-plan <scope> <root> [target] [--diff]`
(lifecycle_cli.py registers the subcommand).
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from packctl import scalar
from packplan import _dir_diff, _manifest_context
from packverb import fetch_ref, load_lockfile, parse_ref


def _pinned_ref(entry: dict[str, Any]) -> str:
    """Build a SHA-pinned ref `gh:owner/repo[/subpath]@<sha>` from a lock entry."""
    parsed = parse_ref(scalar(entry.get("ref")))
    base = f"gh:{parsed['owner']}/{parsed['repo']}"
    if parsed["subpath"]:
        base += f"/{parsed['subpath']}"
    return f"{base}@{scalar(entry.get('sha'))}"


def _resolve_directive(root: Path, pack: dict[str, Any], did: str, with_diff: bool) -> dict[str, Any]:
    """Fetch the pinned source for one directive and classify restore/skip."""
    pack_id = scalar(pack.get("id"))
    fetched = fetch_ref(_pinned_ref(pack))
    source = Path(fetched["pack_dir"]) / "directives" / did
    dest_rel = f".governance/packs/{pack_id}/directives/{did}"
    installed = root / dest_rel
    diff = _dir_diff(installed, source, dest_rel)
    entry: dict[str, Any] = {
        "id": did,
        "pack_id": pack_id,
        "kind": "skip" if (installed.is_dir() and not diff) else "restore",
        "source_dir": str(source),
        "dest": dest_rel,
        "ref": scalar(pack.get("ref")),
        "sha": scalar(pack.get("sha")),
        "subsection_source": str(source / "constitution.md"),
    }
    if with_diff:
        entry["diff"] = diff
    return entry


def compute_reset_plan(root: Path, scope: str, target: str | None,
                       drop_handauthored: bool, with_diff: bool) -> dict[str, Any]:
    lock_path = root / ".governance" / "packs.lock"
    if not lock_path.is_file():
        return {"scope": scope, "lockfile_present": False, "directives": [],
                "preserved_handauthored": [], "errors": ["lockfile missing"]}

    lock = load_lockfile(lock_path)
    by_id = {scalar(p.get("id")): p for p in lock["packs"]}
    gh_packs = {pid: p for pid, p in by_id.items() if scalar(p.get("source")) == "gh"}
    local_packs = {pid: p for pid, p in by_id.items() if scalar(p.get("source")) == "local"}
    handauthored = sorted(
        did for p in local_packs.values() for did in (p.get("directives") or []))

    errors: list[str] = []
    in_scope: list[tuple[dict[str, Any], str]] = []  # (pack entry, directive id)

    if scope == "directive":
        owner_pack = next((p for p in gh_packs.values()
                           if target in (p.get("directives") or [])), None)
        if owner_pack is None:
            errors.append(f"directive {target!r} is not in any source: gh pack in the lockfile")
        else:
            in_scope.append((owner_pack, target))
    elif scope == "pack":
        if target not in gh_packs:
            errors.append(f"pack {target!r} is not a source: gh pack in the lockfile")
        else:
            in_scope.extend((gh_packs[target], did) for did in sorted(gh_packs[target].get("directives") or []))
    elif scope == "all":
        for p in gh_packs.values():
            in_scope.extend((p, did) for did in sorted(p.get("directives") or []))
    else:
        errors.append(f"unknown scope {scope!r}")

    directives: list[dict[str, Any]] = []
    if not errors:
        for pack, did in in_scope:
            directives.append(_resolve_directive(root, pack, did, with_diff))
        if scope == "all" and drop_handauthored:
            for pid, p in local_packs.items():
                for did in sorted(p.get("directives") or []):
                    directives.append({
                        "id": did, "pack_id": pid, "kind": "drop",
                        "dest": f".governance/packs/{pid}/directives/{did}",
                    })

    ctx = _manifest_context(root)
    preserved = [] if (scope == "all" and drop_handauthored) else handauthored
    return {
        "scope": scope,
        "target": target,
        "lockfile_present": True,
        "drop_handauthored": drop_handauthored,
        "hook_strategy": ctx["hook_strategy"],
        "tests_dir": ctx["tests_dir"],
        "directives": directives,
        "preserved_handauthored": preserved,
        "errors": errors,
    }


def cmd_reset_plan(args: argparse.Namespace) -> int:
    root = Path(args.root).resolve()
    try:
        plan = compute_reset_plan(root, args.scope, args.target,
                                  args.drop_handauthored, args.diff)
    except (ValueError, SystemExit) as exc:
        print(json.dumps({"error": str(exc)}, indent=2))
        return 1
    print(json.dumps(plan, indent=2))
    return 0
