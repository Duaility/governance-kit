#!/usr/bin/env python3
"""judge.cmd / judge.group validate_pack_dir tests for packctl.py.

Split from scripts/test-packctl-validate.py to keep both files under the
repo-hygiene 500-line limit. Helpers (load_packctl, make_pack) are duplicated
rather than extracted into a shared module — each test file in this repo
stays standalone.
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


# ---- judge.cmd (issue #355 cmd collapse) --------------------------------
#
# Amendment 3 retired `sink:` and `contest:`. The lane a directive rides on
# is now derived purely from whether `section:` is present (attest lane) or
# absent (sweep-only discovery) — fixtures below use `section: Audit` where
# the old fixtures used `sink: none` to mean "no section at all", and simply
# omit `section:` where the old fixtures used `sink: none` to mean
# "sweep-only". `contest:` is folded into a three-valued `gate:`.


def _cmd_pack(tmp: Path, judge_block: str, *, hook: str = "none") -> Path:
    return make_pack(
        tmp,
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
                "directive_yaml": (
                    "category: Foundation\n"
                    "recommended: true\n"
                    "summary: x\n"
                    "hook: " + hook + "\n"
                    "judge:\n"
                    "  inputs: [range-diff]\n"
                    "  checks:\n"
                    "    - some rubric\n"
                    + judge_block
                ),
                "constitution_md": "no path reference here",
            },
        },
    )


def test_validate_pack_dir_accepts_attest_string_cmd() -> None:
    pkt = load_packctl()
    with tempfile.TemporaryDirectory() as tmp:
        pack = _cmd_pack(
            Path(tmp),
            '  cmd: { attest: "claude -p --output-format text --model haiku" }\n',
        )
        errors = pkt.validate_pack_dir(pack)
        assert not any("cmd" in e for e in errors), "\n".join(errors)


def test_validate_pack_dir_accepts_attest_harness() -> None:
    pkt = load_packctl()
    with tempfile.TemporaryDirectory() as tmp:
        pack = _cmd_pack(
            Path(tmp),
            "  cmd: { attest: harness, sweep: \"claude -p --output-format text --model opus\" }\n",
        )
        errors = pkt.validate_pack_dir(pack)
        assert not any("cmd" in e for e in errors), "\n".join(errors)


def test_validate_pack_dir_accepts_sweep_string_cmd() -> None:
    pkt = load_packctl()
    with tempfile.TemporaryDirectory() as tmp:
        pack = _cmd_pack(
            Path(tmp),
            '  cmd: { sweep: "claude -p --output-format text --model opus" }\n',
        )
        errors = pkt.validate_pack_dir(pack)
        assert errors == [], "\n".join(errors)


def test_validate_pack_dir_flags_unknown_cmd_key() -> None:
    pkt = load_packctl()
    with tempfile.TemporaryDirectory() as tmp:
        pack = _cmd_pack(
            Path(tmp),
            '  cmd: { attest: harness, triage: "some-cli" }\n',
        )
        errors = pkt.validate_pack_dir(pack)
        assert any("unknown key" in e and "triage" in e for e in errors), "\n".join(errors)


def test_validate_pack_dir_flags_sweep_harness() -> None:
    pkt = load_packctl()
    with tempfile.TemporaryDirectory() as tmp:
        pack = _cmd_pack(
            Path(tmp),
            "  cmd: { sweep: harness }\n",
        )
        errors = pkt.validate_pack_dir(pack)
        assert any("cmd.sweep" in e and "harness" in e for e in errors), "\n".join(errors)


def test_validate_pack_dir_flags_tiers_as_forbidden() -> None:
    pkt = load_packctl()
    with tempfile.TemporaryDirectory() as tmp:
        pack = _cmd_pack(
            Path(tmp),
            "  tiers: { sweep: high }\n",
        )
        errors = pkt.validate_pack_dir(pack)
        assert any("judge.tiers" in e for e in errors), "\n".join(errors)


def test_validate_pack_dir_silent_on_section_absent_without_sweep_cmd() -> None:
    # The bundled norm: a sweep-only directive names no judge of its own and
    # the driver resolves one from GOVERNANCE_SWEEP_CMD. Not a defect, so not
    # a warning — 15 bundled directives would otherwise each emit one.
    pkt = load_packctl()
    with tempfile.TemporaryDirectory() as tmp:
        pack = _cmd_pack(Path(tmp), "")
        errors, warnings = pkt.validate_pack_dir_with_warnings(pack)
        assert errors == [], "\n".join(errors)
        assert warnings == [], "\n".join(warnings)


def test_validate_pack_dir_no_warning_when_section_absent_has_sweep_cmd() -> None:
    pkt = load_packctl()
    with tempfile.TemporaryDirectory() as tmp:
        pack = _cmd_pack(
            Path(tmp),
            '  cmd: { sweep: "claude -p --output-format text --model opus" }\n',
        )
        errors, warnings = pkt.validate_pack_dir_with_warnings(pack)
        assert errors == [], "\n".join(errors)
        assert warnings == [], "\n".join(warnings)


# ---- judge.sink / judge.section (issue #355 amendment 3) -------------


def test_validate_pack_dir_flags_sink_as_forbidden() -> None:
    pkt = load_packctl()
    with tempfile.TemporaryDirectory() as tmp:
        pack = _cmd_pack(
            Path(tmp),
            '  sink: none\n  cmd: { sweep: "claude -p --output-format text --model opus" }\n',
        )
        errors = pkt.validate_pack_dir(pack)
        assert any("judge.sink" in e for e in errors), "\n".join(errors)


def test_validate_pack_dir_no_check_sh_or_surface_required_when_section_absent() -> None:
    """Amendment 3: the sweep-only exemption (no check.sh, no surface: needed)
    now keys purely on `section:` being absent — no `sink:` field involved."""
    pkt = load_packctl()
    with tempfile.TemporaryDirectory() as tmp:
        pack = _cmd_pack(
            Path(tmp),
            '  cmd: { sweep: "claude -p --output-format text --model opus" }\n',
        )
        errors = pkt.validate_pack_dir(pack)
        assert not any("check.sh" in e for e in errors), "\n".join(errors)
        assert not any("surface" in e for e in errors), "\n".join(errors)


# ---- judge.gate / judge.contest (issue #355 amendment 3) -------------


def test_validate_pack_dir_flags_contest_as_forbidden() -> None:
    pkt = load_packctl()
    with tempfile.TemporaryDirectory() as tmp:
        pack = _cmd_pack(
            Path(tmp),
            "  section: Audit\n  gate: verdict\n  contest: allow\n",
        )
        errors = pkt.validate_pack_dir(pack)
        assert any("judge.contest" in e for e in errors), "\n".join(errors)


def test_validate_pack_dir_accepts_gate_record_default() -> None:
    """`gate:` omitted entirely defaults to `record`, which never requires a
    `section:`."""
    pkt = load_packctl()
    with tempfile.TemporaryDirectory() as tmp:
        pack = _cmd_pack(Path(tmp), "")
        errors = pkt.validate_pack_dir(pack)
        assert not any("gate" in e for e in errors), "\n".join(errors)


def test_validate_pack_dir_accepts_gate_verdict_with_section() -> None:
    pkt = load_packctl()
    with tempfile.TemporaryDirectory() as tmp:
        pack = _cmd_pack(Path(tmp), "  section: Audit\n  gate: verdict\n")
        errors = pkt.validate_pack_dir(pack)
        assert not any("gate" in e for e in errors), "\n".join(errors)


def test_validate_pack_dir_accepts_gate_verdict_contestable_with_section() -> None:
    pkt = load_packctl()
    with tempfile.TemporaryDirectory() as tmp:
        pack = _cmd_pack(Path(tmp), "  section: Audit\n  gate: verdict-contestable\n")
        errors = pkt.validate_pack_dir(pack)
        assert not any("gate" in e for e in errors), "\n".join(errors)


def test_validate_pack_dir_flags_unknown_gate_value() -> None:
    pkt = load_packctl()
    with tempfile.TemporaryDirectory() as tmp:
        pack = _cmd_pack(Path(tmp), "  section: Audit\n  gate: forbid\n")
        errors = pkt.validate_pack_dir(pack)
        assert any("judge.gate" in e and "unknown value" in e for e in errors), "\n".join(errors)


def test_validate_pack_dir_flags_gate_verdict_without_section() -> None:
    """A `gate:` other than `record` with no `section:` is a declaration
    error — a verdict with nowhere to land."""
    pkt = load_packctl()
    with tempfile.TemporaryDirectory() as tmp:
        pack = _cmd_pack(Path(tmp), "  gate: verdict\n")
        errors = pkt.validate_pack_dir(pack)
        assert any(
            "judge.gate" in e and "requires judge.section" in e for e in errors
        ), "\n".join(errors)


def test_validate_pack_dir_flags_gate_verdict_contestable_without_section() -> None:
    pkt = load_packctl()
    with tempfile.TemporaryDirectory() as tmp:
        pack = _cmd_pack(Path(tmp), "  gate: verdict-contestable\n")
        errors = pkt.validate_pack_dir(pack)
        assert any(
            "judge.gate" in e and "requires judge.section" in e for e in errors
        ), "\n".join(errors)


# ---- judge.group / isolation (issue #355 amendment) ---------------------


def test_validate_pack_dir_flags_isolation_as_forbidden() -> None:
    pkt = load_packctl()
    with tempfile.TemporaryDirectory() as tmp:
        pack = _cmd_pack(
            Path(tmp),
            '  isolation: shared\n  cmd: { sweep: "claude -p --output-format text --model opus" }\n',
        )
        errors = pkt.validate_pack_dir(pack)
        assert any("judge.isolation" in e for e in errors), "\n".join(errors)


def test_validate_pack_dir_accepts_plain_group_scalar() -> None:
    pkt = load_packctl()
    with tempfile.TemporaryDirectory() as tmp:
        pack = _cmd_pack(
            Path(tmp),
            '  group: bundled-intent\n  cmd: { sweep: "claude -p --output-format text --model opus" }\n',
        )
        errors = pkt.validate_pack_dir(pack)
        assert errors == [], "\n".join(errors)


def test_validate_pack_dir_flags_group_with_differing_sweep_cmds() -> None:
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
                          group: bundled-intent
                          cmd: { sweep: "claude -p --output-format text --model opus" }
                    """),
                    "constitution_md": "no path reference here",
                },
                "y": {
                    "directive_yaml": textwrap.dedent("""\
                        category: Foundation
                        recommended: true
                        summary: y
                        hook: none
                        judge:
                          inputs: [range-diff]
                          checks:
                            - another rubric
                          group: bundled-intent
                          cmd: { sweep: "claude -p --output-format text --model haiku" }
                    """),
                    "constitution_md": "no path reference here",
                },
            },
        )
        errors = pkt.validate_pack_dir(pack)
        assert any(
            "group" in e and "bundled-intent" in e and "one invocation, one command" in e
            for e in errors
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
