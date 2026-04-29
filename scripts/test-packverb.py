#!/usr/bin/env python3
"""Contract tests for the public packverb helper surface."""

from __future__ import annotations

import importlib.util
import json
import os
import re
import subprocess
import sys
import tempfile
import textwrap
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PACK_LIB = ROOT / "governance" / "assets" / "packs" / "lib"
PACKVERB_PATH = PACK_LIB / "packverb.py"


def load_packverb():
    sys.path.insert(0, str(PACK_LIB))
    spec = importlib.util.spec_from_file_location("packverb_under_test", PACKVERB_PATH)
    if spec is None or spec.loader is None:
        raise AssertionError(f"cannot load {PACKVERB_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def run_packverb(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            sys.executable,
            str(PACKVERB_PATH),
            *args,
        ],
        cwd=ROOT,
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def test_catalog_search_ref_includes_source_path() -> None:
    result = run_packverb(
        "catalog-search",
        str(ROOT / "extensions" / "catalog.community.json"),
        "agent",
    )
    assert result.returncode == 0, result.stderr
    lines = [line.split("\t") for line in result.stdout.splitlines() if line.strip()]
    rows = {cols[0]: cols for cols in lines}
    ref = rows["duaility/agent-governance"][1]
    assert ref == "gh:Duaility/governance-kit/extensions/packs/agent-governance"

    parsed = run_packverb("parse-ref", ref)
    assert parsed.returncode == 0, parsed.stderr
    assert "subpath=extensions/packs/agent-governance" in parsed.stdout


def test_packverb_validate_pack_public_command() -> None:
    result = run_packverb(
        "validate-pack",
        str(ROOT / "extensions" / "packs" / "agent-governance"),
    )
    assert result.returncode == 0, result.stderr


def test_sha_ref_uses_fetch_checkout_path(monkeypatch) -> None:
    packverb = load_packverb()
    calls: list[list[str]] = []
    sha = "0123456789abcdef0123456789abcdef01234567"

    def fake_run(cmd, check=False, **_kwargs):  # noqa: ANN001 - mirrors subprocess.run.
        calls.append([str(part) for part in cmd])
        if cmd[:2] == ["git", "-C"] and "fetch" in cmd:
            checkout = Path(cmd[2])
            pack_dir = checkout / "packs" / "demo"
            pack_dir.mkdir(parents=True, exist_ok=True)
            (pack_dir / "pack.yaml").write_text(
                "\n".join(
                    [
                        "id: acme/demo",
                        "name: Demo",
                        "version: '1.0'",
                        "min_governance_kit: '0.2'",
                        "description: Demo pack",
                        "author: Test",
                        "presets: {}",
                    ]
                )
                + "\n"
            )
        return subprocess.CompletedProcess(cmd, 0)

    def fake_check_output(cmd, text=False, **_kwargs):  # noqa: ANN001 - mirrors subprocess.
        calls.append([str(part) for part in cmd])
        assert text is True
        return sha + "\n"

    monkeypatch.setattr(packverb.subprocess, "run", fake_run)
    monkeypatch.setattr(packverb.subprocess, "check_output", fake_check_output)

    with tempfile.TemporaryDirectory(prefix="packverb-test-cache-") as tmp:
        result = packverb.fetch_ref(
            f"gh:Example/repo/packs/demo@{sha}",
            cache_dir=Path(tmp),
        )

    assert result["sha"] == sha
    assert result["id"] == "acme/demo"
    assert any("fetch" in call and sha in call for call in calls)
    assert any("checkout" in call and "FETCH_HEAD" in call for call in calls)
    assert not any("--branch" in call for call in calls)


def test_init_flow_does_not_reference_deleted_required_docs_directives() -> None:
    text = (ROOT / "governance" / "references" / "INIT_FLOW.md").read_text()
    stale = {"hooks-configured", "agents-md-exists"}
    found = sorted(
        directive for directive in stale
        if re.search(rf"(?<![\w-]){re.escape(directive)}(?![\w-])", text)
    )
    assert found == []


# ---- parse_ref (every documented form) ------------------------------------

def test_parse_ref_accepts_owner_repo_only() -> None:
    packverb = load_packverb()
    parsed = packverb.parse_ref("gh:Acme/governance")
    assert parsed["owner"] == "Acme"
    assert parsed["repo"] == "governance"
    assert parsed["subpath"] == ""
    assert parsed["rev"] == "HEAD"
    assert parsed["url"] == "https://github.com/Acme/governance.git"


def test_parse_ref_accepts_subpath_and_rev() -> None:
    packverb = load_packverb()
    parsed = packverb.parse_ref("gh:Acme/governance/extensions/packs/foo@v1.2.3")
    assert parsed["subpath"] == "extensions/packs/foo"
    assert parsed["rev"] == "v1.2.3"


def test_parse_ref_accepts_sha_rev() -> None:
    packverb = load_packverb()
    sha = "0123456789abcdef0123456789abcdef01234567"
    parsed = packverb.parse_ref(f"gh:Acme/governance@{sha}")
    assert parsed["rev"] == sha


def test_parse_ref_rejects_unrecognized_scheme() -> None:
    packverb = load_packverb()
    try:
        packverb.parse_ref("https://github.com/Acme/governance")
    except ValueError as exc:
        assert "unrecognized" in str(exc)
    else:
        raise AssertionError("expected ValueError on non-gh: ref")


def test_parse_ref_rejects_missing_repo() -> None:
    packverb = load_packverb()
    try:
        packverb.parse_ref("gh:Acme")
    except ValueError:
        pass
    else:
        raise AssertionError("expected ValueError on missing repo segment")


# ---- cache_root + slugify -------------------------------------------------

def _set_env(key: str, value: str | None) -> str | None:
    """Set or unset `key`, returning the previous value for restoration."""
    prev = os.environ.get(key)
    if value is None:
        os.environ.pop(key, None)
    else:
        os.environ[key] = value
    return prev


def _restore_env(key: str, prev: str | None) -> None:
    if prev is None:
        os.environ.pop(key, None)
    else:
        os.environ[key] = prev


def test_cache_root_honors_governance_kit_home() -> None:
    packverb = load_packverb()
    with tempfile.TemporaryDirectory() as tmp:
        prev = _set_env("GOVERNANCE_KIT_HOME", tmp)
        try:
            assert str(packverb.cache_root()) == str(Path(tmp) / "packs")
        finally:
            _restore_env("GOVERNANCE_KIT_HOME", prev)


def test_cache_root_defaults_under_home_when_unset() -> None:
    packverb = load_packverb()
    prev = _set_env("GOVERNANCE_KIT_HOME", None)
    try:
        expected = Path.home() / ".governance" / "cache" / "packs"
        assert packverb.cache_root() == expected
    finally:
        _restore_env("GOVERNANCE_KIT_HOME", prev)


def test_slugify_pack_id_replaces_slash_with_double_underscore() -> None:
    packverb = load_packverb()
    assert packverb._slugify_pack_id("acme/demo") == "acme__demo"
    assert packverb._slugify_pack_id("flat") == "flat"


# ---- _matches_any (capability glob) ---------------------------------------

def test_matches_any_handles_doublestar_globs() -> None:
    packverb = load_packverb()
    assert packverb._matches_any("src/foo/bar.py", ["src/**/*.py"]) is True
    assert packverb._matches_any("README.md", ["src/**/*.py"]) is False


def test_matches_any_treats_trailing_slash_star_as_directory_prefix() -> None:
    packverb = load_packverb()
    assert packverb._matches_any("src/foo.py", ["src/*"]) is True
    # A nested file matches "src/*" via the trailing-slash directory-prefix rule.
    assert packverb._matches_any("src/sub/foo.py", ["src/*"]) is True


# ---- capability_violations ------------------------------------------------

def _make_directive(tmp: Path, *, directive_yaml: str, check_sh: str) -> Path:
    ddir = tmp / "directive"
    ddir.mkdir(parents=True, exist_ok=True)
    (ddir / "directive.yaml").write_text(directive_yaml)
    (ddir / "check.sh").write_text(check_sh)
    return ddir


def test_capability_violations_returns_empty_when_no_globs_declared() -> None:
    packverb = load_packverb()
    with tempfile.TemporaryDirectory() as tmp:
        ddir = _make_directive(
            Path(tmp),
            directive_yaml="summary: x\n",
            check_sh="#!/usr/bin/env bash\ngrep -q 'foo' \"src/whatever.py\"\n",
        )
        assert packverb.capability_violations(ddir) == []


def test_capability_violations_passes_when_check_stays_within_globs() -> None:
    packverb = load_packverb()
    with tempfile.TemporaryDirectory() as tmp:
        ddir = _make_directive(
            Path(tmp),
            directive_yaml=textwrap.dedent("""\
                summary: x
                reads: ['src/**/*.py']
            """),
            check_sh="#!/usr/bin/env bash\ngrep -q 'foo' \"src/lib/x.py\"\n",
        )
        assert packverb.capability_violations(ddir) == []


def test_capability_violations_flags_paths_outside_declared_globs() -> None:
    packverb = load_packverb()
    with tempfile.TemporaryDirectory() as tmp:
        ddir = _make_directive(
            Path(tmp),
            directive_yaml=textwrap.dedent("""\
                summary: x
                reads: ['src/**/*.py']
            """),
            check_sh="#!/usr/bin/env bash\ncat \"etc/passwd\"\n",
        )
        violations = packverb.capability_violations(ddir)
        assert any("etc/passwd" in v for v in violations)


def test_capability_violations_reports_missing_directive_yaml() -> None:
    packverb = load_packverb()
    with tempfile.TemporaryDirectory() as tmp:
        ddir = Path(tmp) / "empty"
        ddir.mkdir()
        violations = packverb.capability_violations(ddir)
        assert any("directive.yaml missing" in v for v in violations)


# ---- lockfile I/O ---------------------------------------------------------

def test_load_lockfile_returns_empty_when_missing() -> None:
    packverb = load_packverb()
    with tempfile.TemporaryDirectory() as tmp:
        data = packverb.load_lockfile(Path(tmp) / "no-such.lock")
        assert data == {"version": "1", "packs": []}


def test_lockfile_round_trip_via_cli() -> None:
    sha = "0123456789abcdef0123456789abcdef01234567"
    with tempfile.TemporaryDirectory() as tmp:
        lockfile = Path(tmp) / "packs.lock"
        # lock-add #1
        result = run_packverb(
            "lock-add",
            str(lockfile),
            "acme/foo",
            "gh:acme/foo",
            sha,
            "--directive", "alpha",
            "--directive", "beta",
            "--min-kit", "0.2",
        )
        assert result.returncode == 0, result.stderr
        # lock-add same id again — replaces, not appends
        result = run_packverb(
            "lock-add",
            str(lockfile),
            "acme/foo",
            "gh:acme/foo",
            sha,
            "--directive", "gamma",
        )
        assert result.returncode == 0
        listing = run_packverb("lock-list", str(lockfile))
        rows = [line for line in listing.stdout.splitlines() if line.strip()]
        assert len(rows) == 1
        assert rows[0].startswith("acme/foo\t")
        # lock-remove
        result = run_packverb("lock-remove", str(lockfile), "acme/foo")
        assert result.returncode == 0
        # Repeat remove → fails because pack is no longer present.
        result = run_packverb("lock-remove", str(lockfile), "acme/foo")
        assert result.returncode != 0


def test_lock_read_returns_versioned_json() -> None:
    sha = "0123456789abcdef0123456789abcdef01234567"
    with tempfile.TemporaryDirectory() as tmp:
        lockfile = Path(tmp) / "packs.lock"
        run_packverb(
            "lock-add",
            str(lockfile),
            "acme/foo",
            "gh:acme/foo",
            sha,
            "--directive", "alpha",
        )
        result = run_packverb("lock-read", str(lockfile))
        assert result.returncode == 0
        data = json.loads(result.stdout)
        assert data["version"] == "1"
        assert data["packs"][0]["id"] == "acme/foo"
        assert data["packs"][0]["directives"] == ["alpha"]


def test_lockfile_packs_sorted_by_id_on_write() -> None:
    """Pack rows are written in id order regardless of insert order — so a fresh
    PR doesn't churn the lockfile when a new pack lands ahead of existing ones."""
    sha = "0123456789abcdef0123456789abcdef01234567"
    with tempfile.TemporaryDirectory() as tmp:
        lockfile = Path(tmp) / "packs.lock"
        for pid in ("zeta/zz", "alpha/aa", "mu/mm"):
            run_packverb(
                "lock-add", str(lockfile), pid, f"gh:{pid}", sha, "--directive", "x",
            )
        listing = run_packverb("lock-list", str(lockfile))
        rows = [line.split("\t")[0] for line in listing.stdout.splitlines() if line.strip()]
        assert rows == ["alpha/aa", "mu/mm", "zeta/zz"]


# ---- catalog-search -------------------------------------------------------

def test_catalog_search_returns_all_when_query_empty() -> None:
    result = run_packverb(
        "catalog-search",
        str(ROOT / "extensions" / "catalog.community.json"),
        "",
    )
    assert result.returncode == 0, result.stderr
    rows = [line for line in result.stdout.splitlines() if line.strip()]
    assert any(line.startswith("duaility/agent-governance\t") for line in rows)


def test_catalog_search_reports_missing_catalog_with_nonzero_exit() -> None:
    result = run_packverb("catalog-search", "/no/such/catalog.json", "anything")
    assert result.returncode != 0




if __name__ == "__main__":
    failures = 0
    for name, fn in sorted(globals().items()):
        if not name.startswith("test_"):
            continue
        try:
            if name == "test_sha_ref_uses_fetch_checkout_path":
                # Minimal pytest.MonkeyPatch stand-in. Only `setattr` is
                # implemented because that is all the current tests use; if a
                # future test needs `delattr` / `setenv` / `undo`, extend here.
                class MonkeyPatch:
                    def setattr(self, target, attr, value):
                        setattr(target, attr, value)

                fn(MonkeyPatch())
            else:
                fn()
        except Exception as exc:  # noqa: BLE001 - tiny stdlib-only harness.
            failures += 1
            print(f"not ok - {name}: {exc}", file=sys.stderr)
        else:
            print(f"ok - {name}")
    raise SystemExit(1 if failures else 0)
