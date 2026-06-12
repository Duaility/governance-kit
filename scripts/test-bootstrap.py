#!/usr/bin/env python3
"""Contract tests for skill/bootstrap.py — the published skill's fetch-only
bootstrap (issue #198).

Two stakes in the ground:

  1. The shim's behavior contract: `resolve` / `current` return the
     documented JSON, refuse (exit 2, reason + recovery) whenever no kit tree
     is reachable, and never fall back to anything the shim carries — it
     carries nothing.
  2. The cache-layout contract with the kit's own engines: a tree the shim
     fetches must be found by `kitresolve.cached_kit_path`, and vice versa
     (`${GOVERNANCE_KIT_HOME}/kits/<owner>__<repo>@<sha>/`). This is the one
     piece of shared knowledge between the two codebases; this file locks it.

Network-free: every test pre-seeds the cache (or a local upstream git repo)
under a temp GOVERNANCE_KIT_HOME.
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
BOOTSTRAP_PATH = ROOT / "skill" / "bootstrap.py"
PACK_LIB = ROOT / "kit" / "assets" / "packs" / "lib"

# Strip inherited git plumbing vars so fixture repos never alias the host gitdir.
GIT_CLEAN_ENV = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}


def _load(mod_name: str, path: Path):
    spec = importlib.util.spec_from_file_location(mod_name, path)
    if spec is None or spec.loader is None:
        raise AssertionError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


BOOTSTRAP = _load("bootstrap_under_test", BOOTSTRAP_PATH)


def _load_kitresolve():
    sys.path.insert(0, str(PACK_LIB))
    try:
        return _load("kitresolve_under_bootstrap_test", PACK_LIB / "kitresolve.py")
    finally:
        sys.path.remove(str(PACK_LIB))


def run_bootstrap(*argv: str, home: Path) -> tuple[int, dict]:
    env = dict(GIT_CLEAN_ENV)
    env["GOVERNANCE_KIT_HOME"] = str(home)
    result = subprocess.run(
        [sys.executable, str(BOOTSTRAP_PATH), *argv],
        check=False, text=True, capture_output=True, env=env,
    )
    assert result.stdout.strip(), f"no JSON on stdout (stderr: {result.stderr})"
    return result.returncode, json.loads(result.stdout)


def make_cached_kit(home: Path, owner: str, repo: str, version: str, sha: str,
                    subpath: str = "kit") -> str:
    """Lay a delegable kit tree into the `kits/` cache; return its ref."""
    slug = f"{owner.lower()}__{repo.lower()}"
    kit_dir = Path(home) / "kits" / f"{slug}@{sha}" / subpath
    (kit_dir / "assets" / "packs" / "lib").mkdir(parents=True)
    (kit_dir / "assets" / "packs" / "lib" / "kitverb.py").write_text("# engine\n")
    (kit_dir / "references").mkdir()
    (kit_dir / "assets" / "kit.yaml").write_text(f'version: "{version}"\n')
    return f"gh:{owner}/{repo}/{subpath}@kit/v{version}"


def make_repo(tmp: Path, manifest: str | None) -> Path:
    root = Path(tmp)
    if manifest is not None:
        (root / ".governance").mkdir(parents=True)
        (root / ".governance" / "install.yaml").write_text(manifest)
    return root


# ── unit: parsing helpers ──────────────────────────────────────────────────

def test_parse_ref_shapes() -> None:
    parsed = BOOTSTRAP.parse_ref("gh:duaility/governance-kit/kit@kit/v0.6.0")
    assert parsed["owner"] == "duaility" and parsed["subpath"] == "kit"
    assert parsed["rev"] == "kit/v0.6.0"
    legacy = BOOTSTRAP.parse_ref("gh:duaility/governance-kit/governance@kit/v0.4.0")
    assert legacy["subpath"] == "governance"  # pre-split epoch refs stay parseable
    bare = BOOTSTRAP.parse_ref("gh:owner/repo")
    assert bare["subpath"] == "" and bare["rev"] == "HEAD"
    try:
        BOOTSTRAP.parse_ref("owner/repo")
    except ValueError:
        pass
    else:
        raise AssertionError("non-gh ref should raise")


def test_kit_yaml_version_scalar_forms() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        kit = Path(tmp)
        (kit / "assets").mkdir()
        for raw, want in [('version: "0.5.0"\n', "0.5.0"),
                          ("version: 0.5.0\n", "0.5.0"),
                          ("version: 0.5.0  # comment\n", "0.5.0")]:
            (kit / "assets" / "kit.yaml").write_text(raw)
            assert BOOTSTRAP.kit_yaml_version(kit) == want, raw
        assert BOOTSTRAP.kit_yaml_version(Path(tmp) / "nope") is None


def test_read_pin_line_forms() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = make_repo(Path(tmp), 'version: "3"\nkit_ref: gh:a/b/kit@kit/v1.0.0\nkit_sha: ' + "c" * 40 + "\n")
        ref, sha = BOOTSTRAP.read_pin(root)
        assert ref == "gh:a/b/kit@kit/v1.0.0" and sha == "c" * 40
        assert BOOTSTRAP.read_pin(Path(tmp) / "absent") == (None, None)


def test_validate_kit_tree_refusals() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        kit = Path(tmp)
        assert "no assets/kit.yaml" in BOOTSTRAP.validate_kit_tree(kit)
        (kit / "assets").mkdir()
        (kit / "assets" / "kit.yaml").write_text('version: "0.3.0"\n')
        assert "predates delegated apply" in BOOTSTRAP.validate_kit_tree(kit)
        (kit / "assets" / "packs" / "lib").mkdir(parents=True)
        (kit / "assets" / "packs" / "lib" / "kitverb.py").write_text("#\n")
        assert "no references/" in BOOTSTRAP.validate_kit_tree(kit)
        (kit / "references").mkdir()
        assert BOOTSTRAP.validate_kit_tree(kit) is None


# ── contract: cache layout shared with the kit engines ────────────────────

def test_cache_layout_matches_kitresolve_cached_kit_path() -> None:
    # A tree laid out where the SHIM expects it must be found by the KIT's
    # cached_kit_path, both subpath epochs. This is the cross-codebase lock.
    kitresolve = _load_kitresolve()
    with tempfile.TemporaryDirectory() as tmp:
        home = Path(tmp) / "home"
        os.environ["GOVERNANCE_KIT_HOME"] = str(home)
        try:
            for subpath in ("kit", "governance"):
                sha = ("a" if subpath == "kit" else "b") * 40
                ref = make_cached_kit(home, "duaility", "governance-kit", "0.6.0", sha, subpath=subpath)
                shim_hit = BOOTSTRAP.cached_tree(ref, sha)
                kit_hit = kitresolve.cached_kit_path(ref, sha)
                assert shim_hit is not None, f"shim missed its own layout ({subpath})"
                assert kit_hit is not None, f"kit engine missed the shim's layout ({subpath})"
                assert str(shim_hit) == kit_hit["kit_dir"], (shim_hit, kit_hit)
        finally:
            del os.environ["GOVERNANCE_KIT_HOME"]


# ── CLI: current ───────────────────────────────────────────────────────────

def test_current_no_pin_refuses_with_guidance() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        home = Path(tmp) / "home"
        root = make_repo(Path(tmp) / "repo", 'version: "3"\n')
        rc, report = run_bootstrap("current", str(root), "--offline", home=home)
        assert rc == 2 and report["result"] == "refused", report
        assert "no recorded kit pin" in report["reason"]
        assert "governance update" in report["recovery"]


def test_current_cached_pin_resolves_with_paths() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        home = Path(tmp) / "home"
        sha = "d" * 40
        ref = make_cached_kit(home, "duaility", "governance-kit", "0.6.0", sha)
        root = make_repo(Path(tmp) / "repo", f'version: "3"\nkit_ref: {ref}\nkit_sha: {sha}\n')
        rc, report = run_bootstrap("current", str(root), "--offline", home=home)
        assert rc == 0 and report["result"] == "ok", report
        assert report["provenance"] == "cache" and report["version"] == "0.6.0"
        assert report["lib_dir"].endswith("kit/assets/packs/lib")
        assert report["references_dir"].endswith("kit/references")


def test_current_legacy_governance_subpath_pin_resolves() -> None:
    # Pre-split pins (…/governance@kit/v0.4.0) keep working: the subpath comes
    # from the recorded ref, not from the shim's KIT_SUBPATH constant.
    with tempfile.TemporaryDirectory() as tmp:
        home = Path(tmp) / "home"
        sha = "e" * 40
        ref = make_cached_kit(home, "duaility", "governance-kit", "0.4.0", sha, subpath="governance")
        root = make_repo(Path(tmp) / "repo", f'version: "3"\nkit_ref: {ref}\nkit_sha: {sha}\n')
        rc, report = run_bootstrap("current", str(root), "--offline", home=home)
        assert rc == 0 and report["result"] == "ok", report
        assert report["kit_dir"].endswith("governance")


def test_current_uncached_pin_offline_refuses() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        home = Path(tmp) / "home"
        sha = "f" * 40
        root = make_repo(Path(tmp) / "repo",
                         f'version: "3"\nkit_ref: gh:duaility/governance-kit/kit@kit/v0.6.0\nkit_sha: {sha}\n')
        rc, report = run_bootstrap("current", str(root), "--offline", home=home)
        assert rc == 2 and report["result"] == "refused", report
        assert "not in the cache" in report["reason"]


# ── CLI: resolve ───────────────────────────────────────────────────────────

def test_resolve_offline_without_to_refuses() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        rc, report = run_bootstrap("resolve", "--offline", home=Path(tmp) / "home")
        assert rc == 2 and report["result"] == "refused", report
        assert "--offline" in report["reason"]
        assert "--to" in report["recovery"]


def test_resolve_offline_to_served_from_cache_scan() -> None:
    # `--to X.Y.Z` offline succeeds when that version was ever fetched: the
    # cache is scanned by content (the sha isn't known up front).
    with tempfile.TemporaryDirectory() as tmp:
        home = Path(tmp) / "home"
        sha = "9" * 40
        make_cached_kit(home, "duaility", "governance-kit", "0.6.0", sha)
        rc, report = run_bootstrap("resolve", "--offline", "--to", "0.6.0", home=home)
        assert rc == 0 and report["result"] == "ok", report
        assert report["provenance"] == "cache" and report["kit_sha"] == sha
        assert report["assumptions"], "cache-served resolve must surface an assumption"


def test_resolve_offline_to_uncached_refuses() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        rc, report = run_bootstrap("resolve", "--offline", "--to", "0.9.9", home=Path(tmp) / "home")
        assert rc == 2 and report["result"] == "refused", report
        assert "0.9.9" in report["reason"]
        assert "connect once" in report["recovery"]


# ── fetch path (local upstream, no network) ────────────────────────────────

def test_fetch_ref_clones_validates_and_caches() -> None:
    # Exercise the real clone→sha→validate→cache-move path against a local
    # upstream repo (parse_ref patched to a file:// URL — the only seam).
    with tempfile.TemporaryDirectory() as tmp:
        home = Path(tmp) / "home"
        upstream = Path(tmp) / "upstream"
        kit = upstream / "kit"
        (kit / "assets" / "packs" / "lib").mkdir(parents=True)
        (kit / "assets" / "packs" / "lib" / "kitverb.py").write_text("# engine\n")
        (kit / "references").mkdir()
        # git tracks files, not dirs — references/ must carry one to survive the clone.
        (kit / "references" / "VERBS.md").write_text("# verbs\n")
        (kit / "assets" / "kit.yaml").write_text('version: "0.6.0"\n')
        env = dict(GIT_CLEAN_ENV)
        for cmd in (["git", "init", "--quiet", "-b", "main", str(upstream)],
                    ["git", "-C", str(upstream), "add", "-A"],
                    ["git", "-C", str(upstream), "-c", "user.email=t@t", "-c", "user.name=t",
                     "commit", "--quiet", "-m", "kit"],
                    ["git", "-C", str(upstream), "tag", "kit/v0.6.0"]):
            subprocess.run(cmd, check=True, env=env, capture_output=True)

        os.environ["GOVERNANCE_KIT_HOME"] = str(home)
        real_parse = BOOTSTRAP.parse_ref
        try:
            BOOTSTRAP.parse_ref = lambda ref: {**real_parse(ref), "url": str(upstream)}
            fetched = BOOTSTRAP.fetch_ref("gh:duaility/governance-kit/kit@kit/v0.6.0")
            assert len(fetched["sha"]) == 40
            assert BOOTSTRAP.kit_yaml_version(fetched["kit_dir"]) == "0.6.0"
            # Cached where `current` (and the kit's engines) will look for it.
            assert BOOTSTRAP.cached_tree("gh:duaility/governance-kit/kit@x", fetched["sha"]) is not None
            # Idempotent re-fetch of the same tag.
            again = BOOTSTRAP.fetch_ref("gh:duaility/governance-kit/kit@kit/v0.6.0")
            assert again["sha"] == fetched["sha"]
        finally:
            BOOTSTRAP.parse_ref = real_parse
            del os.environ["GOVERNANCE_KIT_HOME"]


def test_fetch_ref_pre_split_subpath_refuses_with_epoch_error() -> None:
    # A tag whose tree has no kit/ subpath (the pre-split epoch) must refuse
    # at fetch time with the documented no-kit.yaml error, not half-cache.
    with tempfile.TemporaryDirectory() as tmp:
        home = Path(tmp) / "home"
        upstream = Path(tmp) / "upstream"
        legacy = upstream / "governance"
        (legacy / "assets").mkdir(parents=True)
        (legacy / "assets" / "kit.yaml").write_text('version: "0.3.5"\n')
        env = dict(GIT_CLEAN_ENV)
        for cmd in (["git", "init", "--quiet", "-b", "main", str(upstream)],
                    ["git", "-C", str(upstream), "add", "-A"],
                    ["git", "-C", str(upstream), "-c", "user.email=t@t", "-c", "user.name=t",
                     "commit", "--quiet", "-m", "legacy"],
                    ["git", "-C", str(upstream), "tag", "kit/v0.3.5"]):
            subprocess.run(cmd, check=True, env=env, capture_output=True)

        os.environ["GOVERNANCE_KIT_HOME"] = str(home)
        real_parse = BOOTSTRAP.parse_ref
        try:
            BOOTSTRAP.parse_ref = lambda ref: {**real_parse(ref), "url": str(upstream)}
            try:
                BOOTSTRAP.fetch_ref("gh:duaility/governance-kit/kit@kit/v0.3.5")
            except SystemExit as exc:
                assert "no assets/kit.yaml" in str(exc)
            else:
                raise AssertionError("pre-split fetch should refuse")
            assert not list((home / "kits").glob("*@*")), "refused fetch must not leave a cache entry"
        finally:
            BOOTSTRAP.parse_ref = real_parse
            del os.environ["GOVERNANCE_KIT_HOME"]


# ── shim self-containment ──────────────────────────────────────────────────

def test_bootstrap_is_stdlib_only_and_standalone() -> None:
    # The shim must run from a bare `python3` with no repo, no PyYAML, no kit
    # modules on path. Copy it alone to a temp dir and exercise --help + a
    # refusal path.
    with tempfile.TemporaryDirectory() as tmp:
        solo = Path(tmp) / "bootstrap.py"
        solo.write_text(BOOTSTRAP_PATH.read_text())
        env = dict(GIT_CLEAN_ENV)
        env["GOVERNANCE_KIT_HOME"] = str(Path(tmp) / "home")
        ok = subprocess.run([sys.executable, str(solo), "--help"],
                            check=False, text=True, capture_output=True, env=env, cwd=tmp)
        assert ok.returncode == 0 and "resolve" in ok.stdout and "current" in ok.stdout
        ref = subprocess.run([sys.executable, str(solo), "resolve", "--offline"],
                             check=False, text=True, capture_output=True, env=env, cwd=tmp)
        assert ref.returncode == 2 and json.loads(ref.stdout)["result"] == "refused"


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
