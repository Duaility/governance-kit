#!/usr/bin/env python3
"""Pure plan computation for `governance uninstall` (issue #172).

`uninstall-plan <root> [--mode soft|hard|dry-run]` surveys the repo against the
UNINSTALL_MATRIX, classifies its state (`fully-installed` / `partial` /
`unmarked-collision` / `none-detected`), and emits the exact deletion/restore
inventory the apply engine will execute — driven by `.governance/install.yaml`
+ `.governance/packs.lock` (manifest), the line-2 `governance-kit:managed`
ownership marker (second layer), and a heuristic fallback (third, dry-run by
default). It writes nothing.

`uninstall-apply` (engine in uninstallapply.py, dispatched from packverb.py)
recomputes this and executes it in the order UNINSTALL_FLOW.md Step 5 fixes
(hooks → config → AGENTS.md → tree → path-B → seeded → backups → manifest last).

Run via:
    uv run --with PyYAML python .../uninstallplan.py uninstall-plan <root> [--mode <m>]
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

from packctl import load_yaml, scalar

HOOK_KINDS = ("pre-commit", "commit-msg", "prepare-commit-msg", "post-commit", "pre-push")
AGENTS_OPEN = "<!-- governance: directives-to-follow -->"
AGENTS_CLOSE = "<!-- /governance: directives-to-follow -->"


def _has_marker(path: Path) -> bool:
    if not path.is_file():
        return False
    try:
        head = path.read_text(errors="replace").splitlines()[:3]
    except OSError:
        return False
    return any(ln.startswith("# governance-kit:managed") for ln in head)


def _survey_hooks(root: Path) -> tuple[list[dict[str, Any]], list[dict[str, str]], list[str]]:
    """Return (marked-hooks-to-delete, userhook-restores, unmarked-collisions)."""
    hookdir = root / ".githooks"
    delete: list[dict[str, Any]] = []
    restores: list[dict[str, str]] = []
    collisions: list[str] = []
    for kind in HOOK_KINDS:
        hook = hookdir / kind
        if hook.is_file():
            if _has_marker(hook):
                delete.append({"path": f".githooks/{kind}", "marker": "present"})
            else:
                collisions.append(f".githooks/{kind}")
        userhook = hookdir / f"{kind}.userhook"
        if userhook.is_file():
            restores.append({"from": f".githooks/{kind}.userhook", "to": f".githooks/{kind}"})
    return delete, restores, collisions


def compute_uninstall_plan(root: Path, mode: str) -> dict[str, Any]:
    manifest_path = root / ".governance" / "install.yaml"
    manifest_present = manifest_path.is_file()
    manifest = load_yaml(manifest_path) if manifest_present else {}

    governance_dir = root / ".governance"
    constitution = root / "CONSTITUTION.md"
    hooks_delete, userhook_restores, collisions = _survey_hooks(root)

    # Artifact presence for classification.
    artifacts_present = constitution.is_file() or governance_dir.is_dir() or bool(hooks_delete)
    if not manifest_present and not artifacts_present and not collisions:
        classification = "none-detected"
    elif collisions:
        classification = "unmarked-collision"
    elif manifest_present:
        classification = "fully-installed"
    else:
        classification = "partial"
    source_of_truth = "manifest" if manifest_present else "heuristic"

    ci_workflow = scalar(manifest.get("ci_workflow")) or ".github/workflows/governance.yml"
    enable_script = scalar(manifest.get("enable_governance_script"))
    tree_deletes = []
    if constitution.is_file():
        tree_deletes.append("CONSTITUTION.md")
    if (root / ci_workflow).is_file():
        tree_deletes.append(ci_workflow)
    if enable_script and (root / enable_script).is_file():
        tree_deletes.append(enable_script)

    seeded = [s for s in (manifest.get("install_assets_seeded") or []) if (root / str(s)).is_file()]
    backups = [str(p.relative_to(root)) for p in sorted(root.rglob("*.pre-governance.bak"))
               if ".git" not in p.parts]

    path_b = manifest.get("path_b") or {}
    path_b_entries = []
    if isinstance(path_b, dict) and path_b.get("entries"):
        path_b_entries = [e.get("file") if isinstance(e, dict) else e for e in path_b["entries"]]

    agents = root / "AGENTS.md"
    agents_text = agents.read_text(errors="replace") if agents.is_file() else ""
    agents_info = {
        "present": agents.is_file(),
        "has_open_marker": AGENTS_OPEN in agents_text,
        "has_close_marker": AGENTS_CLOSE in agents_text,
        "created_by_init": scalar(manifest.get("agents_md_created")) == "true",
    }

    return {
        "mode": mode,
        "classification": classification,
        "source_of_truth": source_of_truth,
        "manifest_present": manifest_present,
        "hook_strategy": scalar(manifest.get("hook_strategy")) or "githooks",
        "hooks_delete": hooks_delete,
        "userhook_restores": userhook_restores,
        "collisions": collisions,
        "core_hookspath": None,  # filled by apply (needs git); plan stays pure
        "agents": agents_info,
        "tree_deletes": tree_deletes,
        "governance_dir": ".governance" if governance_dir.is_dir() else None,
        "path_b_framework": scalar(path_b.get("framework")) if isinstance(path_b, dict) else "",
        "path_b_entries": path_b_entries,
        "seeded_docs": seeded,
        "backups": backups,
    }


def cmd_uninstall_plan(args: argparse.Namespace) -> int:
    root = Path(args.root).resolve()
    print(json.dumps(compute_uninstall_plan(root, args.mode), indent=2))
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("uninstall-plan")
    p.add_argument("root")
    p.add_argument("--mode", choices=["dry-run", "soft", "hard"], default="soft")
    p.set_defaults(func=cmd_uninstall_plan)
    args = parser.parse_args(argv)
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
