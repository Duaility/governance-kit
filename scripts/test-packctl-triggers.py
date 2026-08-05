#!/usr/bin/env python3
"""triggers: and judge.cmd lane validation tests for packctl.py: the optional
top-level `triggers:` list (allowed values, hook-consistency rule) and the
attest/schedule judge cmd lanes (sweep retired).

Split from scripts/test-packctl-validate.py to keep both files under the
repo-hygiene 500-line limit (same split lineage as
scripts/test-packctl-subagent.py). Helpers (load_packctl, make_pack) are
duplicated rather than extracted into a shared module — each test file in
this repo stays standalone.
"""

from __future__ import annotations

import importlib.util
import os
import sys
import tempfile
import textwrap
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PACK_LIB = ROOT / "kit" / "assets" / "packs" / "lib"
PACKCTL_PATH = PACK_LIB / "packctl.py"
PACKS_ROOT = ROOT / "packs"


def load_packctl():
    sys.path.insert(0, str(PACK_LIB))
    spec = importlib.util.spec_from_file_location("packctl_under_test", PACKCTL_PATH)
    if spec is None or spec.loader is None:
        raise AssertionError(f"cannot load {PACKCTL_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def make_pack(tmp: Path, *, pack_yaml: str, directives: dict[str, dict] | None = None) -> Path:
    pack_dir = tmp / "demo"
    pack_dir.mkdir(parents=True, exist_ok=True)
    (pack_dir / "pack.yaml").write_text(pack_yaml)
    directives_root = pack_dir / "directives"
    directives_root.mkdir(exist_ok=True)
    for directive_id, parts in (directives or {}).items():
        ddir = directives_root / directive_id
        ddir.mkdir(parents=True, exist_ok=True)
        if "directive_yaml" in parts:
            (ddir / "directive.yaml").write_text(parts["directive_yaml"])
        if "check_sh" in parts:
            (ddir / "check.sh").write_text(parts["check_sh"])
            os.chmod(ddir / "check.sh", 0o755)
        if "constitution_md" in parts:
            (ddir / "constitution.md").write_text(parts["constitution_md"])
        evals_dir = ddir / "evals"
        evals_dir.mkdir(exist_ok=True)
        (evals_dir / "test.sh").write_text(parts.get("eval_sh", "#!/usr/bin/env bash\nexit 0\n"))
        os.chmod(evals_dir / "test.sh", 0o755)
    return pack_dir


# ---- positive: shipped packs validate cleanly ------------------------------

# ---- triggers: + judge cmd lane matrix -------------------------------------

def test_triggers_valid() -> None:
    pkt = load_packctl()
    with tempfile.TemporaryDirectory() as tmp:
        pack = make_pack(
            Path(tmp),
            pack_yaml=textwrap.dedent("""\
                id: acme/demo
                name: D
                version: "0.1"
                min_governance_kit: "0.1"
                description: d
                author: T
                presets: {}
            """),
            directives={
                "x": {
                    "directive_yaml": textwrap.dedent("""\
                        category: Foundation
                        recommended: true
                        summary: x
                        surface: repo-state
                        hook: pre-commit
                        triggers: [pre-commit, schedule]
                    """),
                    "check_sh": "#!/usr/bin/env bash\nexit 0\n",
                    "constitution_md": "ref .governance/packs/acme/demo/directives/x/check.sh",
                },
            },
        )
        errors = pkt.validate_pack_dir(pack)
        assert errors == [], "\n".join(errors)


def test_triggers_unknown_value() -> None:
    pkt = load_packctl()
    with tempfile.TemporaryDirectory() as tmp:
        pack = make_pack(
            Path(tmp),
            pack_yaml=textwrap.dedent("""\
                id: acme/demo
                name: D
                version: "0.1"
                min_governance_kit: "0.1"
                description: d
                author: T
                presets: {}
            """),
            directives={
                "x": {
                    "directive_yaml": textwrap.dedent("""\
                        category: Foundation
                        recommended: true
                        summary: x
                        surface: repo-state
                        hook: pre-commit
                        triggers: [pre-commit, bogus-lane]
                    """),
                    "check_sh": "#!/usr/bin/env bash\nexit 0\n",
                    "constitution_md": "ref .governance/packs/acme/demo/directives/x/check.sh",
                },
            },
        )
        errors = pkt.validate_pack_dir(pack)
        assert any("triggers has unknown value" in e and "bogus-lane" in e for e in errors), "\n".join(errors)


def test_triggers_missing_hook_value() -> None:
    pkt = load_packctl()
    with tempfile.TemporaryDirectory() as tmp:
        pack = make_pack(
            Path(tmp),
            pack_yaml=textwrap.dedent("""\
                id: acme/demo
                name: D
                version: "0.1"
                min_governance_kit: "0.1"
                description: d
                author: T
                presets: {}
            """),
            directives={
                "x": {
                    "directive_yaml": textwrap.dedent("""\
                        category: Foundation
                        recommended: true
                        summary: x
                        surface: repo-state
                        hook: pre-commit
                        triggers: [schedule]
                    """),
                    "check_sh": "#!/usr/bin/env bash\nexit 0\n",
                    "constitution_md": "ref .governance/packs/acme/demo/directives/x/check.sh",
                },
            },
        )
        errors = pkt.validate_pack_dir(pack)
        assert any(
            "triggers must contain the hook: value" in e and "pre-commit" in e for e in errors
        ), "\n".join(errors)


def test_triggers_two_git_hook_values() -> None:
    pkt = load_packctl()
    with tempfile.TemporaryDirectory() as tmp:
        pack = make_pack(
            Path(tmp),
            pack_yaml=textwrap.dedent("""\
                id: acme/demo
                name: D
                version: "0.1"
                min_governance_kit: "0.1"
                description: d
                author: T
                presets: {}
            """),
            directives={
                "x": {
                    "directive_yaml": textwrap.dedent("""\
                        category: Foundation
                        recommended: true
                        summary: x
                        surface: repo-state
                        hook: pre-commit
                        triggers: [pre-commit, commit-msg]
                    """),
                    "check_sh": "#!/usr/bin/env bash\nexit 0\n",
                    "constitution_md": "ref .governance/packs/acme/demo/directives/x/check.sh",
                },
            },
        )
        errors = pkt.validate_pack_dir(pack)
        assert any(
            "triggers may contain at most one git-hook value" in e for e in errors
        ), "\n".join(errors)


# ---- judge.cmd lane rename (sweep -> schedule, issue #355) -----------------


def test_judge_cmd_schedule_accepted() -> None:
    pkt = load_packctl()
    with tempfile.TemporaryDirectory() as tmp:
        pack = make_pack(
            Path(tmp),
            pack_yaml=textwrap.dedent("""\
                id: acme/demo
                name: D
                version: "0.1"
                min_governance_kit: "0.1"
                description: d
                author: T
                presets: {}
            """),
            directives={
                "x": {
                    "directive_yaml": textwrap.dedent("""\
                        category: Foundation
                        recommended: true
                        summary: x
                        hook: none
                        judge:
                          inputs: [range-diff]
                          checks:
                            - some rubric
                          cmd: { schedule: "claude -p --model opus" }
                    """),
                    "constitution_md": "no path reference here",
                },
            },
        )
        errors = pkt.validate_pack_dir(pack)
        assert not any("cmd" in e for e in errors), "\n".join(errors)


def test_judge_cmd_sweep_rejected_as_unknown() -> None:
    """`sweep` was the OLD cmd lane key, renamed to `schedule`. It is now
    simply an unknown key under `judge.cmd`, not a tolerated alias."""
    pkt = load_packctl()
    with tempfile.TemporaryDirectory() as tmp:
        pack = make_pack(
            Path(tmp),
            pack_yaml=textwrap.dedent("""\
                id: acme/demo
                name: D
                version: "0.1"
                min_governance_kit: "0.1"
                description: d
                author: T
                presets: {}
            """),
            directives={
                "x": {
                    "directive_yaml": textwrap.dedent("""\
                        category: Foundation
                        recommended: true
                        summary: x
                        hook: none
                        judge:
                          inputs: [range-diff]
                          checks:
                            - some rubric
                          cmd: { sweep: "claude -p --model opus" }
                    """),
                    "constitution_md": "no path reference here",
                },
            },
        )
        errors = pkt.validate_pack_dir(pack)
        assert any("cmd has unknown key" in e and "sweep" in e for e in errors), "\n".join(errors)


def test_judge_cmd_schedule_harness_rejected() -> None:
    """The schedule lane runs at rest with no live session, so `schedule:
    harness` is specifically rejected."""
    pkt = load_packctl()
    with tempfile.TemporaryDirectory() as tmp:
        pack = make_pack(
            Path(tmp),
            pack_yaml=textwrap.dedent("""\
                id: acme/demo
                name: D
                version: "0.1"
                min_governance_kit: "0.1"
                description: d
                author: T
                presets: {}
            """),
            directives={
                "x": {
                    "directive_yaml": textwrap.dedent("""\
                        category: Foundation
                        recommended: true
                        summary: x
                        hook: none
                        judge:
                          inputs: [range-diff]
                          checks:
                            - some rubric
                          cmd: { schedule: harness }
                    """),
                    "constitution_md": "no path reference here",
                },
            },
        )
        errors = pkt.validate_pack_dir(pack)
        assert any(
            "cmd.schedule cannot be 'harness'" in e for e in errors
        ), "\n".join(errors)



if __name__ == "__main__":
    failures = 0
    for name, fn in sorted(globals().items()):
        if not name.startswith("test_"):
            continue
        try:
            fn()
        except Exception as exc:  # noqa: BLE001 - tiny stdlib-only harness.
            failures += 1
            print(f"not ok - {name}: {exc}", file=sys.stderr)
        else:
            print(f"ok - {name}")
    raise SystemExit(1 if failures else 0)
