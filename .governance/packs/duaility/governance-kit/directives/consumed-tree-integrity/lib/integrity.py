#!/usr/bin/env python3
"""consumed-tree-integrity (dogfood) — prove the vendored consumed tree is an
honest materialization of the pins in `.governance/packs.lock`.

This repo dogfoods its own product: `.governance/` is meant to be exactly what
`governance install` produces for a consumer pinned at real release tags. The
historical failure mode (#200) was a hand-maintained consumed tree whose lock
pinned a *fictional* sha — paths the consumed tree used did not exist at the
pinned commit, and the hand-synced copy silently drifted from `packs/`. A trust
tool whose own lock file lies is self-refuting, so this check makes the fiction
mechanically impossible to commit.

For every `source: gh` pack entry in the lock it asserts:

  1. The pinned `sha` is a real commit object in *this* repo's history. (The
     dogfood pins point at `gh:duaility/governance-kit`, i.e. this same repo, so
     the commit is always available offline — no fetch needed in the hook/CI.)
  2. The `ref`'s `@<rev>` is a real tag that resolves to that exact `sha`.
     Honest pins reference released tags, never a moving branch like `@main`.
  3. The claimed `subpath/pack.yaml` exists at that sha.
  4. Each vendored directive folder byte-matches what the product's
     `copy_tree_without_evals` would materialize from the pin (the directive
     subtree at the sha, minus the `evals/` and `install-assets/` subfolders).
  5. The set of vendored directives equals the lock's directive list — no orphan
     folders, none missing.

`source: local` packs (this repo's own `duaility/governance-kit` dogfood) have
no upstream to compare against; for them it only asserts the vendored directive
folders match the lock's directive list.

It also asserts every vendored pack under `.governance/packs/` has a lock entry,
so a hand-added pack folder with no pin cannot hide.

Violations are printed one-per-line to stdout; the script always exits 0 unless
it hits an internal error (then it exits non-zero with a traceback on stderr and
check.sh reports the crash). Stdlib only — the repo's python carries no `yaml`.
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

# Subfolders the product never vendors into a consumer repo. Mirrors
# kit/assets/packs/lib/install.sh:copy_tree_without_evals — keep in lockstep.
EXCLUDED_TOP = ("evals", "install-assets")


def git(root: Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["git", *args],
        cwd=str(root),
        capture_output=True,
    )


def strip_val(s: str) -> str:
    s = s.strip()
    if len(s) >= 2 and s[0] in "\"'" and s[-1] == s[0]:
        s = s[1:-1]
    return s


def parse_lock(text: str) -> list[dict]:
    """Parse the `packs:` list out of a packs.lock written by
    `yaml.safe_dump(sort_keys=False, default_flow_style=False)`. The layout is
    regular: list items start with `- id: …` at column 0, scalar fields are at
    a 2-space indent, and the `directives:` block is a 2-space-indented dash
    list. We only need the fields below, so a minimal indentation-aware parser
    beats pulling in a YAML dependency the repo's python doesn't ship."""
    packs: list[dict] = []
    cur: dict | None = None
    in_directives = False
    for raw in text.splitlines():
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        if raw.startswith("- id:"):
            cur = {"id": strip_val(raw[len("- id:"):]), "directives": []}
            packs.append(cur)
            in_directives = False
            continue
        if raw.startswith("  ") and cur is not None:
            body = raw[2:]
            if body.startswith("- "):
                if in_directives:
                    cur["directives"].append(strip_val(body[2:]))
                continue
            m = re.match(r"([A-Za-z_]+):\s*(.*)$", body)
            if m:
                key, val = m.group(1), m.group(2)
                if key == "directives":
                    in_directives = True
                else:
                    in_directives = False
                    cur[key] = strip_val(val)
            continue
        # Any column-0 line that isn't a list item (e.g. `version:`, `packs:`)
        # ends the current item's context.
        in_directives = False
    return packs


def ref_rev(ref: str) -> str:
    """The `@<rev>` of a `gh:owner/repo[/subpath]@rev` ref, or '' if none."""
    return ref.rsplit("@", 1)[1] if "@" in ref else ""


def materialized_files(root: Path, sha: str, src_prefix: str) -> list[str] | None:
    """Tracked file paths under `src_prefix` at `sha`, excluding the top-level
    evals/ and install-assets/ subfolders. Returns repo-relative paths, or None
    if the prefix doesn't exist at the sha."""
    r = git(root, "ls-tree", "-r", "--name-only", "-z", sha, "--", src_prefix + "/")
    if r.returncode != 0:
        return None
    out = r.stdout.decode("utf-8", "surrogateescape")
    paths = [p for p in out.split("\0") if p]
    kept = []
    for p in paths:
        rel = p[len(src_prefix) + 1:]
        top = rel.split("/", 1)[0]
        if top in EXCLUDED_TOP:
            continue
        kept.append(p)
    return kept


def check_gh_pack(root: Path, pack: dict, violations: list[str]) -> None:
    pid = pack["id"]
    sha = pack.get("sha", "")
    ref = pack.get("ref", "")
    subpath = pack.get("subpath", "")
    lock_directives = sorted(pack.get("directives", []))

    if not sha:
        violations.append(f"{pid}: source is gh but the lock has no sha pin")
        return
    if not subpath:
        violations.append(f"{pid}: source is gh but the lock has no subpath")
        return

    # 1. The pinned sha is a real commit in this repo.
    t = git(root, "cat-file", "-t", sha)
    if t.returncode != 0 or t.stdout.decode().strip() != "commit":
        violations.append(
            f"{pid}: pinned sha {sha[:12]} is not a commit in this repo's history "
            f"— the pin is fictional (no fetch can fix this; it must point at a real release commit)"
        )
        return

    # 2. The ref's @rev is a real tag resolving to that sha.
    rev = ref_rev(ref)
    if not rev:
        violations.append(f"{pid}: ref {ref!r} has no @<rev> — honest pins reference a released tag")
    else:
        rp = git(root, "rev-parse", "--verify", "--quiet", f"refs/tags/{rev}^{{commit}}")
        if rp.returncode != 0:
            violations.append(
                f"{pid}: ref pins @{rev}, which is not a tag in this repo "
                f"— honest pins must reference a released tag, not a branch or bare sha"
            )
        elif rp.stdout.decode().strip() != sha:
            violations.append(
                f"{pid}: tag {rev} resolves to {rp.stdout.decode().strip()[:12]}, "
                f"but the lock pins sha {sha[:12]} — the pin and its tag disagree"
            )

    # 3. The claimed subpath exists at the sha.
    e = git(root, "cat-file", "-e", f"{sha}:{subpath}/pack.yaml")
    if e.returncode != 0:
        violations.append(
            f"{pid}: subpath {subpath!r} has no pack.yaml at sha {sha[:12]} "
            f"— the claimed pack does not exist at the pinned commit"
        )
        return

    # 4 + 5. Per-directive byte-match and directive-set agreement.
    vendored_dir = root / ".governance" / "packs" / pid / "directives"
    vendored_present = (
        sorted(p.name for p in vendored_dir.iterdir() if p.is_dir())
        if vendored_dir.is_dir()
        else []
    )
    if vendored_present != lock_directives:
        only_lock = sorted(set(lock_directives) - set(vendored_present))
        only_tree = sorted(set(vendored_present) - set(lock_directives))
        if only_lock:
            violations.append(f"{pid}: directives in lock but not vendored: {', '.join(only_lock)}")
        if only_tree:
            violations.append(f"{pid}: directives vendored but not in lock: {', '.join(only_tree)}")

    for did in lock_directives:
        src_prefix = f"{subpath}/directives/{did}"
        files = materialized_files(root, sha, src_prefix)
        if files is None or not files:
            violations.append(
                f"{pid}/{did}: directive folder {src_prefix} does not exist at sha {sha[:12]}"
            )
            continue
        dest_root = root / ".governance" / "packs" / pid / "directives" / did
        expected_rel: set[str] = set()
        for f in files:
            rel = f[len(src_prefix) + 1:]
            expected_rel.add(rel)
            blob = git(root, "show", f"{sha}:{f}")
            if blob.returncode != 0:
                violations.append(f"{pid}/{did}: cannot read {f} at sha {sha[:12]}")
                continue
            dest = dest_root / rel
            if not dest.is_file():
                violations.append(f"{pid}/{did}: vendored tree is missing {rel} (present at the pin)")
                continue
            if dest.read_bytes() != blob.stdout:
                violations.append(
                    f"{pid}/{did}: vendored {rel} does not byte-match the pin "
                    f"— the consumed tree was hand-edited or is stale (regenerate with `governance pack update`)"
                )
        # Extra files in the vendored tree that the pin would not materialize.
        # Only git-tracked files count: the consumed tree is committed, so its
        # integrity is about committed content, not gitignored runtime artifacts
        # (e.g. __pycache__/*.pyc dropped when a directive's lib/ runs).
        if dest_root.is_dir():
            rel_prefix = str(dest_root.relative_to(root))
            tracked = git(root, "ls-files", "-z", "--", rel_prefix)
            for f in tracked.stdout.decode("utf-8", "surrogateescape").split("\0"):
                if not f:
                    continue
                rel = f[len(rel_prefix) + 1:]
                if rel not in expected_rel:
                    violations.append(
                        f"{pid}/{did}: vendored tree has {rel}, which the pin does not materialize "
                        f"— remove it or re-pin"
                    )


def check_local_pack(root: Path, pack: dict, violations: list[str]) -> None:
    pid = pack["id"]
    lock_directives = sorted(pack.get("directives", []))
    vendored_dir = root / ".governance" / "packs" / pid / "directives"
    vendored_present = (
        sorted(p.name for p in vendored_dir.iterdir() if p.is_dir())
        if vendored_dir.is_dir()
        else []
    )
    if vendored_present != lock_directives:
        only_lock = sorted(set(lock_directives) - set(vendored_present))
        only_tree = sorted(set(vendored_present) - set(lock_directives))
        if only_lock:
            violations.append(f"{pid}: directives in lock but not present: {', '.join(only_lock)}")
        if only_tree:
            violations.append(f"{pid}: directive folders present but not in lock: {', '.join(only_tree)}")


def vendored_pack_ids(root: Path) -> list[str]:
    """Every `<owner>/<name>` under `.governance/packs/` that holds a
    `directives/` folder — the shape a materialized pack takes on disk."""
    base = root / ".governance" / "packs"
    found = []
    if not base.is_dir():
        return found
    for owner in sorted(p for p in base.iterdir() if p.is_dir()):
        for name in sorted(p for p in owner.iterdir() if p.is_dir()):
            if (name / "directives").is_dir():
                found.append(f"{owner.name}/{name.name}")
    return found


def main() -> int:
    root = Path(
        subprocess.run(
            ["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True
        ).stdout.strip()
    )
    lock_path = root / ".governance" / "packs.lock"
    violations: list[str] = []

    if not lock_path.is_file():
        print(".governance/packs.lock is missing")
        return 0

    packs = parse_lock(lock_path.read_text())
    lock_ids = {p["id"] for p in packs}

    for pack in packs:
        source = pack.get("source", "")
        if source == "gh":
            check_gh_pack(root, pack, violations)
        elif source == "local":
            check_local_pack(root, pack, violations)
        else:
            violations.append(f"{pack['id']}: unknown source {source!r} (expected 'gh' or 'local')")

    for vid in vendored_pack_ids(root):
        if vid not in lock_ids:
            violations.append(
                f"{vid}: vendored under .governance/packs/ but has no lock entry "
                f"— every consumed pack must be pinned"
            )

    for v in violations:
        print(v)
    return 0


if __name__ == "__main__":
    sys.exit(main())
