#!/usr/bin/env python3
"""`governance workflow generate` — reconcile the scheduled workflow.

Scheduling is directive-owned.  A directive opts into the scheduled lane with
the author-owned ``triggers:`` list and chooses its consumer cadence through a
typed ``SCHEDULE_CRON`` config entry.  The workflow is a compiled artifact:
one generated GitHub workflow contains every distinct cron and the directives
that should run for it.

The public verb is a single idempotent ``workflow generate`` operation.  The
engine is deliberately network-free and reads only the installed
``.governance`` tree.  A generated workflow is the only managed output; the
directive manifests and their overlays remain the source of truth.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shlex
import sys
from pathlib import Path
from typing import Any

import digestlib
import kityaml
from applylib import (
    KIT_ASSETS,
    append_install_assets_seeded,
    remove_install_assets_seeded,
)
from kitverb import stamped_text
from packctl import KIT_VERSION


TEMPLATE_PATH = KIT_ASSETS / "governance-schedule.template.yml"
WORKFLOW_REL = ".github/workflows/governance-schedule.yml"
_CRON_FIELDS = 5
_CRON_WHITESPACE_RE = re.compile(r"\s+")


def _overlay_scalar(root: Path, owner: str, pack: str, directive_id: str, key: str) -> str | None:
    conf_path = root / ".governance" / "conf" / owner / pack / f"{directive_id}.conf"
    if not conf_path.is_file():
        return None
    for raw in conf_path.read_text().splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line or not line.startswith(f"{key}="):
            continue
        return line.split("=", 1)[1].strip()
    return None


def effective_triggers(
    yaml_triggers: list[str] | None, hook: str,
) -> list[str]:
    """Resolve author-owned explicit triggers, retaining hook-only defaults."""
    if yaml_triggers:
        return list(yaml_triggers)
    return [] if hook == "none" else [hook]


def _config_entry(manifest: dict[str, Any], name: str) -> dict[str, Any] | None:
    config = manifest.get("config")
    if not isinstance(config, list):
        return None
    return next((e for e in config if isinstance(e, dict) and e.get("name") == name), None)


def _config_value(root: Path, directive: dict[str, Any], name: str) -> Any:
    entry = _config_entry(directive["manifest"], name)
    if not entry:
        return None
    if entry.get("tunable") is True and entry.get("type") == "scalar":
        override = _overlay_scalar(root, directive["owner"], directive["pack"], directive["id"], name)
        if override is not None:
            return override
    return entry.get("default")


def _normalize_cron(value: Any) -> str:
    if not isinstance(value, str):
        return ""
    return _CRON_WHITESPACE_RE.sub(" ", value.strip())


def _valid_cron(cron: str) -> bool:
    """Validate the portable shape GitHub Actions accepts without a cron parser."""
    return bool(cron) and "\n" not in cron and len(cron.split()) == _CRON_FIELDS


def _cron_lane(cron: str) -> str:
    """Stable internal state partition for one cadence."""
    digest = hashlib.sha256(cron.encode("utf-8")).hexdigest()[:12]
    return f"cron-{digest}"


def _yaml_quote(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def _installed_directives(root: Path) -> list[dict[str, Any]]:
    """Read every installed directive needed by workflow generation."""
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
            "surface": str(manifest.get("surface") or "repo-state"),
            "manifest": manifest,
        })
    return out


def _resolve_groups(root: Path) -> tuple[list[dict[str, Any]], list[str], list[str]]:
    """Return ``(groups, errors, warnings)`` in deterministic order."""
    grouped: dict[str, list[str]] = {}
    errors: list[str] = []
    warnings: list[str] = []

    for directive in _installed_directives(root):
        triggers = effective_triggers(directive["triggers_yaml"], directive["hook"])
        if "schedule" not in triggers:
            continue

        raw_cron = _config_value(root, directive, "SCHEDULE_CRON")
        cron = _normalize_cron(raw_cron)
        if not cron:
            warnings.append(
                f"workflow: {directive['full_id']} is schedule-eligible but has no SCHEDULE_CRON; it is not enrolled"
            )
            continue
        if not _valid_cron(cron):
            errors.append(
                f"workflow: {directive['full_id']} declares invalid SCHEDULE_CRON {cron!r}; "
                "expected five space-separated cron fields"
            )
            continue
        grouped.setdefault(cron, []).append(directive["full_id"])

    groups = [
        {
            "cron": cron,
            "lane": _cron_lane(cron),
            "members": sorted(set(members)),
        }
        for cron, members in sorted(grouped.items())
    ]
    return groups, errors, warnings


def _dispatch_script(groups: list[dict[str, Any]]) -> str:
    """Render the shell dispatcher embedded in the single workflow."""
    lines = [
        "          run_group() {",
        "            local lane=\"$1\"; shift",
        "            if [ -n \"${SCHEDULE_RANGE_INPUT:-}\" ]; then",
        "              bash .governance/run.sh --scheduled --lane \"$lane\" --range \"$SCHEDULE_RANGE_INPUT\" \"$@\"",
        "            else",
        "              bash .governance/run.sh --scheduled --lane \"$lane\" \"$@\"",
        "            fi",
        "          }",
        "",
        "          selector=\"${SCHEDULE_INPUT:-${SCHEDULE_EVENT:-}}\"",
        "          status=0",
        "          if [ -n \"$selector\" ]; then",
        "            case \"$selector\" in",
    ]
    for group in groups:
        args = " ".join(shlex.quote(value) for value in [group["lane"], *group["members"]])
        lines.extend([
            f"              {shlex.quote(group['cron'])})",
            f"                run_group {args} || status=1",
            "                ;;",
        ])
    lines.extend([
        "              *)",
        "                echo \"governance schedule: no generated cadence matches selector '$selector'\" >&2",
        "                exit 2",
        "                ;;",
        "            esac",
        "          else",
    ])
    for group in groups:
        args = " ".join(shlex.quote(value) for value in [group["lane"], *group["members"]])
        lines.extend([
            f"            run_group {args} || status=1",
        ])
    lines.extend([
        "          fi",
        "          exit \"$status\"",
    ])
    return "\n".join(lines)


def _render(template_text: str, groups: list[dict[str, Any]]) -> str:
    cron_entries = "\n".join(
        f"    - cron: {_yaml_quote(group['cron'])}" for group in groups
    )
    text = template_text.replace("__CRON_ENTRIES__", cron_entries)
    text = text.replace("__DISPATCH_SCRIPT__", _dispatch_script(groups))
    return text


def plan(root: Path) -> dict[str, Any]:
    """Compute the complete generated workflow without writing anything."""
    groups, errors, warnings = _resolve_groups(root)
    target_path = root / WORKFLOW_REL
    result: dict[str, Any] = {
        "target": WORKFLOW_REL,
        "exists": target_path.is_file(),
        "groups": groups,
        "errors": errors,
        "warnings": warnings,
    }
    if not errors and groups:
        result["preview"] = _render(stamped_text(TEMPLATE_PATH, KIT_VERSION), groups)
    return result


def _generated_paths(root: Path) -> list[Path]:
    workflows = root / ".github" / "workflows"
    if not workflows.is_dir():
        return []
    # The exact file is current; the prefixed files are legacy outputs from
    # the old schedule-lane command and are safe to reconcile away because the
    # governance schedule namespace is generated-only.
    paths = [p for p in workflows.glob("governance-schedule*.yml") if p.is_file()]
    return sorted(paths)


def apply(root: Path, *, dry_run: bool = False) -> dict[str, Any]:
    """Reconcile the one generated workflow and its install ledger."""
    result = plan(root)
    if result["errors"]:
        result["result"] = "refused"
        return result

    target_path = root / WORKFLOW_REL
    preview = result.get("preview")
    stale = [p for p in _generated_paths(root) if p != target_path]
    remove_paths = list(stale)
    if not result["groups"] and target_path.is_file():
        remove_paths.append(target_path)
    new_bytes = preview.encode("utf-8") if isinstance(preview, str) else None
    changed = bool(remove_paths) or (
        new_bytes is not None
        and (not target_path.is_file() or target_path.read_bytes() != new_bytes)
    )
    result["removed"] = [str(p.relative_to(root)) for p in remove_paths]
    result["changed"] = changed

    if dry_run:
        result["result"] = "dry-run"
        return result

    if new_bytes is not None:
        target_path.parent.mkdir(parents=True, exist_ok=True)
        target_path.write_bytes(new_bytes)
    for path in remove_paths:
        if path.is_file():
            path.unlink()

    manifest_path = root / ".governance" / "install.yaml"
    if new_bytes is not None:
        append_install_assets_seeded(manifest_path, [WORKFLOW_REL])
    removed_rels = [str(p.relative_to(root)) for p in remove_paths]
    remove_install_assets_seeded(manifest_path, removed_rels)
    if manifest_path.is_file():
        digestlib.write_managed_digests_block(manifest_path, digestlib.managed_digests(root))

    result["result"] = "applied"
    return result


def cmd_workflow_plan(args: argparse.Namespace) -> int:
    result = plan(Path(args.root).resolve())
    print(json.dumps(result, indent=2))
    return 0 if not result["errors"] else 1


def cmd_workflow_apply(args: argparse.Namespace) -> int:
    result = apply(Path(args.root).resolve(), dry_run=args.dry_run)
    print(json.dumps(result, indent=2))
    return 2 if result.get("result") == "refused" else 0


def register_workflow(sub) -> None:
    """Register the internal plan/apply engines behind `workflow generate`."""
    p = sub.add_parser("workflow-plan")
    p.add_argument("root")
    p.set_defaults(func=cmd_workflow_plan)

    p = sub.add_parser("workflow-apply")
    p.add_argument("root")
    p.add_argument("--dry-run", action="store_true")
    p.set_defaults(func=cmd_workflow_apply)

    # The user-facing routed verb is `governance workflow generate`; this
    # one-shot engine keeps the plan/apply split internal to the kit.
    p = sub.add_parser("workflow-generate")
    p.add_argument("root")
    p.add_argument("--dry-run", action="store_true")
    p.set_defaults(func=cmd_workflow_apply)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="cmd", required=True)
    register_workflow(sub)
    args = parser.parse_args(argv)
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
