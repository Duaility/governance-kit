#!/usr/bin/env python3
"""Unit tests for docsurgery.py — the pure CONSTITUTION.md text transforms shared
by the lifecycle engines (init assembly, `pack add`/`update`/`remove`, reset).

Split out of test-packverb-apply.py (which owns the pack-plan/apply integration
tests) so each stays focused and under the file-size limit. These are pure
string→string transforms — no fetch, no filesystem, no git.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACK_LIB = ROOT / "kit" / "assets" / "packs" / "lib"


def _load(name: str):
    sys.path.insert(0, str(PACK_LIB))
    spec = importlib.util.spec_from_file_location(name, PACK_LIB / f"{name}.py")
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


docsurgery = _load("docsurgery")


CONST = (
    "# CONSTITUTION\n\n## Directives\n\n"
    "### required-docs\n\n- body A\n\n"
    "### no-console-log\n\n- body B\n\n"
    "### secrets-hygiene\n\n- body C\n\n"
    "## Evolution Log\n\n<!-- hint -->\n\n- 2026-01-01 — old\n"
)


def test_strip_subsection_removes_only_target() -> None:
    out, removed = docsurgery.strip_directive_subsection(CONST, "no-console-log")
    assert removed
    assert "### no-console-log" not in out
    assert "### required-docs" in out and "### secrets-hygiene" in out
    assert "- body A" in out and "- body C" in out and "- body B" not in out


def test_strip_subsection_absent_is_noop() -> None:
    out, removed = docsurgery.strip_directive_subsection(CONST, "nope")
    assert not removed and out == CONST


def test_strip_subsection_prefix_no_alias() -> None:
    # `doc` must not match `doc-freshness`.
    text = "## Directives\n\n### doc-freshness\n\nbody\n"
    out, removed = docsurgery.strip_directive_subsection(text, "doc")
    assert not removed and out == text


def test_upsert_replaces_in_place() -> None:
    out, action = docsurgery.upsert_directive_subsection(
        CONST, "no-console-log", "### no-console-log\n\n- NEW body\n")
    assert action == "replaced"
    assert "- NEW body" in out and "- body B" not in out
    assert out.count("### no-console-log") == 1


def test_upsert_inserts_at_end_of_directives() -> None:
    out, action = docsurgery.upsert_directive_subsection(
        CONST, "brand-new", "### brand-new\n\n- fresh\n")
    assert action == "inserted"
    # lands inside Directives, before Evolution Log
    assert out.index("### brand-new") < out.index("## Evolution Log")


# A constitution with one pack group already present, for the pack-aware upsert.
_GROUPED = (
    "# CONSTITUTION\n\n## Directives\n\n"
    "### ungrouped-one\n\n- u1\n\n"
    "## governance-kit/foundation\n\n"
    "### required-docs\n\n- rd\n\n"
    "## Evolution Log\n\n- 2026-01-01 — seed\n"
)


def test_upsert_pack_creates_header_and_nests() -> None:
    out, action = docsurgery.upsert_directive_subsection(
        _GROUPED, "no-shims", "### no-shims\n\n- ns\n", "acme/shapes")
    assert action == "inserted"
    assert "## acme/shapes" in out
    # new pack header sits in the Directives region, before Evolution Log
    assert out.index("## governance-kit/foundation") < out.index("## acme/shapes") < out.index("## Evolution Log")
    assert out.index("## acme/shapes") < out.index("### no-shims") < out.index("## Evolution Log")


def test_upsert_pack_nests_into_existing_header_sorted() -> None:
    out, _ = docsurgery.upsert_directive_subsection(
        _GROUPED, "kit-version-sync", "### kit-version-sync\n\n- kv\n", "governance-kit/foundation")
    seg = out[out.index("## governance-kit/foundation"):out.index("## Evolution Log")]
    order = [ln for ln in seg.splitlines() if ln.startswith("### ")]
    # sorted within the group: kit-version-sync precedes required-docs
    assert order == ["### kit-version-sync", "### required-docs"], order


def test_upsert_pack_relocates_ungrouped_subsection() -> None:
    # `ungrouped-one` sits bare under `## Directives`; upserting it with its pack
    # id moves it under the pack header (removing the stray copy), not duplicates.
    out, action = docsurgery.upsert_directive_subsection(
        _GROUPED, "ungrouped-one", "### ungrouped-one\n\n- u1 v2\n", "acme/shapes")
    assert action == "replaced"
    assert out.count("### ungrouped-one") == 1
    assert "- u1\n" not in out and "- u1 v2" in out
    assert out.index("## acme/shapes") < out.index("### ungrouped-one")


def test_upsert_pack_is_idempotent() -> None:
    once, _ = docsurgery.upsert_directive_subsection(
        _GROUPED, "no-shims", "### no-shims\n\n- ns\n", "acme/shapes")
    twice, _ = docsurgery.upsert_directive_subsection(
        once, "no-shims", "### no-shims\n\n- ns\n", "acme/shapes")
    assert once == twice


def test_render_pack_groups_emits_headers_and_blocks() -> None:
    out = docsurgery.render_pack_groups(
        [("a/b", ["### r\n\n- R\n", "### h\n\n- H\n"]), ("a/c", ["### s\n\n- S\n"])])
    assert out == "## a/b\n\n### r\n\n- R\n\n### h\n\n- H\n\n## a/c\n\n### s\n\n- S\n\n"


def test_append_evolution_log_after_last_entry() -> None:
    out = docsurgery.append_evolution_log(CONST, "- 2026-06-10 — new entry")
    assert out.rstrip().endswith("- 2026-06-10 — new entry")
    assert "- 2026-01-01 — old" in out


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
