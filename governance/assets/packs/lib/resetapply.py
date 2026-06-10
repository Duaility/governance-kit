#!/usr/bin/env python3
"""Execution half of `governance reset` — the `reset-apply` engine (issue #172).

Companion to resetplan.py (the pure plan) and packverb.py (the CLI surface).
`cmd_reset_apply` recomputes the plan, enforces in code the gates that were
RESET_FLOW.md prose — refuse when the lockfile is missing (reset is
lockfile-driven; provenance can't be reconstructed by heuristic), when the scope
resolves to nothing, on a dirty working tree without `--force` — then restores
each in-scope directive to its **pinned** pristine source in one call:

  * `restore` — replace the directive folder from the pinned cache via install.sh
    `copy_tree_without_evals`, and replace/insert its CONSTITUTION.md subsection
    via docsurgery from the pinned `constitution.md`.
  * `drop` (only under `--all --drop-handauthored`) — delete the directive folder
    and strip its CONSTITUTION.md subsection.
  * `skip` — byte-identical to pinned; nothing to do.

Then it regenerates the hook dispatcher, appends one Evolution Log entry per
pack, and smoke-tests (never aborting on failure). `--dry-run` writes nothing.
Leaves `.governance/freshness.conf` untouched (it holds opt-in doc paths, not
per-directive state). The operator keeps the diff-before-exec `yes` and commit.
Prints a JSON report; exit 0 applied/no-op/dry-run, 2 refused, 1 error.
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

from applylib import bash_lib, git_dirty, hook_digests, refuse, regenerate_hooks, smoke_test
from packctl import KIT_VERSION
from resetplan import compute_reset_plan


def _restore_folder(source: Path, dest: Path) -> None:
    bash_lib('copy_tree_without_evals "$1" "$2"; chmod +x "$2/check.sh" 2>/dev/null || true',
             str(source), str(dest))


def _short(sha: str) -> str:
    return sha[:8] if sha else "unknown"


def cmd_reset_apply(args: argparse.Namespace) -> int:
    root = Path(args.root).resolve()
    report: dict[str, Any] = {
        "result": None, "scope": args.scope, "target": args.target,
        "restored": [], "dropped": [], "skipped": [],
        "preserved_handauthored": [], "constitution_changed": [],
        "hook_dispatcher": "unchanged", "evolution_log": "unchanged",
        "smoke_test": None, "assumptions": [],
    }

    try:
        plan = compute_reset_plan(root, args.scope, args.target,
                                  args.drop_handauthored, with_diff=False)
    except (ValueError, SystemExit, subprocess.CalledProcessError) as exc:
        return refuse(report, f"plan failed: {exc}", "check the scope/lockfile and network access")

    if not plan["lockfile_present"]:
        return refuse(report, "reset is lockfile-driven and .governance/packs.lock is missing",
                      "governance uninstall, then governance init")
    if plan["errors"]:
        return refuse(report, "; ".join(plan["errors"]),
                      "run `governance pack list` to see installed packs and directives")
    if not plan["directives"]:
        report.update(result="no-op", preserved_handauthored=plan["preserved_handauthored"])
        print(json.dumps(report, indent=2))
        return 0

    try:
        dirty = git_dirty(root)
    except (OSError, subprocess.CalledProcessError) as exc:
        return refuse(report, f"git status failed: {exc}", "run from a git repository")
    if dirty and not args.force:
        return refuse(report, "working tree has uncommitted changes", "commit or stash, or re-run with --force")
    if dirty:
        report["assumptions"].append("--force: applied over a dirty working tree")

    report["preserved_handauthored"] = plan["preserved_handauthored"]
    constitution = root / "CONSTITUTION.md"

    if args.dry_run:
        for d in plan["directives"]:
            report[{"restore": "restored", "drop": "dropped", "skip": "skipped"}[d["kind"]]].append(d["id"])
        report.update(result="dry-run", hook_dispatcher="would-regenerate",
                      evolution_log="would-append")
        print(json.dumps(report, indent=2))
        return 0

    from docsurgery import strip_directive_subsection, upsert_directive_subsection

    const_text = constitution.read_text() if constitution.is_file() else ""
    for d in plan["directives"]:
        if d["kind"] == "skip":
            report["skipped"].append(d["id"])
            continue
        if d["kind"] == "restore":
            _restore_folder(Path(d["source_dir"]), root / d["dest"])
            report["restored"].append(d["id"])
            sub_src = Path(d["subsection_source"])
            if const_text and sub_src.is_file():
                const_text, action = upsert_directive_subsection(const_text, d["id"], sub_src.read_text())
                report["constitution_changed"].append(f"{d['id']}:{action}")
        elif d["kind"] == "drop":
            shutil.rmtree(root / d["dest"], ignore_errors=True)
            report["dropped"].append(d["id"])
            if const_text:
                const_text, removed = strip_directive_subsection(const_text, d["id"])
                if removed:
                    report["constitution_changed"].append(f"{d['id']}:stripped")
    if constitution.is_file() and const_text != constitution.read_text():
        constitution.write_text(const_text)

    before = hook_digests(root, plan["hook_strategy"])
    hooks = regenerate_hooks(root, plan["hook_strategy"], KIT_VERSION)
    if hooks.returncode != 0:
        report.update(result="error", hook_dispatcher="failed",
                      reason=f"hook regeneration failed: {hooks.stderr.strip()}",
                      recovery="`git checkout -- .` to restore, then re-run")
        print(json.dumps(report, indent=2))
        return 1
    report["hook_dispatcher"] = "regenerated" if hook_digests(root, plan["hook_strategy"]) != before else "unchanged"

    if args.date and constitution.is_file() and (report["restored"] or report["dropped"]):
        from docsurgery import append_evolution_log
        author = args.author or "governance"
        text = constitution.read_text()
        by_pack: dict[str, list[str]] = {}
        for d in plan["directives"]:
            if d["kind"] == "restore":
                by_pack.setdefault(d["pack_id"], []).append(d["id"])
        for pid, ids in sorted(by_pack.items()):
            sha = next((d["sha"] for d in plan["directives"] if d["pack_id"] == pid), "")
            text = append_evolution_log(
                text, f"- {args.date} — @{author} — Reset directives from `{pid}` to pinned `{_short(sha)}` "
                      f"({', '.join('`' + i + '`' for i in sorted(ids))}).")
        if report["dropped"]:
            text = append_evolution_log(
                text, f"- {args.date} — @{author} — Drop hand-authored directives via `reset --drop-handauthored` "
                      f"({', '.join('`' + i + '`' for i in sorted(report['dropped']))}).")
        constitution.write_text(text)
        report["evolution_log"] = "appended"

    report["smoke_test"] = smoke_test(root, plan["tests_dir"])
    report["result"] = "applied"
    print(json.dumps(report, indent=2))
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("reset-apply")
    p.add_argument("scope", choices=["directive", "pack", "all"])
    p.add_argument("root")
    p.add_argument("target", nargs="?", default=None)
    p.add_argument("--drop-handauthored", action="store_true")
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--force", action="store_true")
    p.add_argument("--date", default=None, help="YYYY-MM-DD for the Evolution Log entry (operator-supplied)")
    p.add_argument("--author", default=None, help="git user for the Evolution Log entry")
    p.set_defaults(func=cmd_reset_apply)
    args = parser.parse_args(argv)
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
