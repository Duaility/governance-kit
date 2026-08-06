#!/usr/bin/env python3
"""Contract tests for per-directive scheduled-lane planning and generation."""

from __future__ import annotations

import importlib.util
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACK_LIB = ROOT / "kit" / "assets" / "packs" / "lib"
sys.path.insert(0, str(PACK_LIB))
spec = importlib.util.spec_from_file_location("schedulelib", PACK_LIB / "schedulelib.py")
assert spec and spec.loader
schedulelib = importlib.util.module_from_spec(spec)
sys.modules["schedulelib"] = schedulelib
spec.loader.exec_module(schedulelib)

INSTALL = 'version: "3"\nowner: acme\nrepo: demo\ntests_dir: .governance\ninstall_assets_seeded: []\ncollisions: []\n'


def root_at(tmp: Path) -> Path:
    (tmp / ".governance").mkdir(parents=True)
    (tmp / ".governance" / "install.yaml").write_text(INSTALL)
    return tmp


def install(root: Path, directive_id: str, *, surface: str = "repo-state", evidence: str | None = None,
            triggers: str = "[schedule]", staleness: int | None = None) -> None:
    path = root / ".governance" / "packs" / "acme" / "demo" / "directives" / directive_id
    path.mkdir(parents=True)
    config = ""
    if evidence:
        config += f"""config:
  - name: SCHEDULE_EVIDENCE
    type: scalar
    doc: Evidence mode for this directive.
    default: {evidence}
    tunable: false
"""
    if staleness is not None:
        prefix = "config:\n" if not config else ""
        config += prefix + f"""  - name: SCHEDULE_STALENESS_DAYS
    type: scalar
    doc: Maximum scheduled-run interval.
    default: {staleness}
    tunable: true
"""
    (path / "directive.yaml").write_text(
        f"surface: {surface}\nhook: none\ntriggers: {triggers}\n" + config
    )


def test_plan_requires_explicit_schedule_trigger() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = root_at(Path(tmp))
        install(root, "audit", triggers="[]")
        result = schedulelib.plan(root, "nightly", "0 3 * * *", ["audit"])
        assert result["errors"] and "not schedule-eligible" in result["errors"][0]


def test_plan_derives_evidence_per_member() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = root_at(Path(tmp))
        install(root, "state-audit", surface="repo-state")
        install(root, "change-audit", surface="change-set")
        install(root, "forced-commits", surface="repo-state", evidence="commits")
        result = schedulelib.plan(root, "nightly", "0 3 * * *", ["state-audit", "change-audit", "forced-commits"])
        assert result["errors"] == [], result
        evidence = {member["id"]: member["evidence"] for member in result["resolved_members"]}
        assert evidence["acme/demo/state-audit"] == "range"
        assert evidence["acme/demo/change-audit"] == "commits"
        assert evidence["acme/demo/forced-commits"] == "commits"


def test_plan_reports_staleness_advisory() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = root_at(Path(tmp))
        install(root, "audit", staleness=1)
        result = schedulelib.plan(root, "weekly", "0 3 * * 1", ["audit"])
        assert result["errors"] == []
        assert result["warnings"] and "staleness" in result["warnings"][0]


def test_apply_generates_idempotent_workflow_without_evidence_flag() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = root_at(Path(tmp))
        install(root, "audit")
        first = schedulelib.apply(root, "nightly", "0 3 * * *", ["audit"], budget=7)
        assert first["result"] == "applied" and first["changed"] is True
        target = root / ".github" / "workflows" / "governance-schedule-nightly.yml"
        text = target.read_text()
        assert "--evidence" not in text
        assert 'GOVERNANCE_SCHEDULE_BUDGET: "7"' in text
        second = schedulelib.apply(root, "nightly", "0 3 * * *", ["audit"], budget=7)
        assert second["changed"] is False


def test_remove_cleans_workflow_and_ledger() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = root_at(Path(tmp))
        install(root, "audit")
        schedulelib.apply(root, "nightly", "0 3 * * *", ["audit"])
        result = schedulelib.remove(root, "nightly")
        assert result["result"] == "removed"
        assert "governance-schedule-nightly" not in (root / ".governance" / "install.yaml").read_text()


def test_unknown_member_is_an_error() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        result = schedulelib.plan(root_at(Path(tmp)), "nightly", "0 3 * * *", ["missing"])
        assert result["errors"]


if __name__ == "__main__":
    failures = 0
    for name, fn in sorted(globals().items()):
        if not name.startswith("test_"):
            continue
        try:
            fn()
        except Exception as exc:
            failures += 1
            print(f"not ok - {name}: {exc}", file=sys.stderr)
        else:
            print(f"ok - {name}")
    raise SystemExit(1 if failures else 0)
