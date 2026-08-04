#!/usr/bin/env python3
# governance: allow-repo-hygiene file-size-limit one consolidated test layer for the sweep engine (issue #355)
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


# ── the full `subagent:` block reader (issue #355 Phase 2) ───────────────────
def _full_subagent_dir(base: Path, *, gate: str | None = None, sink: str | None = None,
                       sweep_tier: str = "high") -> Path:
    """An installed-layout directive carrying the FULL `subagent:` block
    (inputs, checks, optional gate/sink, section, tiers) — the real shape
    receipt-per-issue/agent-steering-accounting/layer-boundaries ship."""
    root = base / "repo"
    d = root / ".governance" / "packs" / "acme" / "audit" / "directives" / "rec"
    d.mkdir(parents=True)
    gate_line = f"  gate: {gate}\n" if gate else ""
    sink_line = f"  sink: {sink}\n" if sink else ""
    (d / "directive.yaml").write_text(
        "category: AgentDiscipline\nsummary: audit the receipt\n"
        "surface: change-set\nhook: pre-commit\n"
        "subagent:\n"
        "  inputs:  [diff, receipt, issue]\n"
        "  checks:\n"
        "    - \"'## What changed' faithfully describes the diff\"\n"
        "    - \"each '- [x]' item is realized in the diff\"\n"
        f"{gate_line}{sink_line}"
        "  isolation: shared\n  section: Audit\n"
        f"  tiers: {{ attest: low, sweep: {sweep_tier} }}\n")
    return d


def test_subagent_list_reads_inputs_flow_list() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        d = _full_subagent_dir(Path(tmp))
        assert sweep._subagent_list(d, "inputs") == ["diff", "receipt", "issue"]


def test_subagent_list_reads_checks_block_list() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        d = _full_subagent_dir(Path(tmp))
        assert sweep._subagent_list(d, "checks") == [
            "'## What changed' faithfully describes the diff",
            "each '- [x]' item is realized in the diff",
        ]


def test_subagent_scalar_reads_section() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        d = _full_subagent_dir(Path(tmp))
        assert sweep._subagent_scalar(d, "section") == "Audit"


def test_subagent_gate_defaults_to_record() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        d = _full_subagent_dir(Path(tmp))
        assert sweep._subagent_gate(d) == "record"


def test_subagent_gate_reads_verdict() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        d = _full_subagent_dir(Path(tmp), gate="verdict")
        assert sweep._subagent_gate(d) == "verdict"


def test_subagent_sink_defaults_to_section() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        d = _full_subagent_dir(Path(tmp))
        assert sweep._subagent_sink(d) == "section"


def test_subagent_sink_reads_none() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        d = _full_subagent_dir(Path(tmp), sink="none")
        assert sweep._subagent_sink(d) == "none"


def test_subagent_block_absent_returns_empty_list_and_none_scalar() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp) / "repo"
        d = root / ".governance" / "packs" / "acme" / "shape" / "directives" / "ns"
        d.mkdir(parents=True)
        (d / "directive.yaml").write_text("surface: sweep\nhook: none\n")
        assert sweep._subagent_list(d, "checks") == []
        assert sweep._subagent_scalar(d, "section") is None
        assert sweep._subagent_gate(d) == "record"
        assert sweep._subagent_sink(d) == "section"


# ── discovery: subagent-declared directives join the sweep lane ──────────────
def test_discovery_includes_legacy_sweep_directive() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = _fixture_repo(Path(tmp))
        found = sweep.discover_sweep_directives(root)
        assert [d.name for d in found] == ["no-shims"]


def test_discovery_includes_subagent_directive_with_enabled_tier() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        d = _full_subagent_dir(Path(tmp), sweep_tier="high")
        root = Path(tmp) / "repo"
        found = sweep.discover_sweep_directives(root)
        assert d in found


def test_discovery_excludes_subagent_directive_with_tier_none() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        d = _full_subagent_dir(Path(tmp), sweep_tier="none")
        root = Path(tmp) / "repo"
        found = sweep.discover_sweep_directives(root)
        assert d not in found


def test_discovery_excludes_subagent_directive_with_tier_off() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        d = _full_subagent_dir(Path(tmp), sweep_tier="off")
        root = Path(tmp) / "repo"
        found = sweep.discover_sweep_directives(root)
        assert d not in found


def test_discovery_subagent_wins_over_legacy_when_both_present() -> None:
    # A directive.yaml carrying BOTH surface: sweep AND a subagent block is
    # counted exactly once — the subagent-declared path wins, never a double-run.
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp) / "repo"
        d = root / ".governance" / "packs" / "acme" / "audit" / "directives" / "both"
        d.mkdir(parents=True)
        (d / "directive.yaml").write_text(
            "surface: sweep\nhook: none\n"
            "subagent:\n  inputs: [diff]\n  checks:\n    - x\n"
            "  section: X\n  tiers: { attest: low, sweep: high }\n")
        found = sweep.discover_sweep_directives(root)
        assert found.count(d) == 1


# ── rubric build (issue #355 Phase 2) ─────────────────────────────────────────
def test_subagent_rubric_renders_numbered_checks() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        d = _full_subagent_dir(Path(tmp))
        rubric = sweep._subagent_rubric(d)
        assert rubric.splitlines()[0] == "1. '## What changed' faithfully describes the diff"
        assert "2. each '- [x]' item is realized in the diff" in rubric.splitlines()
        assert "adjudication log" not in rubric  # record mode: no standing lines


def test_subagent_rubric_appends_standing_lines_when_gate_verdict() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        d = _full_subagent_dir(Path(tmp), gate="verdict")
        rubric = sweep._subagent_rubric(d)
        assert "well-formed adjudication log" in rubric
        assert "CONTESTED" in rubric
        # the standing lines are numbered on from the authored checks, not reset
        assert rubric.splitlines()[2].startswith("3. ")


# ── batching: rubric build + violation demux (issue #355 Phase 4) ────────────
def test_build_batch_rubric_headers_each_directive() -> None:
    rubric = sweep._build_batch_rubric([("acme/audit/a", "1. x"), ("acme/audit/b", "1. y")])
    assert "## acme/audit/a" in rubric
    assert "## acme/audit/b" in rubric
    assert "1. x" in rubric and "1. y" in rubric


def test_demux_batch_violations_groups_by_directive_field() -> None:
    violations = [
        {"directive": "a", "file": "f", "line": 1, "quote": "q1", "why": "w1"},
        {"directive": "b", "file": "f", "line": 2, "quote": "q2", "why": "w2"},
        {"directive": "a", "file": "f", "line": 3, "quote": "q3", "why": "w3"},
    ]
    grouped = sweep._demux_batch_violations(violations, ["a", "b"])
    assert len(grouped["a"]) == 2
    assert len(grouped["b"]) == 1
    assert "directive" not in grouped["a"][0]


def test_demux_batch_violations_drops_unknown_or_missing_directive() -> None:
    violations = [
        {"directive": "ghost", "file": "f", "line": 1, "quote": "", "why": ""},
        {"file": "f", "line": 2, "quote": "", "why": ""},
    ]
    grouped = sweep._demux_batch_violations(violations, ["a", "b"])
    assert grouped["a"] == [] and grouped["b"] == []


def test_max_tier_picks_the_highest_ranked() -> None:
    assert sweep._max_tier({"low", "high", "medium"}) == "high"
    assert sweep._max_tier({"low", "medium"}) == "medium"
    assert sweep._max_tier({"low"}) == "low"
    # an unrecognized token never wins the max against a named tier
    assert sweep._max_tier({"low", "bogus"}) == "low"


# ── per-judgment retry (issue #355 Phase 4) ───────────────────────────────────
def test_adjudicate_retrying_retries_once_on_transport_failure() -> None:
    calls = []

    def fake(**kwargs):
        calls.append(1)
        return sweep._verdict(passed=True, adjudicated=False, note="boom")

    verdict, retried = sweep._adjudicate_retrying(fake)
    assert retried is True
    assert len(calls) == 2
    assert verdict["adjudicated"] is False


def test_adjudicate_retrying_no_retry_on_clean_verdict() -> None:
    calls = []

    def fake(**kwargs):
        calls.append(1)
        return sweep._verdict(passed=True)

    verdict, retried = sweep._adjudicate_retrying(fake)
    assert retried is False
    assert len(calls) == 1


def test_adjudicate_retrying_recovers_on_second_attempt() -> None:
    results = [sweep._verdict(passed=True, adjudicated=False, note="boom"),
               sweep._verdict(passed=True)]

    def fake(**kwargs):
        return results.pop(0)

    verdict, retried = sweep._adjudicate_retrying(fake)
    assert retried is True
    assert verdict["adjudicated"] is True


# ── triage for the subagent-declared path (receipts as hunks) ────────────────
def test_triage_receipts_filters_to_receipts_md_touched_in_range() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp) / "repo"
        root.mkdir(parents=True)
        (root / "README.md").write_text("seed\n")
        git(root, "init", "-q", ".")
        git(root, "add", "-A")
        git(root, "commit", "-qm", "seed")
        start = subprocess.run(["git", "-C", str(root), "rev-parse", "HEAD"],
                               capture_output=True, text=True, env=GIT_CLEAN_ENV).stdout.strip()
        (root / "receipts").mkdir()
        (root / "receipts" / "issue-1-x.md").write_text("## Audit\n\nPASS\n")
        (root / "src.py").write_text("print(1)\n")
        git(root, "add", "-A")
        git(root, "commit", "-qm", "add receipt and unrelated file")
        touched = sweep._triage_receipts(root, f"{start}..HEAD")
        assert touched == ["receipts/issue-1-x.md"]


# ── end-to-end: a subagent-declared directive is swept via the echo stub ─────
def _subagent_fixture_repo(base: Path) -> Path:
    """A repo with ONE subagent-declared directive (no triage.sh/constitution.md)
    and no legacy sweep directive; a receipt added after the seed commit trips
    the echo keyword stub."""
    root = base / "repo"
    d = root / ".governance" / "packs" / "acme" / "audit" / "directives" / "rec"
    (d / "evals").mkdir(parents=True)
    (d / "directive.yaml").write_text(
        "category: AgentDiscipline\nsummary: audit\nsurface: change-set\nhook: pre-commit\n"
        "subagent:\n  inputs: [diff, receipt]\n  checks:\n"
        "    - \"the Audit section is honest\"\n"
        "  isolation: shared\n  section: Audit\n"
        "  tiers: { attest: low, sweep: high }\n")
    (d / "evals" / "echo-keywords.txt").write_text("scope-creep\n")
    (root / "README.md").write_text("seed\n")
    git(root, "init", "-q", ".")
    git(root, "add", "-A")
    git(root, "commit", "-qm", "seed")
    (root / "receipts").mkdir(parents=True)
    (root / "receipts" / "issue-9-x.md").write_text(
        "## Audit\n\nPASS -- but there's a scope-creep beyond the issue.\n")
    git(root, "add", "-A")
    git(root, "commit", "-qm", "add receipt")
    return root


def test_subagent_declared_directive_is_swept_end_to_end() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = _subagent_fixture_repo(Path(tmp))
        res, calls = _run_sweep(Path(tmp), root, "ok")
        assert res.returncode == 0, res.stderr
        assert "--label governance-sweep" in _issue_create_call(calls)


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
