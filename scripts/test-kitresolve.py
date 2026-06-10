#!/usr/bin/env python3
"""Contract tests for kitresolve.py — the repo-pinned resolution/pin half of
`governance kit update` (issue #177).

Covers `build_kit_ref` / `_direction` / `cached_kit_path` / `set_manifest_pin`,
the `kit-pin` and `kit-resolve` CLIs (offline floor refusal, the downgrade gate,
and the installed-skill fallback), and the `kit-apply` delegation parameters
(`--assets-root` / `--stamp-version` / `--hooks-lib` / `--allow-downgrade`) that
let the local engine apply a fetched older/alternate tree.
"""

from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PACK_LIB = ROOT / "governance" / "assets" / "packs" / "lib"
KITVERB_PATH = PACK_LIB / "kitverb.py"


def _load(mod_name: str, filename: str):
    sys.path.insert(0, str(PACK_LIB))
    spec = importlib.util.spec_from_file_location(mod_name, PACK_LIB / filename)
    if spec is None or spec.loader is None:
        raise AssertionError(f"cannot load {filename}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


KITVERB = _load("kitverb_under_test", "kitverb.py")
KITRESOLVE = _load("kitresolve_under_test", "kitresolve.py")
KIT_VERSION = KITVERB.KIT_VERSION
OLDER = "0.0.1"          # always below any real kit version
NEWER = "999.0"          # always above

# Strip inherited git plumbing vars so fixture repos never alias the host gitdir.
GIT_CLEAN_ENV = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}

BASE_MANIFEST = (
    'version: "3"\n'
    "tests_dir: .governance\n"
    "ci_workflow: .github/workflows/governance.yml\n"
    "enable_governance_script: scripts/enable-governance.sh\n"
    "hook_strategy: githooks\n"
)


def _marked(version):
    marker = "# governance-kit:managed"
    if version is not None:
        marker += f" kit-version={version}"
    return f"#!/usr/bin/env bash\n{marker}\nplaceholder\n"


def make_repo(tmp, *, manifest, files=None):
    root = Path(tmp)
    (root / ".governance").mkdir(parents=True, exist_ok=True)
    if manifest is not None:
        (root / ".governance" / "install.yaml").write_text(manifest)
    for rel, content in (files or {}).items():
        dest = root / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(content)
    return root


def git(root, *argv):
    subprocess.run(
        ["git", "-C", str(root), "-c", "user.email=t@t", "-c", "user.name=t",
         "-c", "commit.gpgsign=false", *argv],
        check=True, env=GIT_CLEAN_ENV, capture_output=True,
    )


def make_git_repo(tmp, *, manifest, files=None):
    root = make_repo(tmp, manifest=manifest, files=files)
    git(root, "init", "-q")
    git(root, "add", "-A")
    git(root, "commit", "-qm", "fixture")
    return root


def kit_apply(root, *flags):
    result = subprocess.run(
        [sys.executable, str(KITVERB_PATH), "kit-apply", str(root), *flags],
        cwd=ROOT, check=False, text=True, env=GIT_CLEAN_ENV,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    assert result.stdout.strip(), f"kit-apply printed no report: {result.stderr}"
    return result.returncode, json.loads(result.stdout)


def make_assets(tmp: Path, version: str, tag: str) -> Path:
    """A minimal source asset tree (the shape `--assets-root` points at)."""
    a = Path(tmp) / "assets"
    (a / "dot-governance").mkdir(parents=True)
    (a / "dot-governance" / "run.sh").write_text(
        f"#!/usr/bin/env bash\n# governance-kit:managed kit-version={version}\necho {tag} run\n")
    (a / "dot-governance" / "lib.sh").write_text(
        f"#!/usr/bin/env bash\n# governance-kit:managed kit-version={version}\necho {tag} lib\n")
    (a / "governance.yml").write_text(
        f"# governance-kit:managed kit-version={version}\nname: {tag}\n")
    (a / "enable-governance.sh").write_text(
        f"#!/usr/bin/env bash\n# governance-kit:managed kit-version={version}\necho {tag} enable\n")
    return a


def test_build_kit_ref_canonical_shape() -> None:
    assert KITRESOLVE.build_kit_ref("duaility/governance-kit", "0.4.0") == \
        "gh:duaility/governance-kit/governance@kit/v0.4.0"


def test_direction_forward_same_downgrade_unknown() -> None:
    assert KITRESOLVE._direction("0.4.0", "0.5.0") == "forward"
    assert KITRESOLVE._direction("0.5.0", "0.5.0") == "same"
    assert KITRESOLVE._direction("0.5.0", "0.4.0") == "downgrade"
    assert KITRESOLVE._direction(None, "0.5.0") == "unknown"


def test_cached_kit_path_none_when_not_cached() -> None:
    assert KITRESOLVE.cached_kit_path(
        "gh:duaility/governance-kit/governance@kit/v9.9.9", "0" * 40) is None
    assert KITRESOLVE.cached_kit_path("not-a-ref", "0" * 40) is None


def test_set_manifest_pin_inserts_then_updates_idempotently() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "install.yaml"
        path.write_text(BASE_MANIFEST + f'kit_version: "{KIT_VERSION}"\n')
        ref = "gh:duaility/governance-kit/governance@kit/v0.4.0"
        KITRESOLVE.set_manifest_pin(path, ref, "a" * 40)
        text = path.read_text()
        assert f"kit_ref: {ref}\n" in text
        assert f"kit_sha: {'a' * 40}\n" in text
        # original fields preserved
        assert "tests_dir: .governance" in text
        # update in place — no duplicate lines, new sha
        KITRESOLVE.set_manifest_pin(path, ref, "b" * 40)
        text = path.read_text()
        assert text.count("kit_ref:") == 1 and text.count("kit_sha:") == 1
        assert f"kit_sha: {'b' * 40}" in text


def test_kit_pin_command_writes_pin() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = make_repo(tmp, manifest=BASE_MANIFEST + f'kit_version: "{KIT_VERSION}"\n')
        ref = "gh:duaility/governance-kit/governance@kit/v0.4.0"
        result = subprocess.run(
            [sys.executable, str(KITVERB_PATH), "kit-pin", str(root),
             "--kit-ref", ref, "--kit-sha", "c" * 40],
            cwd=ROOT, check=False, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        assert result.returncode == 0, result.stderr
        assert json.loads(result.stdout)["result"] == "pinned"
        text = (root / ".governance/install.yaml").read_text()
        assert f"kit_ref: {ref}" in text and f"kit_sha: {'c' * 40}" in text


def test_kit_pin_command_errors_without_manifest() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / ".governance").mkdir()
        result = subprocess.run(
            [sys.executable, str(KITVERB_PATH), "kit-pin", str(root),
             "--kit-ref", "gh:x/y/governance@kit/v0.4.0", "--kit-sha", "d" * 40],
            cwd=ROOT, check=False, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        assert result.returncode == 1
        assert json.loads(result.stdout)["result"] == "error"


def test_plan_stamp_version_classifies_downgrade() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = make_repo(tmp, manifest=BASE_MANIFEST + f'kit_version: "{NEWER}"\n')
        result = subprocess.run(
            [sys.executable, str(KITVERB_PATH), "kit-plan", str(root), "--stamp-version", OLDER],
            cwd=ROOT, check=False, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        assert result.returncode == 0, result.stderr
        plan = json.loads(result.stdout)
        assert plan["delta"] == "downgrade"
        assert plan["kit_version"] == OLDER


def test_apply_allow_downgrade_stamps_target_version() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        # repo currently at NEWER; downgrade to OLDER, applying from an alt tree.
        files = {
            ".governance/run.sh": _marked(NEWER),
            ".governance/lib.sh": _marked(NEWER),
            ".github/workflows/governance.yml": f"# governance-kit:managed kit-version={NEWER}\nname: governance\n",
            "scripts/enable-governance.sh": f"#!/usr/bin/env bash\n# governance-kit:managed kit-version={NEWER}\nx\n",
        }
        root = make_git_repo(Path(tmp) / "repo", manifest=BASE_MANIFEST + f'kit_version: "{NEWER}"\n', files=files)
        assets = make_assets(Path(tmp) / "alt", OLDER, "ALT")
        # refused without the flag
        rc, report = kit_apply(root, "--assets-root", str(assets), "--stamp-version", OLDER)
        assert rc == 2 and report["result"] == "refused", report
        assert "--allow-downgrade" in report["recovery"]
        # allowed with it — stamps OLDER, copies the alt tree's content
        rc, report = kit_apply(
            root, "--assets-root", str(assets), "--stamp-version", OLDER,
            "--hooks-lib", str(PACK_LIB), "--allow-downgrade")
        assert rc == 0 and report["result"] == "applied", report
        assert report["to"] == OLDER
        assert any("--allow-downgrade" in a for a in report["assumptions"])
        assert KITVERB.read_marker(root / ".governance/run.sh") == {"state": "versioned", "version": OLDER}
        assert "ALT run" in (root / ".governance/run.sh").read_text()
        assert f'kit_version: "{OLDER}"' in (root / ".governance/install.yaml").read_text()


def test_apply_assets_root_forward_copies_alt_tree() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        files = {
            ".governance/run.sh": _marked(OLDER),
            ".governance/lib.sh": _marked(OLDER),
            ".github/workflows/governance.yml": f"# governance-kit:managed kit-version={OLDER}\nname: governance\n",
            "scripts/enable-governance.sh": f"#!/usr/bin/env bash\n# governance-kit:managed kit-version={OLDER}\nx\n",
        }
        root = make_git_repo(Path(tmp) / "repo", manifest=BASE_MANIFEST + f'kit_version: "{OLDER}"\n', files=files)
        mid = "0.0.5"  # OLDER < mid, a forward update from the alt tree
        assets = make_assets(Path(tmp) / "alt", mid, "ALT")
        rc, report = kit_apply(root, "--assets-root", str(assets), "--stamp-version", mid)
        assert rc == 0 and report["result"] == "applied", report
        assert report["to"] == mid
        assert "ALT lib" in (root / ".governance/lib.sh").read_text()
        assert KITVERB.read_marker(root / ".governance/lib.sh") == {"state": "versioned", "version": mid}


def make_cached_kit(home: Path, owner: str, repo: str, version: str, sha: str) -> str:
    """Lay a fake kit tree into the `kits/` cache; return its ref."""
    slug = f"{owner.lower()}__{repo.lower()}"
    kit_dir = Path(home) / "kits" / f"{slug}@{sha}" / "governance"
    (kit_dir / "assets" / "packs" / "lib").mkdir(parents=True)
    (kit_dir / "assets" / "kit.yaml").write_text(f'version: "{version}"\n')
    return f"gh:{owner}/{repo}/governance@kit/v{version}"


def kit_resolve(root: Path, *flags: str, home: Path) -> tuple[int, dict]:
    env = {**GIT_CLEAN_ENV, "GOVERNANCE_KIT_HOME": str(home)}
    result = subprocess.run(
        [sys.executable, str(KITVERB_PATH), "kit-resolve", str(root), *flags],
        cwd=ROOT, check=False, text=True, env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    assert result.stdout.strip(), f"kit-resolve printed nothing: {result.stderr}"
    return result.returncode, json.loads(result.stdout)


def test_resolve_offline_cache_floor_refusal() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        home = Path(tmp) / "home"
        sha = "1" * 40
        ref = make_cached_kit(home, "duaility", "governance-kit", "0.3.5", sha)
        manifest = BASE_MANIFEST + f'kit_version: "{KIT_VERSION}"\nkit_ref: {ref}\nkit_sha: {sha}\n'
        root = make_repo(Path(tmp) / "repo", manifest=manifest)
        rc, report = kit_resolve(root, "--offline", home=home)
        assert rc == 2 and report["result"] == "refused", report
        assert report["provenance"] == "cache"
        assert report["target_version"] == "0.3.5"
        assert report["floor_ok"] is False
        assert "0.4.0" in report["reason"] and "skills add" in report["recovery"]


def test_resolve_offline_cache_downgrade_gate() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        home = Path(tmp) / "home"
        sha = "2" * 40
        ref = make_cached_kit(home, "duaility", "governance-kit", "0.4.0", sha)
        manifest = BASE_MANIFEST + f'kit_version: "{NEWER}"\nkit_ref: {ref}\nkit_sha: {sha}\n'
        root = make_repo(Path(tmp) / "repo", manifest=manifest)
        # downgrade (0.4.0 < 999.0) refused without the flag
        rc, report = kit_resolve(root, "--offline", home=home)
        assert rc == 2 and report["direction"] == "downgrade", report
        assert "--allow-downgrade" in report["recovery"]
        # allowed with it — local engine drives, fetched older assets
        rc, report = kit_resolve(root, "--offline", "--allow-downgrade", home=home)
        assert rc == 0 and report["result"] == "ok", report
        assert report["delegate"] is True
        assert report["engine_path"] == str(KITVERB_PATH)              # local newer engine
        assert report["assets_root"].endswith("/governance/assets")    # fetched older tree


def test_resolve_offline_to_mismatch_refused() -> None:
    # `--to` is a contract: a fallback that resolves a *different* version must
    # refuse, not exit 0 with a silent substitute.
    with tempfile.TemporaryDirectory() as tmp:
        home = Path(tmp) / "home"
        sha = "3" * 40
        ref = make_cached_kit(home, "duaility", "governance-kit", "0.4.0", sha)
        manifest = BASE_MANIFEST + f'kit_version: "0.4.0"\nkit_ref: {ref}\nkit_sha: {sha}\n'
        root = make_repo(Path(tmp) / "repo", manifest=manifest)
        rc, report = kit_resolve(root, "--offline", "--to", "0.5.0", home=home)
        assert rc == 2 and report["result"] == "refused", report
        assert "--to 0.5.0" in report["reason"] and "0.4.0" in report["reason"]
        # ...but a fallback that satisfies the exact request is fine.
        rc, report = kit_resolve(root, "--offline", "--to", "0.4.0", home=home)
        assert rc == 0 and report["result"] == "ok", report
        assert report["provenance"] == "cache"
        assert report["target_version"] == "0.4.0"


def test_resolve_offline_no_pin_falls_back_to_installed_skill() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        home = Path(tmp) / "home"
        root = make_repo(Path(tmp) / "repo", manifest=BASE_MANIFEST + f'kit_version: "{KIT_VERSION}"\n')
        rc, report = kit_resolve(root, "--offline", home=home)
        assert rc == 0 and report["result"] == "ok", report
        assert report["provenance"] == "installed-skill"
        assert report["target_version"] == KIT_VERSION
        assert report["delegate"] is False
        assert any("installed skill" in a for a in report["assumptions"])


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
