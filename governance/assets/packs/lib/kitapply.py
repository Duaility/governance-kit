#!/usr/bin/env python3
"""Execution half of `governance kit update` — the `kit-apply` engine (issue #172).

Companion module to kitverb.py, which owns the CLI surface (`kitverb.py
kit-apply …`) and the pure plan computation this engine consumes. Split out
so each module stays a focused, reviewable unit.

`cmd_kit_apply` recomputes the plan at execution time (never trusts a stale
one), enforces the gates that used to live as UPDATE_FLOW.md prose — refuse
on `downgrade` / `no-recoverable-pin`, on `pre-tracking` without
`--record-pre-tracking`, on a reconstructed pin without `--owner`/`--repo`,
on a dirty working tree without `--force` — then executes the apply in one
call: writes each approved file pre-stamped, honors per-file `--decisions`
overrides (`keep` / `apply` / `overwrite-with-backup`; managed files default
to `apply`, unmanaged to `keep`), regenerates hook dispatchers through
hooks.sh `generate_hooks_for_strategy`, writes `kit_version` through to
`install.yaml` (in-place edit when the manifest exists; a fresh v3 manifest
via install.sh `write_installed_manifest` on the reconstructed path),
smoke-tests `run.sh`, and prints a JSON report. The operator (agent or
human) keeps what is genuinely theirs: eliciting the decisions, showing the
diffs, and the commit. `--dry-run` resolves every action and writes nothing.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
from pathlib import Path
from typing import Any

from applylib import (
    bash_lib,
    dirty_gate,
    load_decisions,
    refuse,
    regen_hooks_step,
    smoke_test,
)
from kitverb import KIT_ASSETS, KIT_VERSION, compute_plan, stamped_text

# Per-file decision verbs. Defaults when a dest is not named: `apply` for
# managed files (the marker is the regeneration contract), `keep` for
# unmanaged ones (no marker means user-owned, never silently overwritten).
_UNMANAGED_DECISIONS = ("keep", "apply", "overwrite-with-backup")


def _update_manifest_kit_version(manifest_path: Path, kit_version: str) -> None:
    """In-place `kit_version:` write-through that preserves every other field.

    Re-emitting the whole manifest via write_installed_manifest would need all
    of init's original flags (collisions, seeded assets, path_b) round-tripped;
    a line edit can't lose what it never touches. `generated_at` is left alone
    — it records the init, and rewriting it would make the apply wall-clock
    dependent.
    """
    lines = manifest_path.read_text().splitlines(keepends=True)
    new_line = f'kit_version: "{kit_version}"\n'
    for i, line in enumerate(lines):
        if re.match(r"kit_version\s*:", line):
            lines[i] = new_line
            break
    else:
        for i, line in enumerate(lines):
            if re.match(r"repo\s*:", line):
                lines.insert(i + 1, new_line)
                break
        else:
            lines.append(new_line)
    manifest_path.write_text("".join(lines))


def _write_fresh_manifest(root: Path, plan: dict[str, Any], owner: str, repo: str,
                          stamp_version: str) -> subprocess.CompletedProcess[str]:
    """v3 manifest for the reconstructed-pin path, via install.sh write_installed_manifest.

    Records only `kit_version`; the `kit_ref`/`kit_sha` pin is written separately
    by the orchestration's `kit-pin` step after a successful apply (issue #177),
    so the value-write is identical regardless of which target engine applied.
    """
    argv = [
        str(root),
        "--owner", owner, "--repo", repo,
        "--kit-version", stamp_version,
        "--hook-strategy", plan["hook_strategy"],
        "--tests-dir", plan["tests_dir"],
    ]
    enable_script = root / "scripts" / "enable-governance.sh"
    if enable_script.is_file():
        argv += ["--enable-governance-script", "scripts/enable-governance.sh"]
    return bash_lib('write_installed_manifest "$@"', *argv)


def cmd_kit_apply(args: argparse.Namespace) -> int:
    root = Path(args.root).resolve()
    # The forward/same case delegates to the fetched target's own engine, which
    # uses its own KIT_ASSETS/KIT_VERSION. The overrides below are exercised only
    # on a delegated downgrade: the local (newer) engine writing the fetched
    # older target's assets, stamped the older version, hooks from its lib.
    assets_root = Path(args.assets_root).resolve() if args.assets_root else KIT_ASSETS
    stamp_version = args.stamp_version or KIT_VERSION
    hooks_lib = Path(args.hooks_lib).resolve() if args.hooks_lib else None
    plan = compute_plan(root, assets_root=assets_root, stamp_version=stamp_version)

    report: dict[str, Any] = {
        "result": None,
        "from": plan["installed_kit_version"],
        "to": stamp_version,
        "delta": plan["delta"],
        "manifest_source": plan["manifest_source"],
        "updated": [], "added": [], "skipped": [], "kept": [],
        "unmanaged": [], "backups": [],
        "hook_dispatcher": "unchanged",
        "manifest": "unchanged",
        "smoke_test": None,
        "assumptions": [],
    }

    try:
        decisions = load_decisions(args.decisions, _UNMANAGED_DECISIONS)
    except (ValueError, OSError, json.JSONDecodeError) as exc:
        return refuse(report, f"bad --decisions: {exc}", "fix the decisions JSON and re-run")

    # --- delta gates (UPDATE_FLOW.md Step 2, now enforced in code) ---
    if plan["delta"] == "up-to-date":
        # Same-version no-op for the file apply. The shim still records the
        # kit_ref/kit_sha pin afterward via `kit-pin` (the backfill path for a
        # repo whose manifest predates the pin fields).
        report.update(result="up-to-date", skipped=[f["dest"] for f in plan["files"]])
        print(json.dumps(report, indent=2))
        return 0
    if plan["delta"] == "downgrade" and not args.allow_downgrade:
        return refuse(
            report,
            f"recorded kit_version {plan['installed_kit_version']} is newer than the target ({stamp_version})",
            "re-run with --allow-downgrade to roll the kit-runtime backward",
        )
    if plan["delta"] == "downgrade":
        report["assumptions"].append(
            f"--allow-downgrade: rolling the kit-runtime from {plan['installed_kit_version']} back to {stamp_version}"
        )
    if plan["delta"] == "no-recoverable-pin":
        return refuse(
            report,
            "no install.yaml and no kit-version= marker on any managed file",
            "governance uninstall, then governance init",
        )
    if plan["delta"] == "pre-tracking" and not args.record_pre_tracking:
        return refuse(
            report,
            "install.yaml carries no kit_version (pre-tracking install)",
            "re-run with --record-pre-tracking to record the current kit version",
        )

    if plan["manifest_source"] == "reconstructed":
        if not (args.owner and args.repo):
            return refuse(
                report,
                "install.yaml is missing (pin reconstructed from markers); a fresh manifest needs the repo identity",
                "re-run with --owner <github-owner> --repo <repo-name>",
            )
        report["assumptions"].append(
            "kit_version reconstructed from markers on: " + ", ".join(plan["reconstructed_from"])
        )
    if plan["delta"] == "pre-tracking":
        report["assumptions"].append("pre-tracking install: recording kit_version for the first time")

    gated = dirty_gate(root, args.force, report)
    if gated is not None:
        return gated

    # --- resolve per-file actions ---
    by_dest = {f["dest"]: f for f in plan["files"]}
    decidable = {d for d, f in by_dest.items() if f["status"] != "skip"}
    unknown = sorted(set(decisions) - decidable)
    if unknown:
        return refuse(
            report,
            f"--decisions names destinations with nothing to decide in the plan: {', '.join(unknown)}",
            "re-run kit-plan and rebuild the decisions object",
        )

    writes: list[tuple[dict[str, Any], bool]] = []  # (file entry, backup?)
    for entry in plan["files"]:
        status = entry["status"]
        if status == "skip":
            report["skipped"].append(entry["dest"])
            continue
        # Managed files default to apply (the marker is the regeneration
        # contract); unmanaged ones default to keep (user-owned).
        decision = decisions.get(entry["dest"], "keep" if status == "unmanaged" else "apply")
        if status == "unmanaged":
            report["unmanaged"].append({"dest": entry["dest"], "decision": decision})
        elif decision == "keep":
            report["kept"].append(entry["dest"])
        if decision != "keep":
            writes.append((entry, decision == "overwrite-with-backup"))

    if args.dry_run:
        for entry, backup in writes:
            key = "added" if entry["status"] == "add" else "updated"
            report[key].append(entry["dest"])
            if backup:
                report["backups"].append(entry["dest"] + ".pre-update.bak")
        report.update(
            result="dry-run",
            hook_dispatcher="would-regenerate",
            manifest="would-create" if plan["manifest_source"] == "reconstructed" else "would-update",
        )
        print(json.dumps(report, indent=2))
        return 0

    # --- execute: files, hooks, manifest, smoke test ---
    # The dirty-tree gate above is the rollback story: every path written here
    # is tracked, so `git checkout -- .` restores a clean tree if a later step
    # fails. No partial-state bookkeeping beyond that.
    for entry, backup in writes:
        src, dest = Path(entry["src"]), root / entry["dest"]
        if backup:
            bak = Path(str(dest) + ".pre-update.bak")
            shutil.copy2(dest, bak)
            report["backups"].append(entry["dest"] + ".pre-update.bak")
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(stamped_text(src, stamp_version))
        shutil.copymode(src, dest)
        report["added" if entry["status"] == "add" else "updated"].append(entry["dest"])

    hook_kwargs = {"lib_dir": hooks_lib} if hooks_lib is not None else {}
    hooks_rc = regen_hooks_step(
        root, plan["hook_strategy"], stamp_version, report,
        recovery="resolve the hook collision (unmanaged hook file), `git checkout -- .` to restore, re-run",
        **hook_kwargs)
    if hooks_rc is not None:
        return hooks_rc

    manifest_path = root / ".governance" / "install.yaml"
    if manifest_path.is_file():
        _update_manifest_kit_version(manifest_path, stamp_version)
        report["manifest"] = "updated"
    else:
        fresh = _write_fresh_manifest(root, plan, args.owner, args.repo, stamp_version)
        if fresh.returncode != 0:
            report.update(
                result="error",
                reason=f"write_installed_manifest failed: {fresh.stderr.strip()}",
                recovery="`git checkout -- .` to restore, then re-run",
            )
            print(json.dumps(report, indent=2))
            return 1
        report["manifest"] = "created"

    report["smoke_test"] = smoke_test(root, plan["tests_dir"])
    report["result"] = "applied"
    print(json.dumps(report, indent=2))
    return 0

