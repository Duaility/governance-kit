#!/usr/bin/env python3
"""Pure plan computation + CONSTITUTION assembly for `governance init` (#172).

`init` is the most interactive verb — pack/preset/directive selection, principle
inference, collision resolution, and the Step-8 finding loop are genuine
elicitation that stays with the operator. This module owns the *mechanical*
remainder: validating the resolved install set (no duplicate directive id across
packs — a flat namespace would silently overwrite) and assembling CONSTITUTION.md
from the template + operator principles + each directive's `constitution.md`
subsection. Both are pure string/structure transforms; `init-apply`
(initapply.py) owns the file I/O.

The plan consumes a `decisions` object the operator serialized (selected packs
with their final directive lists + source dirs, the inferred principles, the GH
identity). `init-plan` prints the resolved inventory for the diff-before-exec
step; `init-apply` recomputes it and writes.
"""

from __future__ import annotations

import argparse
import json
import re
from typing import Any

from packctl import scalar


def collisions(packs: list[dict[str, Any]]) -> list[str]:
    """Directive ids claimed by more than one pack — a flat-namespace overwrite."""
    seen: dict[str, str] = {}
    dupes: list[str] = []
    for pack in packs:
        for did in pack.get("directives") or []:
            if did in seen and seen[did] != pack["id"]:
                dupes.append(f"{did} (in {seen[did]} and {pack['id']})")
            seen[did] = pack["id"]
    return dupes


def directive_inventory(packs: list[dict[str, Any]]) -> list[dict[str, str]]:
    out: list[dict[str, str]] = []
    for pack in packs:
        pack_dir = pack.get("pack_dir", "")
        for did in sorted(pack.get("directives") or []):
            out.append({
                "id": did,
                "pack_id": pack["id"],
                "source": f"{pack_dir}/directives/{did}",
                "dest": f".governance/packs/{pack['id']}/directives/{did}",
                "subsection_source": f"{pack_dir}/directives/{did}/constitution.md",
            })
    return out


def assemble_constitution(
    template: str, principles: list[str], groups: list[tuple[str, list[str]]]
) -> str:
    """Template → CONSTITUTION.md: operator principles spliced into Principles,
    each directive's `constitution.md` spliced into Directives (replacing the
    example) and grouped under its `## <owner>/<pack>` header, the rest verbatim.

    `groups` is `[(pack_id, [subsection, …]), …]` in display order — the same
    pack-grouped shape the `pack add`/`update` upsert maintains, so a fresh
    install and an incrementally-grown CONSTITUTION.md share one structure.
    """
    from docsurgery import render_pack_groups

    lines = template.splitlines(keepends=True)

    def find(pat: str) -> int:
        idx = next((i for i, ln in enumerate(lines) if re.match(pat, ln)), None)
        if idx is None:
            raise ValueError(f"template missing heading {pat!r}")
        return idx

    directives_i = find(r"^##[ \t]+Directives[ \t]*$")
    amendment_i = find(r"^##[ \t]+Amendment process[ \t]*$")

    # Rebuild the Directives section body: heading + pack-grouped subsections.
    body = "## Directives\n\n" + render_pack_groups(groups)
    new_lines = lines[:directives_i] + [body] + lines[amendment_i:]

    text = "".join(new_lines)
    if principles:
        bullets = "".join(f"- {p.rstrip()}\n" for p in principles)
        # Insert operator principles right before the Directives heading.
        text = re.sub(r"(\n)(##[ \t]+Directives[ \t]*\n)",
                      rf"\1{bullets}\n\2", text, count=1)
    return text


def compute_init_plan(decisions: dict[str, Any]) -> dict[str, Any]:
    packs = decisions.get("packs") or []
    return {
        "owner": scalar(decisions.get("owner")),
        "repo": scalar(decisions.get("repo")),
        "hook_strategy": scalar(decisions.get("hook_strategy")) or "githooks",
        "collisions": collisions(packs),
        "directives": directive_inventory(packs),
        "principles": decisions.get("principles") or [],
    }


def cmd_init_plan(args: argparse.Namespace) -> int:
    from applylib import load_decisions

    try:
        decisions = load_decisions(args.decisions)
    except (ValueError, OSError, json.JSONDecodeError) as exc:
        print(json.dumps({"error": f"bad --decisions: {exc}"}, indent=2))
        return 1
    print(json.dumps(compute_init_plan(decisions), indent=2))
    return 0
