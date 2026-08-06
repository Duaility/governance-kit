"""Content digests for the managed governance tree (issue #253).

The single source of truth for how `managed-tree-integrity` and every apply
engine hash a managed unit. The apply verbs record these digests at
materialization time (per-directive in `packs.lock`, per-runtime-file in
`install.yaml`); the directive recomputes them on disk and compares. This is
what lets integrity be verified OFFLINE in any consumer repo — no upstream pack
git objects required, unlike the dogfood-only `git show <sha>:<path>` check.

The directive ships a byte-identical copy of `file_digest` / `directory_digest`
in its own `lib/` (it cannot import from the kit cache at hook time); a parity
test (`scripts/test-digestlib.py`) pins the two together.

Reproducibility rules (must match the directive's copy exactly):
  * hash RAW BYTES, never decoded text — no newline/encoding normalization;
  * a directory digest folds in (relpath, file-digest) pairs in sorted relpath
    order, so it is stable regardless of filesystem walk order;
  * exclude `evals/`, `install-assets/` (never materialized into the consumed
    tree), and `__pycache__/` + `*.pyc` (runtime droppings, never committed).
"""
from __future__ import annotations

import hashlib
import re
from pathlib import Path

# Directory names excluded from every digest. `evals`/`install-assets` are
# excluded by `install.sh:copy_tree_without_evals` at materialization; listing
# them here too keeps the recompute identical even if a stray copy appears.
EXCLUDED_DIRS = ("evals", "install-assets", "__pycache__")


def file_digest(path: str | Path) -> str:
    """sha256 hexdigest of a single file's raw bytes."""
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def _managed_rel_files(directory: Path):
    """Yield (posix-relpath, abspath) of files under `directory` that count
    toward its digest, in sorted relpath order. Excludes EXCLUDED_DIRS and
    `*.pyc`."""
    pairs = []
    for p in directory.rglob("*"):
        if not p.is_file():
            continue
        rel = p.relative_to(directory)
        if any(part in EXCLUDED_DIRS for part in rel.parts):
            continue
        if p.suffix == ".pyc":
            continue
        pairs.append((rel.as_posix(), p))
    pairs.sort(key=lambda t: t[0])
    return pairs


def directory_digest(directory: str | Path) -> str:
    """sha256 over a directory's files: for each (relpath, file) in sorted
    relpath order, fold `relpath\\0filedigest\\n` into one running hash.
    Returns "" for a missing/empty directory."""
    directory = Path(directory)
    if not directory.is_dir():
        return ""
    h = hashlib.sha256()
    any_file = False
    for rel, p in _managed_rel_files(directory):
        any_file = True
        h.update(rel.encode("utf-8"))
        h.update(b"\0")
        h.update(file_digest(p).encode("ascii"))
        h.update(b"\n")
    return h.hexdigest() if any_file else ""


def directive_digests(pack_dest: str | Path, directive_ids) -> dict[str, str]:
    """Map each directive id to the digest of its materialized folder under a
    consumed pack root (`.governance/packs/<owner>/<pack>`)."""
    pack_dest = Path(pack_dest)
    out: dict[str, str] = {}
    for did in directive_ids:
        d = directory_digest(pack_dest / "directives" / did)
        if d:
            out[did] = d
    return out


# ── kit-runtime managed files ───────────────────────────────────────────────
# The individually-managed runtime files (the kit axis), enumerated from the
# install manifest so init and kit-update record the SAME set — a mismatch
# would make the directive false-positive after an update. Read with the tiny
# stdlib scalar reader below (manifests are emitted by write_installed_manifest,
# not arbitrary YAML).

def _manifest_scalar(manifest_text: str, key: str) -> str:
    m = re.search(rf"(?m)^{re.escape(key)}:[ \t]*['\"]?([^'\"#\s]*)['\"]?", manifest_text)
    return m.group(1) if m else ""


def _schedule_managed_files(root: Path) -> list[str]:
    """Scheduled-lane generated workflow relpaths (issue #259, and the
    scheduled-triggers redesign that retired the sweep lane).

    Unlike the retired sweep lane's fixed asset pair (one workflow + one
    driver, both seeded the moment a live-sweep directive was installed),
    every scheduled lane is a consumer-authored artifact created explicitly
    via `governance schedule` (`schedulelib.apply`) — there is no fixed set
    to source from a static map. Each lane emits its own
    `.github/workflows/governance-schedule-<lane>.yml`, so this simply globs
    what's actually on disk. `schedule.sh` itself (the at-rest engine,
    replacing `.governance/sweep.sh`) needs no special case any more — it now
    lives in `<tests_dir>/schedule.sh`, next to run.sh/lib.sh, and is added to
    the static candidates list in `managed_runtime_files` below instead."""
    workflows_dir = Path(root) / ".github" / "workflows"
    if not workflows_dir.is_dir():
        return []
    return sorted(
        f".github/workflows/{p.name}"
        for p in workflows_dir.glob("governance-schedule-*.yml")
        if p.is_file()
    )


def managed_runtime_files(root: str | Path) -> list[str]:
    """Repo-relative paths of the kit-managed runtime files that exist on disk,
    derived from `.governance/install.yaml` (plus `schedule.sh` and any
    generated schedule-lane workflows). Order-stable (sorted).

    Scope = the **trust-chain** artifacts CI actually executes: `run.sh`,
    `lib.sh`, `schedule.sh`, the CI workflow, and every generated
    `governance-schedule-<lane>.yml`. Deliberately *excluded* (issue #267):

      * the `.githooks/*` (or `.husky/` / `.governance/hooks/`) dispatchers —
        local-only convenience plumbing. CI enforcement (`bash .governance/run.sh`)
        never touches `core.hooksPath`, so gutting a dispatcher changes nothing
        CI enforces; `SKIP_GOVERNANCE=1` / `--no-verify` make them intentionally
        bypassable; and they are regenerated from `(kit, install set, strategy)`.
        Digesting them buys near-zero protection and broke the **Wrap**
        hook-collision flow (the agent appends `exec <kind>.userhook` after the
        digest is recorded, and the `<kind>.userhook` itself got swept in and
        locked — both fixed by not recording them here).
      * `enable-governance.sh` — de-vendored entirely; the install verb sets
        `core.hooksPath` itself (the kit-less fallback is a documented one-liner).
    """
    root = Path(root)
    manifest = root / ".governance" / "install.yaml"
    if not manifest.is_file():
        return []
    text = manifest.read_text()
    tests_dir = _manifest_scalar(text, "tests_dir") or ".governance"
    candidates = [f"{tests_dir}/run.sh", f"{tests_dir}/lib.sh", f"{tests_dir}/schedule.sh"]
    ci = _manifest_scalar(text, "ci_workflow")
    if ci:
        candidates.append(ci)
    # Scheduled-lane generated workflows (issue #259) — one per lane created via
    # `governance schedule`; enumerated straight from disk (see
    # `_schedule_managed_files`), so absent when no lane has been created.
    candidates.extend(_schedule_managed_files(root))
    # Only digest what actually exists; dedupe; sort for stability.
    present = sorted({c for c in candidates if (root / c).is_file()})
    return present


def managed_digests(root: str | Path) -> dict[str, str]:
    """Map each managed runtime relpath to its file digest."""
    root = Path(root)
    return {rel: file_digest(root / rel) for rel in managed_runtime_files(root)}


# ── manifest block I/O (install.yaml) ───────────────────────────────────────
# The manifest is emitted by write_installed_manifest (bash). Rather than thread
# a digest map through bash, the engines write the `managed_digests:` block
# in-place here, the same line-surgery approach as kitapply's kit_version edit.

_BLOCK_KEY = "managed_digests"


def write_managed_digests_block(manifest_path: str | Path, mapping: dict[str, str]) -> None:
    """Replace (or append) the `managed_digests:` block in install.yaml with
    `mapping`. A two-space-indented block of `  <relpath>: <sha>` rows, keys
    sorted. An empty mapping emits `managed_digests: {}`."""
    manifest_path = Path(manifest_path)
    text = manifest_path.read_text()
    lines = text.splitlines(keepends=True)

    # Drop any existing block: the `managed_digests:` line plus its indented body.
    out: list[str] = []
    i = 0
    n = len(lines)
    while i < n:
        if re.match(rf"^{_BLOCK_KEY}:", lines[i]):
            i += 1
            while i < n and re.match(r"^[ \t]+\S", lines[i]):
                i += 1
            continue
        out.append(lines[i])
        i += 1

    if out and not out[-1].endswith("\n"):
        out[-1] += "\n"

    if mapping:
        out.append(f"{_BLOCK_KEY}:\n")
        for rel in sorted(mapping):
            out.append(f"  {rel}: {mapping[rel]}\n")
    else:
        out.append(f"{_BLOCK_KEY}: {{}}\n")

    manifest_path.write_text("".join(out))
