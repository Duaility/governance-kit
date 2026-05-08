#!/usr/bin/env python3
"""Unit tests for the public packctl helper surface.

packctl.py is the brain of pack manifest validation, preset resolution
(union semantics, inheritance, cycle detection), `min_governance_kit`
gating, and the CLI subcommands invoked by packs.sh. A silent bug here
changes which directives get installed, so the tests cover both the
library API and the argparse CLI.
"""

from __future__ import annotations

import importlib.util
import os
import subprocess
import sys
import tempfile
import textwrap
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PACK_LIB = ROOT / "governance" / "assets" / "packs" / "lib"
PACKCTL_PATH = PACK_LIB / "packctl.py"
CORE_PACK = ROOT / "packs" / "core"


def load_packctl():
    sys.path.insert(0, str(PACK_LIB))
    spec = importlib.util.spec_from_file_location("packctl_under_test", PACKCTL_PATH)
    if spec is None or spec.loader is None:
        raise AssertionError(f"cannot load {PACKCTL_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def run_packctl(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(PACKCTL_PATH), *args],
        cwd=ROOT,
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


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


# ---- _version_tuple + kit_supports ----------------------------------------

def test_version_tuple_orders_numeric_segments_numerically() -> None:
    pkt = load_packctl()
    # 0.10 must rank above 0.2, not lexicographically below.
    assert pkt._version_tuple("0.10") > pkt._version_tuple("0.2")
    assert pkt._version_tuple("1.0") > pkt._version_tuple("0.99")
    assert pkt._version_tuple("0.2") == pkt._version_tuple("0.2")


def test_version_tuple_handles_non_numeric_segments() -> None:
    pkt = load_packctl()
    # Non-numeric segments fall under a higher tag than numeric, so a
    # pre-release "0.2.alpha" sorts above plain "0.2" — caller must ensure
    # `min_governance_kit` uses pure numeric SemVer when comparing.
    assert pkt._version_tuple("0.2.alpha") > pkt._version_tuple("0.2")


def test_kit_supports_accepts_equal_and_lower_minimum() -> None:
    pkt = load_packctl()
    assert pkt.kit_supports("") is True  # empty min_required → no constraint
    assert pkt.kit_supports("0.1") is True
    assert pkt.kit_supports(pkt.KIT_VERSION) is True


def test_kit_supports_rejects_higher_minimum() -> None:
    pkt = load_packctl()
    too_new = ".".join([pkt.KIT_VERSION.split(".")[0], str(int(pkt.KIT_VERSION.split(".")[1]) + 1)])
    assert pkt.kit_supports(too_new) is False


# ---- resolve_preset --------------------------------------------------------

def test_resolve_preset_returns_directive_ids_in_declared_order() -> None:
    pkt = load_packctl()
    with tempfile.TemporaryDirectory() as tmp:
        pack = make_pack(
            Path(tmp),
            pack_yaml=textwrap.dedent("""\
                id: demo
                name: Demo
                version: "0.1"
                description: Demo
                author: T
                presets:
                  minimal:
                    directives: [a, b]
                  standard:
                    extends: minimal
                    directives: [c]
            """),
            directives={
                "a": {"directive_yaml": "summary: a\n"},
                "b": {"directive_yaml": "summary: b\n"},
                "c": {"directive_yaml": "summary: c\n"},
            },
        )
        assert pkt.resolve_preset(pack, "minimal") == ["a", "b"]
        assert pkt.resolve_preset(pack, "standard") == ["a", "b", "c"]


def test_resolve_preset_dedupes_inherited_ids() -> None:
    pkt = load_packctl()
    with tempfile.TemporaryDirectory() as tmp:
        pack = make_pack(
            Path(tmp),
            pack_yaml=textwrap.dedent("""\
                id: demo
                name: Demo
                version: "0.1"
                description: Demo
                author: T
                presets:
                  minimal:
                    directives: [a, b]
                  standard:
                    extends: minimal
                    directives: [b, c]
            """),
            directives={k: {"directive_yaml": f"summary: {k}\n"} for k in ("a", "b", "c")},
        )
        assert pkt.resolve_preset(pack, "standard") == ["a", "b", "c"]


def test_resolve_preset_detects_inheritance_cycle() -> None:
    pkt = load_packctl()
    with tempfile.TemporaryDirectory() as tmp:
        pack = make_pack(
            Path(tmp),
            pack_yaml=textwrap.dedent("""\
                id: demo
                name: Demo
                version: "0.1"
                description: Demo
                author: T
                presets:
                  loop_a:
                    extends: loop_b
                    directives: []
                  loop_b:
                    extends: loop_a
                    directives: []
            """),
            directives={},
        )
        try:
            pkt.resolve_preset(pack, "loop_a")
        except ValueError as exc:
            assert "cycle" in str(exc).lower()
        else:
            raise AssertionError("expected ValueError on preset cycle")


def test_resolve_preset_raises_keyerror_for_unknown_preset() -> None:
    pkt = load_packctl()
    with tempfile.TemporaryDirectory() as tmp:
        pack = make_pack(
            Path(tmp),
            pack_yaml=textwrap.dedent("""\
                id: demo
                name: Demo
                version: "0.1"
                description: Demo
                author: T
                presets:
                  minimal:
                    directives: [a]
            """),
            directives={"a": {"directive_yaml": "summary: a\n"}},
        )
        try:
            pkt.resolve_preset(pack, "no-such-preset")
        except KeyError:
            pass
        else:
            raise AssertionError("expected KeyError on unknown preset")


# ---- directives_for_pack ---------------------------------------------------

def test_directives_for_pack_returns_sorted_directive_ids() -> None:
    pkt = load_packctl()
    listed = pkt.directives_for_pack(CORE_PACK)
    assert listed == sorted(listed)
    # Sanity: a known core directive is in the list.
    assert "secrets-hygiene" in listed


def test_directives_for_pack_skips_folders_without_directive_yaml() -> None:
    pkt = load_packctl()
    with tempfile.TemporaryDirectory() as tmp:
        pack = make_pack(
            Path(tmp),
            pack_yaml="id: demo\nname: D\nversion: '0'\ndescription: d\nauthor: T\npresets: {}\n",
            directives={"a": {"directive_yaml": "summary: a\n"}},
        )
        # Sibling folder without a directive.yaml is ignored.
        (pack / "directives" / "stray").mkdir()
        assert pkt.directives_for_pack(pack) == ["a"]


# ---- validate_pack_dir -----------------------------------------------------
# Validation tests live in scripts/test-packctl-validate.py to keep this file
# under the repo-hygiene 500-line limit. They share the same load_packctl /
# make_pack helpers (duplicated, since the kit avoids private test-helper
# modules to keep each test file standalone).


# ---- CLI subcommands -------------------------------------------------------

def test_cli_kit_version_prints_constant() -> None:
    pkt = load_packctl()
    result = run_packctl("kit-version")
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == pkt.KIT_VERSION


def test_cli_directives_for_lists_known_core_directives() -> None:
    result = run_packctl("directives-for", str(CORE_PACK))
    assert result.returncode == 0, result.stderr
    listed = [line for line in result.stdout.splitlines() if line]
    assert "secrets-hygiene" in listed
    assert "required-docs" in listed


def test_cli_pack_field_prints_id_and_version() -> None:
    res_id = run_packctl("pack-field", str(CORE_PACK), "id")
    res_version = run_packctl("pack-field", str(CORE_PACK), "version")
    assert res_id.returncode == 0
    assert res_version.returncode == 0
    assert res_id.stdout.strip() == "governance-kit/core"
    # Version is a string scalar.
    assert res_version.stdout.strip() != ""


def test_cli_directive_field_returns_blank_for_unknown_field() -> None:
    result = run_packctl("directive-field", str(CORE_PACK), "secrets-hygiene", "no-such-key")
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == ""


def test_cli_preset_resolve_returns_nonzero_for_unknown_preset() -> None:
    result = run_packctl("preset-resolve", str(CORE_PACK), "no-such-preset")
    assert result.returncode != 0


def test_cli_union_preset_unions_across_packs_no_fallback() -> None:
    pkt = load_packctl()
    with tempfile.TemporaryDirectory() as tmp:
        # Build a synthetic second pack so `union-preset` can be exercised
        # against more than one pack.
        second = make_pack(
            Path(tmp),
            pack_yaml=textwrap.dedent(
                """\
                id: acme/widgets
                name: Demo
                version: "0.1"
                min_governance_kit: "0.1"
                description: Synthetic demo pack for union-preset coverage.
                author: tests
                presets:
                  minimal:
                    directives: [demo-rule]
                  standard:
                    extends: minimal
                    directives: []
                  strict:
                    extends: standard
                    directives: []
                """
            ),
            directives={
                "demo-rule": {
                    "directive_yaml": (
                        "category: Foundation\nrecommended: true\n"
                        "summary: demo\nsurface: repo-state\nhook: none\n"
                    ),
                    "check_sh": "#!/usr/bin/env bash\nexit 0\n",
                    "constitution_md": "### demo-rule\n",
                },
            },
        )
        result = run_packctl(
            "union-preset",
            "minimal",
            str(CORE_PACK),
            str(second),
        )
        assert result.returncode == 0, result.stderr
        out_ids = [line for line in result.stdout.splitlines() if line]
        expected: list[str] = []
        seen: set[str] = set()
        for pack in (CORE_PACK, second):
            try:
                for did in pkt.resolve_preset(pack, "minimal"):
                    if did not in seen:
                        seen.add(did)
                        expected.append(did)
            except KeyError:
                continue
        assert out_ids == expected


def test_cli_always_install_lists_only_always_install_directives() -> None:
    pkt = load_packctl()
    result = run_packctl("always-install-directives", str(CORE_PACK))
    assert result.returncode == 0, result.stderr
    listed = [line for line in result.stdout.splitlines() if line]
    # Cross-check: every listed directive's manifest declares always_install: true.
    for did in listed:
        manifest = pkt.directive_manifest(CORE_PACK, did)
        assert manifest.get("always_install") is True
    # Cross-check: every always_install directive in core appears.
    expected = sorted(
        did for did in pkt.directives_for_pack(CORE_PACK)
        if pkt.directive_manifest(CORE_PACK, did).get("always_install") is True
    )
    assert sorted(listed) == expected


def test_cli_validate_pack_set_flags_duplicate_directive_ids_across_packs() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        pack_a = make_pack(
            Path(tmp) / "a",
            pack_yaml=textwrap.dedent("""\
                id: pack-a
                name: A
                version: "0.1"
                min_governance_kit: "0.1"
                description: a
                author: T
                presets: {}
            """),
            directives={
                "shared": {
                    "directive_yaml": textwrap.dedent("""\
                        category: Foundation
                        recommended: true
                        summary: s
                        surface: repo-state
                        hook: none
                    """),
                    "check_sh": "#!/usr/bin/env bash\nexit 0\n",
                    "constitution_md": "ref .governance/packs/pack-a/directives/shared/check.sh",
                },
            },
        )
        pack_b = make_pack(
            Path(tmp) / "b",
            pack_yaml=textwrap.dedent("""\
                id: pack-b
                name: B
                version: "0.1"
                min_governance_kit: "0.1"
                description: b
                author: T
                presets: {}
            """),
            directives={
                "shared": {
                    "directive_yaml": textwrap.dedent("""\
                        category: Foundation
                        recommended: true
                        summary: s
                        surface: repo-state
                        hook: none
                    """),
                    "check_sh": "#!/usr/bin/env bash\nexit 0\n",
                    "constitution_md": "ref .governance/packs/pack-b/directives/shared/check.sh",
                },
            },
        )
        # Rename to match pack ids for the directory-name check.
        pack_a.rename(pack_a.parent / "pack-a")
        pack_b.rename(pack_b.parent / "pack-b")
        result = run_packctl(
            "validate-pack-set",
            str(pack_a.parent / "pack-a"),
            str(pack_b.parent / "pack-b"),
        )
        assert result.returncode != 0
        assert "duplicate directive id 'shared'" in result.stdout


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
