#!/usr/bin/env python3
"""Contract tests for the public packverb helper surface."""

from __future__ import annotations

import importlib.util
import re
import subprocess
import sys
import tempfile
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
