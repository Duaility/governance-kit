#!/usr/bin/env python3
"""Shared execution helpers for the deterministic lifecycle apply engines.

`governance kit update`, `pack {add,update,remove}`, `reset`, `uninstall`, and
`init` each have a pure plan module and an apply engine (issue #172). The apply
engines all need the same primitives — the dirty-working-tree gate that doubles
as the rollback story, a way to run bash with install.sh/hooks.sh sourced,
hook-dispatcher regeneration, a non-fatal smoke test, and the JSON refusal
shape — so they live here once rather than copied into each engine.

These are the mechanical halves that used to be verb-flow prose. The operator
(agent or human) still owns what is genuinely theirs: eliciting decisions,
showing diffs, and the commit.
"""

from __future__ import annotations

import hashlib
import json
import subprocess
from pathlib import Path
from typing import Any

LIB_DIR = Path(__file__).resolve().parent

# Where each hook strategy lands its dispatchers — kept in sync with
# hooks.sh `generate_hooks_for_strategy`.
HOOK_DIR_FOR_STRATEGY = {
    "githooks": ".githooks",
    "husky": ".husky",
    "pre-commit": ".governance/hooks",
}

HOOK_KINDS = ("pre-commit", "commit-msg", "prepare-commit-msg", "post-commit", "pre-push")


def git_dirty(root: Path) -> bool:
    """True when the working tree has uncommitted changes.

    The apply engines gate on this without `--force`: every path an apply
    writes is tracked, so a clean starting tree means `git checkout -- .`
    restores it if a late step fails — no partial-state bookkeeping.
    """
    proc = subprocess.run(
        ["git", "-C", str(root), "status", "--porcelain"],
        check=True, text=True, capture_output=True,
    )
    return bool(proc.stdout.strip())


def bash_lib(script: str, *argv: str) -> subprocess.CompletedProcess[str]:
    """Run a snippet with install.sh + hooks.sh sourced ($1 = lib dir)."""
    return subprocess.run(
        ["bash", "-c", f'set -eu; source "$1/install.sh"; source "$1/hooks.sh"; shift; {script}',
         "_", str(LIB_DIR), *argv],
        check=False, text=True, capture_output=True,
    )


def hook_digests(root: Path, strategy: str) -> dict[str, str]:
    """sha256 of each generated dispatcher — used to report regenerated vs unchanged."""
    hook_dir = root / HOOK_DIR_FOR_STRATEGY[strategy]
    digests: dict[str, str] = {}
    for kind in HOOK_KINDS:
        path = hook_dir / kind
        if path.is_file():
            digests[kind] = hashlib.sha256(path.read_bytes()).hexdigest()
    return digests


def regenerate_hooks(root: Path, strategy: str, kit_version: str) -> subprocess.CompletedProcess[str]:
    """Rebuild the hook dispatchers from the installed directive set.

    Composes install.sh `build_hook_spec_from_installed_directives` and hooks.sh
    `generate_hooks_for_strategy` — the same pair init uses — so a directive
    added or removed since the last write is picked up automatically.
    """
    script = (
        'spec="$(mktemp)"; trap \'rm -f "$spec"\' EXIT; '
        'build_hook_spec_from_installed_directives "$1" "$spec"; '
        'generate_hooks_for_strategy "$1" "$2" "$3" "$spec"'
    )
    return bash_lib(script, str(root), strategy, kit_version)


def smoke_test(root: Path, tests_dir: str) -> dict[str, Any]:
    """Run `<tests_dir>/run.sh` and summarize. Never aborts the apply — a failing
    smoke test is surfaced in the report for the operator, not a hard error."""
    runner = root / tests_dir / "run.sh"
    if not runner.is_file():
        return {"exit_code": None, "summary": f"{tests_dir}/run.sh missing — not run"}
    try:
        proc = subprocess.run(
            ["bash", str(runner)], cwd=root,
            check=False, text=True, capture_output=True, timeout=600,
        )
    except subprocess.TimeoutExpired:
        return {"exit_code": None, "summary": "timed out after 600s"}
    output = (proc.stdout + proc.stderr).strip()
    failing = [ln.strip() for ln in output.splitlines() if ln.lstrip().startswith("✗")]
    summary = failing[0] if failing else (output.splitlines()[-1].strip() if output else "")
    return {"exit_code": proc.returncode, "summary": summary}


def refuse(report: dict[str, Any], reason: str, recovery: str) -> int:
    """Stamp a refusal onto the report, print it, and return the refuse exit code (2)."""
    report.update(result="refused", reason=reason, recovery=recovery)
    print(json.dumps(report, indent=2))
    return 2
