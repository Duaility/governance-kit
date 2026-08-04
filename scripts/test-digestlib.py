#!/usr/bin/env python3
"""scripts/test-digestlib.py — the shared digest helper (issue #253).

Covers the two correctness properties `managed-tree-integrity` depends on:
  1. determinism + exclusions — `directory_digest` is stable regardless of
     filesystem walk order and ignores `evals/`, `install-assets/`,
     `__pycache__/`, and `*.pyc`;
  2. parity — the digest routine the apply engines use
     (`kit/assets/packs/lib/digestlib.py`, Python) and the pure bash/awk copy
     the directive ships (`packs/foundation/directives/managed-tree-integrity/
     lib/digest.sh` — issue #355 moved the commit path off python) produce the
     SAME hex for the same inputs. A drift between the two would silently
     break offline verification, so it's pinned here.

The bash side is exercised as a real subprocess (`bash -c 'source digest.sh;
mti_dir_digest <dir>'`), not re-implemented in Python — a parity test that
duplicated the bash logic in Python could drift from the actual check.sh
behavior without ever failing.
"""
import hashlib
import importlib.util
import re
import shlex
import subprocess
import sys
import tempfile
from pathlib import Path

# Don't write .pyc into the source dirs we import from — a vendored __pycache__
# would trip repo-hygiene downstream (issue #253).
sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[1]
DIGEST_SH = ROOT / "packs/foundation/directives/managed-tree-integrity/lib/digest.sh"


def _load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


digestlib = _load("digestlib", ROOT / "kit/assets/packs/lib/digestlib.py")

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


def _bash(fn: str, *args: str) -> str:
    """Invoke a lib/digest.sh function as a real bash subprocess and return its
    stdout, trailing newline stripped (the digest routines print a bare hex
    string, or nothing at all for a missing/empty directory)."""
    quoted_args = " ".join(shlex.quote(a) for a in args)
    cmd = f"source {shlex.quote(str(DIGEST_SH))}; {fn} {quoted_args}"
    r = subprocess.run(["bash", "-c", cmd], capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"{fn} {args} failed (exit {r.returncode}): {r.stderr}")
    return r.stdout.strip("\n")


def bash_dir_digest(path) -> str:
    return _bash("mti_dir_digest", str(path))


def bash_file_digest(path) -> str:
    return _bash("mti_sha256_file", str(path))


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
    d2 = bash_dir_digest(base)

    check("directory_digest is non-empty for a populated folder", bool(d1))
    check("digestlib (python) and digest.sh (bash) directory_digest agree (parity)", d1 == d2)

    f1 = digestlib.file_digest(base / "check.sh")
    f2 = bash_file_digest(base / "check.sh")
    check("file_digest parity", f1 == f2 == hashlib.sha256((base / "check.sh").read_bytes()).hexdigest())

    # adding an excluded artifact must NOT change the digest
    (base / "lib" / "__pycache__").mkdir()
    (base / "lib" / "__pycache__" / "helper.cpython-312.pyc").write_text("bytecode")
    (base / "lib" / "stale.pyc").write_text("more bytecode")
    (base / "evals").mkdir()
    (base / "evals" / "test.sh").write_text("echo eval\n")
    (base / "install-assets").mkdir()
    (base / "install-assets" / "x.yml").write_text("a: b\n")
    check("excluded dirs/.pyc do not affect the digest (python)", digestlib.directory_digest(base) == d1)
    check("excluded dirs/.pyc do not affect the digest (bash)", bash_dir_digest(base) == d1)

    # a real content change MUST change the digest
    (base / "check.sh").write_text("#!/usr/bin/env bash\necho TAMPERED\n")
    check("content change flips the digest (python)", digestlib.directory_digest(base) != d1)
    check("content change flips the digest (bash)", bash_dir_digest(base) != d1)

    # adding a real (non-excluded) file MUST change the digest
    (base / "check.sh").write_text("#!/usr/bin/env bash\necho ok\n")  # restore
    check("restore returns to original digest (python)", digestlib.directory_digest(base) == d1)
    check("restore returns to original digest (bash)", bash_dir_digest(base) == d1)
    (base / "extra.md").write_text("new\n")
    check("adding a tracked file flips the digest (python)", digestlib.directory_digest(base) != d1)
    check("adding a tracked file flips the digest (bash)", bash_dir_digest(base) != d1)

    # missing directory → empty
    check("missing dir digests to empty string (python)", digestlib.directory_digest(Path(tmp) / "nope") == "")
    check("missing dir digests to empty string (bash)", bash_dir_digest(Path(tmp) / "nope") == "")

    # EXCLUDED_DIRS names are still literally present in the bash routine —
    # cheap guard against one of the three exclusions silently disappearing
    # from lib/digest.sh (there is no shared constant to import across
    # languages, so this is a textual sanity check, not a parity assertion).
    digest_sh_src = DIGEST_SH.read_text()
    check(
        "EXCLUDED_DIRS names present in digest.sh's exclusion filter",
        all(name in digest_sh_src for name in digestlib.EXCLUDED_DIRS),
    )

# managed_digests block round-trip. `directive.parse_managed_digests` is gone
# (issue #355 moved the directive off python) — the real consumer of the
# written block is now check.sh's own awk parser, exercised end-to-end by
# `packs/foundation/directives/managed-tree-integrity/evals/test.sh`. Here we
# only need to confirm the WRITER (digestlib.write_managed_digests_block, the
# apply engines' side of the contract) round-trips faithfully, so this test
# carries a tiny local reader — a stand-in for "a human/awk can read this
# block back", not a copy of check.sh's parser.
def _parse_managed_digests_for_test(path: Path):
    text = path.read_text()
    out = {}
    in_block = False
    for raw in text.splitlines():
        if raw.startswith("managed_digests:"):
            rest = raw.split(":", 1)[1].strip()
            in_block = rest != "{}"
            continue
        if in_block:
            if raw.startswith("  ") and not raw.lstrip().startswith("#"):
                k, _, v = raw.strip().partition(":")
                if k:
                    out[k.strip()] = v.strip()
                continue
            if raw and not raw.startswith(" "):
                in_block = False
    return out


with tempfile.TemporaryDirectory() as tmp:
    manifest = Path(tmp) / "install.yaml"
    manifest.write_text('version: "3"\nkit_version: "0.7.2"\ncollisions: []\n')
    digestlib.write_managed_digests_block(manifest, {".governance/lib.sh": "abc", ".governance/run.sh": "def"})
    parsed = _parse_managed_digests_for_test(manifest)
    check("manifest managed_digests round-trips through writer+reader",
          parsed == {".governance/lib.sh": "abc", ".governance/run.sh": "def"})
    # rewrite replaces (not appends) the block
    digestlib.write_managed_digests_block(manifest, {".governance/lib.sh": "zzz"})
    parsed = _parse_managed_digests_for_test(manifest)
    check("rewrite replaces the block", parsed == {".governance/lib.sh": "zzz"})
    check("other manifest keys survive the rewrite", 'kit_version: "0.7.2"' in manifest.read_text())
    # empty mapping → managed_digests: {}
    digestlib.write_managed_digests_block(manifest, {})
    check("empty mapping emits {} and reads back as {}", _parse_managed_digests_for_test(manifest) == {})
    check("empty mapping literal is present", re.search(r"(?m)^managed_digests:\s*\{\}\s*$", manifest.read_text()) is not None)

print()
if failed:
    print(f"✗ test-digestlib: {failed} failed, {passed} passed", file=sys.stderr)
    sys.exit(1)
print(f"✓ test-digestlib: {passed} assertions passed")
