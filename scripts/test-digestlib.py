#!/usr/bin/env python3
"""scripts/test-digestlib.py — the shared digest helper (issue #253).

Covers the two correctness properties `managed-tree-integrity` depends on:
  1. determinism + exclusions — `directory_digest` is stable regardless of
     filesystem walk order and ignores `evals/`, `install-assets/`,
     `__pycache__/`, and `*.pyc`;
  2. parity — the digest routine the apply engines use
     (`kit/assets/packs/lib/digestlib.py`) and the byte-identical copy the
     directive ships (`packs/foundation/directives/managed-tree-integrity/lib/
     integrity.py`) produce the SAME hex for the same inputs. A drift between
     the two would silently break offline verification, so it's pinned here.
"""
import hashlib
import importlib.util
import sys
import tempfile
from pathlib import Path

# Don't write .pyc into the source dirs we import from — a vendored __pycache__
# would trip repo-hygiene downstream (issue #253).
sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[1]


def _load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


digestlib = _load("digestlib", ROOT / "kit/assets/packs/lib/digestlib.py")
directive = _load(
    "mti_integrity",
    ROOT / "packs/foundation/directives/managed-tree-integrity/lib/integrity.py",
)

passed = 0
failed = 0


def check(name: str, cond: bool):
    global passed, failed
    if cond:
        passed += 1
        print(f"  ✓ {name}")
    else:
        failed += 1
        print(f"  ✗ {name}", file=sys.stderr)


def _populate(d: Path):
    (d / "check.sh").write_text("#!/usr/bin/env bash\necho ok\n")
    (d / "directive.yaml").write_text("summary: demo\n")
    (d / "lib").mkdir()
    (d / "lib" / "helper.py").write_text("x = 1\n")


with tempfile.TemporaryDirectory() as tmp:
    base = Path(tmp) / "dir"
    base.mkdir()
    _populate(base)

    d1 = digestlib.directory_digest(base)
    d2 = directive.directory_digest(base)

    check("directory_digest is non-empty for a populated folder", bool(d1))
    check("digestlib and directive directory_digest agree (parity)", d1 == d2)

    f1 = digestlib.file_digest(base / "check.sh")
    f2 = directive.file_digest(base / "check.sh")
    check("file_digest parity", f1 == f2 == hashlib.sha256((base / "check.sh").read_bytes()).hexdigest())

    # adding an excluded artifact must NOT change the digest
    (base / "lib" / "__pycache__").mkdir()
    (base / "lib" / "__pycache__" / "helper.cpython-312.pyc").write_text("bytecode")
    (base / "lib" / "stale.pyc").write_text("more bytecode")
    (base / "evals").mkdir()
    (base / "evals" / "test.sh").write_text("echo eval\n")
    (base / "install-assets").mkdir()
    (base / "install-assets" / "x.yml").write_text("a: b\n")
    check("excluded dirs/.pyc do not affect the digest", digestlib.directory_digest(base) == d1)
    check("directive copy agrees after exclusions", directive.directory_digest(base) == d1)

    # a real content change MUST change the digest
    (base / "check.sh").write_text("#!/usr/bin/env bash\necho TAMPERED\n")
    check("content change flips the digest", digestlib.directory_digest(base) != d1)

    # adding a real (non-excluded) file MUST change the digest
    (base / "check.sh").write_text("#!/usr/bin/env bash\necho ok\n")  # restore
    check("restore returns to original digest", digestlib.directory_digest(base) == d1)
    (base / "extra.md").write_text("new\n")
    check("adding a tracked file flips the digest", digestlib.directory_digest(base) != d1)

    # missing directory → empty
    check("missing dir digests to empty string", digestlib.directory_digest(Path(tmp) / "nope") == "")

    # EXCLUDED_DIRS constant parity
    check("EXCLUDED_DIRS match between modules",
          tuple(digestlib.EXCLUDED_DIRS) == tuple(directive.EXCLUDED_DIRS))

# managed_digests block round-trip
with tempfile.TemporaryDirectory() as tmp:
    manifest = Path(tmp) / "install.yaml"
    manifest.write_text('version: "3"\nkit_version: "0.7.2"\ncollisions: []\n')
    digestlib.write_managed_digests_block(manifest, {".governance/lib.sh": "abc", ".governance/run.sh": "def"})
    parsed = directive.parse_managed_digests(manifest)
    check("manifest managed_digests round-trips through writer+parser",
          parsed == {".governance/lib.sh": "abc", ".governance/run.sh": "def"})
    # rewrite replaces (not appends) the block
    digestlib.write_managed_digests_block(manifest, {".governance/lib.sh": "zzz"})
    parsed = directive.parse_managed_digests(manifest)
    check("rewrite replaces the block", parsed == {".governance/lib.sh": "zzz"})
    check("other manifest keys survive the rewrite", 'kit_version: "0.7.2"' in manifest.read_text())
    # empty mapping → managed_digests: {}
    digestlib.write_managed_digests_block(manifest, {})
    check("empty mapping emits {} and parses to {}", directive.parse_managed_digests(manifest) == {})

print()
if failed:
    print(f"✗ test-digestlib: {failed} failed, {passed} passed", file=sys.stderr)
    sys.exit(1)
print(f"✓ test-digestlib: {passed} assertions passed")
