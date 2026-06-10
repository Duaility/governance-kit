#!/usr/bin/env python3
"""Contract tests for kitverb.py — the `kit-plan` deterministic core.

Covers the version-delta resolution, manifest reconstruction, and the
managed-file inventory/status logic that UPDATE_FLOW.md Steps 1–3 depend on
(issue #170, finding B), plus a drift guard that fails loudly if the
up-to-date eval fixture stops matching the kit's KIT_VERSION (the latent rot
that turned eval 2's up-to-date case into a forward update once the kit bumped
0.3 → 0.3.5).
"""

from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PACK_LIB = ROOT / "governance" / "assets" / "packs" / "lib"
KITVERB_PATH = PACK_LIB / "kitverb.py"


def load_kitverb():
    sys.path.insert(0, str(PACK_LIB))
    spec = importlib.util.spec_from_file_location("kitverb_under_test", KITVERB_PATH)
    if spec is None or spec.loader is None:
        raise AssertionError(f"cannot load {KITVERB_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


KITVERB = load_kitverb()
KIT_VERSION = KITVERB.KIT_VERSION
OLDER = "0.0.1"          # always below any real kit version
NEWER = "999.0"          # always above


def kit_plan(root: Path) -> dict:
    result = subprocess.run(
        [sys.executable, str(KITVERB_PATH), "kit-plan", str(root)],
        cwd=ROOT, check=False, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    assert result.returncode == 0, f"kit-plan failed: {result.stderr}"
    return json.loads(result.stdout)


def _marked(version: str | None) -> str:
    """A managed runtime file: shebang + marker on line 2 (versioned or bare)."""
    marker = "# governance-kit:managed"
    if version is not None:
        marker += f" kit-version={version}"
    return f"#!/usr/bin/env bash\n{marker}\nplaceholder\n"


def make_repo(tmp: Path, *, manifest: str | None, files: dict[str, str] | None = None) -> Path:
    root = Path(tmp)
    (root / ".governance").mkdir(parents=True, exist_ok=True)
    if manifest is not None:
        (root / ".governance" / "install.yaml").write_text(manifest)
    for rel, content in (files or {}).items():
        dest = root / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(content)
    return root


BASE_MANIFEST = (
    'version: "3"\n'
    "tests_dir: .governance\n"
    "ci_workflow: .github/workflows/governance.yml\n"
    "enable_governance_script: scripts/enable-governance.sh\n"
    "hook_strategy: githooks\n"
)


def test_delta_forward_when_installed_below_kit() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = make_repo(tmp, manifest=BASE_MANIFEST + f'kit_version: "{OLDER}"\n')
        plan = kit_plan(root)
        assert plan["delta"] == "forward"
        assert plan["installed_kit_version"] == OLDER
        assert plan["manifest_source"] == "install.yaml"


def test_delta_up_to_date_when_installed_equals_kit() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = make_repo(tmp, manifest=BASE_MANIFEST + f'kit_version: "{KIT_VERSION}"\n')
        assert kit_plan(root)["delta"] == "up-to-date"


def test_delta_downgrade_when_installed_above_kit() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = make_repo(tmp, manifest=BASE_MANIFEST + f'kit_version: "{NEWER}"\n')
        assert kit_plan(root)["delta"] == "downgrade"


def test_pre_tracking_when_manifest_present_without_kit_version() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = make_repo(tmp, manifest=BASE_MANIFEST)  # no kit_version line
        plan = kit_plan(root)
        assert plan["delta"] == "pre-tracking"
        assert plan["installed_kit_version"] is None


def test_no_recoverable_pin_when_no_manifest_and_no_markers() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        # No manifest; runtime files carry only the bare marker (no kit-version=).
        root = make_repo(tmp, manifest=None, files={
            ".governance/run.sh": _marked(None),
            ".governance/lib.sh": _marked(None),
        })
        plan = kit_plan(root)
        assert plan["delta"] == "no-recoverable-pin"
        assert plan["manifest_source"] == "absent"


def test_reconstruct_takes_min_of_markers_when_manifest_absent() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = make_repo(tmp, manifest=None, files={
            ".governance/run.sh": _marked("0.2"),
            ".governance/lib.sh": _marked("0.1"),       # min → reconstructed pin
        })
        plan = kit_plan(root)
        assert plan["manifest_source"] == "reconstructed"
        assert plan["installed_kit_version"] == "0.1"
        assert plan["delta"] == "forward"
        assert set(plan["reconstructed_from"]) == {".governance/run.sh", ".governance/lib.sh"}


def test_single_quoted_kit_version_is_read() -> None:
    # Robustness mirror of finding A: older-init repos single-quote the pin.
    # The Python reader uses a real YAML parser, so both quote styles work.
    with tempfile.TemporaryDirectory() as tmp:
        root = make_repo(tmp, manifest=BASE_MANIFEST + f"kit_version: '{KIT_VERSION}'\n")
        assert kit_plan(root)["installed_kit_version"] == KIT_VERSION


def test_inventory_status_hints() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = make_repo(tmp, manifest=BASE_MANIFEST + f'kit_version: "{OLDER}"\n', files={
            ".governance/run.sh": _marked(KIT_VERSION),        # versioned == kit → skip
            ".governance/lib.sh": _marked(OLDER),              # versioned older → apply
            ".github/workflows/governance.yml": _marked(None),  # bare marker → apply
            "scripts/enable-governance.sh": "#!/usr/bin/env bash\nno marker here\n",  # → unmanaged
        })
        files = {f["key"]: f for f in kit_plan(root)["files"]}
        assert files["run.sh"]["status"] == "skip"
        assert files["lib.sh"]["status"] == "apply"
        assert files["ci_workflow"]["status"] == "apply"
        assert files["enable_governance_script"]["status"] == "unmanaged"


def test_inventory_status_add_when_dest_missing() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = make_repo(tmp, manifest=BASE_MANIFEST + f'kit_version: "{OLDER}"\n')  # no files
        files = {f["key"]: f for f in kit_plan(root)["files"]}
        assert files["run.sh"]["status"] == "add"
        assert files["run.sh"]["exists"] is False


SAMPLE_LS_REMOTE = "\n".join([
    "a1b2c3\trefs/tags/kit/v0.3.5",
    "d4e5f6\trefs/tags/kit/v0.4.0",
    "d4e5f6\trefs/tags/kit/v0.4.0^{}",     # annotated-tag deref duplicate
    "778899\trefs/tags/kit/v0.4.1",
    "aabbcc\trefs/tags/core/v0.4.0",        # non-kit axis — ignored
    "ddeeff\trefs/heads/main",              # non-tag — ignored
])


def test_parse_kit_tags_extracts_dedupes_and_filters() -> None:
    assert KITVERB.parse_kit_tags(SAMPLE_LS_REMOTE) == ["0.3.5", "0.4.0", "0.4.1"]


def test_parse_kit_tags_empty_when_no_kit_tags() -> None:
    assert KITVERB.parse_kit_tags("aabbcc\trefs/tags/core/v0.4.0\n") == []


def test_upstream_status_behind_counts_newer_releases() -> None:
    st = KITVERB.upstream_status(["0.3.5", "0.4.0", "0.4.1"], "0.3.5")
    assert st["status"] == "behind"
    assert st["latest_published"] == "0.4.1"
    assert st["releases_behind"] == 2


def test_upstream_status_current_when_installed_is_latest() -> None:
    st = KITVERB.upstream_status(["0.3.5", "0.4.0", "0.4.1"], "0.4.1")
    assert st["status"] == "current"
    assert st["releases_behind"] == 0


def test_upstream_status_ahead_when_installed_above_latest() -> None:
    st = KITVERB.upstream_status(["0.3.5", "0.4.0"], "0.9.0")
    assert st["status"] == "ahead"
    assert st["releases_behind"] == 0


def test_upstream_status_unknown_when_no_published_tags() -> None:
    st = KITVERB.upstream_status([], "0.3.5")
    assert st["status"] == "unknown"
    assert st["latest_published"] is None


def test_up_to_date_fixture_pin_tracks_kit_version() -> None:
    # Drift guard: scripts/release.sh skips governance/evals/*, so a kit bump
    # that forgets this fixture silently turns eval 2's up-to-date case into a
    # forward update. Keep the pin equal to the kit's KIT_VERSION.
    import yaml  # noqa: PLC0415 - test-only dep, provided by the suite runner.
    fixture = ROOT / "governance/evals/kit-update/files/up-to-date-repo/.governance/install.yaml"
    pin = yaml.safe_load(fixture.read_text())["kit_version"]
    assert str(pin) == KIT_VERSION, (
        f"up-to-date fixture pins kit_version={pin!r} but the kit is {KIT_VERSION!r} — "
        "re-pin governance/evals/kit-update/files/up-to-date-repo/ to match a kit release"
    )


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
