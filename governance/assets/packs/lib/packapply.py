#!/usr/bin/env python3
"""Execution half of `governance pack {add,update,remove}` — the `pack-apply`
engine (issue #172).

Companion to packplan.py (the pure plan) and packverb.py (the CLI surface +
fetch/lockfile/capability plumbing this engine composes). `cmd_pack_apply`
recomputes the plan at execution time (never trusts a stale one), enforces in
code the gates that used to be PACK_VERBS.md prose — refuse on validation or
capability violations, on a dirty working tree without `--force`, on removing
`governance-kit/core` wholesale, on a pack absent from the lockfile — then runs
the apply in one call:

  * **add / update** — copy each approved directive folder via install.sh
    `install_directive_folder` (+ `install_directive_assets`), record any seeded
    files in `install.yaml`'s `install_assets_seeded`, regenerate the hook
    dispatchers, and upsert the lockfile pin last (so a crash never leaves the
    lock claiming directives that aren't installed).
  * **remove** — delete each directive folder, strip its CONSTITUTION.md
    subsection via docsurgery, drop the now-empty pack root, regenerate hooks,
    and prune the lock entry first.

Per-directive `--decisions {<id>: skip}` holds individual directives back
(default: install/keep all approved). `--dry-run` resolves every action and
writes nothing. The operator keeps eliciting the decisions, showing the diffs,
and the commit. Prints a JSON report; exit 0 applied/up-to-date/dry-run, 2
refused, 1 error.
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

from applylib import (
    bash_lib,
    git_dirty,
    hook_digests,
    refuse,
    regenerate_hooks,
    smoke_test,
)
from packctl import KIT_VERSION
from packplan import compute_pack_plan
from packverb import load_lockfile, write_lockfile, _utc_now

_DIRECTIVE_DECISIONS = ("apply", "skip")


def _load_decisions(raw: str | None) -> dict[str, str]:
    """Per-directive overrides: {<directive-id>: apply|skip}. Default apply."""
    if not raw:
        return {}
    text = raw if raw.lstrip().startswith("{") else Path(raw).read_text()
    decisions = json.loads(text)
    if not isinstance(decisions, dict):
        raise ValueError("--decisions must be a JSON object of {directive-id: apply|skip}")
    for did, decision in decisions.items():
        if decision not in _DIRECTIVE_DECISIONS:
            raise ValueError(
                f"--decisions[{did!r}]: {decision!r} is not one of {', '.join(_DIRECTIVE_DECISIONS)}"
            )
    return decisions


def _install_asset_rels(pack_dir: Path, did: str) -> list[str]:
    assets = pack_dir / "directives" / did / "install-assets"
    if not assets.is_dir():
        return []
    return ["/".join(p.relative_to(assets).parts) for p in sorted(assets.rglob("*")) if p.is_file()]


def _append_install_assets_seeded(manifest_path: Path, rels: list[str]) -> None:
    """Append newly-seeded asset paths to install.yaml's `install_assets_seeded`,
    in place — the uninstall hard-mode ledger. Idempotent: existing entries are
    not duplicated. Handles both the empty (`[]`) and block-list YAML forms."""
    if not rels or not manifest_path.is_file():
        return
    lines = manifest_path.read_text().splitlines(keepends=True)
    key_i = next((i for i, ln in enumerate(lines) if ln.startswith("install_assets_seeded:")), None)
    existing: set[str] = set()
    if key_i is not None:
        for j in range(key_i + 1, len(lines)):
            stripped = lines[j].lstrip()
            if lines[j].startswith("  - ") or lines[j].startswith("- "):
                existing.add(stripped[2:].strip())
            elif stripped and not lines[j][0].isspace():
                break
    new = [r for r in rels if r not in existing]
    if not new:
        return
    block = "".join(f"  - {r}\n" for r in (*sorted(existing), *new))
    header = "install_assets_seeded:\n"
    if key_i is None:
        manifest_path.write_text("".join(lines) + header + block)
        return
    # Replace the key line + any existing list lines with the merged block.
    end = key_i + 1
    while end < len(lines) and (lines[end].startswith("  - ") or lines[end].startswith("- ")):
        end += 1
    lines[key_i:end] = [header + block]
    manifest_path.write_text("".join(lines))


def _lock_upsert(lockpath: Path, entry: dict[str, Any]) -> None:
    data = load_lockfile(lockpath)
    data["packs"] = [p for p in data["packs"] if p.get("id") != entry["id"]]
    data["packs"].append(entry)
    write_lockfile(lockpath, data)


def _lock_remove(lockpath: Path, pack_id: str) -> None:
    data = load_lockfile(lockpath)
    data["packs"] = [p for p in data["packs"] if p.get("id") != pack_id]
    write_lockfile(lockpath, data)


def _gate_add_update(plan: dict[str, Any], report: dict[str, Any]) -> int | None:
    for pack in plan["packs"]:
        if pack.get("validation_errors"):
            return refuse(report, f"{pack['id']}: pack validation failed: {'; '.join(pack['validation_errors'])}",
                          "fix the pack or pin a different ref")
        if pack.get("capability_violations"):
            return refuse(report, f"{pack['id']}: capability violations: {'; '.join(pack['capability_violations'])}",
                          "a directive's check.sh references paths outside its declared reads/writes globs")
    return None


def _apply_add_update(root: Path, plan: dict[str, Any], decisions: dict[str, str],
                      report: dict[str, Any], dry_run: bool) -> int:
    manifest_path = root / ".governance" / "install.yaml"

    # up-to-date no-op: every pack's SHA already matches (update mode).
    if plan["mode"] == "update" and all(p.get("action") in ("skip",) for p in plan["packs"]):
        report.update(result="up-to-date",
                      skipped=[p["id"] for p in plan["packs"]])
        print(json.dumps(report, indent=2))
        return 0

    for pack in plan["packs"]:
        if pack.get("action") == "skip":
            report["skipped"].append(pack["id"])
            continue
        pack_dir = Path(pack["pack_dir"])
        installed_dids: list[str] = []
        seeded: list[str] = []
        for d in pack["directives"]:
            did = d["id"]
            if decisions.get(did) == "skip":
                report["held_back"].append(did)
                continue
            installed_dids.append(did)
            report["added" if d["status"] == "add" else "updated"].append(d["dest"])
            seeded.extend(r for r in _install_asset_rels(pack_dir, did) if not (root / r).exists())
            if dry_run:
                continue
            res = bash_lib(
                'install_directive_folder "$1" "$2" "$3"; install_directive_assets "$1" "$2" "$3"',
                str(pack_dir), did, str(root))
            if res.returncode != 0:
                report.update(result="error",
                              reason=f"install of {pack['id']}/{did} failed: {res.stderr.strip()}",
                              recovery="`git checkout -- .` and `git clean -fd .governance/packs` to restore, then re-run")
                print(json.dumps(report, indent=2))
                return 1
        if not installed_dids:
            continue
        if not dry_run:
            _append_install_assets_seeded(manifest_path, sorted(set(seeded)))
        report["seeded_assets"].extend(sorted(set(seeded)))
        lock_entry = {
            "id": pack["id"], "version": pack["version"], "source": "gh",
            "ref": pack["ref"], "sha": pack["sha"], "subpath": pack.get("subpath", ""),
            "min_governance_kit": pack.get("min_governance_kit", ""),
            "installed_at": _utc_now(), "directives": sorted(installed_dids),
        }
        if not dry_run:
            _lock_upsert(root / ".governance" / "packs.lock", lock_entry)
        report["lock"].append({"id": pack["id"], "sha": pack["sha"], "directives": sorted(installed_dids)})

    return _finish(root, plan, report, dry_run)


def _apply_remove(root: Path, plan: dict[str, Any], report: dict[str, Any], dry_run: bool) -> int:
    from docsurgery import strip_directive_subsection

    pack = plan["packs"][0]
    if pack.get("action") == "absent":
        return refuse(report, pack.get("reason", "pack not in lockfile"),
                      "run `governance pack list` to see installed packs")
    if pack.get("is_core"):
        return refuse(report, "governance-kit/core is the bedrock pack and is never removed wholesale",
                      "remove individual core directives with `governance directive remove <id>`")

    constitution = root / "CONSTITUTION.md"
    for dest in pack["directive_dirs"]:
        report["removed"].append(dest)
        if not dry_run:
            shutil.rmtree(root / dest, ignore_errors=True)
    for did in pack["constitution_subsections"]:
        report["constitution_stripped"].append(did)
        if not dry_run and constitution.is_file():
            new_text, removed = strip_directive_subsection(constitution.read_text(), did)
            if removed:
                constitution.write_text(new_text)
    # Drop the now-empty pack root (<owner>/<name>) and a childless <owner>/.
    pack_root = root / pack["pack_root"]
    if not dry_run:
        for d in (pack_root / "directives", pack_root, pack_root.parent):
            if d.is_dir() and not any(d.iterdir()):
                d.rmdir()
        _lock_remove(root / ".governance" / "packs.lock", pack["id"])
    report["lock"].append({"id": pack["id"], "removed": True})
    return _finish(root, plan, report, dry_run)


def _finish(root: Path, plan: dict[str, Any], report: dict[str, Any], dry_run: bool) -> int:
    strategy, tests_dir = plan["hook_strategy"], plan["tests_dir"]
    if dry_run:
        report.update(result="dry-run", hook_dispatcher="would-regenerate")
        print(json.dumps(report, indent=2))
        return 0
    before = hook_digests(root, strategy)
    hooks = regenerate_hooks(root, strategy, KIT_VERSION)
    if hooks.returncode != 0:
        report.update(result="error", hook_dispatcher="failed",
                      reason=f"hook regeneration failed: {hooks.stderr.strip()}",
                      recovery="resolve the hook collision, `git checkout -- .` to restore, re-run")
        print(json.dumps(report, indent=2))
        return 1
    report["hook_dispatcher"] = "regenerated" if hook_digests(root, strategy) != before else "unchanged"
    report["smoke_test"] = smoke_test(root, tests_dir)
    report["result"] = "applied"
    print(json.dumps(report, indent=2))
    return 0


def cmd_pack_apply(args: argparse.Namespace) -> int:
    root = Path(args.root).resolve()
    report: dict[str, Any] = {
        "result": None, "mode": args.mode, "target": args.target,
        "added": [], "updated": [], "removed": [], "skipped": [], "held_back": [],
        "constitution_stripped": [], "seeded_assets": [], "lock": [],
        "hook_dispatcher": "unchanged", "smoke_test": None, "assumptions": [],
    }
    try:
        decisions = _load_decisions(args.decisions)
    except (ValueError, OSError, json.JSONDecodeError) as exc:
        return refuse(report, f"bad --decisions: {exc}", "fix the decisions JSON and re-run")

    try:
        plan = compute_pack_plan(root, args.mode, args.target, with_diff=False)
    except (ValueError, SystemExit, subprocess.CalledProcessError) as exc:
        return refuse(report, f"plan failed: {exc}", "check the ref/pack-id and network access")

    if args.mode in ("add", "update"):
        gated = _gate_add_update(plan, report)
        if gated is not None:
            return gated

    try:
        dirty = git_dirty(root)
    except (OSError, subprocess.CalledProcessError) as exc:
        return refuse(report, f"git status failed: {exc}", "run from a git repository")
    if dirty and not args.force:
        return refuse(report, "working tree has uncommitted changes", "commit or stash, or re-run with --force")
    if dirty:
        report["assumptions"].append("--force: applied over a dirty working tree")

    if args.mode == "remove":
        return _apply_remove(root, plan, report, args.dry_run)
    return _apply_add_update(root, plan, decisions, report, args.dry_run)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("pack-apply")
    p.add_argument("mode", choices=["add", "update", "remove"])
    p.add_argument("root")
    p.add_argument("target", nargs="?", default=None)
    p.add_argument("--decisions", default=None)
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--force", action="store_true")
    p.set_defaults(func=cmd_pack_apply)
    args = parser.parse_args(argv)
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
