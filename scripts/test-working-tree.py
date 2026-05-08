#!/usr/bin/env python3
"""Contract tests for the working-tree fetch resolver.

Covers `working_tree.origin_matches_target` (URL parsing) and
`working_tree.resolve_from_working_tree` (the short-circuit applied by
`packverb.fetch_ref` when the requested ref points at the very repo
we're inside). The latter exercises real git invocations against
throwaway tmp repos — there is no network or external dependency.
"""

from __future__ import annotations

import importlib.util
import inspect
import os
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PACK_LIB = ROOT / "governance" / "assets" / "packs" / "lib"


def _load(module_name: str, file_name: str):
    sys.path.insert(0, str(PACK_LIB))
    spec = importlib.util.spec_from_file_location(module_name, PACK_LIB / file_name)
    if spec is None or spec.loader is None:
        raise AssertionError(f"cannot load {file_name}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_working_tree():
    return _load("working_tree_under_test", "working_tree.py")


def load_packverb():
    # working_tree imports nothing from packverb, but packverb imports
    # working_tree — ensure it loads first so the import resolves.
    load_working_tree()
    return _load("packverb_under_test", "packverb.py")


# ---- origin_matches_target ------------------------------------------------

def test_origin_matches_target_accepts_https_with_git_suffix() -> None:
    wt = load_working_tree()
    assert wt.origin_matches_target(
        "https://github.com/Acme/Widgets.git", "acme", "widgets"
    ) is True


def test_origin_matches_target_accepts_https_without_git_suffix() -> None:
    wt = load_working_tree()
    assert wt.origin_matches_target(
        "https://github.com/Acme/Widgets", "Acme", "Widgets"
    ) is True


def test_origin_matches_target_accepts_ssh_form() -> None:
    wt = load_working_tree()
    assert wt.origin_matches_target(
        "git@github.com:Acme/Widgets.git", "acme", "widgets"
    ) is True


def test_origin_matches_target_rejects_mismatched_owner_or_repo() -> None:
    wt = load_working_tree()
    assert wt.origin_matches_target(
        "https://github.com/Acme/Widgets.git", "acme", "other"
    ) is False
    assert wt.origin_matches_target(
        "https://github.com/Other/Widgets.git", "acme", "widgets"
    ) is False


def test_origin_matches_target_rejects_substring_owner() -> None:
    """`xacme/widgets` must not match owner `acme` — the path-segment
    boundary (`/` or `:`) anchors the comparison."""
    wt = load_working_tree()
    assert wt.origin_matches_target(
        "https://github.com/xacme/widgets.git", "acme", "widgets"
    ) is False


# ---- resolve_from_working_tree --------------------------------------------

def _git(cwd: Path, *args: str) -> str:
    return subprocess.check_output(
        ["git", "-C", str(cwd), *args], text=True, stderr=subprocess.DEVNULL,
    ).strip()


def _seed_repo(repo: Path, *, origin: str, subpath: str,
               pack_id: str = "acme/demo") -> None:
    repo.mkdir(parents=True, exist_ok=True)
    _git(repo, "init", "--quiet", "--initial-branch=main")
    _git(repo, "config", "user.email", "test@example.com")
    _git(repo, "config", "user.name", "Test")
    _git(repo, "config", "commit.gpgsign", "false")
    _git(repo, "remote", "add", "origin", origin)
    pack_root = repo / subpath if subpath else repo
    pack_root.mkdir(parents=True, exist_ok=True)
    (pack_root / "pack.yaml").write_text(
        "\n".join([
            f"id: {pack_id}",
            "name: Demo",
            "version: '1.0'",
            "min_governance_kit: '0.2'",
            "description: Demo pack",
            "author: Test",
            "presets: {}",
        ]) + "\n"
    )
    _git(repo, "add", "-A")
    _git(repo, "commit", "--quiet", "-m", "seed")


def test_resolve_returns_none_outside_git_repo(monkeypatch) -> None:
    pv = load_packverb()
    wt = load_working_tree()
    with tempfile.TemporaryDirectory() as tmp:
        scratch = Path(tmp) / "scratch"
        scratch.mkdir()
        monkeypatch.chdir(scratch)
        result = wt.resolve_from_working_tree(
            pv.parse_ref("gh:acme/widgets/packs/demo"),
            Path(tmp) / "cache",
            slugify=pv._slugify_pack_id,
            pack_id_re=pv.PACK_ID_RE,
            read_pack_id=pv._read_pack_id,
        )
        assert result is None


def test_resolve_returns_none_when_origin_mismatches(monkeypatch) -> None:
    pv = load_packverb()
    wt = load_working_tree()
    with tempfile.TemporaryDirectory() as tmp:
        repo = Path(tmp) / "repo"
        _seed_repo(repo, origin="https://github.com/other/repo.git", subpath="packs/demo")
        monkeypatch.chdir(repo)
        result = wt.resolve_from_working_tree(
            pv.parse_ref("gh:acme/widgets/packs/demo"),
            Path(tmp) / "cache",
            slugify=pv._slugify_pack_id,
            pack_id_re=pv.PACK_ID_RE,
            read_pack_id=pv._read_pack_id,
        )
        assert result is None


def test_resolve_returns_none_when_subpath_has_no_pack(monkeypatch) -> None:
    pv = load_packverb()
    wt = load_working_tree()
    with tempfile.TemporaryDirectory() as tmp:
        repo = Path(tmp) / "repo"
        _seed_repo(repo, origin="https://github.com/acme/widgets.git", subpath="packs/demo")
        monkeypatch.chdir(repo)
        result = wt.resolve_from_working_tree(
            pv.parse_ref("gh:acme/widgets/packs/missing"),
            Path(tmp) / "cache",
            slugify=pv._slugify_pack_id,
            pack_id_re=pv.PACK_ID_RE,
            read_pack_id=pv._read_pack_id,
        )
        assert result is None


def test_resolve_copies_pack_into_cache(monkeypatch) -> None:
    pv = load_packverb()
    wt = load_working_tree()
    with tempfile.TemporaryDirectory() as tmp:
        repo = Path(tmp) / "repo"
        _seed_repo(repo, origin="https://github.com/acme/widgets.git", subpath="packs/demo")
        head = _git(repo, "rev-parse", "HEAD")
        monkeypatch.chdir(repo)
        result = wt.resolve_from_working_tree(
            pv.parse_ref("gh:acme/widgets/packs/demo"),
            Path(tmp) / "cache",
            slugify=pv._slugify_pack_id,
            pack_id_re=pv.PACK_ID_RE,
            read_pack_id=pv._read_pack_id,
        )
        assert result is not None
        assert result["sha"] == head
        assert result["id"] == "acme/demo"
        assert (Path(result["pack_dir"]) / "pack.yaml").is_file()
        assert not (Path(result["cache_dir"]) / ".git").exists()


def test_fetch_ref_short_circuits_without_cloning(monkeypatch) -> None:
    """When the URL points at the repo we're inside, fetch_ref must NOT
    invoke `git clone` / `git fetch` / `git checkout` (the network/checkout
    operations the clone path performs). Plumbing (`rev-parse`,
    `remote get-url`) is fine — the resolver itself uses those."""
    pv = load_packverb()
    with tempfile.TemporaryDirectory() as tmp:
        repo = Path(tmp) / "repo"
        _seed_repo(repo, origin="https://github.com/acme/widgets.git", subpath="packs/demo")
        monkeypatch.chdir(repo)

        forbidden = {"clone", "fetch", "checkout"}
        real_run = subprocess.run

        def gated_run(cmd, *args, **kwargs):  # noqa: ANN001
            tokens = [str(part) for part in cmd]
            if tokens and tokens[0] == "git":
                tail = tokens[1:]
                if len(tail) >= 2 and tail[0] == "-C":
                    tail = tail[2:]
                if tail and tail[0] in forbidden:
                    raise AssertionError(
                        f"fetch_ref invoked forbidden git op {tail[0]!r}: {tokens}"
                    )
            return real_run(cmd, *args, **kwargs)

        monkeypatch.setattr(pv.subprocess, "run", gated_run)

        result = pv.fetch_ref(
            "gh:acme/widgets/packs/demo", cache_dir=Path(tmp) / "cache"
        )
        assert result["id"] == "acme/demo"


# ---- harness --------------------------------------------------------------

if __name__ == "__main__":
    # Minimal pytest.MonkeyPatch stand-in. Each method records an undo so
    # the harness can restore state between tests.
    class MonkeyPatch:
        def __init__(self) -> None:
            self._undos: list = []

        def setattr(self, target, attr, value):  # noqa: ANN001
            original = getattr(target, attr)
            setattr(target, attr, value)
            self._undos.append(lambda t=target, a=attr, v=original: setattr(t, a, v))

        def chdir(self, path) -> None:  # noqa: ANN001
            prev = os.getcwd()
            os.chdir(str(path))
            self._undos.append(lambda p=prev: os.chdir(p))

        def undo(self) -> None:
            while self._undos:
                self._undos.pop()()

    failures = 0
    for name, fn in sorted(globals().items()):
        if not name.startswith("test_"):
            continue
        try:
            sig = inspect.signature(fn)
            if "monkeypatch" in sig.parameters:
                mp = MonkeyPatch()
                try:
                    fn(mp)
                finally:
                    mp.undo()
            else:
                fn()
        except Exception as exc:  # noqa: BLE001 - tiny stdlib-only harness.
            failures += 1
            print(f"not ok - {name}: {exc}", file=sys.stderr)
        else:
            print(f"ok - {name}")
    raise SystemExit(1 if failures else 0)
