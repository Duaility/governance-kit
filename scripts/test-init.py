#!/usr/bin/env python3
"""Contract tests for initplan/initapply — the deterministic `init` engine
(issue #172, phase 4). Pure functions (collision detection, CONSTITUTION
assembly) plus an end-to-end `init-apply` against a throwaway git repo with a
local source pack (no network)."""

from __future__ import annotations

import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACK_LIB = ROOT / "kit" / "assets" / "packs" / "lib"
PACKVERB = PACK_LIB / "packverb.py"
MTI_DIR = ROOT / "packs/foundation/directives/managed-tree-integrity"


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
        # hooks + onboarding: dispatchers generated, core.hooksPath set by the
        # verb itself (no vendored enable-governance.sh anymore — issue #267)
        assert (root / ".githooks/pre-commit").is_file()
        assert not (root / "scripts/enable-governance.sh").exists()
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
        # issue #267: the manifest no longer records the de-vendored enable script,
        # and the local-only hook dispatchers are NOT in the digest set (so Wrap
        # can append to / replace them without tripping managed-tree-integrity).
        assert "enable_governance_script" not in manifest_text
        assert ".githooks/" not in manifest_text
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


def test_init_apply_wrap_collision_then_commit_is_clean() -> None:
    # issue #267: a repo that already carries its own pre-commit adopts governance
    # via the documented Wrap flow — stash the existing hook as <kind>.userhook,
    # generate ours, then exec the userhook at the end of the generated hook.
    # Because the local-only dispatchers are no longer in the digest set, the
    # post-wrap edits (a new exec line + the .userhook file) do NOT trip
    # managed-tree-integrity. Closes the dogfood gap (this repo has no collision).
    with tempfile.TemporaryDirectory() as tmp:
        src = _write_source_pack(Path(tmp) / "src")
        root = _fresh_repo(Path(tmp) / "repo")
        # Pre-existing, unmarked hook is the collision the operator hits; Wrap
        # step 1 (before init-apply) stashes it as the .userhook.
        hooks = root / ".githooks"
        hooks.mkdir()
        (hooks / "pre-commit.userhook").write_text("#!/usr/bin/env bash\necho user-hook\n")

        rc, report = init_apply_cli(root, _decisions(src))
        assert rc == 0 and report["result"] == "applied", report

        # The generated dispatcher exists but is NOT in the recorded digest set,
        # and neither is the stashed .userhook.
        manifest = (root / ".governance/install.yaml").read_text()
        assert ".githooks/" not in manifest
        gen = root / ".githooks/pre-commit"
        assert gen.is_file()

        # Wrap step 2 (after init-apply): exec the stashed hook at the end of the
        # generated one — the exact edit that, under the old digest behavior,
        # diverged the on-disk hook from its recorded digest and hard-failed.
        gen.write_text(gen.read_text() + '\nexec "$(dirname "$0")/pre-commit.userhook" "$@"\n')

        # managed-tree-integrity reports nothing: dispatchers + .userhook are out
        # of scope; the recorded runtime files + directive folders are intact.
        # The check is pure bash since #355 and expects to run from its
        # installed .governance path, so install the source copy into the
        # fixture (the fixture's .governance/lib.sh exists from init-apply).
        installed = root / ".governance/packs/governance-kit/foundation/directives/managed-tree-integrity"
        (installed / "lib").mkdir(parents=True)
        shutil.copy2(MTI_DIR / "check.sh", installed / "check.sh")
        shutil.copy2(MTI_DIR / "lib" / "digest.sh", installed / "lib" / "digest.sh")
        proc = subprocess.run(
            ["bash", str(installed / "check.sh")],
            cwd=root, text=True, capture_output=True, env=GIT_CLEAN_ENV)
        assert proc.returncode == 0, (
            f"unexpected integrity violations after Wrap:\n{proc.stdout}\n{proc.stderr}")


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


def _write_judge_pack(base: Path, pack_id: str = "acme/shape", did: str = "no-shims") -> Path:
    """A discovery source pack (issue #355) with a `judge:` block and no
    `section:` key — re-adjudicated by the scheduled lane's driver
    (`.governance/schedule.sh`), not by a commit-lane check.sh."""
    pack = base / "shape"
    ddir = pack / "directives" / did
    (ddir / "evals").mkdir(parents=True)
    (pack / "pack.yaml").write_text(
        f"id: {pack_id}\nname: Shape\nversion: \"0.1\"\nmin_governance_kit: \"0.0.1\"\n"
        "description: test\nauthor: acme\nsource: gh\n")
    (ddir / "directive.yaml").write_text(
        "category: ArchitecturalShape\nrecommended: false\nsummary: no shims.\n"
        "surface: repo-state\nhook: none\n"
        "judge:\n  inputs: [range-diff]\n  checks:\n    - no shims\n")
    (ddir / "constitution.md").write_text(
        f"### {did}\n\n- **Directive**: no shims.\n"
        f"- **Enforced by**: the scheduled-lane driver `.governance/schedule.sh`, "
        f"re-adjudicating the `judge:` block declared in "
        f".governance/packs/{pack_id}/directives/{did}/directive.yaml\n")
    (ddir / "evals" / "test.sh").write_text("#!/usr/bin/env bash\nexit 0\n")
    (ddir / "evals" / "test.sh").chmod(0o755)
    return pack


def test_init_apply_lays_down_schedule_runtime() -> None:
    # issue #355 (schedule redesign): `.governance/schedule.sh` (renamed from
    # the retired sweep.sh) is an unconditional runtime file, copied and
    # digested on every install exactly like run.sh/lib.sh — regardless of
    # whether any installed directive has a `judge:` block. No workflow file
    # is auto-created; a schedule-lane workflow is only created explicitly via
    # `governance schedule create`.
    with tempfile.TemporaryDirectory() as tmp:
        src = _write_judge_pack(Path(tmp) / "src")
        root = _fresh_repo(Path(tmp) / "repo")
        d = _decisions(src)
        d["packs"] = [{"id": "acme/shape", "version": "0.1", "source": "gh",
                       "ref": "gh:acme/shape", "sha": "f" * 40, "subpath": "",
                       "pack_dir": str(src), "directives": ["no-shims"]}]
        rc, report = init_apply_cli(root, d)
        assert rc == 0 and report["result"] == "applied", report
        drv = root / ".governance/schedule.sh"
        assert drv.is_file() and "kit-version=" in drv.read_text().splitlines()[1]
        assert os.access(drv, os.X_OK)
        # No workflow is auto-created, and schedule.sh is a managed runtime
        # file (managed_digests), not a one-time seeded asset.
        assert ".governance/schedule.sh" not in report.get("seeded_assets", [])
        assert not (root / ".github/workflows/governance-sweep.yml").exists()
        assert not list((root / ".github/workflows").glob("governance-schedule-*.yml"))
        ledger = (root / ".governance/install.yaml").read_text()
        assert "\n  .governance/schedule.sh: " in ledger, ledger

    # A plain install (no judge-block directive at all) still lays down
    # schedule.sh unconditionally, same as run.sh/lib.sh.
    with tempfile.TemporaryDirectory() as tmp:
        src = _write_source_pack(Path(tmp) / "src")
        root = _fresh_repo(Path(tmp) / "repo")
        rc, report = init_apply_cli(root, _decisions(src))
        assert rc == 0, report
        assert (root / ".governance/schedule.sh").is_file()
        assert not (root / ".github/workflows/governance-sweep.yml").exists()
        assert not list((root / ".github/workflows").glob("governance-schedule-*.yml"))


def test_init_apply_seeds_the_runtime_adapter_registry() -> None:
    # issue #355: `.governance/runtimes/<harness>.sh` is a kit-managed runtime
    # file, laid down by every install regardless of which directives were
    # selected — "which harness is running" is a property of the repo, and both
    # the accounting lane (`cost`) and a `cli:` executor (`judge`) resolve an
    # adapter by name at that fixed path. Stamped, executable, and digested
    # exactly like run.sh / lib.sh, so a hand-edit is caught offline.
    with tempfile.TemporaryDirectory() as tmp:
        src = _write_source_pack(Path(tmp) / "src")
        root = _fresh_repo(Path(tmp) / "repo")
        rc, report = init_apply_cli(root, _decisions(src))
        assert rc == 0 and report["result"] == "applied", report
        registry = root / ".governance" / "runtimes"
        adapters = sorted(p.name for p in registry.glob("*.sh"))
        assert adapters, "no runtime adapters seeded"
        assert {"claude-code.sh", "codex.sh", "manual.sh"} <= set(adapters), adapters
        ledger = (root / ".governance/install.yaml").read_text()
        for name in adapters:
            adapter = registry / name
            assert os.access(adapter, os.X_OK), name
            assert "kit-version=" in adapter.read_text().splitlines()[1], name
            assert f"\n  .governance/runtimes/{name}: " in ledger, (name, ledger)


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
