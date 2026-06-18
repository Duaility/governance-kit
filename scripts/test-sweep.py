#!/usr/bin/env python3
"""Contract tests for the sweep engine's digest-filing path (issue #235).

`sweep run` files its digest under SWEEP_LABEL, which doubles as the engine's
state key (resume + dedupe both query by it) — but nothing in the install path
creates the label, so the engine must. These tests run the real CLI against a
throwaway repo with a stub `gh` on PATH and pin the three filing scenarios:
label creatable → filed labeled; label pre-existing → filed labeled; label
uncreatable → filed unlabeled with a warning, run still succeeds.
"""

from __future__ import annotations

import importlib.util
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SWEEP = ROOT / "kit" / "assets" / "dot-governance" / "sweep.py"

# Import the engine as a module for the pure-function unit tests below (the
# filing tests above drive the real CLI in a subprocess; the tier-resolution
# tests just call resolve_model_tier directly).
_spec = importlib.util.spec_from_file_location("sweep_engine", SWEEP)
sweep = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(sweep)

GIT_CLEAN_ENV = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}

GH_STUB = """\
#!/usr/bin/env bash
# Stub gh: log every invocation, answer per the scenario file next to this script.
dir="$(cd "$(dirname "$0")" && pwd)"
printf '%s\\n' "$*" >> "$dir/gh-calls.log"
scenario="$(cat "$dir/gh-scenario")"
case "$1 $2" in
  "label create")
    case "$scenario" in
      ok) exit 0 ;;
      exists) echo 'label with name "governance-sweep" already exists' >&2; exit 1 ;;
      denied) echo 'HTTP 403: Resource not accessible by integration' >&2; exit 1 ;;
    esac ;;
  "issue list") echo "[]" ;;
  "issue create") echo "https://example.test/issues/1" ;;
esac
exit 0
"""


def git(root: Path, *argv: str) -> None:
    subprocess.run(["git", "-C", str(root), "-c", "user.email=t@t", "-c", "user.name=t",
                    "-c", "commit.gpgsign=false", *argv],
                   check=True, env=GIT_CLEAN_ENV, capture_output=True)


def _fixture_repo(base: Path) -> Path:
    """A repo with one sweep directive whose echo judge always finds a violation."""
    root = base / "repo"
    d = root / ".governance" / "packs" / "acme" / "shape" / "directives" / "no-shims"
    (d / "evals").mkdir(parents=True)
    (d / "directive.yaml").write_text(
        "category: architecture\nrecommended: true\nsummary: no shims\n"
        "surface: sweep\nhook: none\nengine: llm\nmodel_tier: high\n")
    (d / "triage.sh").write_text("#!/usr/bin/env bash\necho 'f.txt:1'\n")
    (d / "constitution.md").write_text("### no-shims\n\n- **Directive**: no shims.\n")
    (d / "evals" / "echo-keywords.txt").write_text("shim\n")
    (root / "f.txt").write_text("a legacy shim kept for compatibility\n")
    git(root, "init", "-q", ".")
    git(root, "add", "-A")
    git(root, "commit", "-qm", "seed")
    return root


def _run_sweep(base: Path, root: Path, scenario: str) -> tuple[subprocess.CompletedProcess[str], list[str]]:
    bin_dir = base / "bin"
    bin_dir.mkdir(exist_ok=True)
    gh = bin_dir / "gh"
    gh.write_text(GH_STUB)
    gh.chmod(0o755)
    (bin_dir / "gh-scenario").write_text(scenario)
    log = bin_dir / "gh-calls.log"
    if log.exists():
        log.unlink()
    env = dict(GIT_CLEAN_ENV, PATH=f"{bin_dir}:{os.environ['PATH']}")
    env.pop("GITHUB_TOKEN", None)
    env.pop("MODELS_TOKEN", None)
    res = subprocess.run(
        [sys.executable, str(SWEEP), "run", "--root", str(root), "--judge", "echo"],
        capture_output=True, text=True, env=env)
    calls = log.read_text().splitlines() if log.exists() else []
    return res, calls


def _issue_create_call(calls: list[str]) -> str:
    hits = [c for c in calls if c.startswith("issue create")]
    assert len(hits) == 1, f"expected exactly one issue create, got: {calls}"
    return hits[0]


def test_filing_creates_missing_label_then_files_labeled() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = _fixture_repo(Path(tmp))
        res, calls = _run_sweep(Path(tmp), root, "ok")
        assert res.returncode == 0, res.stderr
        label_idx = next(i for i, c in enumerate(calls)
                         if c.startswith("label create governance-sweep"))
        create_idx = calls.index(_issue_create_call(calls))
        assert label_idx < create_idx, f"label must be ensured before filing: {calls}"
        assert "--label governance-sweep" in _issue_create_call(calls)


def test_filing_treats_existing_label_as_success() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = _fixture_repo(Path(tmp))
        res, calls = _run_sweep(Path(tmp), root, "exists")
        assert res.returncode == 0, res.stderr
        assert "--label governance-sweep" in _issue_create_call(calls)
        assert "could not create label" not in res.stderr


def test_filing_falls_back_to_unlabeled_when_label_uncreatable() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = _fixture_repo(Path(tmp))
        res, calls = _run_sweep(Path(tmp), root, "denied")
        assert res.returncode == 0, res.stderr
        assert "could not create label" in res.stderr
        assert "--label" not in _issue_create_call(calls)


def test_dry_run_never_touches_labels() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = _fixture_repo(Path(tmp))
        bin_dir = Path(tmp) / "bin"
        bin_dir.mkdir()
        gh = bin_dir / "gh"
        gh.write_text(GH_STUB)
        gh.chmod(0o755)
        (bin_dir / "gh-scenario").write_text("ok")
        env = dict(GIT_CLEAN_ENV, PATH=f"{bin_dir}:{os.environ['PATH']}")
        res = subprocess.run(
            [sys.executable, str(SWEEP), "run", "--root", str(root),
             "--judge", "echo", "--dry-run"],
            capture_output=True, text=True, env=env)
        assert res.returncode == 0, res.stderr
        log = bin_dir / "gh-calls.log"
        calls = log.read_text().splitlines() if log.exists() else []
        assert not any(c.startswith("label create") or c.startswith("issue create")
                       for c in calls), calls


# ── resolve_model_tier: operator-tunable SUBAGENT_TIERS_SWEEP (issue #331) ───
def _subagent_dir(base: Path, *, with_defaults: bool, sweep_tier_yaml: str = "high",
                  overlay_tier: str | None = None) -> Path:
    """An installed-layout directive carrying a `subagent:` block, so
    resolve_model_tier and _overlay_conf_path see the real
    `.governance/{packs,conf}/<owner>/<pack>/...` shape."""
    root = base / "repo"
    d = root / ".governance" / "packs" / "acme" / "audit" / "directives" / "rec"
    d.mkdir(parents=True)
    (d / "directive.yaml").write_text(
        "category: x\nsurface: sweep\nhook: none\n"
        "subagent:\n"
        "  inputs:  [diff]\n"
        "  checks:\n    - one\n"
        "  isolation: shared\n  section: Audit\n"
        f"  tiers: {{ attest: low, sweep: {sweep_tier_yaml} }}\n")
    if with_defaults:
        (d / "defaults.conf").write_text(
            "SUBAGENT_ISOLATION=shared\nSUBAGENT_TIERS_ATTEST=low\n"
            "SUBAGENT_TIERS_SWEEP=high\n")
    if overlay_tier is not None:
        ov = root / ".governance" / "conf" / "acme" / "audit" / "rec.conf"
        ov.parent.mkdir(parents=True, exist_ok=True)
        ov.write_text(f"SUBAGENT_TIERS_SWEEP={overlay_tier}\n")
    return d


def test_resolve_tier_uses_defaults_conf() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        d = _subagent_dir(Path(tmp), with_defaults=True)
        assert sweep.resolve_model_tier(d) == "high"


def test_resolve_tier_overlay_wins() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        d = _subagent_dir(Path(tmp), with_defaults=True, overlay_tier="low")
        assert sweep.resolve_model_tier(d) == "low"


def test_resolve_tier_falls_back_to_directive_yaml() -> None:
    # No defaults.conf, no overlay (a directive vendored from a pre-#331 release):
    # the directive.yaml `subagent.tiers.sweep` value is the default.
    with tempfile.TemporaryDirectory() as tmp:
        d = _subagent_dir(Path(tmp), with_defaults=False, sweep_tier_yaml="low")
        assert sweep.resolve_model_tier(d) == "low"


def test_resolve_tier_env_wins() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        d = _subagent_dir(Path(tmp), with_defaults=True, overlay_tier="low")
        os.environ["GOVERNANCE_SUBAGENT_TIERS_SWEEP"] = "medium"
        try:
            assert sweep.resolve_model_tier(d) == "medium"
        finally:
            del os.environ["GOVERNANCE_SUBAGENT_TIERS_SWEEP"]


def test_resolve_tier_legacy_directive_keeps_model_tier() -> None:
    # A non-subagent sweep directive keeps its top-level model_tier (default high).
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp) / "repo"
        d = root / ".governance" / "packs" / "acme" / "shape" / "directives" / "ns"
        d.mkdir(parents=True)
        (d / "directive.yaml").write_text("surface: sweep\nhook: none\nmodel_tier: low\n")
        assert sweep.resolve_model_tier(d) == "low"
        (d / "directive.yaml").write_text("surface: sweep\nhook: none\n")
        assert sweep.resolve_model_tier(d) == "high"


if __name__ == "__main__":
    failures = 0
    for name, fn in sorted(globals().items()):
        if not name.startswith("test_"):
            continue
        try:
            fn()
        except Exception as exc:  # noqa: BLE001
            failures += 1
            print(f"not ok - {name}: {exc}", file=sys.stderr)
        else:
            print(f"ok - {name}")
    raise SystemExit(1 if failures else 0)
