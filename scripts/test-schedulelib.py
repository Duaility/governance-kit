#!/usr/bin/env python3
"""Contract tests for directive-owned schedule workflow generation."""

from __future__ import annotations

import importlib.util
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACK_LIB = ROOT / "kit" / "assets" / "packs" / "lib"
sys.path.insert(0, str(PACK_LIB))
spec = importlib.util.spec_from_file_location("workflowlib", PACK_LIB / "workflowlib.py")
assert spec and spec.loader
workflowlib = importlib.util.module_from_spec(spec)
sys.modules["workflowlib"] = workflowlib
spec.loader.exec_module(workflowlib)

INSTALL = 'version: "3"\nowner: acme\nrepo: demo\ntests_dir: .governance\ninstall_assets_seeded: []\ncollisions: []\n'


def root_at(tmp: Path) -> Path:
    (tmp / ".governance").mkdir(parents=True)
    (tmp / ".governance" / "install.yaml").write_text(INSTALL)
    return tmp


def install(
    root: Path,
    directive_id: str,
    *,
    cron: str = "",
    surface: str = "repo-state",
    evidence: str | None = None,
    triggers: str = "[schedule]",
    staleness: int | None = None,
    cron_tunable: bool = True,
) -> None:
    path = root / ".governance" / "packs" / "acme" / "demo" / "directives" / directive_id
    path.mkdir(parents=True)
    config = "config:\n"
    config += "  - name: SCHEDULE_CRON\n"
    config += "    type: scalar\n"
    config += "    doc: Consumer-selected cadence.\n"
    config += f'    default: "{cron}"\n'
    config += f"    tunable: {'true' if cron_tunable else 'false'}\n"
    if evidence:
        config += "  - name: SCHEDULE_EVIDENCE\n"
        config += "    type: scalar\n"
        config += "    doc: Evidence mode for this directive.\n"
        config += f"    default: {evidence}\n"
        config += "    tunable: false\n"
    if staleness is not None:
        config += "  - name: SCHEDULE_STALENESS_DAYS\n"
        config += "    type: scalar\n"
        config += "    doc: Maximum scheduled-run interval.\n"
        config += f"    default: {staleness}\n"
        config += "    tunable: true\n"
    (path / "directive.yaml").write_text(
        f"surface: {surface}\nhook: none\ntriggers: {triggers}\n" + config
    )


def test_plan_requires_explicit_schedule_trigger() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = root_at(Path(tmp))
        install(root, "audit", cron="0 3 * * *", triggers="[]")
        result = workflowlib.plan(root)
        assert not result["groups"]
        assert result["warnings"] == []


def test_plan_groups_directives_by_cron() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = root_at(Path(tmp))
        install(root, "audit-a", cron="0 3 * * *")
        install(root, "audit-b", cron="0 3 * * *")
        install(root, "audit-c", cron="0 4 * * *")
        result = workflowlib.plan(root)
        assert result["errors"] == [], result
        assert [g["cron"] for g in result["groups"]] == ["0 3 * * *", "0 4 * * *"]
        assert result["groups"][0]["members"] == ["acme/demo/audit-a", "acme/demo/audit-b"]


def test_plan_reports_staleness_advisory() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = root_at(Path(tmp))
        install(root, "audit", cron="0 3 * * 1", staleness=1)
        result = workflowlib.plan(root)
        assert result["errors"] == []
        # Staleness is evaluated by the runtime against the actual cadence;
        # generation only compiles the source-of-truth cron entries.
        assert result["warnings"] == []


def test_apply_generates_one_idempotent_workflow_without_budget() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = root_at(Path(tmp))
        install(root, "audit", cron="0 3 * * *")
        first = workflowlib.apply(root)
        assert first["result"] == "applied" and first["changed"] is True
        target = root / ".github" / "workflows" / "governance-schedule.yml"
        text = target.read_text()
        assert 'cron: "0 3 * * *"' in text
        assert "acme/demo/audit" in text
        assert "BUDGET" not in text
        second = workflowlib.apply(root)
        assert second["changed"] is False


def test_apply_reconciles_legacy_lane_workflows() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = root_at(Path(tmp))
        install(root, "audit", cron="0 3 * * *")
        legacy = root / ".github" / "workflows" / "governance-schedule-nightly.yml"
        legacy.parent.mkdir(parents=True)
        legacy.write_text("# governance-kit:managed kit-version=0.13.0\nlegacy\n")
        result = workflowlib.apply(root)
        assert result["result"] == "applied"
        assert not legacy.exists()
        assert (root / ".github" / "workflows" / "governance-schedule.yml").exists()


def test_apply_preserves_unmarked_schedule_workflow() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = root_at(Path(tmp))
        install(root, "audit", cron="0 3 * * *")
        extra = root / ".github" / "workflows" / "governance-schedule-extra.yml"
        extra.parent.mkdir(parents=True)
        extra.write_text("name: hand-authored\n")
        workflowlib.apply(root)
        assert extra.exists()


def test_apply_removes_workflow_when_all_crons_are_empty() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = root_at(Path(tmp))
        install(root, "audit", cron="0 3 * * *")
        workflowlib.apply(root)
        (root / ".governance" / "packs" / "acme" / "demo" / "directives" / "audit" / "directive.yaml").write_text(
            "surface: repo-state\nhook: none\ntriggers: [schedule]\nconfig:\n"
            "  - name: SCHEDULE_CRON\n    type: scalar\n    doc: Cadence.\n    default: \"\"\n    tunable: true\n"
        )
        result = workflowlib.apply(root)
        assert result["result"] == "applied"
        assert not (root / ".github" / "workflows" / "governance-schedule.yml").exists()


def test_invalid_cron_is_an_error() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = root_at(Path(tmp))
        install(root, "audit", cron="nightly")
        result = workflowlib.plan(root)
        assert result["errors"] and "five space-separated cron fields" in result["errors"][0]


def test_non_tunable_cron_overlay_is_ignored() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = root_at(Path(tmp))
        install(root, "audit", cron="", cron_tunable=False)
        conf = root / ".governance" / "conf" / "acme" / "demo"
        conf.mkdir(parents=True)
        (conf / "audit.conf").write_text("SCHEDULE_CRON=0 3 * * *\n")
        result = workflowlib.plan(root)
        assert result["groups"] == []
        assert any("not enrolled" in warning for warning in result["warnings"])


def test_overlay_inline_comment_is_not_part_of_cron() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = root_at(Path(tmp))
        install(root, "audit", cron="", cron_tunable=True)
        conf = root / ".governance" / "conf" / "acme" / "demo"
        conf.mkdir(parents=True)
        (conf / "audit.conf").write_text("SCHEDULE_CRON=0 3 * * * # nightly\n")
        result = workflowlib.plan(root)
        assert result["errors"] == []
        assert [group["cron"] for group in result["groups"]] == ["0 3 * * *"]


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
