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
    git_dirty,
    hook_digests,
    refuse,
    regenerate_hooks,
    smoke_test,
)
from kitverb import KIT_VERSION, compute_plan, stamped_text

_UNMANAGED_DECISIONS = ("keep", "apply", "overwrite-with-backup")


def _load_decisions(raw: str | None) -> dict[str, str]:
    """Per-file decision overrides: {<dest-rel>: keep|apply|overwrite-with-backup}.

    Defaults when a dest is not named: `apply` for managed files (`apply`/`add`
    status — the marker is the regeneration contract), `keep` for `unmanaged`
    ones (no marker means user-owned, never silently overwritten). Accepts
    inline JSON or a path to a JSON file. Unknown decision values are rejected
    here; destinations that don't need a decision (status `skip`, or absent
    from the plan) are rejected later — a decisions object that doesn't match
    reality is an error, not a shrug.
    """
    if not raw:
        return {}
    text = raw if raw.lstrip().startswith("{") else Path(raw).read_text()
    decisions = json.loads(text)
    if not isinstance(decisions, dict):
        raise ValueError("--decisions must be a JSON object of {dest: decision}")
    for dest, decision in decisions.items():
        if decision not in _UNMANAGED_DECISIONS:
            raise ValueError(
                f"--decisions[{dest!r}]: {decision!r} is not one of {', '.join(_UNMANAGED_DECISIONS)}"
            )
    return decisions


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


def _write_fresh_manifest(root: Path, plan: dict[str, Any], owner: str, repo: str) -> subprocess.CompletedProcess[str]:
    """v3 manifest for the reconstructed-pin path, via install.sh write_installed_manifest."""
    argv = [
        str(root),
        "--owner", owner, "--repo", repo,
        "--kit-version", KIT_VERSION,
        "--hook-strategy", plan["hook_strategy"],
        "--tests-dir", plan["tests_dir"],
    ]
    enable_script = root / "scripts" / "enable-governance.sh"
    if enable_script.is_file():
        argv += ["--enable-governance-script", "scripts/enable-governance.sh"]
    return bash_lib('write_installed_manifest "$@"', *argv)


def cmd_kit_apply(args: argparse.Namespace) -> int:
    root = Path(args.root).resolve()
    plan = compute_plan(root)

    report: dict[str, Any] = {
        "result": None,
        "from": plan["installed_kit_version"],
        "to": KIT_VERSION,
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
        decisions = _load_decisions(args.decisions)
    except (ValueError, OSError, json.JSONDecodeError) as exc:
        return refuse(report, f"bad --decisions: {exc}", "fix the decisions JSON and re-run")

    # --- delta gates (UPDATE_FLOW.md Step 2, now enforced in code) ---
    if plan["delta"] == "up-to-date":
        report.update(result="up-to-date", skipped=[f["dest"] for f in plan["files"]])
        print(json.dumps(report, indent=2))
        return 0
    if plan["delta"] == "downgrade":
        return refuse(
            report,
            f"recorded kit_version {plan['installed_kit_version']} is newer than the kit on PATH ({KIT_VERSION})",
            "upgrade the kit on PATH (refresh the installed skill), then re-run",
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

    try:
        dirty = git_dirty(root)
    except (OSError, subprocess.CalledProcessError) as exc:
        return refuse(report, f"git status failed: {exc}", "run from a git repository")
    if dirty and not args.force:
        return refuse(report, "working tree has uncommitted changes", "commit or stash, or re-run with --force")
    if dirty:
        report["assumptions"].append("--force: applied over a dirty working tree")

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
        dest.write_text(stamped_text(src, KIT_VERSION))
        shutil.copymode(src, dest)
        report["added" if entry["status"] == "add" else "updated"].append(entry["dest"])

    before = hook_digests(root, plan["hook_strategy"])
    hooks = regenerate_hooks(root, plan["hook_strategy"], KIT_VERSION)
    if hooks.returncode != 0:
        report.update(
            result="error",
            hook_dispatcher="failed",
            reason=f"hook regeneration failed: {hooks.stderr.strip()}",
            recovery="resolve the hook collision (unmanaged hook file), `git checkout -- .` to restore, re-run",
        )
        print(json.dumps(report, indent=2))
        return 1
    report["hook_dispatcher"] = "regenerated" if hook_digests(root, plan["hook_strategy"]) != before else "unchanged"

    manifest_path = root / ".governance" / "install.yaml"
    if manifest_path.is_file():
        _update_manifest_kit_version(manifest_path, KIT_VERSION)
        report["manifest"] = "updated"
    else:
        fresh = _write_fresh_manifest(root, plan, args.owner, args.repo)
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

