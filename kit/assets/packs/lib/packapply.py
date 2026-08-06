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
    files in `install.yaml`'s `install_assets_seeded`, seed each freshly-added
    configurable directive's overlay from the generic conf stub (never on
    update — user-owned conf is untouchable), upsert each installed directive's
    CONSTITUTION.md subsection (insert on add, replace on update — the symmetric
    counterpart to remove's strip, keeping the GDD invariant that every directive
    has a constitution entry), regenerate the hook dispatchers, and upsert
    the lockfile pin last (so a crash never leaves the lock claiming directives
    that aren't installed).
  * **remove** — delete each directive folder and its user conf, strip its
    CONSTITUTION.md subsection via docsurgery, drop the now-empty pack root,
    regenerate hooks, and prune the lock entry first.

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
from pathlib import Path
from typing import Any

from applylib import (
    append_install_assets_seeded,
    bash_lib,
    dirty_gate,
    load_decisions,
    refuse,
    regen_hooks_step,
    smoke_test,
)
import digestlib
import kityaml
from packctl import KIT_VERSION
from packplan import compute_pack_plan
from packverb import load_lockfile, write_lockfile, _utc_now

# Per-directive overrides: {<directive-id>: apply|skip}. Default apply.
_DIRECTIVE_DECISIONS = ("apply", "skip")


def _install_asset_rels(pack_dir: Path, did: str) -> list[str]:
    assets = pack_dir / "directives" / did / "install-assets"
    if not assets.is_dir():
        return []
    return ["/".join(p.relative_to(assets).parts) for p in sorted(assets.rglob("*")) if p.is_file()]


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
    from docsurgery import upsert_directive_subsection

    manifest_path = root / ".governance" / "install.yaml"
    # (directive-id, constitution.md text) for every directive installed this run,
    # upserted into CONSTITUTION.md after the loop so the live rulebook keeps an
    # entry for every directive that gained a test — the GDD invariant.
    constitution_upserts: list[tuple[str, str]] = []

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
            # Per-directive user conf is seeded only on a fresh add — never on
            # update, where an existing `.governance/conf/<id>.conf` is
            # user-owned and a deleted one must not be resurrected.
            # seed_directive_conf is augment-only as a second guard.
            # Every self-contained config registry gets one generic overlay.
            conf_manifest = pack_dir / "directives" / did / "directive.yaml"
            conf_dest = root / ".governance" / "conf" / pack["id"] / f"{did}.conf"
            manifest_data = kityaml.load(conf_manifest) if conf_manifest.is_file() else {}
            if d["status"] == "add" and manifest_data.get("config") and not conf_dest.exists():
                report["conf_seeded"].append(f".governance/conf/{pack['id']}/{did}.conf")
            # Collect the directive's constitution subsection (read from the source
            # pack, as init does) for the CONSTITUTION.md upsert after the loop —
            # in both modes, so dry-run can report it.
            sub = pack_dir / "directives" / did / "constitution.md"
            if sub.is_file():
                constitution_upserts.append((pack["id"], did, sub.read_text()))
            if dry_run:
                continue
            cmd = 'install_directive_folder "$1" "$2" "$3"; install_directive_assets "$1" "$2" "$3"'
            if d["status"] == "add":
                cmd += '; seed_directive_conf "$1" "$2" "$3"'
            res = bash_lib(cmd, str(pack_dir), did, str(root))
            if res.returncode != 0:
                report.update(result="error",
                              reason=f"install of {pack['id']}/{did} failed: {res.stderr.strip()}",
                              recovery="`git checkout -- .` and `git clean -fd .governance/packs` to restore, then re-run")
                print(json.dumps(report, indent=2))
                return 1
        if not installed_dids:
            continue
        if not dry_run:
            append_install_assets_seeded(manifest_path, sorted(set(seeded)))
        report["seeded_assets"].extend(sorted(set(seeded)))
        lock_entry = {
            "id": pack["id"], "version": pack["version"], "source": "gh",
            "ref": pack["ref"], "sha": pack["sha"], "subpath": pack.get("subpath", ""),
            "min_governance_kit": pack.get("min_governance_kit", ""),
            "installed_at": _utc_now(), "directives": sorted(installed_dids),
        }
        if not dry_run:
            # Record a per-directive content digest of the just-materialized
            # folders so `managed-tree-integrity` can verify the vendored tree
            # offline (issue #253).
            lock_entry["digest"] = digestlib.directive_digests(
                root / ".governance" / "packs" / pack["id"], installed_dids)
            _lock_upsert(root / ".governance" / "packs.lock", lock_entry)
        report["lock"].append({"id": pack["id"], "sha": pack["sha"], "directives": sorted(installed_dids)})

    # No scheduled-lane workflow is seeded here (unlike the retired sweep
    # lane, which vendored its workflow the moment a live-sweep directive was
    # installed). A schedule lane is a consumer-defined artifact — created
    # explicitly via `governance schedule` (packverb.py schedule-apply), never
    # implied by which directives this pack add/update happened to install.

    # CONSTITUTION.md: upsert each installed directive's subsection so the live
    # rulebook gains (add) or refreshes (update) an entry for every directive that
    # gained a test — the GDD invariant (every directive ↔ a constitution entry).
    # init assembles these at bootstrap and `pack remove` strips them; this keeps
    # add/update symmetric. The upsert homes each subsection under its pack's
    # `## <owner>/<pack>` header (creating it if absent, relocating a stray copy),
    # matching init's pack-grouped placement.
    constitution = root / "CONSTITUTION.md"
    if constitution_upserts and constitution.is_file():
        text = constitution.read_text()
        for pack_id, did, subsection in constitution_upserts:
            text, _action = upsert_directive_subsection(text, did, subsection, pack_id)
            report["constitution_upserted"].append(did)
        if not dry_run:
            constitution.write_text(text)

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
    # Drop each removed directive's user conf — the pack is leaving, so its
    # pack-qualified `.governance/conf/<owner>/<pack>/<id>.conf` has no owner.
    # The plan lists only those that currently exist on disk.
    conf_dir = root / ".governance" / "conf"
    for conf_rel in pack.get("conf_files", []):
        report["removed"].append(conf_rel)
        if not dry_run:
            target = root / conf_rel
            target.unlink(missing_ok=True)
            # Prune now-empty pack-qualified parent dirs up to .governance/conf.
            parent = target.parent
            while parent != conf_dir and parent.is_dir() and not any(parent.iterdir()):
                parent.rmdir()
                parent = parent.parent
    if not dry_run and conf_dir.is_dir() and not any(conf_dir.iterdir()):
        conf_dir.rmdir()
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
    hooks_rc = regen_hooks_step(
        root, strategy, KIT_VERSION, report,
        recovery="resolve the hook collision, `git checkout -- .` to restore, re-run")
    if hooks_rc is not None:
        return hooks_rc
    # Re-stamp the kit-runtime managed-file digests now that hooks (a managed
    # file class) were regenerated, so `managed-tree-integrity` stays accurate
    # after a pack add/update/remove (issue #253).
    manifest = root / ".governance" / "install.yaml"
    if manifest.is_file():
        digestlib.write_managed_digests_block(manifest, digestlib.managed_digests(root))
    report["smoke_test"] = smoke_test(root, tests_dir)
    report["result"] = "applied"
    print(json.dumps(report, indent=2))
    return 0


def cmd_pack_apply(args: argparse.Namespace) -> int:
    root = Path(args.root).resolve()
    report: dict[str, Any] = {
        "result": None, "mode": args.mode, "target": args.target,
        "added": [], "updated": [], "removed": [], "skipped": [], "held_back": [],
        "constitution_stripped": [], "constitution_upserted": [], "seeded_assets": [], "conf_seeded": [], "lock": [],
        "hook_dispatcher": "unchanged", "smoke_test": None, "assumptions": [],
    }
    try:
        decisions = load_decisions(args.decisions, _DIRECTIVE_DECISIONS)
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

    gated = dirty_gate(root, args.force, report)
    if gated is not None:
        return gated

    if args.mode == "remove":
        return _apply_remove(root, plan, report, args.dry_run)
    return _apply_add_update(root, plan, decisions, report, args.dry_run)
