#!/usr/bin/env python3
"""Contract tests for schedulelib.py — the `governance schedule` plan/apply
engine that replaced the retired sweep lane (see
kit/references/SCHEDULE_FLOW.md). Mirrors the house style of
scripts/test-packverb-apply.py: build a minimal fixture root by hand
(no real git repo needed — schedulelib.py is pure Path-based file I/O, no
`git` subprocess calls), import the engine module directly, call plan()/
apply()/remove() in-process, and assert on the returned dict + filesystem
side effects.
"""

from __future__ import annotations

import importlib.util
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACK_LIB = ROOT / "kit" / "assets" / "packs" / "lib"


def _load(name: str):
    sys.path.insert(0, str(PACK_LIB))
    spec = importlib.util.spec_from_file_location(name, PACK_LIB / f"{name}.py")
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


schedulelib = _load("schedulelib")

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


def _make_root(tmp: Path) -> Path:
    """A bare fixture root: just `.governance/install.yaml`, no git repo —
    schedulelib.py never shells out to git, it only touches Path objects."""
    root = Path(tmp)
    (root / ".governance").mkdir(parents=True)
    (root / ".governance" / "install.yaml").write_text(INSTALL_YAML)
    return root


def _install_directive(
    root: Path, owner: str, pack: str, directive_id: str,
    hook: str = "pre-commit", triggers: list[str] | None = None,
) -> Path:
    """Write a minimal `directive.yaml` under `.governance/packs/<owner>/
    <pack>/directives/<id>/` — just the fields `_installed_directives` reads
    (`hook:`, optionally `triggers:`)."""
    ddir = root / ".governance" / "packs" / owner / pack / "directives" / directive_id
    ddir.mkdir(parents=True, exist_ok=True)
    lines = [f"hook: {hook}\n"]
    if triggers is not None:
        rendered = ", ".join(triggers)
        lines.append(f"triggers: [{rendered}]\n")
    (ddir / "directive.yaml").write_text("".join(lines))
    return ddir


def _overlay(root: Path, owner: str, pack: str, directive_id: str, triggers_row: str) -> None:
    conf = root / ".governance" / "conf" / owner / pack / f"{directive_id}.conf"
    conf.parent.mkdir(parents=True, exist_ok=True)
    conf.write_text(f"TRIGGERS={triggers_row}\n")


# --- plan(): error surfacing (plan() never raises) --------------------------

def test_plan_unknown_member_errors() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = _make_root(Path(tmp))
        result = schedulelib.plan(root, "nightly", "0 3 * * *", ["nope-such-directive"])
        assert result["errors"], result
        assert any("nope-such-directive" in e for e in result["errors"]), result["errors"]


def test_plan_ineligible_member_errors_then_overlay_fixes_it() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = _make_root(Path(tmp))
        _install_directive(root, "acme", "widgets", "no-console-log", hook="pre-commit")

        result = schedulelib.plan(root, "nightly", "0 3 * * *", ["no-console-log"])
        assert result["errors"], result
        assert any(
            "acme/widgets/no-console-log" in e and "not schedule-eligible" in e
            for e in result["errors"]
        ), result["errors"]
        assert any("['pre-commit']" in e or "pre-commit" in e for e in result["errors"])

        # fix via an overlay TRIGGERS= row adding `schedule`
        _overlay(root, "acme", "widgets", "no-console-log", "pre-commit,schedule")
        result2 = schedulelib.plan(root, "nightly", "0 3 * * *", ["no-console-log"])
        assert result2["errors"] == [], result2["errors"]
        member = result2["resolved_members"][0]
        assert member["id"] == "acme/widgets/no-console-log"
        assert member["eligible"] is True
        assert "schedule" in member["effective_triggers"]


def test_plan_bad_lane_errors() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = _make_root(Path(tmp))
        _install_directive(root, "acme", "widgets", "no-shims", hook="none", triggers=["schedule"])
        for bad_lane in ("Nightly", "week_ly", "has space"):
            result = schedulelib.plan(root, bad_lane, "0 3 * * *", ["no-shims"])
            assert result["errors"], (bad_lane, result)
            assert any("lane" in e for e in result["errors"]), result["errors"]


def test_plan_bad_evidence_errors() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = _make_root(Path(tmp))
        _install_directive(root, "acme", "widgets", "no-shims", hook="none", triggers=["schedule"])
        result = schedulelib.plan(
            root, "nightly", "0 3 * * *", ["no-shims"], evidence="bogus",
        )
        assert result["errors"], result
        assert any("--evidence" in e for e in result["errors"]), result["errors"]


def test_plan_empty_members_errors() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = _make_root(Path(tmp))
        result = schedulelib.plan(root, "nightly", "0 3 * * *", [])
        assert result["errors"], result
        assert any("--member" in e for e in result["errors"]), result["errors"]


def test_plan_eligible_bare_id_resolves_cleanly() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = _make_root(Path(tmp))
        _install_directive(root, "acme", "widgets", "no-shims", hook="none", triggers=["schedule"])
        result = schedulelib.plan(root, "nightly", "0 3 * * *", ["no-shims"])
        assert result["errors"] == [], result["errors"]
        assert len(result["resolved_members"]) == 1
        member = result["resolved_members"][0]
        assert member["id"] == "acme/widgets/no-shims"
        assert member["eligible"] is True


# --- apply(): file rendering + ledger side effects ---------------------------

def _apply_kwargs(**overrides):
    base = dict(root=None, lane="nightly", cron="0 3 * * *", members=["no-shims"],
                evidence="range", budget=None, dry_run=False)
    base.update(overrides)
    return base


def _eligible_root(tmp: Path) -> Path:
    root = _make_root(Path(tmp))
    _install_directive(root, "acme", "widgets", "no-shims", hook="none", triggers=["schedule"])
    return root


def test_apply_writes_stamped_workflow_with_substituted_placeholders() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = _eligible_root(Path(tmp))
        result = schedulelib.apply(
            root, "nightly", "0 3 * * *", ["no-shims"], evidence="range", budget=7,
        )
        assert result["result"] == "applied", result
        target = root / ".github/workflows/governance-schedule-nightly.yml"
        assert target.is_file()
        text = target.read_text()
        assert "__LANE__" not in text and "__CRON__" not in text
        assert "__MEMBERS__" not in text and "__EVIDENCE__" not in text
        assert "__BUDGET__" not in text
        assert "nightly" in text
        assert '"0 3 * * *"' in text
        # __MEMBERS__ is rendered from the raw input tokens (deduped_members),
        # not the resolved full <owner>/<pack>/<id> — run.sh's own filter
        # re-resolves the same bare token at run time (see _resolve_member).
        assert "no-shims" in text
        assert "--evidence range" in text
        assert 'GOVERNANCE_SCHEDULE_BUDGET: "7"' in text
        first_line = text.splitlines()[0]
        assert first_line.startswith("# governance-kit:managed kit-version=")


def test_apply_appends_install_assets_seeded() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = _eligible_root(Path(tmp))
        schedulelib.apply(root, "nightly", "0 3 * * *", ["no-shims"])
        manifest = (root / ".governance" / "install.yaml").read_text()
        assert ".github/workflows/governance-schedule-nightly.yml" in manifest
        assert "install_assets_seeded:" in manifest


def test_apply_rewrites_managed_digests_block() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = _eligible_root(Path(tmp))
        schedulelib.apply(root, "nightly", "0 3 * * *", ["no-shims"])
        manifest = (root / ".governance" / "install.yaml").read_text()
        assert "managed_digests:" in manifest
        assert ".github/workflows/governance-schedule-nightly.yml:" in manifest


def test_apply_reapply_same_inputs_is_byte_identical_and_unchanged() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = _eligible_root(Path(tmp))
        r1 = schedulelib.apply(root, "nightly", "0 3 * * *", ["no-shims"])
        assert r1["result"] == "applied" and r1["changed"] is True, r1
        target = root / ".github/workflows/governance-schedule-nightly.yml"
        before = target.read_bytes()

        r2 = schedulelib.apply(root, "nightly", "0 3 * * *", ["no-shims"])
        assert r2["result"] == "applied", r2
        assert r2["changed"] is False, r2
        after = target.read_bytes()
        assert before == after


def test_apply_different_input_changes_file() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = _eligible_root(Path(tmp))
        schedulelib.apply(root, "nightly", "0 3 * * *", ["no-shims"])
        target = root / ".github/workflows/governance-schedule-nightly.yml"
        before = target.read_bytes()

        r2 = schedulelib.apply(root, "nightly", "0 4 * * *", ["no-shims"])
        assert r2["result"] == "applied" and r2["changed"] is True, r2
        after = target.read_bytes()
        assert before != after


def test_apply_dry_run_writes_nothing() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = _eligible_root(Path(tmp))
        target = root / ".github/workflows/governance-schedule-nightly.yml"
        assert not target.exists()

        result = schedulelib.apply(
            root, "nightly", "0 3 * * *", ["no-shims"], dry_run=True,
        )
        assert result["result"] == "dry-run", result
        assert result["changed"] is True
        assert not target.exists()

        # once a file exists, a no-op dry run reports changed: False and still
        # leaves the file untouched.
        schedulelib.apply(root, "nightly", "0 3 * * *", ["no-shims"])
        before = target.read_bytes()
        result2 = schedulelib.apply(
            root, "nightly", "0 3 * * *", ["no-shims"], dry_run=True,
        )
        assert result2["result"] == "dry-run" and result2["changed"] is False, result2
        assert target.read_bytes() == before


def test_apply_refuses_when_plan_has_errors() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = _make_root(Path(tmp))  # no directives installed at all
        target = root / ".github/workflows/governance-schedule-nightly.yml"
        result = schedulelib.apply(root, "nightly", "0 3 * * *", ["no-such-directive"])
        assert result["result"] == "refused", result
        assert result["errors"], result
        assert not target.exists()


def test_apply_refuses_ineligible_member_writes_nothing() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = _make_root(Path(tmp))
        _install_directive(root, "acme", "widgets", "no-console-log", hook="pre-commit")
        target = root / ".github/workflows/governance-schedule-nightly.yml"
        result = schedulelib.apply(root, "nightly", "0 3 * * *", ["no-console-log"])
        assert result["result"] == "refused", result
        assert not target.exists()


# --- remove(): deletion + ledger cleanup -------------------------------------

def test_remove_deletes_file_and_ledger_rows() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = _eligible_root(Path(tmp))
        schedulelib.apply(root, "nightly", "0 3 * * *", ["no-shims"])
        target = root / ".github/workflows/governance-schedule-nightly.yml"
        assert target.is_file()

        result = schedulelib.remove(root, "nightly")
        assert result["result"] == "removed", result
        assert not target.exists()

        manifest = (root / ".governance" / "install.yaml").read_text()
        assert ".github/workflows/governance-schedule-nightly.yml" not in manifest
        assert ".github/workflows/governance-schedule-nightly.yml:" not in manifest


def test_remove_absent_lane_is_noop() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = _eligible_root(Path(tmp))
        result = schedulelib.remove(root, "nonexistent-lane")
        assert result["result"] == "absent", result


# --- homonym resolution ------------------------------------------------------

def test_bare_id_resolves_all_homonyms_qualified_id_resolves_one() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = _make_root(Path(tmp))
        _install_directive(root, "acme", "widgets", "no-shims", hook="none", triggers=["schedule"])
        _install_directive(root, "beta", "gadgets", "no-shims", hook="none", triggers=["schedule"])

        result = schedulelib.plan(root, "nightly", "0 3 * * *", ["no-shims"])
        assert result["errors"] == [], result["errors"]
        ids = {m["id"] for m in result["resolved_members"]}
        assert ids == {"acme/widgets/no-shims", "beta/gadgets/no-shims"}, ids

        qualified = schedulelib.plan(
            root, "nightly", "0 3 * * *", ["acme/widgets/no-shims"],
        )
        assert qualified["errors"] == [], qualified["errors"]
        assert [m["id"] for m in qualified["resolved_members"]] == ["acme/widgets/no-shims"]


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
