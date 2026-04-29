#!/usr/bin/env python3
"""validate_pack_dir matrix tests for packctl.py.

Split from scripts/test-packctl.py to keep both files under the repo-hygiene
500-line limit. Helpers (load_packctl, make_pack) are duplicated rather than
extracted into a shared module — each test file in this repo stays standalone.
"""

from __future__ import annotations

import importlib.util
import os
import sys
import tempfile
import textwrap
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PACK_LIB = ROOT / "governance" / "assets" / "packs" / "lib"
PACKCTL_PATH = PACK_LIB / "packctl.py"
CORE_PACK = ROOT / "governance" / "assets" / "packs" / "core"
AGENT_PACK = ROOT / "extensions" / "packs" / "agent-governance"


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

def test_validate_pack_dir_passes_on_shipped_core_pack() -> None:
    pkt = load_packctl()
    errors = pkt.validate_pack_dir(CORE_PACK)
    assert errors == [], "\n".join(errors)


def test_validate_pack_dir_passes_on_shipped_agent_pack() -> None:
    pkt = load_packctl()
    errors = pkt.validate_pack_dir(AGENT_PACK)
    assert errors == [], "\n".join(errors)


# ---- pack-level fields -----------------------------------------------------

def test_validate_pack_dir_flags_missing_required_pack_fields() -> None:
    pkt = load_packctl()
    with tempfile.TemporaryDirectory() as tmp:
        pack = make_pack(
            Path(tmp),
            pack_yaml="id: demo\npresets: {}\n",
            directives={},
        )
        errors = pkt.validate_pack_dir(pack)
        joined = "\n".join(errors)
        assert "missing required field 'name'" in joined
        assert "missing required field 'version'" in joined
        assert "missing required field 'description'" in joined
        assert "missing required field 'author'" in joined


def test_validate_pack_dir_flags_id_directory_mismatch() -> None:
    pkt = load_packctl()
    with tempfile.TemporaryDirectory() as tmp:
        pack = make_pack(
            Path(tmp),
            pack_yaml=textwrap.dedent("""\
                id: acme/not-demo
                name: D
                version: "0.1"
                min_governance_kit: "0.1"
                description: d
                author: T
                presets: {}
            """),
            directives={},
        )
        errors = pkt.validate_pack_dir(pack)
        assert any("does not match directory name" in e for e in errors)


def test_validate_pack_dir_rejects_unscoped_pack_id() -> None:
    """Pack ids must be `<author>/<slug>`. An unscoped id (no `/`) is rejected
    so installed packs always land at `.governance/packs/<owner>/<name>/`."""
    pkt = load_packctl()
    with tempfile.TemporaryDirectory() as tmp:
        pack = make_pack(
            Path(tmp),
            pack_yaml=textwrap.dedent("""\
                id: demo
                name: D
                version: "0.1"
                min_governance_kit: "0.1"
                description: d
                author: T
                presets: {}
            """),
            directives={},
        )
        errors = pkt.validate_pack_dir(pack)
        assert any("must be scoped" in e for e in errors), "\n".join(errors)


def test_validate_pack_dir_accepts_scoped_id_against_slug() -> None:
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
            directives={},
        )
        errors = pkt.validate_pack_dir(pack)
        assert not any("does not match directory name" in e for e in errors)


def test_validate_pack_dir_rejects_min_kit_newer_than_installed() -> None:
    pkt = load_packctl()
    with tempfile.TemporaryDirectory() as tmp:
        pack = make_pack(
            Path(tmp),
            pack_yaml=textwrap.dedent("""\
                id: acme/demo
                name: D
                version: "0.1"
                min_governance_kit: "999.0"
                description: d
                author: T
                presets: {}
            """),
            directives={},
        )
        errors = pkt.validate_pack_dir(pack)
        assert any("newer than installed kit" in e for e in errors)


# ---- preset references -----------------------------------------------------

def test_validate_pack_dir_flags_preset_referencing_unknown_directive() -> None:
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
                presets:
                  minimal:
                    directives: [does-not-exist]
            """),
            directives={},
        )
        errors = pkt.validate_pack_dir(pack)
        assert any("references unknown directive" in e for e in errors)


# ---- directive metadata ----------------------------------------------------

def test_validate_pack_dir_rejects_always_install_outside_core() -> None:
    pkt = load_packctl()
    with tempfile.TemporaryDirectory() as tmp:
        pack = make_pack(
            Path(tmp),
            pack_yaml=textwrap.dedent("""\
                id: not-core
                name: D
                version: "0.1"
                min_governance_kit: "0.1"
                description: d
                author: T
                presets: {}
            """),
            directives={
                "demo": {
                    "directive_yaml": textwrap.dedent("""\
                        category: Foundation
                        recommended: true
                        summary: demo
                        surface: repo-state
                        hook: none
                        always_install: true
                    """),
                    "check_sh": "#!/usr/bin/env bash\nexit 0\n",
                    "constitution_md": "ref .governance/packs/not-core/directives/demo/check.sh",
                },
            },
        )
        renamed = pack.parent / "not-core"
        pack.rename(renamed)
        errors = pkt.validate_pack_dir(renamed)
        assert any("always_install: true is reserved to the governance-kit/core pack" in e for e in errors)


def test_validate_pack_dir_flags_unknown_hook_value() -> None:
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
                        hook: not-a-real-hook
                    """),
                    "check_sh": "#!/usr/bin/env bash\nexit 0\n",
                    "constitution_md": "ref .governance/packs/demo/directives/x/check.sh",
                },
            },
        )
        errors = pkt.validate_pack_dir(pack)
        assert any("unknown hook value 'not-a-real-hook'" in e for e in errors)


def test_validate_pack_dir_flags_unknown_surface_value() -> None:
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
                        surface: nonsense
                        hook: none
                    """),
                    "check_sh": "#!/usr/bin/env bash\nexit 0\n",
                    "constitution_md": "ref .governance/packs/demo/directives/x/check.sh",
                },
            },
        )
        errors = pkt.validate_pack_dir(pack)
        assert any("unknown surface value 'nonsense'" in e for e in errors)


def test_validate_pack_dir_requires_constitution_to_reference_check_path() -> None:
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
                        hook: none
                    """),
                    "check_sh": "#!/usr/bin/env bash\nexit 0\n",
                    "constitution_md": "no path reference here",
                },
            },
        )
        errors = pkt.validate_pack_dir(pack)
        assert any("constitution.md must reference" in e for e in errors)


def test_validate_pack_dir_flags_non_executable_check_sh() -> None:
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
                        hook: none
                    """),
                    "check_sh": "#!/usr/bin/env bash\nexit 0\n",
                    "constitution_md": "ref .governance/packs/demo/directives/x/check.sh",
                },
            },
        )
        os.chmod(pack / "directives" / "x" / "check.sh", 0o644)
        errors = pkt.validate_pack_dir(pack)
        assert any("check.sh is not executable" in e for e in errors)


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
