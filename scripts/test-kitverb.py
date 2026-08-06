#!/usr/bin/env python3
# governance: allow-repo-hygiene file-size-limit one consolidated test layer for the kit-update verbs (issue #355)
"""Contract tests for kitverb.py — the `kit-plan` / `kit-apply` deterministic core.

Covers the version-delta resolution, manifest reconstruction, and the
managed-file inventory/status logic that UPDATE_FLOW.md Steps 1–3 depend on
(issue #170, finding B), plus a drift guard that fails loudly if the
up-to-date eval fixture stops matching the kit's KIT_VERSION (the latent rot
that turned eval 2's up-to-date case into a forward update once the kit bumped
0.3 → 0.3.5).

The `kit-apply` section (issue #172) exercises the execution half against
throwaway git repos: the delta gates (downgrade / pre-tracking /
no-recoverable-pin refusals), the dirty-tree gate and `--force`, per-file
unmanaged decisions (`keep` / `apply` / `overwrite-with-backup`), `--dry-run`
purity, marker re-stamping, manifest write-through (in-place and the
reconstructed fresh-manifest path), and hook-dispatcher regeneration.
"""

from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PACK_LIB = ROOT / "kit" / "assets" / "packs" / "lib"
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
        })
        files = {f["key"]: f for f in kit_plan(root)["files"]}
        assert files["run.sh"]["status"] == "skip"
        assert files["lib.sh"]["status"] == "apply"
        assert files["ci_workflow"]["status"] == "apply"
        # enable-governance.sh is no longer in the managed inventory (issue #267).
        assert "enable_governance_script" not in files


def test_inventory_status_add_when_dest_missing() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = make_repo(tmp, manifest=BASE_MANIFEST + f'kit_version: "{OLDER}"\n')  # no files
        files = {f["key"]: f for f in kit_plan(root)["files"]}
        assert files["run.sh"]["status"] == "add"
        assert files["run.sh"]["exists"] is False


# --- kit-apply (issue #172) -------------------------------------------------

# Strip inherited git plumbing vars so fixture repos never alias the host
# gitdir when this file runs under a hook (same guard scripts/test.sh applies).
GIT_CLEAN_ENV = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}


def git(root: Path, *argv: str) -> None:
    subprocess.run(
        ["git", "-C", str(root), "-c", "user.email=t@t", "-c", "user.name=t",
         "-c", "commit.gpgsign=false", *argv],
        check=True, env=GIT_CLEAN_ENV, capture_output=True,
    )


def make_git_repo(tmp: Path, *, manifest: str | None, files: dict[str, str] | None = None) -> Path:
    root = make_repo(tmp, manifest=manifest, files=files)
    git(root, "init", "-q")
    git(root, "add", "-A")
    git(root, "commit", "-qm", "fixture")
    return root


def kit_apply(root: Path, *flags: str) -> tuple[int, dict]:
    result = subprocess.run(
        [sys.executable, str(KITVERB_PATH), "kit-apply", str(root), *flags],
        cwd=ROOT, check=False, text=True, env=GIT_CLEAN_ENV,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    assert result.stdout.strip(), f"kit-apply printed no report: {result.stderr}"
    return result.returncode, json.loads(result.stdout)


def tree_digest(root: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    for path in sorted(root.rglob("*")):
        if path.is_file() and ".git" not in path.parts:
            out[str(path.relative_to(root))] = hashlib.sha256(path.read_bytes()).hexdigest()
    return out


STALE_FILES = {
    ".governance/run.sh": _marked(OLDER),
    ".governance/lib.sh": _marked(OLDER),
    ".github/workflows/governance.yml": f"# governance-kit:managed kit-version={OLDER}\nname: governance\n",
}
STALE_MANIFEST = BASE_MANIFEST + f'kit_version: "{OLDER}"\n'

# A managed-file slot left user-owned (no ownership marker) exercises the
# unmanaged decision machinery, now that enable-governance.sh is no longer
# vendored (issue #267): the CI workflow without its marker reads as unmanaged.
UNMANAGED_DEST = ".github/workflows/governance.yml"
UNMANAGED_FILES = {
    ".governance/run.sh": _marked(OLDER),
    ".governance/lib.sh": _marked(OLDER),
    UNMANAGED_DEST: "name: governance\n",  # no marker → unmanaged
}


def test_apply_forward_stamps_files_and_writes_manifest_through() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = make_git_repo(Path(tmp), manifest=STALE_MANIFEST, files=STALE_FILES)
        rc, report = kit_apply(root)
        assert rc == 0 and report["result"] == "applied", report
        assert set(report["updated"]) == {
            ".governance/run.sh", ".governance/lib.sh", ".github/workflows/governance.yml",
        }
        for rel in report["updated"]:
            marker = KITVERB.read_marker(root / rel)
            assert marker == {"state": "versioned", "version": KIT_VERSION}, (rel, marker)
        manifest = (root / ".governance/install.yaml").read_text()
        assert f'kit_version: "{KIT_VERSION}"' in manifest
        # in-place write-through preserves every other manifest field
        assert "ci_workflow: .github/workflows/governance.yml" in manifest
        assert report["manifest"] == "updated"
        assert report["hook_dispatcher"] == "regenerated"
        for kind in ("pre-commit", "commit-msg", "pre-push"):
            assert (root / ".githooks" / kind).is_file(), kind
        assert report["smoke_test"]["exit_code"] == 0, report["smoke_test"]


def test_apply_up_to_date_is_a_pure_noop() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = make_git_repo(
            Path(tmp),
            manifest=BASE_MANIFEST + f'kit_version: "{KIT_VERSION}"\n',
            files={".governance/run.sh": _marked(KIT_VERSION)},
        )
        before = tree_digest(root)
        rc, report = kit_apply(root)
        assert rc == 0 and report["result"] == "up-to-date", report
        assert tree_digest(root) == before


def test_apply_refuses_downgrade() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = make_git_repo(Path(tmp), manifest=BASE_MANIFEST + f'kit_version: "{NEWER}"\n')
        before = tree_digest(root)
        rc, report = kit_apply(root)
        assert rc == 2 and report["result"] == "refused", report
        assert "newer than the target" in report["reason"]
        assert "--allow-downgrade" in report["recovery"]
        assert tree_digest(root) == before


def test_apply_refuses_no_recoverable_pin() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = make_git_repo(Path(tmp), manifest=None,
                             files={".governance/run.sh": _marked(None)})
        rc, report = kit_apply(root)
        assert rc == 2 and report["result"] == "refused", report
        assert "uninstall" in report["recovery"]


def test_apply_refuses_dirty_tree_unless_forced() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = make_git_repo(Path(tmp), manifest=STALE_MANIFEST, files=STALE_FILES)
        (root / "wip.txt").write_text("uncommitted\n")
        rc, report = kit_apply(root)
        assert rc == 2 and "uncommitted" in report["reason"], report
        rc, report = kit_apply(root, "--force")
        assert rc == 0 and report["result"] == "applied", report
        assert any("--force" in a for a in report["assumptions"])


def test_apply_unmanaged_default_keep_leaves_file_alone() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = make_git_repo(Path(tmp), manifest=STALE_MANIFEST, files=UNMANAGED_FILES)
        original = (root / UNMANAGED_DEST).read_text()
        rc, report = kit_apply(root)
        assert rc == 0, report
        assert report["unmanaged"] == [{"dest": UNMANAGED_DEST, "decision": "keep"}]
        assert (root / UNMANAGED_DEST).read_text() == original


def test_apply_unmanaged_overwrite_with_backup() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = make_git_repo(Path(tmp), manifest=STALE_MANIFEST, files=UNMANAGED_FILES)
        original = (root / UNMANAGED_DEST).read_text()
        rc, report = kit_apply(
            root, "--decisions", f'{{"{UNMANAGED_DEST}": "overwrite-with-backup"}}')
        assert rc == 0, report
        assert report["backups"] == [f"{UNMANAGED_DEST}.pre-update.bak"]
        assert (root / f"{UNMANAGED_DEST}.pre-update.bak").read_text() == original
        marker = KITVERB.read_marker(root / UNMANAGED_DEST)
        assert marker == {"state": "versioned", "version": KIT_VERSION}


def test_apply_managed_keep_override_skips_the_file() -> None:
    # Interaction policy: a hand-edited managed file may be kept per-file.
    with tempfile.TemporaryDirectory() as tmp:
        root = make_git_repo(Path(tmp), manifest=STALE_MANIFEST, files=STALE_FILES)
        original = (root / ".governance/lib.sh").read_text()
        rc, report = kit_apply(root, "--decisions", '{".governance/lib.sh": "keep"}')
        assert rc == 0 and report["result"] == "applied", report
        assert report["kept"] == [".governance/lib.sh"]
        assert ".governance/lib.sh" not in report["updated"]
        assert (root / ".governance/lib.sh").read_text() == original
        # the others still applied
        marker = KITVERB.read_marker(root / ".governance/run.sh")
        assert marker == {"state": "versioned", "version": KIT_VERSION}


def test_apply_rejects_bad_decisions() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = make_git_repo(Path(tmp), manifest=STALE_MANIFEST, files=STALE_FILES)
        # invalid decision value
        rc, report = kit_apply(root, "--decisions", '{".governance/lib.sh": "merge"}')
        assert rc == 2 and "bad --decisions" in report["reason"], report
        # destination with nothing to decide (not in the plan at all)
        rc, report = kit_apply(root, "--decisions", '{"README.md": "apply"}')
        assert rc == 2 and "nothing to decide" in report["reason"], report


def test_apply_dry_run_writes_nothing() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = make_git_repo(Path(tmp), manifest=STALE_MANIFEST, files=UNMANAGED_FILES)
        before = tree_digest(root)
        rc, report = kit_apply(
            root, "--dry-run",
            "--decisions", f'{{"{UNMANAGED_DEST}": "overwrite-with-backup"}}')
        assert rc == 0 and report["result"] == "dry-run", report
        assert tree_digest(root) == before
        assert ".governance/run.sh" in report["updated"]
        assert report["backups"] == [f"{UNMANAGED_DEST}.pre-update.bak"]


def test_apply_pre_tracking_needs_explicit_consent() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = make_git_repo(Path(tmp), manifest=BASE_MANIFEST,  # no kit_version
                             files={".governance/run.sh": _marked(OLDER)})
        rc, report = kit_apply(root)
        assert rc == 2 and "--record-pre-tracking" in report["recovery"], report
        rc, report = kit_apply(root, "--record-pre-tracking")
        assert rc == 0 and report["result"] == "applied", report
        assert f'kit_version: "{KIT_VERSION}"' in (root / ".governance/install.yaml").read_text()


def test_apply_reconstructed_pin_writes_fresh_manifest() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = make_git_repo(Path(tmp), manifest=None, files={
            ".governance/run.sh": _marked(OLDER),
            ".governance/lib.sh": _marked(OLDER),
        })
        rc, report = kit_apply(root)
        assert rc == 2 and "--owner" in report["recovery"], report
        rc, report = kit_apply(root, "--owner", "acme", "--repo", "demo")
        assert rc == 0 and report["result"] == "applied", report
        assert report["manifest"] == "created"
        assert any("reconstructed" in a for a in report["assumptions"])
        manifest = (root / ".governance/install.yaml").read_text()
        assert "owner: acme" in manifest and "repo: demo" in manifest
        assert f'kit_version: "{KIT_VERSION}"' in manifest


def test_kit_plan_diff_emits_per_file_unified_diffs() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = make_repo(tmp, manifest=STALE_MANIFEST, files=STALE_FILES)
        result = subprocess.run(
            [sys.executable, str(KITVERB_PATH), "kit-plan", str(root), "--diff"],
            cwd=ROOT, check=False, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        assert result.returncode == 0, result.stderr
        files = {f["dest"]: f for f in json.loads(result.stdout)["files"]}
        run_sh = files[".governance/run.sh"]
        assert run_sh["diff"].startswith("--- a/.governance/run.sh")
        # the diff is computed against the *stamped* source: the new side of the
        # marker line carries the kit's version, not the template's bare form
        assert f"+# governance-kit:managed kit-version={KIT_VERSION}" in run_sh["diff"]


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
    # Drift guard: scripts/release.sh skips kit/evals/*, so a kit bump
    # that forgets this fixture silently turns eval 2's up-to-date case into a
    # forward update. Keep the pin equal to the kit's KIT_VERSION.
    import kityaml  # noqa: PLC0415 - PACK_LIB is on sys.path via load_kitverb() (#355: stdlib-only, no PyYAML).
    fixture = ROOT / "kit/evals/kit-update/files/up-to-date-repo/.governance/install.yaml"
    pin = kityaml.load(fixture)["kit_version"]
    assert str(pin) == KIT_VERSION, (
        f"up-to-date fixture pins kit_version={pin!r} but the kit is {KIT_VERSION!r} — "
        "re-pin kit/evals/kit-update/files/up-to-date-repo/ to match a kit release"
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
