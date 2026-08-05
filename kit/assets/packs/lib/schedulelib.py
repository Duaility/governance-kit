#!/usr/bin/env python3
"""`governance schedule` — plan/apply engine for the scheduled lane (replaces
the retired sweep lane; see kit/references/SCHEDULE_FLOW.md).

A schedule lane is a consumer-authored artifact: one generated GitHub
workflow (`.github/workflows/governance-schedule-<lane>.yml`) that invokes
`bash .governance/run.sh --scheduled` over a named list of member
directives, on its own cron. The workflow IS the config — nothing
coordinates lanes beyond each carrying its own file, and there is no
kit-owned default lane. `governance schedule` is the single writer of that
file: `plan()` is a side-effect-free computation (same JSON-on-stdout shape
as packplan.py's `pack-plan`), `apply()` recomputes the plan and executes it,
and `remove()` deletes a lane and its ledger rows.

Membership resolution mirrors run.sh's own filter (bare `<id>` hits every
homonym across installed packs, `<owner>/<pack>/<id>` matches exactly one) so
authoring a lane and running it never disagree about who a token names. A
member is only accepted once it is *schedule-eligible* — its effective
`triggers` (the consumer's `.governance/conf/<owner>/<pack>/<id>.conf`
`TRIGGERS=` overlay row, else its `directive.yaml` `triggers:` list, else the
derived `[<hook>]`/`[]`) contains `schedule`. Eligibility is authored once per
directive; a lane's *membership* is still an explicit, per-lane choice.

Run via:
    python3 kit/assets/packs/lib/packverb.py schedule-plan <root> <lane> \\
        --cron '<cron>' --member <id> [--member <id> ...] \\
        [--evidence range|commits] [--budget N]
    python3 kit/assets/packs/lib/packverb.py schedule-apply <root> <lane> ... [--dry-run]
    python3 kit/assets/packs/lib/packverb.py schedule-remove <root> <lane>
"""

from __future__ import annotations

import argparse
import json
import re
import shlex
import sys
from pathlib import Path
from typing import Any

import digestlib
import kityaml
from applylib import KIT_ASSETS, append_install_assets_seeded, remove_install_assets_seeded
from kitverb import stamped_text
from packctl import KIT_VERSION

TEMPLATE_PATH = KIT_ASSETS / "governance-schedule.template.yml"

_LANE_RE = re.compile(r"^[a-z0-9-]+$")
_EVIDENCE_VALUES = {"range", "commits"}
DEFAULT_BUDGET = 20

# The bespoke overlay reader for the `TRIGGERS=` row (scheduled-lane redesign,
# issue: scheduled triggers). Mirrors lib.sh's `_directive_triggers_resolve`
# bash helper (which this module cannot call — no bash at plan time) against
# the same tiny conf-file grammar every overlay uses: `KEY=value` scalar
# rows, `#` comments, blank lines ignored (see lib.sh's conf-file format
# doc). Deliberately NOT layered on packctl/kityaml's YAML reader — the
# overlay is not YAML.
_TRIGGERS_ROW_RE = re.compile(r"^TRIGGERS=(.*)$")


def _overlay_triggers_row(root: Path, owner: str, pack: str, directive_id: str) -> str | None:
    """The raw value of the first `TRIGGERS=` row in the directive's user
    overlay conf, or None when the overlay (or the row) is absent."""
    conf_path = root / ".governance" / "conf" / owner / pack / f"{directive_id}.conf"
    if not conf_path.is_file():
        return None
    for raw in conf_path.read_text().splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        m = _TRIGGERS_ROW_RE.match(line)
        if m:
            return m.group(1).strip()
    return None


def effective_triggers(
    root: Path, owner: str, pack: str, directive_id: str,
    yaml_triggers: list[str] | None, hook: str,
) -> list[str]:
    """A directive's effective triggers list — overlay `TRIGGERS=` row (even
    an empty one, which yields `[]`, replaces the author's list) else the
    `directive.yaml` `triggers:` list else the derived `[<hook>]` (or `[]`
    when `hook: none`). Matches the precedence SCHEDULE_FLOW.md documents."""
    overlay = _overlay_triggers_row(root, owner, pack, directive_id)
    if overlay is not None:
        return [t.strip() for t in overlay.split(",") if t.strip()]
    if yaml_triggers:
        return list(yaml_triggers)
    return [] if hook == "none" else [hook]


def _installed_directives(root: Path) -> list[dict[str, Any]]:
    """Every installed directive under `.governance/packs/<owner>/<pack>/
    directives/<id>/directive.yaml`, as the fields member resolution needs."""
    packs_dir = root / ".governance" / "packs"
    out: list[dict[str, Any]] = []
    if not packs_dir.is_dir():
        return out
    for yaml_path in sorted(packs_dir.glob("*/*/directives/*/directive.yaml")):
        directive_id = yaml_path.parent.name
        pack = yaml_path.parents[2].name
        owner = yaml_path.parents[3].name
        manifest = kityaml.load(yaml_path) or {}
        hook = str(manifest.get("hook") or "none")
        triggers = manifest.get("triggers")
        out.append({
            "owner": owner,
            "pack": pack,
            "id": directive_id,
            "full_id": f"{owner}/{pack}/{directive_id}",
            "hook": hook,
            "triggers_yaml": triggers if isinstance(triggers, list) else None,
        })
    return out


def _resolve_member(token: str, installed: list[dict[str, Any]]) -> tuple[list[dict[str, Any]], list[str]]:
    """Resolve one member token to the installed directive(s) it names, same
    matching rules as run.sh's filter: a pack-qualified `<owner>/<pack>/<id>`
    token matches exactly one directive; a bare `<id>` matches every homonym
    across installed packs (all of them become members). Returns
    `(matches, errors)` — an unmatched token is always an error (config bug,
    fail loud), never a silent no-op."""
    if token.count("/") >= 2:
        matches = [d for d in installed if d["full_id"] == token]
        if not matches:
            return [], [f"schedule: no directive matching {token!r} (pack-qualified id) under .governance/packs"]
        return matches, []
    matches = [d for d in installed if d["id"] == token]
    if not matches:
        return [], [f"schedule: no directive matching {token!r} under .governance/packs"]
    return matches, []


def _render(template_text: str, *, lane: str, cron: str, members: list[str], evidence: str, budget: int) -> str:
    members_str = " ".join(shlex.quote(m) for m in members)
    text = template_text
    for placeholder, value in (
        ("__LANE__", lane),
        ("__CRON__", cron),
        ("__MEMBERS__", members_str),
        ("__EVIDENCE__", evidence),
        ("__BUDGET__", str(budget)),
    ):
        text = text.replace(placeholder, value)
    return text


def plan(
    root: Path, lane: str, cron: str, members: list[str],
    evidence: str = "range", budget: int | None = None,
) -> dict[str, Any]:
    """The full `schedule-plan` resolution as a side-effect-free computation
    (network-free, unlike pack-plan's `add`/`update` — everything here reads
    only the local `.governance/` tree). Shared by `schedule-plan` (prints it)
    and `schedule-apply` (recomputes at execution time). Never raises for a
    bad input — every problem lands in the `errors` list so a caller can
    surface the whole picture at once, the way an author iterating on a new
    lane wants to see it."""
    errors: list[str] = []

    if not lane or not _LANE_RE.match(lane):
        errors.append(f"schedule: lane {lane!r} must be non-empty and match [a-z0-9-]+")
    if not cron or not cron.strip():
        errors.append("schedule: --cron is required and must be non-empty")
    if evidence not in _EVIDENCE_VALUES:
        errors.append(f"schedule: --evidence must be one of {sorted(_EVIDENCE_VALUES)}, got {evidence!r}")
    if not members:
        errors.append("schedule: at least one --member is required")

    resolved_budget = DEFAULT_BUDGET if budget is None else budget
    if not isinstance(resolved_budget, int) or resolved_budget <= 0:
        errors.append(f"schedule: --budget must be a positive integer, got {resolved_budget!r}")

    installed = _installed_directives(root)
    deduped_members = list(dict.fromkeys(members))
    resolved_members: list[dict[str, Any]] = []
    for token in deduped_members:
        matches, member_errors = _resolve_member(token, installed)
        errors.extend(member_errors)
        for d in matches:
            triggers = effective_triggers(root, d["owner"], d["pack"], d["id"], d["triggers_yaml"], d["hook"])
            eligible = "schedule" in triggers
            if not eligible:
                errors.append(
                    f"schedule: {d['full_id']} is not schedule-eligible (effective triggers "
                    f"{triggers!r} do not include 'schedule' — add `schedule` to its "
                    f"directive.yaml `triggers:` list, or set an overlay override at "
                    f".governance/conf/{d['owner']}/{d['pack']}/{d['id']}.conf with a "
                    "`TRIGGERS=` row that includes it)"
                )
            resolved_members.append({
                "input": token,
                "id": d["full_id"],
                "hook": d["hook"],
                "effective_triggers": triggers,
                "eligible": eligible,
            })

    target_rel = f".github/workflows/governance-schedule-{lane}.yml"
    target_path = root / target_rel
    result: dict[str, Any] = {
        "lane": lane,
        "cron": cron,
        "evidence": evidence,
        "budget": resolved_budget,
        "members": deduped_members,
        "resolved_members": resolved_members,
        "target": target_rel,
        "exists": target_path.is_file(),
        "errors": errors,
    }
    if not errors:
        stamped = stamped_text(TEMPLATE_PATH, KIT_VERSION)
        result["preview"] = _render(
            stamped, lane=lane, cron=cron, members=deduped_members,
            evidence=evidence, budget=resolved_budget,
        )
    return result


def apply(
    root: Path, lane: str, cron: str, members: list[str],
    evidence: str = "range", budget: int | None = None, dry_run: bool = False,
) -> dict[str, Any]:
    """Recompute the plan and execute it. Idempotent: identical inputs render
    a byte-identical file (the template + `stamped_text`'s deterministic
    marker rewrite carry no wall-clock content), so a re-run over an
    unchanged lane reports `changed: false`. Refuses (never writes) when the
    plan carries any error — an unknown or ineligible member, a malformed
    lane/cron/evidence/budget."""
    result = plan(root, lane, cron, members, evidence, budget)
    if result["errors"]:
        result["result"] = "refused"
        return result

    target_rel = result["target"]
    target_path = root / target_rel
    new_text = result["preview"]
    changed = not target_path.is_file() or target_path.read_bytes() != new_text.encode("utf-8")

    if dry_run:
        result["result"] = "dry-run"
        result["changed"] = changed
        return result

    target_path.parent.mkdir(parents=True, exist_ok=True)
    target_path.write_text(new_text)

    manifest_path = root / ".governance" / "install.yaml"
    append_install_assets_seeded(manifest_path, [target_rel])
    if manifest_path.is_file():
        digestlib.write_managed_digests_block(manifest_path, digestlib.managed_digests(root))

    result["result"] = "applied"
    result["changed"] = changed
    return result


def remove(root: Path, lane: str) -> dict[str, Any]:
    """Delete a lane's generated workflow, drop its `install_assets_seeded`
    row, and re-digest. A missing file is reported, not an error — removing
    an already-absent lane is a no-op, matching every other apply engine's
    idempotence story."""
    target_rel = f".github/workflows/governance-schedule-{lane}.yml"
    target_path = root / target_rel
    result: dict[str, Any] = {"lane": lane, "target": target_rel}
    if not target_path.is_file():
        result["result"] = "absent"
        return result

    target_path.unlink()
    manifest_path = root / ".governance" / "install.yaml"
    remove_install_assets_seeded(manifest_path, [target_rel])
    if manifest_path.is_file():
        digestlib.write_managed_digests_block(manifest_path, digestlib.managed_digests(root))

    result["result"] = "removed"
    return result


def cmd_schedule_plan(args: argparse.Namespace) -> int:
    root = Path(args.root).resolve()
    result = plan(root, args.lane, args.cron, args.member, args.evidence, args.budget)
    print(json.dumps(result, indent=2))
    return 0 if not result["errors"] else 1


def cmd_schedule_apply(args: argparse.Namespace) -> int:
    root = Path(args.root).resolve()
    result = apply(root, args.lane, args.cron, args.member, args.evidence, args.budget, args.dry_run)
    print(json.dumps(result, indent=2))
    return 2 if result.get("result") == "refused" else 0


def cmd_schedule_remove(args: argparse.Namespace) -> int:
    root = Path(args.root).resolve()
    result = remove(root, args.lane)
    print(json.dumps(result, indent=2))
    return 0


def register_schedule(sub) -> None:
    """Register the schedule-* subcommands on an argparse subparsers object.

    Called by packverb.py's main() (the packverb surface is what the flow docs
    invoke) and by this module's own main() for standalone use — one
    registration, two entry points, no drift.
    """

    def _add_common(p: argparse.ArgumentParser) -> None:
        p.add_argument("root")
        p.add_argument("lane")
        p.add_argument("--cron", required=True)
        p.add_argument("--member", action="append", dest="member", default=[])
        p.add_argument("--evidence", default="range", choices=sorted(_EVIDENCE_VALUES))
        p.add_argument("--budget", type=int, default=None)

    p = sub.add_parser("schedule-plan")
    _add_common(p)
    p.set_defaults(func=cmd_schedule_plan)

    p = sub.add_parser("schedule-apply")
    _add_common(p)
    p.add_argument("--dry-run", action="store_true")
    p.set_defaults(func=cmd_schedule_apply)

    p = sub.add_parser("schedule-remove")
    p.add_argument("root")
    p.add_argument("lane")
    p.set_defaults(func=cmd_schedule_remove)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="cmd", required=True)
    register_schedule(sub)
    args = parser.parse_args(argv)
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
