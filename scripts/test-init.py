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
    template = (ROOT / "kit/assets/CONSTITUTION.template.md").read_text()
    out = initplan.assemble_constitution(
        template, ["Ship receipts, not promises."],
        [("acme/widgets", ["### no-console-log\n\n- **Directive**: no console.log.\n"])])
    assert "Ship receipts, not promises." in out
    assert "### no-console-log" in out
    # the template example directive is replaced, not kept
    assert "### Example — constitution-exists" not in out
    # structure preserved
    assert "## Amendment process" in out and "## Evolution Log" in out


def test_assemble_constitution_groups_subsections_by_pack() -> None:
    template = (ROOT / "kit/assets/CONSTITUTION.template.md").read_text()
    out = initplan.assemble_constitution(
        template, [],
        [("acme/widgets", ["### widget-naming\n\n- **Directive**: x.\n",
                           "### widget-size\n\n- **Directive**: y.\n"]),
         ("acme/shapes", ["### no-shims\n\n- **Directive**: z.\n"])])
    # each pack gets a `## <owner>/<pack>` header, between `## Directives` and
    # `## Amendment process`, with its directives nested under it.
    assert "## acme/widgets" in out and "## acme/shapes" in out
    assert out.index("## Directives") < out.index("## acme/widgets") < out.index("## Amendment process")
    assert out.index("## acme/widgets") < out.index("### widget-naming") < out.index("## acme/shapes")
    assert out.index("## acme/shapes") < out.index("### no-shims") < out.index("## Amendment process")


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
    (ddir / "defaults.conf").write_text("# fixture defaults + docs\n# KEY=value\n")
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
        # directive installed minus evals; defaults.conf (live defaults + docs) ships
        dest = root / ".governance/packs/acme/widgets/directives/no-console-log"
        assert (dest / "check.sh").is_file() and not (dest / "evals").exists()
        assert (dest / "defaults.conf").is_file()
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
        # digests recorded for managed-tree-integrity (issue #253): a per-directive
        # `digest:` map in the lock entry, and a runtime `managed_digests:` block
        # in the manifest covering the stamped runtime files.
        lock_text = (root / ".governance/packs.lock").read_text()
        assert "digest:" in lock_text and "no-console-log:" in lock_text
        manifest_text = (root / ".governance/install.yaml").read_text()
        assert "managed_digests:" in manifest_text
        assert ".governance/run.sh:" in manifest_text and ".governance/lib.sh:" in manifest_text
        # seeded asset + AGENTS stub
        assert (root / "WIDGETS.md").is_file() and "WIDGETS.md" in report["seeded_assets"]
        assert (root / "AGENTS.md").is_file() and report["agents_md"] == "stub created"
        assert "WIDGETS.md" in (root / ".governance/install.yaml").read_text()
        # per-directive overlay seeded from the generic conf stub; reported, not ledgered
        conf = root / ".governance/conf/acme/widgets/no-console-log.conf"
        assert conf.is_file() and ".governance/conf/acme/widgets/no-console-log.conf" in report["conf_seeded"]
        # the seeded overlay is the generic stub — names the directive + points at its defaults.conf
        conf_text = conf.read_text()
        assert "no-console-log" in conf_text
        assert ".governance/packs/acme/widgets/directives/no-console-log/defaults.conf" in conf_text
        assert "no-console-log.conf" not in (root / ".governance/install.yaml").read_text()
        # the deleted hardcoded special case must not resurface
        assert not (root / ".governance/integrity.conf").exists()
        assert not (root / ".governance/freshness.conf").exists()


def test_init_apply_records_kit_provenance_when_supplied() -> None:
    # issue #194: when the flow's kit-resolve step threads `kit_provenance`, the
    # manifest records how `init` resolved the kit it installed from. Absent by
    # default (pre-#194 decisions) so existing fixtures are unaffected.
    with tempfile.TemporaryDirectory() as tmp:
        src = _write_source_pack(Path(tmp) / "src")
        root = _fresh_repo(Path(tmp) / "repo")
        d = _decisions(src)
        d["kit_provenance"] = "published-tag"
        rc, report = init_apply_cli(root, d)
        assert rc == 0 and report["result"] == "applied", report
        assert "kit_provenance: published-tag" in (root / ".governance/install.yaml").read_text()

    with tempfile.TemporaryDirectory() as tmp:
        src = _write_source_pack(Path(tmp) / "src")
        root = _fresh_repo(Path(tmp) / "repo")
        rc, report = init_apply_cli(root, _decisions(src))
        assert rc == 0 and "kit_provenance" not in (root / ".governance/install.yaml").read_text()


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


def _write_sweep_pack(base: Path, pack_id: str = "acme/shape", did: str = "no-shims") -> Path:
    pack = base / "shape"
    ddir = pack / "directives" / did
    (ddir / "evals").mkdir(parents=True)
    (pack / "pack.yaml").write_text(
        f"id: {pack_id}\nname: Shape\nversion: \"0.1\"\nmin_governance_kit: \"0.0.1\"\n"
        "description: test\nauthor: acme\nsource: gh\n")
    # surface: sweep ⇒ triage.sh, not check.sh; engine: llm; model_tier pinned.
    (ddir / "directive.yaml").write_text(
        "category: ArchitecturalShape\nrecommended: false\nsummary: no shims.\n"
        "surface: sweep\nhook: none\nengine: llm\nmodel_tier: high\n")
    (ddir / "triage.sh").write_text("#!/usr/bin/env bash\nexit 0\n")
    (ddir / "constitution.md").write_text(
        f"### {did}\n\n- **Directive**: no shims.\n"
        f"- **Enforced by**: `.governance/packs/{pack_id}/directives/{did}/triage.sh`\n")
    (ddir / "evals" / "test.sh").write_text("#!/usr/bin/env bash\nexit 0\n")
    (ddir / "triage.sh").chmod(0o755)
    (ddir / "evals" / "test.sh").chmod(0o755)
    return pack


def test_init_apply_vendors_sweep_lane() -> None:
    # issue #142: selecting a `surface: sweep` directive lays down the scheduled
    # workflow + the vendored engine, both recorded as seeded assets so uninstall
    # removes them. A non-sweep install must NOT carry them.
    with tempfile.TemporaryDirectory() as tmp:
        src = _write_sweep_pack(Path(tmp) / "src")
        root = _fresh_repo(Path(tmp) / "repo")
        d = _decisions(src)
        d["packs"] = [{"id": "acme/shape", "version": "0.1", "source": "gh",
                       "ref": "gh:acme/shape", "sha": "f" * 40, "subpath": "",
                       "pack_dir": str(src), "directives": ["no-shims"]}]
        rc, report = init_apply_cli(root, d)
        assert rc == 0 and report["result"] == "applied", report
        wf = root / ".github/workflows/governance-sweep.yml"
        eng = root / ".governance/sweep.py"
        assert wf.is_file() and "kit-version=" in wf.read_text().splitlines()[0]
        assert eng.is_file() and "kit-version=" in eng.read_text().splitlines()[1]
        assert os.access(eng, os.X_OK)
        assert ".github/workflows/governance-sweep.yml" in report["seeded_assets"]
        assert ".governance/sweep.py" in report["seeded_assets"]
        ledger = (root / ".governance/install.yaml").read_text()
        assert ".governance/sweep.py" in ledger
        # issue #259: the vendored sweep engine + its workflow are now first-class
        # managed runtime files — recorded in `managed_digests:` (a two-space
        # `  <relpath>: <sha>` row, distinct from the dashed `install_assets_seeded`
        # ledger row) so a hand-edit is caught offline by managed-tree-integrity,
        # exactly like run.sh/lib.sh.
        assert "\n  .governance/sweep.py: " in ledger, ledger
        assert "\n  .github/workflows/governance-sweep.yml: " in ledger, ledger

    # A plain (non-sweep) install must not vendor the sweep lane.
    with tempfile.TemporaryDirectory() as tmp:
        src = _write_source_pack(Path(tmp) / "src")
        root = _fresh_repo(Path(tmp) / "repo")
        rc, report = init_apply_cli(root, _decisions(src))
        assert rc == 0, report
        assert not (root / ".github/workflows/governance-sweep.yml").exists()
        assert not (root / ".governance/sweep.py").exists()


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
