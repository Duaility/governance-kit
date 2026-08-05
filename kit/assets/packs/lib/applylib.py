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
import re
import shutil
import subprocess
from pathlib import Path
from typing import Any

LIB_DIR = Path(__file__).resolve().parent
KIT_ASSETS = LIB_DIR.parents[1]  # kit/assets

# The sweep lane's vendored assets (issue #142, harness-pegged per #355): kit-level
# files laid down into a target repo whenever a directive declares a live sweep
# tier. There is one judgment primitive — a `judge:` block re-adjudicated at
# rest by a bash driver through the same runtime-adapter `judge` verb the commit
# lane uses; no separate engine, no vendor transport, no keyword stub. Each value
# is the path parts under KIT_ASSETS. This is the single source of truth, shared
# by init-apply and pack-apply so the two install paths can never diverge — the
# no-path-bifurcation invariant the sweep lane itself enforces.
SWEEP_ASSETS = {
    ".github/workflows/governance-sweep.yml": ("governance-sweep.yml",),
    ".governance/sweep.sh": ("dot-governance", "sweep.sh"),
}

# The kit-level runtime adapter registry (issue #355). One file per harness at
# `<tests_dir>/runtimes/<name>.sh`, answering the accounting lane's two verbs —
# `resolve` and `emit` (session identity). Judging is not an adapter concern:
# each directive's `judge.cmd` names its own judge CLI, run by lib.sh. These
# are ordinary kit-managed runtime files, not seed-once assets: `init` lays them
# down stamped, `kit update` re-syncs them, `managed-tree-integrity` digests
# them. Enumerated from the shipped tree so adding an adapter is one file drop.
RUNTIMES_SUBDIR = "runtimes"


def kit_runtime_adapters(assets_root: Path | None = None) -> list[str]:
    """Filenames of the runtime adapters shipped in `dot-governance/runtimes/`,
    sorted. Empty when the kit being applied predates the registry."""
    src = (assets_root or KIT_ASSETS) / "dot-governance" / RUNTIMES_SUBDIR
    if not src.is_dir():
        return []
    return sorted(p.name for p in src.glob("*.sh") if p.is_file())

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


def dirty_gate(root: Path, force: bool, report: dict[str, Any]) -> int | None:
    """The shared dirty-working-tree gate. Returns the refuse exit code,
    or None to proceed (recording the --force assumption when taken)."""
    try:
        dirty = git_dirty(root)
    except (OSError, subprocess.CalledProcessError) as exc:
        return refuse(report, f"git status failed: {exc}", "run from a git repository")
    if dirty and not force:
        return refuse(report, "working tree has uncommitted changes", "commit or stash, or re-run with --force")
    if dirty:
        report["assumptions"].append("--force: applied over a dirty working tree")
    return None


def load_decisions(raw: str | None, allowed: tuple[str, ...] | None = None) -> dict[str, Any]:
    """Parse a `--decisions` value — inline JSON or a path to a JSON file.

    With `allowed`, every value must be one of those strings (per-file /
    per-directive decision verbs); a decisions object that doesn't match is an
    error, not a shrug. Without it, any JSON object passes (init's free-form
    decisions document)."""
    if not raw:
        return {}
    text = raw if raw.lstrip().startswith("{") else Path(raw).read_text()
    decisions = json.loads(text)
    if not isinstance(decisions, dict):
        raise ValueError("--decisions must be a JSON object")
    if allowed:
        for key, decision in decisions.items():
            if decision not in allowed:
                raise ValueError(
                    f"--decisions[{key!r}]: {decision!r} is not one of {', '.join(allowed)}"
                )
    return decisions


def bash_lib(script: str, *argv: str, lib_dir: Path | None = None) -> subprocess.CompletedProcess[str]:
    """Run a snippet with install.sh + hooks.sh sourced ($1 = lib dir).

    `lib_dir` None means this kit's own `lib/`. A delegated downgrade passes
    the *fetched older target's* lib dir so the dispatchers are generated by the
    version whose assets are being written — the hooks the older kit shipped,
    stamped its version (issue #177, open question 1, option b).
    """
    return subprocess.run(
        ["bash", "-c", f'set -eu; source "$1/install.sh"; source "$1/hooks.sh"; shift; {script}',
         "_", str(lib_dir or LIB_DIR), *argv],
        check=False, text=True, capture_output=True,
    )


def _participates_in_sweep(directive_yaml: Path) -> bool:
    """True when this directive.yaml puts the directive in the sweep lane.

    One way in (issue #355): the directive declares a `judge:` block at all.
    Every judgment is re-adjudicated at rest — a sectionless declaration is
    sweep-ONLY, and one with a `section:` is swept as well as attested — so a
    repo that installs either needs the lane vendored. There is no per-
    directive opt-out to read here: the retired `tiers:` map named a model
    capability, and the judge command now comes from the directive's rare
    `cmd.sweep` override or the repo-level `GOVERNANCE_SWEEP_CMD` knob, both
    resolved by the driver at run time rather than at install time. Hand-rolled
    line read, matching this module's stdlib-only discipline: the apply engines
    never import a YAML parser.
    """
    for raw in directive_yaml.read_text().splitlines():
        if raw.strip() == "judge:" and raw == raw.strip():
            return True
    return False


def selects_sweep_directive(packs: list[dict[str, Any]]) -> bool:
    """True if any directive in `packs` participates in the sweep lane — a
    `judge:` declaration whose sweep tier is live (issues #142, #355).
    `packs` entries carry `pack_dir` + a `directives` id list, the shape both
    init-plan and pack-plan emit.
    """
    for pack in packs:
        pack_dir = Path(pack["pack_dir"])
        for did in pack.get("directives") or []:
            y = pack_dir / "directives" / did / "directive.yaml"
            if not y.is_file():
                continue
            if _participates_in_sweep(y):
                return True
    return False


def pending_sweep_assets(root: Path, packs: list[dict[str, Any]]) -> list[str]:
    """The sweep assets a live-sweep-tier install still needs to lay down — those
    not already vendored. Empty when no sweep directive is selected, or when every
    asset is already present (idempotent: a second sweep directive seeds nothing
    new, and re-running over an existing lane is a no-op)."""
    if not selects_sweep_directive(packs):
        return []
    return [rel for rel in SWEEP_ASSETS if not (root / rel).exists()]


def seed_sweep_assets(root: Path, packs: list[dict[str, Any]], kit_version: str) -> list[str]:
    """Lay down the sweep workflow + at-rest driver for a live-sweep-tier install,
    stamped with `kit_version`, and return the rel paths actually seeded.

    Shared by init-apply and pack-apply so the lane is vendored identically no
    matter which verb installs the first sweep directive (issue #142). The caller
    records the returned rels in install.yaml's `install_assets_seeded` ledger so
    `governance uninstall` reverses them.
    """
    rels = pending_sweep_assets(root, packs)
    for rel in rels:
        dest = root / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(KIT_ASSETS.joinpath(*SWEEP_ASSETS[rel]), dest)
        bash_lib('stamp_managed_marker "$1" "$2"', str(dest), kit_version)
        if dest.name == "sweep.sh":
            dest.chmod(0o755)
    return rels


def hook_digests(root: Path, strategy: str) -> dict[str, str]:
    """sha256 of each generated dispatcher — used to report regenerated vs unchanged."""
    hook_dir = root / HOOK_DIR_FOR_STRATEGY[strategy]
    digests: dict[str, str] = {}
    for kind in HOOK_KINDS:
        path = hook_dir / kind
        if path.is_file():
            digests[kind] = hashlib.sha256(path.read_bytes()).hexdigest()
    return digests


def regenerate_hooks(root: Path, strategy: str, kit_version: str,
                     lib_dir: Path | None = None) -> subprocess.CompletedProcess[str]:
    """Rebuild the hook dispatchers from the installed directive set.

    Composes install.sh `build_hook_spec_from_installed_directives` and hooks.sh
    `generate_hooks_for_strategy` — the same pair init uses — so a directive
    added or removed since the last write is picked up automatically. `lib_dir`
    selects which kit's generator runs (defaults to this kit's; a delegated
    downgrade points it at the fetched older target's lib).
    """
    script = (
        'spec="$(mktemp)"; trap \'rm -f "$spec"\' EXIT; '
        'build_hook_spec_from_installed_directives "$1" "$spec"; '
        'generate_hooks_for_strategy "$1" "$2" "$3" "$spec"'
    )
    return bash_lib(script, str(root), strategy, kit_version, lib_dir=lib_dir)


def regen_hooks_step(root: Path, strategy: str, kit_version: str, report: dict[str, Any],
                     recovery: str, changed_label: str = "regenerated",
                     lib_dir: Path | None = None) -> int | None:
    """Regenerate the dispatchers and record the outcome on the report.

    Sets `hook_dispatcher` to `changed_label` / `unchanged` by digest
    comparison. On failure, stamps the error + recovery onto the report,
    prints it, and returns the error exit code (1); returns None on success."""
    before = hook_digests(root, strategy)
    hooks = regenerate_hooks(root, strategy, kit_version, lib_dir=lib_dir)
    if hooks.returncode != 0:
        report.update(result="error", hook_dispatcher="failed",
                      reason=f"hook regeneration failed: {hooks.stderr.strip()}",
                      recovery=recovery)
        print(json.dumps(report, indent=2))
        return 1
    report["hook_dispatcher"] = changed_label if hook_digests(root, strategy) != before else "unchanged"
    return None


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
