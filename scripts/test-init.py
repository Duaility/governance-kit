#!/usr/bin/env python3
"""Contract tests for initplan/initapply — the deterministic `init` engine
(issue #172, phase 4). Pure functions (collision detection, CONSTITUTION
assembly) plus an end-to-end `init-apply` against a throwaway git repo with a
local source pack (no network)."""

from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACK_LIB = ROOT / "governance" / "assets" / "packs" / "lib"
PACKVERB = PACK_LIB / "packverb.py"


def _load(name: str):
    sys.path.insert(0, str(PACK_LIB))
    spec = importlib.util.spec_from_file_location(name, PACK_LIB / f"{name}.py")
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


initplan = _load("initplan")

GIT_CLEAN_ENV = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}


def git(root: Path, *argv: str) -> None:
    subprocess.run(["git", "-C", str(root), "-c", "user.email=t@t", "-c", "user.name=t",
                    "-c", "commit.gpgsign=false", *argv],
                   check=True, env=GIT_CLEAN_ENV, capture_output=True)


# --- pure: collisions + assembly -------------------------------------------

def test_collisions_detects_cross_pack_dupe() -> None:
    packs = [{"id": "a/x", "directives": ["d1", "d2"]}, {"id": "b/y", "directives": ["d2"]}]
    assert any("d2" in c for c in initplan.collisions(packs))
    assert initplan.collisions([{"id": "a/x", "directives": ["d1"]}]) == []


def test_assemble_constitution_splices_principles_and_subsections() -> None:
    template = (ROOT / "governance/assets/CONSTITUTION.template.md").read_text()
    out = initplan.assemble_constitution(
        template, ["Ship receipts, not promises."],
        ["### no-console-log\n\n- **Directive**: no console.log.\n"])
    assert "Ship receipts, not promises." in out
    assert "### no-console-log" in out
    # the template example directive is replaced, not kept
    assert "### Example — constitution-exists" not in out
    # structure preserved
    assert "## Amendment process" in out and "## Evolution Log" in out


# --- end-to-end init-apply --------------------------------------------------

def _write_source_pack(base: Path, pack_id: str = "acme/widgets", did: str = "no-console-log") -> Path:
    pack = base / "widgets"
    ddir = pack / "directives" / did
    (ddir / "evals").mkdir(parents=True)
    (ddir / "install-assets").mkdir(parents=True)
    (pack / "pack.yaml").write_text(
        f"id: {pack_id}\nname: Widgets\nversion: \"0.1\"\nmin_governance_kit: \"0.0.1\"\n"
        "description: test\nauthor: acme\nsource: gh\n")
    (ddir / "directive.yaml").write_text(
        "category: Quality\nrecommended: true\nsummary: no console.log.\nsurface: change-set\nhook: pre-commit\n")
    (ddir / "check.sh").write_text("#!/usr/bin/env bash\nexit 0\n")
    (ddir / "constitution.md").write_text(
        f"### {did}\n\n- **Directive**: no console.log.\n"
        f"- **Enforced by**: `.governance/packs/{pack_id}/directives/{did}/check.sh`\n")
    (ddir / "evals" / "test.sh").write_text("#!/usr/bin/env bash\nexit 0\n")
    (ddir / "install-assets" / "WIDGETS.md").write_text("# Widgets\n")
    (ddir / "check.sh").chmod(0o755)
    (ddir / "evals" / "test.sh").chmod(0o755)
    return pack


def _decisions(pack_dir: Path) -> dict:
    return {
        "owner": "acme", "repo": "demo", "hook_strategy": "githooks",
        "principles": ["Ship receipts, not promises."],
        "seed_agents_stub": True,
        "packs": [{"id": "acme/widgets", "version": "0.1", "source": "gh",
                   "ref": "gh:acme/widgets", "sha": "e" * 40, "subpath": "",
                   "pack_dir": str(pack_dir), "directives": ["no-console-log"]}],
    }


def _fresh_repo(tmp: Path) -> Path:
    root = Path(tmp)
    root.mkdir(parents=True, exist_ok=True)
    git(root, "init", "-q")
    (root / "README.md").write_text("# demo\n")
    git(root, "add", "-A")
    git(root, "commit", "-qm", "init")
    return root


def init_apply_cli(root: Path, decisions: dict, *flags: str):
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
        json.dump(decisions, f)
        dpath = f.name
    res = subprocess.run(
        [sys.executable, str(PACKVERB), "init-apply", str(root), "--decisions", dpath, *flags],
        cwd=ROOT, check=False, text=True, env=GIT_CLEAN_ENV,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    Path(dpath).unlink()
    assert res.stdout.strip(), res.stderr
    return res.returncode, json.loads(res.stdout)


def test_init_apply_assembles_full_install() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        src = _write_source_pack(Path(tmp) / "src")
        root = _fresh_repo(Path(tmp) / "repo")
        rc, report = init_apply_cli(root, _decisions(src))
        assert rc == 0 and report["result"] == "applied", report
        # directive installed minus evals
        dest = root / ".governance/packs/acme/widgets/directives/no-console-log"
        assert (dest / "check.sh").is_file() and not (dest / "evals").exists()
        # CONSTITUTION assembled
        const = (root / "CONSTITUTION.md").read_text()
        assert "Ship receipts, not promises." in const and "### no-console-log" in const
        # runtime + workflow stamped
        assert "kit-version=" in (root / ".governance/run.sh").read_text().splitlines()[1]
        assert (root / ".github/workflows/governance.yml").is_file()
        # hooks + onboarding
        assert (root / ".githooks/pre-commit").is_file()
        assert (root / "scripts/enable-governance.sh").is_file()
        hookspath = subprocess.run(["git", "-C", str(root), "config", "--get", "core.hooksPath"],
                                   capture_output=True, text=True, env=GIT_CLEAN_ENV).stdout.strip()
        assert hookspath == ".githooks"
        # manifest + lock
        assert (root / ".governance/install.yaml").is_file()
        assert "acme/widgets" in (root / ".governance/packs.lock").read_text()
        # seeded asset + AGENTS stub
        assert (root / "WIDGETS.md").is_file() and "WIDGETS.md" in report["seeded_assets"]
        assert (root / "AGENTS.md").is_file() and report["agents_md"] == "stub created"
        assert "WIDGETS.md" in (root / ".governance/install.yaml").read_text()


def test_init_apply_refuses_existing_install() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        src = _write_source_pack(Path(tmp) / "src")
        root = _fresh_repo(Path(tmp) / "repo")
        (root / ".governance").mkdir()
        (root / ".governance/install.yaml").write_text('version: "3"\n')
        rc, report = init_apply_cli(root, _decisions(src))
        assert rc == 2 and "already installed" in report["reason"], report


def test_init_apply_refuses_collision() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        src = _write_source_pack(Path(tmp) / "src")
        root = _fresh_repo(Path(tmp) / "repo")
        d = _decisions(src)
        d["packs"].append({"id": "other/pack", "version": "0.1", "source": "local",
                           "pack_dir": str(src), "directives": ["no-console-log"]})
        rc, report = init_apply_cli(root, d)
        assert rc == 2 and "more than one pack" in report["reason"], report


def test_init_apply_dry_run_writes_nothing() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        src = _write_source_pack(Path(tmp) / "src")
        root = _fresh_repo(Path(tmp) / "repo")
        rc, report = init_apply_cli(root, _decisions(src), "--dry-run")
        assert rc == 0 and report["result"] == "dry-run", report
        assert not (root / "CONSTITUTION.md").exists()
        assert not (root / ".governance/packs").exists()


if __name__ == "__main__":
    failures = 0
    for name, fn in sorted(globals().items()):
        if not name.startswith("test_"):
            continue
        try:
            fn()
        except Exception as exc:  # noqa: BLE001
            failures += 1
            print(f"not ok - {name}: {exc}", file=sys.stderr)
        else:
            print(f"ok - {name}")
    raise SystemExit(1 if failures else 0)
