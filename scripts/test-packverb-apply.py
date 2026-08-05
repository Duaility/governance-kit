#!/usr/bin/env python3
"""Contract tests for packplan.py / packapply.py — the deterministic
`pack-plan` / `pack-apply` pair for `governance pack {add,update,remove}` (#172).

`remove` is exercised end-to-end through the CLI (fully offline: it reads only
the lockfile + CONSTITUTION.md). `add` / `update` need a pack fetch, so they run
in-process with `packplan.fetch_ref` stubbed to a local source tree — no network
— which still drives the real install.sh copy, hook regeneration, lockfile
upsert, and CONSTITUTION surgery.
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
    # Register before exec so a sibling's `from packplan import …` reuses THIS
    # instance — letting the in-process tests stub `packplan.fetch_ref`.
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


packplan = _load("packplan")
packapply = _load("packapply")

GIT_CLEAN_ENV = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}


def git(root: Path, *argv: str) -> None:
    subprocess.run(
        ["git", "-C", str(root), "-c", "user.email=t@t", "-c", "user.name=t",
         "-c", "commit.gpgsign=false", *argv],
        check=True, env=GIT_CLEAN_ENV, capture_output=True,
    )


INSTALL_YAML = (
    'version: "3"\n'
    "owner: acme\nrepo: demo\n"
    "hook_strategy: githooks\n"
    "constitution: true\n"
    "ci_workflow: .github/workflows/governance.yml\n"
    "tests_dir: .governance\n"
    "install_assets_seeded: []\n"
    "collisions: []\n"
)


def _write_source_pack(base: Path, pack_id: str = "acme/widgets") -> Path:
    """A minimal valid source pack with one directive + one install-asset."""
    pack = base / "widgets"
    did = "no-console-log"
    ddir = pack / "directives" / did
    (ddir / "evals").mkdir(parents=True)
    (ddir / "install-assets").mkdir(parents=True)
    (pack / "pack.yaml").write_text(
        f"id: {pack_id}\nname: Widgets\nversion: \"0.1\"\n"
        "min_governance_kit: \"0.0.1\"\ndescription: test pack\nauthor: acme\n"
        "source: gh\n"
    )
    (ddir / "directive.yaml").write_text(
        "category: Quality\nrecommended: true\n"
        "summary: no console.log in tracked files.\n"
        "surface: change-set\nhook: pre-commit\n"
    )
    (ddir / "check.sh").write_text("#!/usr/bin/env bash\nexit 0\n")
    (ddir / "constitution.md").write_text(
        f"### {did}\n\n- **Directive**: No `console.log` in tracked source.\n"
        f"- **Enforced by**: `.governance/packs/{pack_id}/directives/{did}/check.sh`\n"
    )
    (ddir / "evals" / "test.sh").write_text("#!/usr/bin/env bash\nexit 0\n")
    (ddir / "install-assets" / "WIDGETS.md").write_text("# Widgets doc\n")
    (ddir / "defaults.conf").write_text("# fixture defaults + docs\n# KEY=value\n")
    (ddir / "check.sh").chmod(0o755)
    (ddir / "evals" / "test.sh").chmod(0o755)
    return pack


def _write_judge_source_pack(base: Path, pack_id: str = "acme/shape", did: str = "no-shims") -> Path:
    """A minimal valid discovery source pack (issue #355): a `judge:` block
    with no `section:` — no commit-lane gate, no check.sh — re-adjudicated by
    the scheduled lane's driver (`.governance/schedule.sh`) against the range
    diff, when a consumer explicitly wires it into a schedule workflow."""
    pack = base / "shape"
    ddir = pack / "directives" / did
    (ddir / "evals").mkdir(parents=True)
    (pack / "pack.yaml").write_text(
        f"id: {pack_id}\nname: Shape\nversion: \"0.1\"\nmin_governance_kit: \"0.0.1\"\n"
        "description: test\nauthor: acme\nsource: gh\n")
    (ddir / "directive.yaml").write_text(
        "category: ArchitecturalShape\nrecommended: false\nsummary: no shims.\n"
        "surface: repo-state\nhook: none\n"
        "judge:\n  inputs: [range-diff]\n  checks:\n    - no shims\n"
        "  group: shape-intent\n")
    (ddir / "constitution.md").write_text(
        f"### {did}\n\n- **Directive**: no shims.\n"
        f"- **Enforced by**: the scheduled-lane driver `.governance/schedule.sh`, "
        f"re-adjudicating the `judge:` block declared in "
        f".governance/packs/{pack_id}/directives/{did}/directive.yaml\n")
    (ddir / "evals" / "test.sh").write_text("#!/usr/bin/env bash\nexit 0\n")
    (ddir / "evals" / "test.sh").chmod(0o755)
    return pack


def _make_repo(tmp: Path, *, constitution: str | None = None,
               lock: str | None = None, installed_directive: str | None = None) -> Path:
    root = Path(tmp)
    (root / ".governance").mkdir(parents=True)
    (root / ".governance" / "install.yaml").write_text(INSTALL_YAML)
    (root / ".governance" / "packs.lock").write_text(lock or 'version: "2"\npacks: []\n')
    # ship run.sh/lib.sh so the smoke test + hook discovery have a runtime
    for fn in ("run.sh", "lib.sh"):
        src = ROOT / "kit" / "assets" / "dot-governance" / fn
        if src.is_file():
            (root / ".governance" / fn).write_text(src.read_text())
    if constitution is not None:
        (root / "CONSTITUTION.md").write_text(constitution)
    if installed_directive is not None:
        ddir = root / installed_directive
        ddir.mkdir(parents=True)
        (ddir / "directive.yaml").write_text(
            "category: Quality\nrecommended: true\nsummary: x.\n"
            "surface: change-set\nhook: pre-commit\n")
        (ddir / "check.sh").write_text("#!/usr/bin/env bash\nexit 0\n")
        (ddir / "constitution.md").write_text("### no-console-log\n\nbody\n")
    git(root, "init", "-q")
    git(root, "add", "-A")
    git(root, "commit", "-qm", "fixture")
    return root


def _ns(**kw):
    base = dict(mode="add", root=None, target=None, decisions=None, dry_run=False, force=False)
    base.update(kw)
    return argparse.Namespace(**base)


def _stub_fetch(pack_dir: Path, pack_id: str, sha: str):
    def fake(ref, cache_dir=None):
        return {"sha": sha, "pack_dir": str(pack_dir), "cache_dir": str(pack_dir.parent), "id": pack_id}
    return fake


def _capture(fn):
    """Run an in-process command, returning (rc, parsed_report)."""
    import io
    import contextlib
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        rc = fn()
    out = buf.getvalue().strip()
    return rc, json.loads(out)


# Pure docsurgery transforms (strip/upsert/render/evolution-log) are unit-tested
# in scripts/test-docsurgery.py; this file owns the pack-plan/apply integration.


# --- pack-plan / pack-apply: add -------------------------------------------

def test_add_installs_directive_lock_and_hooks() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        src = _write_source_pack(Path(tmp) / "src")
        root = _make_repo(Path(tmp) / "repo")
        packplan.fetch_ref = _stub_fetch(src, "acme/widgets", "a" * 40)
        rc, report = _capture(lambda: packapply.cmd_pack_apply(
            _ns(mode="add", root=str(root), target="gh:acme/widgets")))
        assert rc == 0 and report["result"] == "applied", report
        assert report["added"] == [".governance/packs/acme/widgets/directives/no-console-log"]
        dest = root / ".governance/packs/acme/widgets/directives/no-console-log"
        assert (dest / "check.sh").is_file()
        assert not (dest / "evals").exists()  # evals never shipped
        # install-asset seeded + ledgered
        assert (root / "WIDGETS.md").is_file()
        assert report["seeded_assets"] == ["WIDGETS.md"]
        assert "WIDGETS.md" in (root / ".governance/install.yaml").read_text()
        # per-directive overlay seeded from the generic conf stub; reported, not ledgered
        conf = root / ".governance/conf/acme/widgets/no-console-log.conf"
        assert conf.is_file()
        conf_text = conf.read_text()
        assert "no-console-log" in conf_text
        assert ".governance/packs/acme/widgets/directives/no-console-log/defaults.conf" in conf_text
        assert report["conf_seeded"] == [".governance/conf/acme/widgets/no-console-log.conf"]
        assert "no-console-log.conf" not in (root / ".governance/install.yaml").read_text()
        # lock upserted
        lock = (root / ".governance/packs.lock").read_text()
        assert "acme/widgets" in lock and "a" * 40 in lock
        assert report["hook_dispatcher"] == "regenerated"
        assert (root / ".githooks/pre-commit").is_file()


def test_update_does_not_reseed_user_conf() -> None:
    """A second apply (update) must never overwrite or resurrect the user conf,
    and the plan flags config drift when defaults.conf changes."""
    with tempfile.TemporaryDirectory() as tmp:
        src = _write_source_pack(Path(tmp) / "src")
        root = _make_repo(Path(tmp) / "repo")
        packplan.fetch_ref = _stub_fetch(src, "acme/widgets", "a" * 40)
        # initial add seeds the conf
        _capture(lambda: packapply.cmd_pack_apply(
            _ns(mode="add", root=str(root), target="gh:acme/widgets")))
        conf = root / ".governance/conf/acme/widgets/no-console-log.conf"
        conf.write_text("USER=tweak\n")  # the user customizes it
        # commit the install + customization so the tree is clean for update
        git(root, "add", "-A")
        git(root, "commit", "-qm", "install + customize")

        # the upstream ships a new defaults.conf at a new sha
        (src / "directives" / "no-console-log" / "defaults.conf").write_text(
            "# fixture defaults + docs v2\n# KEY=value\n# NEWKEY=\n")
        packplan.fetch_ref = _stub_fetch(src, "acme/widgets", "f" * 40)

        # plan: the directive is an update and flags config drift
        plan = packplan.compute_pack_plan(root, "update", None, with_diff=False)
        d = plan["packs"][0]["directives"][0]
        assert d["status"] == "update" and d["config_drift"] is True, d
        assert d["user_conf"] == ".governance/conf/acme/widgets/no-console-log.conf"
        assert d["user_conf_present"] is True

        # apply update: conf untouched, not re-seeded
        rc, report = _capture(lambda: packapply.cmd_pack_apply(
            _ns(mode="update", root=str(root), target=None)))
        assert rc == 0 and report["result"] == "applied", report
        assert conf.read_text() == "USER=tweak\n"
        assert report["conf_seeded"] == []
        # the pack-owned defaults.conf was refreshed in the installed tree
        installed_defaults = root / ".governance/packs/acme/widgets/directives/no-console-log/defaults.conf"
        assert "v2" in installed_defaults.read_text()


def test_add_dry_run_writes_nothing() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        src = _write_source_pack(Path(tmp) / "src")
        root = _make_repo(Path(tmp) / "repo")
        packplan.fetch_ref = _stub_fetch(src, "acme/widgets", "b" * 40)
        rc, report = _capture(lambda: packapply.cmd_pack_apply(
            _ns(mode="add", root=str(root), target="gh:acme/widgets", dry_run=True)))
        assert rc == 0 and report["result"] == "dry-run", report
        assert not (root / ".governance/packs/acme/widgets").exists()
        assert "acme/widgets" not in (root / ".governance/packs.lock").read_text()
        assert report["added"]  # the plan still reports what *would* install


def test_add_refuses_capability_violation() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        src = _write_source_pack(Path(tmp) / "src")
        ddir = src / "directives" / "no-console-log"
        # declare a writes glob then reference a path outside it
        (ddir / "directive.yaml").write_text(
            (ddir / "directive.yaml").read_text() + 'writes:\n  - "src/**"\n')
        (ddir / "check.sh").write_text("#!/usr/bin/env bash\ncat \"/etc/passwd\"\n")
        (ddir / "check.sh").chmod(0o755)
        root = _make_repo(Path(tmp) / "repo")
        packplan.fetch_ref = _stub_fetch(src, "acme/widgets", "c" * 40)
        rc, report = _capture(lambda: packapply.cmd_pack_apply(
            _ns(mode="add", root=str(root), target="gh:acme/widgets")))
        assert rc == 2 and "capability" in report["reason"], report
        assert not (root / ".governance/packs/acme/widgets").exists()


def test_add_held_back_directive_via_decisions() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        src = _write_source_pack(Path(tmp) / "src")
        root = _make_repo(Path(tmp) / "repo")
        packplan.fetch_ref = _stub_fetch(src, "acme/widgets", "d" * 40)
        rc, report = _capture(lambda: packapply.cmd_pack_apply(
            _ns(mode="add", root=str(root), target="gh:acme/widgets",
                decisions='{"no-console-log": "skip"}')))
        assert rc == 0, report
        assert report["held_back"] == ["no-console-log"]
        assert not (root / ".governance/packs/acme/widgets").exists()


def test_add_judge_directive_seeds_no_schedule_lane() -> None:
    # issue #355 (schedule redesign): `pack add` of a directive carrying a
    # `judge:` block must NOT auto-vendor a schedule workflow or the
    # `.governance/schedule.sh` driver — that's the retired sweep-lane
    # behavior. `schedule.sh` is copied unconditionally at init time only
    # (like run.sh/lib.sh); pack add/update never touches kit runtime files,
    # and a schedule-lane workflow is only ever created explicitly via
    # `governance schedule create` (packverb.py schedule-apply).
    with tempfile.TemporaryDirectory() as tmp:
        src = _write_judge_source_pack(Path(tmp) / "src")
        root = _make_repo(Path(tmp) / "repo")
        packplan.fetch_ref = _stub_fetch(src, "acme/shape", "c" * 40)
        rc, report = _capture(lambda: packapply.cmd_pack_apply(
            _ns(mode="add", root=str(root), target="gh:acme/shape")))
        assert rc == 0 and report["result"] == "applied", report
        assert not (root / ".governance/schedule.sh").exists()
        assert not (root / ".github/workflows/governance-sweep.yml").exists()
        assert not list((root / ".github/workflows").glob("governance-schedule-*.yml"))
        assert ".governance/schedule.sh" not in report["seeded_assets"]
        ledger = (root / ".governance/install.yaml").read_text()
        assert ".governance/schedule.sh" not in ledger
        assert ".github/workflows/governance-sweep.yml" not in ledger


def test_add_held_back_judge_directive_seeds_nothing() -> None:
    # Held back or installed, a judge-block directive never pulls in a
    # schedule workflow or driver via pack add.
    with tempfile.TemporaryDirectory() as tmp:
        src = _write_judge_source_pack(Path(tmp) / "src")
        root = _make_repo(Path(tmp) / "repo")
        packplan.fetch_ref = _stub_fetch(src, "acme/shape", "c" * 40)
        rc, report = _capture(lambda: packapply.cmd_pack_apply(
            _ns(mode="add", root=str(root), target="gh:acme/shape",
                decisions='{"no-shims": "skip"}')))
        assert rc == 0, report
        assert report["held_back"] == ["no-shims"]
        assert not (root / ".governance/schedule.sh").exists()
        assert not (root / ".github/workflows/governance-sweep.yml").exists()
        assert report["seeded_assets"] == []


# `## Directives` with no `no-console-log` entry → add INSERTs (GDD: init
# assembles, remove strips, add inserts; missing-file guard covered by add_installs_*).
_CONST_SKELETON = (
    "# CONSTITUTION\n\n## Directives\n\n### required-docs\n\n- body\n\n"
    "## Evolution Log\n\n- 2026-01-01 — seed\n"
)


def test_add_upserts_constitution_subsection() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        src = _write_source_pack(Path(tmp) / "src")
        root = _make_repo(Path(tmp) / "repo", constitution=_CONST_SKELETON)
        packplan.fetch_ref = _stub_fetch(src, "acme/widgets", "a" * 40)
        rc, report = _capture(lambda: packapply.cmd_pack_apply(
            _ns(mode="add", root=str(root), target="gh:acme/widgets")))
        assert rc == 0 and report["result"] == "applied", report
        text = (root / "CONSTITUTION.md").read_text()
        assert text.count("### no-console-log") == 1
        assert text.index("### no-console-log") < text.index("## Evolution Log")
        assert "### required-docs" in text  # existing entry untouched
        # pack-group-aware: the subsection lands under a `## acme/widgets` header.
        assert "## acme/widgets" in text
        assert text.index("## acme/widgets") < text.index("### no-console-log")
        assert report["constitution_upserted"] == ["no-console-log"]


def test_add_relocates_ungrouped_subsection_under_pack_header() -> None:
    # A directive whose subsection already sits ungrouped (an earlier flat upsert,
    # or a hand-curated doc) is moved under its `## <owner>/<pack>` header — not
    # duplicated. This is the path that fixes a previously-ungrouped subsection on
    # a re-pin.
    with tempfile.TemporaryDirectory() as tmp:
        src = _write_source_pack(Path(tmp) / "src")
        ungrouped = (
            "# CONSTITUTION\n\n## Directives\n\n"
            "### no-console-log\n\n- stale flat body\n\n"
            "### required-docs\n\n- body\n\n"
            "## Evolution Log\n\n- 2026-01-01 — seed\n"
        )
        root = _make_repo(Path(tmp) / "repo", constitution=ungrouped)
        packplan.fetch_ref = _stub_fetch(src, "acme/widgets", "a" * 40)
        rc, report = _capture(lambda: packapply.cmd_pack_apply(
            _ns(mode="add", root=str(root), target="gh:acme/widgets")))
        assert rc == 0 and report["result"] == "applied", report
        text = (root / "CONSTITUTION.md").read_text()
        assert text.count("### no-console-log") == 1  # relocated, not duplicated
        assert "stale flat body" not in text          # old copy gone
        assert text.index("## acme/widgets") < text.index("### no-console-log")
        # the unrelated ungrouped entry is left where it was
        assert text.index("### required-docs") < text.index("## acme/widgets")


def test_update_replaces_constitution_subsection_in_place() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        src = _write_source_pack(Path(tmp) / "src")
        root = _make_repo(Path(tmp) / "repo", constitution=_CONST_SKELETON)
        packplan.fetch_ref = _stub_fetch(src, "acme/widgets", "a" * 40)
        _capture(lambda: packapply.cmd_pack_apply(
            _ns(mode="add", root=str(root), target="gh:acme/widgets")))
        git(root, "add", "-A"); git(root, "commit", "-qm", "install")
        (src / "directives" / "no-console-log" / "constitution.md").write_text(
            "### no-console-log\n\n- **Directive**: REVISED body.\n"
            "- **Enforced by**: `.governance/packs/acme/widgets/directives/no-console-log/check.sh`\n")
        packplan.fetch_ref = _stub_fetch(src, "acme/widgets", "f" * 40)
        rc, report = _capture(lambda: packapply.cmd_pack_apply(
            _ns(mode="update", root=str(root), target=None)))
        assert rc == 0 and report["result"] == "applied", report
        text = (root / "CONSTITUTION.md").read_text()
        assert text.count("### no-console-log") == 1  # replaced, not duplicated
        assert "REVISED body" in text
        # still grouped under its pack header after the update
        assert text.index("## acme/widgets") < text.index("### no-console-log")
        assert report["constitution_upserted"] == ["no-console-log"]


# --- pack-apply: remove (offline, via CLI) ----------------------------------

REMOVE_CONST = (
    "# CONSTITUTION\n\n## Directives\n\n"
    "### required-docs\n\n- keep me\n\n"
    "### no-console-log\n\n- strip me\n\n"
    "## Evolution Log\n\n<!-- hint -->\n"
)
REMOVE_LOCK = (
    'version: "2"\npacks:\n'
    "  - id: acme/widgets\n    version: \"0.1\"\n    source: gh\n"
    "    ref: gh:acme/widgets\n    sha: " + "e" * 40 + "\n    subpath: \"\"\n"
    "    directives:\n      - no-console-log\n"
)


def pack_apply_cli(root: Path, mode: str, *argv: str):
    # CLI positional order is: pack-apply <mode> <root> [target] [flags]
    res = subprocess.run(
        [sys.executable, str(PACKVERB), "pack-apply", mode, str(root), *argv],
        cwd=ROOT, check=False, text=True, env=GIT_CLEAN_ENV,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    assert res.stdout.strip(), res.stderr
    return res.returncode, json.loads(res.stdout)


def test_remove_deletes_folder_strips_subsection_prunes_lock() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = _make_repo(Path(tmp) / "repo", constitution=REMOVE_CONST, lock=REMOVE_LOCK,
                          installed_directive=".governance/packs/acme/widgets/directives/no-console-log")
        # a user conf exists (committed) for the directive being removed
        conf = root / ".governance/conf/acme/widgets/no-console-log.conf"
        conf.parent.mkdir(parents=True, exist_ok=True)
        conf.write_text("USER=tweak\n")
        git(root, "add", "-A")
        git(root, "commit", "-qm", "seed user conf")
        rc, report = pack_apply_cli(root, "remove", "acme/widgets")
        assert rc == 0 and report["result"] == "applied", report
        assert not (root / ".governance/packs/acme/widgets").exists()
        const = (root / "CONSTITUTION.md").read_text()
        assert "### no-console-log" not in const and "### required-docs" in const
        assert "acme/widgets" not in (root / ".governance/packs.lock").read_text()
        assert report["constitution_stripped"] == ["no-console-log"]
        # the directive's user conf is removed with the pack; empty dir pruned
        assert not conf.exists()
        assert ".governance/conf/acme/widgets/no-console-log.conf" in report["removed"]
        assert not (root / ".governance/conf").exists()


def test_remove_refuses_core() -> None:
    core_lock = REMOVE_LOCK.replace("acme/widgets", "governance-kit/core")
    with tempfile.TemporaryDirectory() as tmp:
        root = _make_repo(Path(tmp) / "repo", constitution=REMOVE_CONST, lock=core_lock,
                          installed_directive=".governance/packs/governance-kit/core/directives/no-console-log")
        rc, report = pack_apply_cli(root, "remove", "governance-kit/core")
        assert rc == 2 and "bedrock" in report["reason"], report
        assert (root / ".governance/packs/governance-kit/core").exists()


def test_remove_refuses_absent_pack() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = _make_repo(Path(tmp) / "repo", constitution=REMOVE_CONST)
        rc, report = pack_apply_cli(root, "remove", "acme/nope")
        assert rc == 2 and "not present" in report["reason"], report


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
