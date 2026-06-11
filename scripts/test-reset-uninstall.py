#!/usr/bin/env python3
"""Contract tests for resetplan/resetapply and uninstallplan/uninstallapply —
the deterministic `reset` / `uninstall` engines (issue #172, phase 3).

`reset` runs in-process with `resetplan.fetch_ref` stubbed to a local pinned
source (no network); it drives the real folder restore, CONSTITUTION subsection
surgery, hook regeneration, and Evolution Log append. `uninstall` is fully
offline (manifest + marker driven) and runs through the CLI.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACK_LIB = ROOT / "kit" / "assets" / "packs" / "lib"
PACKVERB = PACK_LIB / "packverb.py"


def _load(name: str):
    sys.path.insert(0, str(PACK_LIB))
    spec = importlib.util.spec_from_file_location(name, PACK_LIB / f"{name}.py")
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


resetplan = _load("resetplan")
resetapply = _load("resetapply")

GIT_CLEAN_ENV = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}


def git(root: Path, *argv: str) -> None:
    subprocess.run(
        ["git", "-C", str(root), "-c", "user.email=t@t", "-c", "user.name=t",
         "-c", "commit.gpgsign=false", *argv],
        check=True, env=GIT_CLEAN_ENV, capture_output=True,
    )


PRISTINE_CHECK = "#!/usr/bin/env bash\n# pristine\nexit 0\n"
PRISTINE_SUBSECTION = "### no-console-log\n\n- **Directive**: pristine rule.\n"


def _write_pinned_source(base: Path) -> Path:
    pack = base / "widgets"
    ddir = pack / "directives" / "no-console-log"
    ddir.mkdir(parents=True)
    (pack / "pack.yaml").write_text("id: acme/widgets\nversion: \"0.1\"\nsource: gh\n")
    (ddir / "directive.yaml").write_text(
        "category: Quality\nrecommended: true\nsummary: x.\nsurface: change-set\nhook: pre-commit\n")
    (ddir / "check.sh").write_text(PRISTINE_CHECK)
    (ddir / "constitution.md").write_text(PRISTINE_SUBSECTION)
    return pack


LOCK = (
    'version: "2"\npacks:\n'
    "  - id: acme/widgets\n    version: \"0.1\"\n    source: gh\n"
    "    ref: gh:acme/widgets\n    sha: " + "e" * 40 + "\n    subpath: \"\"\n"
    "    directives:\n      - no-console-log\n"
)
INSTALL_YAML = (
    'version: "3"\nowner: acme\nrepo: demo\nhook_strategy: githooks\n'
    "constitution: true\nci_workflow: .github/workflows/governance.yml\ntests_dir: .governance\n"
    "install_assets_seeded: []\ncollisions: []\n"
)
CONST = (
    "# CONSTITUTION\n\n## Directives\n\n"
    "### no-console-log\n\n- **Directive**: DRIFTED rule.\n\n"
    "## Evolution Log\n\n<!-- hint -->\n\n- 2026-01-01 — old\n"
)


def _make_repo(tmp: Path, *, drifted: bool) -> Path:
    root = Path(tmp)
    g = root / ".governance"
    (g / "packs" / "acme" / "widgets" / "directives" / "no-console-log").mkdir(parents=True)
    (g / "install.yaml").write_text(INSTALL_YAML)
    (g / "packs.lock").write_text(LOCK)
    for fn in ("run.sh", "lib.sh"):
        src = ROOT / "kit" / "assets" / "dot-governance" / fn
        if src.is_file():
            (g / fn).write_text(src.read_text())
    ddir = g / "packs" / "acme" / "widgets" / "directives" / "no-console-log"
    (ddir / "directive.yaml").write_text(
        "category: Quality\nrecommended: true\nsummary: x.\nsurface: change-set\nhook: pre-commit\n")
    (ddir / "check.sh").write_text("#!/usr/bin/env bash\n# DRIFTED\nexit 1\n" if drifted else PRISTINE_CHECK)
    (ddir / "constitution.md").write_text(PRISTINE_SUBSECTION)
    (root / "CONSTITUTION.md").write_text(CONST)
    git(root, "init", "-q")
    git(root, "add", "-A")
    git(root, "commit", "-qm", "fixture")
    return root


def _ns(**kw):
    base = dict(scope="all", root=None, target=None, drop_handauthored=False,
                dry_run=False, force=False, date=None, author=None)
    base.update(kw)
    return argparse.Namespace(**base)


def _capture(fn):
    import io
    import contextlib
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        rc = fn()
    return rc, json.loads(buf.getvalue().strip())


def test_reset_restores_drifted_directive_and_subsection() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        src = _write_pinned_source(Path(tmp) / "src")
        root = _make_repo(Path(tmp) / "repo", drifted=True)
        # a user overlay exists; reset restores the pinned folder but must never
        # touch the user-owned .governance/conf/.
        conf = root / ".governance/conf/acme/widgets/no-console-log.conf"
        conf.parent.mkdir(parents=True, exist_ok=True)
        conf.write_text("USER=tweak\n")
        git(root, "add", "-A")
        git(root, "commit", "-qm", "seed user conf")
        resetplan.fetch_ref = lambda ref, cache_dir=None: {
            "sha": "e" * 40, "pack_dir": str(src), "cache_dir": str(src.parent), "id": "acme/widgets"}
        rc, report = _capture(lambda: resetapply.cmd_reset_apply(
            _ns(scope="all", root=str(root), date="2026-06-10", author="srikanth")))
        assert rc == 0 and report["result"] == "applied", report
        assert report["restored"] == ["no-console-log"]
        # the user overlay is left exactly as it was
        assert conf.read_text() == "USER=tweak\n"
        # folder restored to pristine
        assert (root / ".governance/packs/acme/widgets/directives/no-console-log/check.sh").read_text() == PRISTINE_CHECK
        # CONSTITUTION subsection restored
        const = (root / "CONSTITUTION.md").read_text()
        assert "pristine rule" in const and "DRIFTED" not in const
        # evolution log appended
        assert "Reset directives from `acme/widgets`" in const
        assert report["evolution_log"] == "appended"
        assert report["hook_dispatcher"] == "regenerated"


def test_reset_skips_pristine_directive() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        src = _write_pinned_source(Path(tmp) / "src")
        root = _make_repo(Path(tmp) / "repo", drifted=False)
        resetplan.fetch_ref = lambda ref, cache_dir=None: {
            "sha": "e" * 40, "pack_dir": str(src), "cache_dir": str(src.parent), "id": "acme/widgets"}
        rc, report = _capture(lambda: resetapply.cmd_reset_apply(
            _ns(scope="all", root=str(root), date="2026-06-10")))
        assert rc == 0 and report["result"] == "applied", report
        assert report["skipped"] == ["no-console-log"] and report["restored"] == []


def test_reset_refuses_missing_lockfile() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = _make_repo(Path(tmp) / "repo", drifted=True)
        (root / ".governance" / "packs.lock").unlink()
        rc, report = _capture(lambda: resetapply.cmd_reset_apply(_ns(scope="all", root=str(root))))
        assert rc == 2 and "lockfile-driven" in report["reason"], report


def test_reset_refuses_unknown_directive() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = _make_repo(Path(tmp) / "repo", drifted=True)
        rc, report = _capture(lambda: resetapply.cmd_reset_apply(
            _ns(scope="directive", root=str(root), target="nope")))
        assert rc == 2 and "not in any" in report["reason"], report


def test_reset_refuses_dirty_tree_unless_forced() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        src = _write_pinned_source(Path(tmp) / "src")
        root = _make_repo(Path(tmp) / "repo", drifted=True)
        (root / "wip.txt").write_text("uncommitted\n")
        resetplan.fetch_ref = lambda ref, cache_dir=None: {
            "sha": "e" * 40, "pack_dir": str(src), "cache_dir": str(src.parent), "id": "acme/widgets"}
        rc, report = _capture(lambda: resetapply.cmd_reset_apply(_ns(scope="all", root=str(root))))
        assert rc == 2 and "uncommitted" in report["reason"], report
        rc, report = _capture(lambda: resetapply.cmd_reset_apply(
            _ns(scope="all", root=str(root), force=True, date="2026-06-10")))
        assert rc == 0 and any("--force" in a for a in report["assumptions"]), report


def test_reset_dry_run_writes_nothing() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        src = _write_pinned_source(Path(tmp) / "src")
        root = _make_repo(Path(tmp) / "repo", drifted=True)
        before = (root / ".governance/packs/acme/widgets/directives/no-console-log/check.sh").read_text()
        resetplan.fetch_ref = lambda ref, cache_dir=None: {
            "sha": "e" * 40, "pack_dir": str(src), "cache_dir": str(src.parent), "id": "acme/widgets"}
        rc, report = _capture(lambda: resetapply.cmd_reset_apply(
            _ns(scope="all", root=str(root), dry_run=True)))
        assert rc == 0 and report["result"] == "dry-run", report
        assert report["restored"] == ["no-console-log"]
        assert (root / ".governance/packs/acme/widgets/directives/no-console-log/check.sh").read_text() == before


# --- uninstall (offline, via CLI) ------------------------------------------

HOOK_MARKED = "#!/usr/bin/env bash\n# governance-kit:managed kit-version=0.4.0\nexit 0\n"
AGENTS = (
    "# AGENTS\n\nIntro paragraph.\n\n"
    "<!-- governance: directives-to-follow -->\nRead CONSTITUTION.md and follow it.\n"
    "<!-- /governance: directives-to-follow -->\n\n## Other\n\nuser content\n"
)


def _make_installed_repo(tmp: Path, *, manifest: bool = True, marked_hooks: bool = True,
                         collision: bool = False, seeded: bool = True) -> Path:
    root = Path(tmp)
    g = root / ".governance"
    (g / "packs" / "acme" / "widgets" / "directives" / "no-console-log").mkdir(parents=True)
    seeded_line = "install_assets_seeded:\n  - QUALITY.md\n" if seeded else "install_assets_seeded: []\n"
    if manifest:
        (g / "install.yaml").write_text(
            'version: "3"\nowner: acme\nrepo: demo\nhook_strategy: githooks\n'
            "constitution: true\nci_workflow: .github/workflows/governance.yml\ntests_dir: .governance\n"
            "enable_governance_script: scripts/enable-governance.sh\n"
            "agents_md_snippet: true\nagents_md_created: false\n" + seeded_line + "collisions: []\n")
        (g / "packs.lock").write_text(LOCK)
    for fn in ("run.sh", "lib.sh"):
        src = ROOT / "kit" / "assets" / "dot-governance" / fn
        if src.is_file():
            (g / fn).write_text(src.read_text())
    (root / "CONSTITUTION.md").write_text(CONST)
    (root / ".github" / "workflows").mkdir(parents=True)
    (root / ".github/workflows/governance.yml").write_text("# governance-kit:managed kit-version=0.4.0\nname: g\n")
    (root / "scripts").mkdir()
    (root / "scripts/enable-governance.sh").write_text("#!/usr/bin/env bash\n# governance-kit:managed kit-version=0.4.0\n")
    hookdir = root / ".githooks"
    hookdir.mkdir()
    for kind in ("pre-commit", "commit-msg"):
        (hookdir / kind).write_text(HOOK_MARKED if (marked_hooks and not collision) else "#!/usr/bin/env bash\nexit 0\n")
    (root / "AGENTS.md").write_text(AGENTS)
    if seeded:
        (root / "QUALITY.md").write_text("# Quality (user-edited)\n")
    (root / "stale.pre-governance.bak").write_text("backup\n")
    git(root, "init", "-q")
    git(root, "add", "-A")
    git(root, "commit", "-qm", "fixture")
    git(root, "config", "core.hooksPath", ".githooks")
    return root


def uninstall_cli(root: Path, *argv: str):
    res = subprocess.run(
        [sys.executable, str(PACKVERB), "uninstall-apply", str(root), *argv],
        cwd=ROOT, check=False, text=True, env=GIT_CLEAN_ENV,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    assert res.stdout.strip(), res.stderr
    return res.returncode, json.loads(res.stdout)


def test_uninstall_soft_removes_managed_preserves_seeded() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = _make_installed_repo(Path(tmp))
        rc, report = uninstall_cli(root, "--mode", "soft")
        assert rc == 0 and report["result"] == "applied", report
        assert not (root / "CONSTITUTION.md").exists()
        assert not (root / ".governance").exists()
        assert not (root / ".github/workflows/governance.yml").exists()
        assert not (root / ".githooks/pre-commit").exists()
        # AGENTS block stripped, user content kept
        agents = (root / "AGENTS.md").read_text()
        assert "directives-to-follow" not in agents and "user content" in agents
        assert report["agents_md"].startswith("directive block stripped")
        # soft: seeded + backup preserved
        assert (root / "QUALITY.md").is_file()
        assert (root / "stale.pre-governance.bak").is_file()
        assert "QUALITY.md" in report["preserved"]
        # core.hooksPath unset
        assert report["git_config"] == "core.hooksPath unset"


def test_uninstall_hard_removes_seeded_and_backups() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = _make_installed_repo(Path(tmp))
        rc, report = uninstall_cli(root, "--mode", "hard")
        assert rc == 0, report
        assert not (root / "QUALITY.md").exists()
        assert not (root / "stale.pre-governance.bak").exists()
        assert "QUALITY.md" in report["deleted"]


def test_uninstall_dry_run_writes_nothing() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = _make_installed_repo(Path(tmp))
        rc, report = uninstall_cli(root, "--mode", "dry-run")
        assert rc == 0 and report["result"] == "dry-run", report
        assert (root / "CONSTITUTION.md").is_file() and (root / ".governance").is_dir()
        assert "CONSTITUTION.md" in report["deleted"]  # would-delete


def test_uninstall_none_detected_is_noop() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        root.mkdir(exist_ok=True)
        git(root, "init", "-q")
        (root / "README.md").write_text("hi\n")
        git(root, "add", "-A")
        git(root, "commit", "-qm", "x")
        rc, report = uninstall_cli(root, "--mode", "soft")
        assert rc == 0 and report["result"] == "none-detected", report


def test_uninstall_refuses_unmarked_collision() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = _make_installed_repo(Path(tmp), collision=True)
        rc, report = uninstall_cli(root, "--mode", "soft")
        assert rc == 2 and "no governance-kit marker" in report["reason"], report
        assert (root / "CONSTITUTION.md").is_file()  # nothing deleted


def test_uninstall_heuristic_refuses_without_optin() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = _make_installed_repo(Path(tmp), manifest=False)
        rc, report = uninstall_cli(root, "--mode", "soft")
        assert rc == 2 and "explicit opt-in" in report["reason"], report
        # dry-run still allowed
        rc, report = uninstall_cli(root, "--mode", "dry-run")
        assert rc == 0 and report["source_of_truth"] == "heuristic", report
        # explicit opt-in proceeds
        rc, report = uninstall_cli(root, "--mode", "soft", "--allow-heuristic")
        assert rc == 0 and report["result"] == "applied", report


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
