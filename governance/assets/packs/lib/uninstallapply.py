#!/usr/bin/env python3
"""Execution half of `governance uninstall` — the `uninstall-apply` engine (#172).

Companion to uninstallplan.py (the pure survey/plan) and packverb.py (the CLI).
`cmd_uninstall_apply` recomputes the plan and enforces in code the gates that
were UNINSTALL_FLOW.md prose: `none-detected` → idempotent no-op; an
`unmarked-collision` (a hook at a managed path without the ownership marker) →
refuse, surface the colliding paths, and stop (never delete somebody else's
hook); a missing manifest (heuristic source-of-truth) → refuse a destructive
mode unless explicitly `--allow-heuristic` (silence is not consent). It never
runs destructive git ops (`git clean` / `reset --hard` / stash) and never
commits.

It then deletes/restores in the order Step 5 fixes (so the manifest pair is gone
last — its absence is the idempotency signal): managed hooks → restore
`.userhook` siblings → unset `core.hooksPath` (only if it still points at
`.githooks`) → strip the AGENTS.md directive block (docsurgery, byte-safe) →
`CONSTITUTION.md` / CI workflow / enable-script → Path-B framework entries →
seeded docs (hard only) → `.pre-governance.bak` backups (hard only) →
`.governance/` recursively. `--mode dry-run` reports the would-be actions and
writes nothing. Prints a JSON report; exit 0 applied/no-op/dry-run, 2 refused.
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

from applylib import refuse
from uninstallplan import AGENTS_CLOSE, AGENTS_OPEN, compute_uninstall_plan


def _git(root: Path, *argv: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["git", "-C", str(root), *argv],
                          check=False, text=True, capture_output=True)


def _core_hookspath(root: Path) -> str:
    return _git(root, "config", "--get", "core.hooksPath").stdout.strip()


def _strip_path_b(root: Path, framework: str, entries: list[str], report: dict[str, Any]) -> None:
    """Remove only the kit's governance entries from a husky / pre-commit config."""
    for rel in entries:
        f = root / rel
        if not f.is_file():
            continue
        kept = [ln for ln in f.read_text().splitlines(keepends=True)
                if ".governance/run.sh" not in ln]
        f.write_text("".join(kept))
        report["path_b_edited"].append(rel)


def cmd_uninstall_apply(args: argparse.Namespace) -> int:
    root = Path(args.root).resolve()
    plan = compute_uninstall_plan(root, args.mode)
    mode = args.mode
    report: dict[str, Any] = {
        "result": None, "mode": mode,
        "classification": plan["classification"],
        "source_of_truth": plan["source_of_truth"],
        "deleted": [], "preserved": [], "hooks_restored": [],
        "agents_md": "untouched", "git_config": "left as-is",
        "path_b_edited": [], "collisions": plan["collisions"], "assumptions": [],
    }

    if _git(root, "rev-parse", "--show-toplevel").returncode != 0:
        return refuse(report, "not a git repository", "run uninstall from inside the repo")
    if plan["classification"] == "none-detected":
        report.update(result="none-detected")
        print(json.dumps(report, indent=2))
        return 0
    if plan["classification"] == "unmarked-collision":
        return refuse(
            report,
            "hook(s) at a managed path carry no governance-kit marker: " + ", ".join(plan["collisions"]),
            "resolve each collision (restore its .userhook, or move it to <path>.pre-reset.bak), then re-run",
        )
    if plan["source_of_truth"] == "heuristic" and mode != "dry-run" and not args.allow_heuristic:
        return refuse(
            report,
            "install.yaml is missing (heuristic detection); a destructive mode needs explicit opt-in",
            "re-run with --allow-heuristic to proceed in this mode, or --mode dry-run to preview",
        )
    if plan["source_of_truth"] == "heuristic":
        report["assumptions"].append("manifest absent — artifacts detected heuristically")

    dry = mode == "dry-run"

    def rm(rel: str, *, recursive: bool = False) -> None:
        report["deleted"].append(rel)
        if dry:
            return
        target = root / rel
        if recursive:
            shutil.rmtree(target, ignore_errors=True)
        elif target.exists():
            target.unlink()

    # 1. Managed hooks.
    for h in plan["hooks_delete"]:
        rm(h["path"])
    # 1b. Restore userhook siblings.
    for r in plan["userhook_restores"]:
        report["hooks_restored"].append(f"{r['from']} → {r['to']}")
        if not dry:
            (root / r["from"]).rename(root / r["to"])

    # 2. core.hooksPath (Path A only).
    if plan["hook_strategy"] == "githooks":
        current = _core_hookspath(root)
        if current == ".githooks":
            report["git_config"] = "core.hooksPath unset"
            if not dry:
                _git(root, "config", "--unset", "core.hooksPath")
        elif current:
            report["git_config"] = f"left as-is — pointed at {current}"

    # 3. AGENTS.md directive block.
    agents = root / "AGENTS.md"
    if plan["agents"]["present"] and plan["agents"]["has_open_marker"]:
        from docsurgery import strip_marker_block
        new_text, status, rest_ok = strip_marker_block(agents.read_text(), AGENTS_OPEN, AGENTS_CLOSE)
        if not rest_ok:
            return refuse(report, "AGENTS.md byte-diff guard: a non-block line would change",
                          "inspect AGENTS.md and remove the directive block by hand")
        report["agents_md"] = "directive block stripped" + (
            " (opening-marker heuristic)" if status == "unbounded-stripped" else "")
        if status == "unbounded-stripped":
            report["assumptions"].append("AGENTS.md had only the opening marker — block boundary inferred")
        if not dry:
            agents.write_text(new_text)
        if mode == "hard" and plan["agents"]["created_by_init"]:
            # Stub created by init: offer-to-delete is the skill's; we only
            # delete when it is still ~stub-sized to avoid nuking grown docs.
            report["assumptions"].append("agents_md_created: stub left in place (delete by hand if desired)")

    # 4. Tree deletes (CONSTITUTION, CI workflow, enable-script).
    for rel in plan["tree_deletes"]:
        rm(rel)

    # 5. Path B.
    if plan["path_b_framework"]:
        if dry:
            report["path_b_edited"].extend(plan["path_b_entries"])
        else:
            _strip_path_b(root, plan["path_b_framework"], plan["path_b_entries"], report)

    # 6. Seeded docs (hard only; preserved in soft).
    for s in plan["seeded_docs"]:
        if mode == "hard":
            rm(str(s))
        else:
            report["preserved"].append(str(s))
    # 7. Backups (hard only).
    for b in plan["backups"]:
        if mode == "hard":
            rm(b)
        else:
            report["preserved"].append(b)

    # 8. Manifest pair / .governance tree last.
    if plan["governance_dir"]:
        rm(plan["governance_dir"], recursive=True)

    report["result"] = "dry-run" if dry else "applied"
    print(json.dumps(report, indent=2))
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("uninstall-apply")
    p.add_argument("root")
    p.add_argument("--mode", choices=["dry-run", "soft", "hard"], default="soft")
    p.add_argument("--allow-heuristic", action="store_true",
                   help="permit a destructive mode when the manifest is absent (explicit opt-in)")
    p.set_defaults(func=cmd_uninstall_apply)
    args = parser.parse_args(argv)
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
