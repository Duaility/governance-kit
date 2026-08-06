#!/usr/bin/env python3
"""Judge/config separation validation tests for directive manifests."""

from __future__ import annotations

import importlib.util
import os
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACK_LIB = ROOT / "kit" / "assets" / "packs" / "lib"


def load_packctl():
    sys.path.insert(0, str(PACK_LIB))
    spec = importlib.util.spec_from_file_location("packctl_under_test", PACK_LIB / "packctl.py")
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def make_pack(tmp: Path, manifest: str, *, defaults: bool = False) -> Path:
    pack = tmp / "demo"
    directive = pack / "directives" / "x"
    (directive / "evals").mkdir(parents=True)
    (pack / "pack.yaml").write_text(
        'id: acme/demo\nname: Demo\nversion: "0.1"\nmin_governance_kit: "0.1"\n'
        'description: demo\nauthor: Test\npresets: {}\n'
    )
    (directive / "directive.yaml").write_text(manifest)
    (directive / "check.sh").write_text("#!/usr/bin/env bash\nexit 0\n")
    os.chmod(directive / "check.sh", 0o755)
    (directive / "constitution.md").write_text(
        "Enforced by `.governance/packs/acme/demo/directives/x/check.sh`.\n"
    )
    (directive / "evals" / "test.sh").write_text("#!/usr/bin/env bash\nexit 0\n")
    os.chmod(directive / "evals" / "test.sh", 0o755)
    if defaults:
        (directive / "defaults.conf").write_text("LIMIT=1\n")
    return pack


BASE = """category: Foundation
recommended: true
summary: x
surface: repo-state
hook: none
triggers: [schedule]
config:
  - name: SCHEDULE_CMD
    type: scalar
    doc: Fixed scheduled judge command.
    default: judge-cli
    tunable: false
judge:
  inputs: [range-diff]
  checks: [review the change]
  gate: record
"""


def errors_for(suffix: str = "", *, defaults: bool = False) -> list[str]:
    with tempfile.TemporaryDirectory() as tmp:
        pack = make_pack(Path(tmp), BASE + suffix, defaults=defaults)
        return load_packctl().validate_pack_dir(pack)


def test_judge_semantics_only_is_valid() -> None:
    assert errors_for() == []


def test_judge_rejects_lane_behavior() -> None:
    for row in ("  section: Audit\n", "  cmd: {schedule: claude}\n", "  group: audit\n"):
        errors = errors_for(row)
        assert any("only inputs, checks, and gate" in error for error in errors), errors


def test_lane_behavior_lives_in_config() -> None:
    extra = """  - name: SCHEDULE_EVIDENCE
    type: scalar
    doc: Evidence mode used by this directive.
    default: range
    tunable: false
  - name: SCHEDULE_STALENESS_DAYS
    type: scalar
    doc: Advisory maximum age for the last successful run.
    default: 48
    tunable: true
"""
    with tempfile.TemporaryDirectory() as tmp:
        manifest = BASE.replace("judge:\n", extra + "judge:\n")
        errors = load_packctl().validate_pack_dir(make_pack(Path(tmp), manifest))
    assert errors == [], errors


def test_schedule_command_is_author_fixed() -> None:
    manifest = BASE.replace("tunable: false\njudge:", "tunable: true\njudge:")
    with tempfile.TemporaryDirectory() as tmp:
        errors = load_packctl().validate_pack_dir(make_pack(Path(tmp), manifest))
    assert any("fixed SCHEDULE_CMD" in error for error in errors), errors


def test_attest_execution_contract_is_fixed() -> None:
    extra = """  - name: ATTEST_SECTION
    type: scalar
    doc: Receipt section populated by attestation.
    default: Audit
    tunable: false
  - name: ATTEST_CMD
    type: scalar
    doc: Command used by live attestation.
    default: harness
    tunable: false
  - name: SCHEDULE_EVIDENCE
    type: scalar
    doc: Evidence mode used by this directive.
    default: range
    tunable: false
"""
    with tempfile.TemporaryDirectory() as tmp:
        manifest = BASE.replace("judge:\n", extra + "judge:\n")
        errors = load_packctl().validate_pack_dir(make_pack(Path(tmp), manifest))
    assert errors == [], errors


def test_defaults_conf_is_rejected() -> None:
    errors = errors_for(defaults=True)
    assert any("defaults.conf" in error for error in errors), errors


def test_verdict_gate_requires_attest_section_config() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        manifest = BASE.replace("gate: record", "gate: verdict")
        pack = make_pack(Path(tmp), manifest)
        errors = load_packctl().validate_pack_dir(pack)
        assert any("ATTEST_SECTION" in error for error in errors), errors


def main() -> int:
    failures = 0
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            try:
                fn()
                print(f"ok - {name}")
            except Exception as exc:
                failures += 1
                print(f"not ok - {name}: {exc}")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
