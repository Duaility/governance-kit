#!/usr/bin/env python3
"""Contract tests for kityaml.py — the stdlib-only restricted-YAML load/dump
pair that replaced `uv run --with PyYAML` across the kit's lifecycle tooling
(issue #355).

Three layers:
  1. Grammar unit tests — every shape the locked grammar promises (block
     maps/sequences, both sequence-nesting conventions, list-of-maps,
     flow collections, quoting, coercion) plus the loud-error cases
     (anchors/aliases/tags/block-scalars/tabs).
  2. Byte-for-byte writer parity against this repo's real
     `.governance/packs.lock` (produced, before #355, by
     `yaml.safe_dump(sort_keys=False, default_flow_style=False)`).
  3. Load-parity: every YAML file the kit itself ships or reads
     (packs/*/pack.yaml, packs/*/directives/*/directive.yaml,
     kit/assets/kit.yaml, .governance/install.yaml, .governance/packs.lock)
     parses to a sane dict. When PyYAML happens to be importable in the
     environment this also asserts equality with `yaml.safe_load` — a bonus
     check, not a requirement: this suite must pass with PyYAML absent,
     which is the entire point of #355.

Run via: python3 scripts/test-kityaml.py  (plain python3 — no uv, no PyYAML).
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
PACK_LIB = ROOT / "kit" / "assets" / "packs" / "lib"
KITYAML_PATH = PACK_LIB / "kityaml.py"


def _load_kityaml():
    sys.path.insert(0, str(PACK_LIB))
    spec = importlib.util.spec_from_file_location("kityaml_under_test", KITYAML_PATH)
    if spec is None or spec.loader is None:
        raise AssertionError(f"cannot load {KITYAML_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


KY = _load_kityaml()


def _expect_error(text: str, label: str) -> None:
    try:
        KY.loads(text)
    except KY.YAMLError:
        return
    raise AssertionError(f"{label}: expected YAMLError, none raised for {text!r}")


# ---------------------------------------------------------------------------
# 1. Grammar: scalars, coercion, quoting
# ---------------------------------------------------------------------------


def test_bool_coercion() -> None:
    for text in ("true", "True", "TRUE", "yes", "Yes", "on", "On"):
        assert KY.loads(f"k: {text}")["k"] is True, text
    for text in ("false", "False", "FALSE", "no", "No", "off", "Off"):
        assert KY.loads(f"k: {text}")["k"] is False, text


def test_null_coercion() -> None:
    for text in ("null", "Null", "NULL", "~"):
        assert KY.loads(f"k: {text}")["k"] is None, text
    # A key with nothing after the colon is also None.
    assert KY.loads("k:")["k"] is None


def test_int_and_float_coercion() -> None:
    assert KY.loads("k: 2")["k"] == 2 and isinstance(KY.loads("k: 2")["k"], int)
    assert KY.loads("k: -5")["k"] == -5
    assert KY.loads("k: 0.8")["k"] == 0.8 and isinstance(KY.loads("k: 0.8")["k"], float)
    assert KY.loads("k: 1e10")["k"] == 1e10


def test_multi_dot_version_stays_str() -> None:
    # The locked grammar's whole reason for existing: `0.8.1` must NOT
    # coerce to a number just because it starts with digits and dots.
    for text in ("0.8.1", "0.10.0", "0.12.0"):
        value = KY.loads(f"k: {text}")["k"]
        assert value == text and isinstance(value, str), (text, value)


def test_quoted_scalar_always_str() -> None:
    # A quoted scalar that LOOKS like a bool/int/null lookalike stays a
    # string — quoting always wins over coercion (this is exactly why
    # write_lockfile quotes LOCK_VERSION = "2").
    assert KY.loads("k: '2'")["k"] == "2"
    assert isinstance(KY.loads("k: '2'")["k"], str)
    assert KY.loads('k: "true"')["k"] == "true"
    assert KY.loads("k: ''")["k"] == ""


def test_single_quote_escape() -> None:
    assert KY.loads("k: 'it''s'")["k"] == "it's"


def test_double_quote_escapes() -> None:
    d = KY.loads(r'k: "a\tb\nc\\d"')
    assert d["k"] == "a\tb\nc\\d"


def test_comment_stripped_outside_quotes() -> None:
    d = KY.loads("k: value # trailing comment\n")
    assert d["k"] == "value"
    d = KY.loads("k: 'value # not a comment'\n")
    assert d["k"] == "value # not a comment"


def test_hash_not_preceded_by_whitespace_is_not_a_comment() -> None:
    # Matches real yaml.safe_load: a `#` glued onto a plain scalar (no
    # preceding whitespace) does not start a comment. The shipped YAML corpus
    # is also covered by the load-parity test below.
    assert KY.loads("k: before#glued\n")["k"] == "before#glued"
    assert KY.loads("k: before #spaced\n")["k"] == "before"


# ---------------------------------------------------------------------------
# 1b. Grammar: block/flow collections
# ---------------------------------------------------------------------------


def test_flow_list_and_map() -> None:
    d = KY.loads("inputs: [diff, receipt]\ntiers: { attest: low, schedule: high }\n")
    assert d == {"inputs": ["diff", "receipt"], "tiers": {"attest": "low", "schedule": "high"}}


def test_empty_flow_collections() -> None:
    d = KY.loads("collisions: []\nempty_map: {}\n")
    assert d == {"collisions": [], "empty_map": {}}


def test_indentless_sequence_convention() -> None:
    # The shape yaml.safe_dump produces: sequence items at the SAME column
    # as the key that introduces them.
    text = "directives:\n- a\n- b\n"
    assert KY.loads(text) == {"directives": ["a", "b"]}


def test_indented_sequence_convention() -> None:
    # The shape humans hand-author (see packs/*/pack.yaml presets): sequence
    # items indented further than the key.
    text = "presets:\n  standard:\n    directives:\n      - a\n      - b\n"
    assert KY.loads(text) == {"presets": {"standard": {"directives": ["a", "b"]}}}


def test_sequence_of_maps() -> None:
    text = (
        "packs:\n"
        "- id: a/b\n"
        "  version: '0.1'\n"
        "  directives:\n"
        "  - x\n"
        "  - y\n"
        "  digest:\n"
        "    x: deadbeef\n"
    )
    d = KY.loads(text)
    assert d == {
        "packs": [
            {
                "id": "a/b",
                "version": "0.1",
                "directives": ["x", "y"],
                "digest": {"x": "deadbeef"},
            }
        ]
    }


def test_nested_flow_list_value() -> None:
    d = KY.loads("k: [a, 'b c', 2, true]\n")
    assert d["k"] == ["a", "b c", 2, True]


# ---------------------------------------------------------------------------
# 1c. Loud errors on out-of-grammar constructs
# ---------------------------------------------------------------------------


def test_rejects_anchor() -> None:
    _expect_error("a: &anchor foo\n", "anchor")


def test_rejects_alias() -> None:
    _expect_error("a: *alias\n", "alias")


def test_rejects_tag() -> None:
    _expect_error("a: !!str foo\n", "tag")


def test_rejects_block_scalars() -> None:
    _expect_error("a: |\n  block\n", "literal block scalar")
    _expect_error("a: >\n  folded\n", "folded block scalar")


def test_rejects_tab_indentation() -> None:
    _expect_error("\ta: foo\n", "tab indentation")


def test_error_message_names_file_and_line() -> None:
    try:
        KY.loads("a: foo\n\tb: bar\n", source="some/file.yaml")
    except KY.YAMLError as exc:
        assert "some/file.yaml:2" in str(exc), str(exc)
    else:
        raise AssertionError("expected YAMLError")


# ---------------------------------------------------------------------------
# 2. Writer parity
# ---------------------------------------------------------------------------


def test_round_trip_idempotent() -> None:
    obj: dict[str, Any] = {
        "version": "2",
        "packs": [
            {
                "id": "a/b",
                "version": "0.1",
                "source": "local",
                "directives": ["x", "y"],
            },
            {
                "id": "c/d",
                "version": "1.2.3",
                "source": "gh",
                "sha": "deadbeefcafe",
                "digest": {"x": "aaa", "y": "bbb"},
                "installed_at": "2026-06-17T18:56:01Z",
            },
        ],
    }
    dumped = KY.dump(obj)
    reloaded = KY.loads(dumped)
    assert reloaded == obj, (reloaded, obj)
    # Dumping the reloaded structure again must be byte-identical (stable
    # fixed point), not just structurally equal.
    assert KY.dump(reloaded) == dumped


def test_quoting_decisions() -> None:
    # bool/int/float/null lookalikes, and the "yaml-timestamp" lookalike a
    # real yaml.safe_dump also quotes (see kityaml.py's writer docstring) —
    # all must round-trip through dump() -> loads() unchanged.
    for value in ("2", "true", "0.1", "", "2026-06-17T18:56:01Z", "- not a seq item"):
        dumped = KY.dump({"k": value})
        assert KY.loads(dumped)["k"] == value, (value, dumped)


def test_unambiguous_scalars_stay_unquoted() -> None:
    dumped = KY.dump({"id": "governance-kit/audit", "hook": "pre-commit"})
    assert "'" not in dumped, dumped


def test_packs_lock_byte_parity() -> None:
    lockfile = ROOT / ".governance" / "packs.lock"
    original = lockfile.read_text()
    data = KY.load(lockfile)
    assert KY.dump(data) == original, "dump(load(packs.lock)) must reproduce the file byte-for-byte"


def test_install_yaml_loads_but_is_not_dump_parity_checked() -> None:
    # install.yaml is NOT produced by kityaml.dump() / yaml.safe_dump — it is
    # hand-templated line-by-line by install.sh's write_installed_manifest
    # (bash printf, not a YAML emitter), so its quoting choices (e.g.
    # `version: "3"` in double quotes) are an authoring convention, not a
    # dump() contract. kityaml only needs to LOAD it correctly, which every
    # kitverb.py/kitresolve.py/packplan.py/uninstallplan.py call site relies
    # on; there is no writer call site for install.yaml to hold to byte
    # parity, so — unlike packs.lock — no round-trip assertion is meaningful
    # here.
    manifest = ROOT / ".governance" / "install.yaml"
    data = KY.load(manifest)
    assert isinstance(data, dict)
    assert data["kit_version"]
    assert isinstance(data.get("install_assets_seeded"), list)
    assert isinstance(data.get("managed_digests"), dict)


# ---------------------------------------------------------------------------
# 3. Load-parity across the kit's own shipped YAML corpus
# ---------------------------------------------------------------------------


def _corpus_files() -> list[Path]:
    files: set[Path] = set()
    files.update((ROOT / "packs").glob("*/pack.yaml"))
    files.update((ROOT / "packs").glob("*/directives/*/directive.yaml"))
    files.update((ROOT / ".governance" / "packs").glob("*/*/pack.yaml"))
    files.update((ROOT / ".governance" / "packs").glob("*/*/directives/*/directive.yaml"))
    files.add(ROOT / "kit" / "assets" / "kit.yaml")
    files.add(ROOT / ".governance" / "install.yaml")
    files.add(ROOT / ".governance" / "packs.lock")
    return sorted(f for f in files if f.is_file())


def test_load_parity_across_shipped_corpus() -> None:
    files = _corpus_files()
    assert len(files) >= 30, f"expected the corpus walk to find a good few files, found {len(files)}"
    for path in files:
        data = KY.load(path)
        assert isinstance(data, dict), f"{path}: kityaml.load did not return a mapping"


def test_load_parity_bonus_against_pyyaml_if_available() -> None:
    try:
        import yaml  # noqa: PLC0415 - optional bonus check, see module docstring (#355).
    except ImportError:
        return  # The whole point of #355: this suite must pass without PyYAML.

    import datetime

    def normalize(value: Any) -> Any:
        if isinstance(value, dict):
            return {k: normalize(v) for k, v in value.items()}
        if isinstance(value, list):
            return [normalize(v) for v in value]
        if isinstance(value, datetime.date):
            # yaml.safe_load resolves bare ISO-8601 strings to date/datetime
            # objects; kityaml never coerces timestamps (str always), so
            # normalize PyYAML's richer type back down for comparison.
            if isinstance(value, datetime.datetime):
                return value.strftime("%Y-%m-%dT%H:%M:%SZ")
            return value.isoformat()
        return value

    for path in _corpus_files():
        mine = KY.load(path)
        theirs = normalize(yaml.safe_load(path.read_text()))
        assert mine == theirs, f"{path}: kityaml/PyYAML disagree\n  mine  ={mine}\n  theirs={theirs}"


if __name__ == "__main__":
    failures = 0
    for name, fn in sorted(globals().items()):
        if not name.startswith("test_"):
            continue
        try:
            fn()
        except Exception as exc:  # noqa: BLE001 - tiny stdlib-only harness (#355).
            failures += 1
            print(f"not ok - {name}: {exc}", file=sys.stderr)
        else:
            print(f"ok - {name}")
    raise SystemExit(1 if failures else 0)
