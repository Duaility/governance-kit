#!/usr/bin/env python3
"""Execution half of `governance init` — the `init-apply` engine (issue #172).

Companion to initplan.py (the pure plan + CONSTITUTION assembly) and packverb.py
(the CLI). `init` keeps its genuinely-interactive surface with the operator —
pack/preset/directive selection, principle inference, hook-collision choices, the
Step-8 finding-resolution loop, and the commit. `init-apply` consumes the
operator's serialized `--decisions` and does the mechanical assembly in one
tested call: install each directive folder + its install-assets, seed each
directive's user config from its shipped `config.conf`, assemble and write
CONSTITUTION.md, create the
AGENTS.md stub when asked, lay down + stamp the runtime (run.sh/lib.sh), generate
the hook dispatchers (and, for githooks, `core.hooksPath` + enable-governance.sh),
stamp the CI workflow, write the install.yaml receipt + packs.lock pin, and
smoke-test.

It enforces in code the gates that were INIT_FLOW.md prose: refuse outside a git
repo, refuse to clobber an existing install without `--force`, refuse a
cross-pack directive-id collision (a flat-namespace overwrite). `--dry-run`
reports the would-be writes and changes nothing. Prints a JSON report; exit 0
applied/dry-run, 2 refused, 1 error.
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
from pathlib import Path
from typing import Any

from applylib import bash_lib, load_decisions, refuse, regen_hooks_step, smoke_test
from initplan import assemble_constitution, collisions
from packctl import KIT_VERSION
from packverb import load_lockfile, write_lockfile, _utc_now

KIT_ASSETS = Path(__file__).resolve().parents[2]  # governance/assets


def _copy_stamp(src: Path, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dest)
    bash_lib('stamp_managed_marker "$1" "$2"', str(dest), KIT_VERSION)


def _install_directives(root: Path, packs: list[dict[str, Any]], report: dict[str, Any]) -> tuple[list[str], list[str], list[str]]:
    seeded: list[str] = []
    conf_seeded: list[str] = []
    all_dids: list[str] = []
    for pack in packs:
        pack_dir = pack["pack_dir"]
        for did in sorted(pack.get("directives") or []):
            all_dids.append(did)
            res = bash_lib(
                'install_directive_folder "$1" "$2" "$3"; '
                'install_directive_assets "$1" "$2" "$3"; '
                'seed_directive_conf "$1" "$2" "$3"',
                pack_dir, did, str(root))
            if res.returncode != 0:
                raise RuntimeError(f"install of {pack['id']}/{did} failed: {res.stderr.strip()}")
            report["directives_installed"].append(f"{pack['id']}/{did}")
            # seed_directive_conf prints the repo-relative path it seeded (if any).
            conf_seeded.extend(line for line in res.stdout.splitlines() if line.strip())
            assets = Path(pack_dir) / "directives" / did / "install-assets"
            if assets.is_dir():
                seeded.extend("/".join(p.relative_to(assets).parts)
                              for p in sorted(assets.rglob("*")) if p.is_file())
    return all_dids, sorted(set(seeded)), sorted(set(conf_seeded))


def _write_manifest(root: Path, decisions: dict[str, Any], seeded: list[str], report: dict[str, Any]) -> None:
    argv = [str(root), "--owner", decisions["owner"], "--repo", decisions["repo"],
            "--kit-version", KIT_VERSION, "--hook-strategy", decisions.get("hook_strategy", "githooks"),
            "--ci-workflow", ".github/workflows/governance.yml", "--tests-dir", ".governance"]
    # Record the content-addressed pin of the installing kit (issue #177): the
    # ref is constructible offline; the sha is pre-resolved by the flow (via
    # `git ls-remote`) and threaded through decisions, omitted when unavailable
    # (backfilled on the first `kit update`). No network in the engine itself.
    from kitverb import DEFAULT_KIT_REPO  # lazy: avoid import cycle
    from kitresolve import build_kit_ref
    kit_ref = decisions.get("kit_ref") or build_kit_ref(DEFAULT_KIT_REPO, KIT_VERSION)
    kit_sha = decisions.get("kit_sha")
    argv += ["--kit-ref", kit_ref]
    if kit_sha:
        argv += ["--kit-sha", kit_sha]
    if (root / "AGENTS.md").is_file():
        argv.append("--agents-md-snippet")
    if report.get("agents_md") == "stub created":
        argv.append("--agents-md-created")
    if decisions.get("hook_strategy", "githooks") == "githooks":
        argv += ["--enable-governance-script", "scripts/enable-governance.sh"]
    for s in seeded:
        argv += ["--install-asset", s]
    res = bash_lib('write_installed_manifest "$@"', *argv)
    if res.returncode != 0:
        raise RuntimeError(f"write_installed_manifest failed: {res.stderr.strip()}")


def _write_lock(root: Path, packs: list[dict[str, Any]]) -> None:
    lockpath = root / ".governance" / "packs.lock"
    data = load_lockfile(lockpath)
    for pack in packs:
        entry: dict[str, Any] = {"id": pack["id"], "version": pack.get("version", ""),
                                 "source": pack.get("source", "gh"),
                                 "directives": sorted(pack.get("directives") or [])}
        if pack.get("source", "gh") == "gh":
            entry.update(ref=pack.get("ref", ""), sha=pack.get("sha", ""),
                         subpath=pack.get("subpath", ""),
                         min_governance_kit=pack.get("min_governance_kit", ""),
                         installed_at=_utc_now())
        data["packs"] = [p for p in data["packs"] if p.get("id") != pack["id"]]
        data["packs"].append(entry)
    write_lockfile(lockpath, data)


def cmd_init_apply(args: argparse.Namespace) -> int:
    report: dict[str, Any] = {
        "result": None, "directives_installed": [], "seeded_assets": [],
        "conf_seeded": [],
        "constitution": "unchanged", "agents_md": "untouched",
        "hook_dispatcher": "unchanged", "manifest": "unchanged",
        "smoke_test": None, "assumptions": [],
    }
    try:
        decisions = load_decisions(args.decisions)
    except (ValueError, OSError, json.JSONDecodeError) as exc:
        return refuse(report, f"bad --decisions: {exc}", "fix the decisions JSON and re-run")

    root = Path(args.root).resolve()
    if subprocess.run(["git", "-C", str(root), "rev-parse", "--show-toplevel"],
                      capture_output=True).returncode != 0:
        return refuse(report, "not a git repository", "run governance init inside a git repo")
    if (root / ".governance" / "install.yaml").is_file() and not args.force:
        return refuse(report, "governance is already installed here (.governance/install.yaml present)",
                      "re-run with --force to overwrite, or use governance pack/directive verbs to amend")
    dupes = collisions(decisions.get("packs") or [])
    if dupes:
        return refuse(report, "directive id claimed by more than one pack: " + "; ".join(dupes),
                      "remove the duplicate directive from one pack before installing")

    packs = decisions.get("packs") or []
    strategy = decisions.get("hook_strategy", "githooks")

    if args.dry_run:
        from initplan import directive_inventory
        would_seed_conf = []
        for pack in packs:
            for did in sorted(pack.get("directives") or []):
                tpl = Path(pack["pack_dir"]) / "directives" / did / "config.conf"
                dest = root / ".governance" / "conf" / f"{did}.conf"
                if tpl.is_file() and not dest.exists():
                    would_seed_conf.append(f".governance/conf/{did}.conf")
        report.update(result="dry-run",
                      directives_installed=[d["dest"] for d in directive_inventory(packs)],
                      conf_seeded=sorted(set(would_seed_conf)),
                      constitution="would-write", hook_dispatcher="would-generate", manifest="would-write")
        print(json.dumps(report, indent=2))
        return 0

    try:
        all_dids, seeded, conf_seeded = _install_directives(root, packs, report)
        report["seeded_assets"] = seeded
        # Per-directive user config is seeded from each directive's shipped
        # `config.conf` into `.governance/conf/<id>.conf` (augment-only) by
        # seed_directive_conf, inside _install_directives.
        report["conf_seeded"] = conf_seeded

        # CONSTITUTION.md: template + principles + spliced subsections.
        subsections = []
        for pack in packs:
            for did in sorted(pack.get("directives") or []):
                sub = Path(pack["pack_dir"]) / "directives" / did / "constitution.md"
                if sub.is_file():
                    subsections.append(sub.read_text())
        template = (KIT_ASSETS / "CONSTITUTION.template.md").read_text()
        (root / "CONSTITUTION.md").write_text(
            assemble_constitution(template, decisions.get("principles") or [], subsections))
        report["constitution"] = "written"

        # AGENTS.md stub (Case 2 — operator handles in-place insertion into an
        # existing AGENTS.md; the engine only creates the stub when asked).
        agents = root / "AGENTS.md"
        if decisions.get("seed_agents_stub") and not agents.is_file():
            snippet = (KIT_ASSETS / "AGENTS.snippet.md").read_text()
            agents.write_text(f"# AGENTS.md\n\nGovernance-driven development.\n\n{snippet}\n\n## What this repo is\n\nTODO.\n")
            report["agents_md"] = "stub created"

        # Runtime + CI workflow (copy + stamp).
        for fn in ("run.sh", "lib.sh"):
            _copy_stamp(KIT_ASSETS / "dot-governance" / fn, root / ".governance" / fn)
            (root / ".governance" / fn).chmod(0o755)
        _copy_stamp(KIT_ASSETS / "governance.yml", root / ".github" / "workflows" / "governance.yml")

        # Hooks + Path-A onboarding.
        hooks_rc = regen_hooks_step(
            root, strategy, KIT_VERSION, report, changed_label="generated",
            recovery="`git clean -fdx .governance .githooks` and `git checkout -- .` to reset, then re-run")
        if hooks_rc is not None:
            return hooks_rc
        if strategy == "githooks":
            subprocess.run(["git", "-C", str(root), "config", "core.hooksPath", ".githooks"], check=False)
            _copy_stamp(KIT_ASSETS / "enable-governance.sh", root / "scripts" / "enable-governance.sh")
            (root / "scripts" / "enable-governance.sh").chmod(0o755)

        _write_manifest(root, decisions, seeded, report)
        report["manifest"] = "written"
        _write_lock(root, packs)
    except (RuntimeError, OSError) as exc:
        report.update(result="error", reason=str(exc),
                      recovery="`git clean -fdx .governance .githooks` and `git checkout -- .` to reset, then re-run")
        print(json.dumps(report, indent=2))
        return 1

    report["smoke_test"] = smoke_test(root, ".governance")
    report["result"] = "applied"
    print(json.dumps(report, indent=2))
    return 0
