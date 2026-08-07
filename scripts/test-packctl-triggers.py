#!/usr/bin/env python3
"""Explicit trigger and config-registry validation tests."""

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


def validate(manifest: str) -> list[str]:
    with tempfile.TemporaryDirectory() as tmp:
        pack = Path(tmp) / "demo"
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
        return load_packctl().validate_pack_dir(pack)


BASE = """category: Foundation
recommended: true
summary: x
surface: repo-state
hook: pre-commit
triggers: [pre-commit, schedule]
"""


def test_explicit_triggers_are_valid() -> None:
    assert validate(BASE) == []


def test_invalid_trigger_is_rejected() -> None:
    errors = validate(BASE.replace("schedule", "bogus"))
    assert any("unknown value" in error for error in errors), errors


def test_hook_must_appear_in_explicit_triggers() -> None:
    errors = validate(BASE.replace("[pre-commit, schedule]", "[schedule]"))
    assert any("must contain the hook" in error for error in errors), errors


def test_schedule_only_shape_is_explicit() -> None:
    manifest = BASE.replace("hook: pre-commit", "hook: none").replace(
        "[pre-commit, schedule]", "[schedule]"
    )
    assert validate(manifest) == []


def test_config_registry_accepts_scalar_and_list_defaults() -> None:
    errors = validate(BASE + """config:
  - name: LIMIT
    type: scalar
    doc: Maximum accepted count.
    default: 5
    tunable: true
  - name: RULES
    type: list
    doc: Rules evaluated by the directive.
    default:
      - one
      - two
    tunable: false
""")
    assert errors == [], errors


def test_config_registry_is_strict() -> None:
    cases = {
        "lowercase name": "name: limit",
        "unknown type": "type: number",
        "unknown field": "mystery: value",
    }
    base = BASE + """config:
  - name: LIMIT
    type: scalar
    doc: Maximum accepted count.
    default: 5
    tunable: true
"""
    for label, replacement in cases.items():
        if label == "lowercase name":
            manifest = base.replace("name: LIMIT", replacement)
        elif label == "unknown type":
            manifest = base.replace("type: scalar", replacement)
        else:
            manifest = base + "    mystery: value\n"
        errors = validate(manifest)
        assert errors, label


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
