#!/usr/bin/env python3
"""Pack manifest helper for governance-bootstrap.

Run via:
    uv run --with PyYAML python governance-bootstrap/assets/packs/lib/packctl.py ...
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path
from typing import Any

import yaml


HOOKS = {"pre-commit", "commit-msg", "prepare-commit-msg", "none"}
SURFACES = {"repo-state", "change-set"}
HOOK_STRATEGIES = {"githooks", "husky", "pre-commit"}
PACK_FIELDS = ("id", "name", "version", "min_governance_kit", "description", "author")
RULE_FIELDS = ("category", "recommended", "summary", "surface", "hook")
CAPABILITY_FIELDS = ("reads", "writes")

# Governance-kit version advertised to pack manifests. Packs declare
# `min_governance_kit` to express the minimum kit version they need; validation
# refuses packs whose minimum is newer than this constant. The comparison uses a
# lexicographic SemVer-ish tuple (split on `.`, numeric segments compared as
# ints, non-numeric segments as strings) — see `_version_tuple`.
KIT_VERSION = "0.2"


def _version_tuple(value: str) -> tuple[Any, ...]:
    parts: list[Any] = []
    for segment in str(value).split("."):
        try:
            parts.append((0, int(segment)))
        except ValueError:
            parts.append((1, segment))
    return tuple(parts)


def kit_supports(min_required: str) -> bool:
    """Return True when KIT_VERSION >= min_required."""
    if not min_required:
        return True
    return _version_tuple(KIT_VERSION) >= _version_tuple(min_required)


def load_yaml(path: Path) -> dict[str, Any]:
    try:
        data = yaml.safe_load(path.read_text()) or {}
    except yaml.YAMLError as exc:
        raise SystemExit(f"{path}: invalid YAML: {exc}") from exc
    if not isinstance(data, dict):
        raise SystemExit(f"{path}: expected a YAML mapping")
    return data


def pack_manifest(pack_dir: Path) -> dict[str, Any]:
    return load_yaml(pack_dir / "pack.yaml")


def rule_manifest(pack_dir: Path, rule_id: str) -> dict[str, Any]:
    path = pack_dir / "rules" / rule_id / "rule.yaml"
    if not path.exists():
        return {}
    return load_yaml(path)


def scalar(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, bool):
        return "true" if value else "false"
    return str(value)


def rules_for_pack(pack_dir: Path) -> list[str]:
    rules_root = pack_dir / "rules"
    if not rules_root.is_dir():
        return []
    return sorted(
        path.name
        for path in rules_root.iterdir()
        if path.is_dir() and (path / "rule.yaml").is_file()
    )


def resolve_preset(pack_dir: Path, preset: str) -> list[str]:
    manifest = pack_manifest(pack_dir)
    presets = manifest.get("presets") or {}
    if not isinstance(presets, dict) or preset not in presets:
        raise KeyError(preset)

    out: list[str] = []
    seen: set[str] = set()

    def add(rule_id: str) -> None:
        if rule_id not in seen:
            seen.add(rule_id)
            out.append(rule_id)

    def walk(name: str, stack: tuple[str, ...] = ()) -> None:
        if name in stack:
            chain = " -> ".join((*stack, name))
            raise ValueError(f"preset inheritance cycle: {chain}")
        node = presets.get(name)
        if node is None:
            raise KeyError(name)
        if not isinstance(node, dict):
            raise ValueError(f"preset {name!r} must be a mapping")
        parent = node.get("extends")
        if parent:
            walk(str(parent), (*stack, name))
        rules = node.get("rules") or []
        if not isinstance(rules, list):
            raise ValueError(f"preset {name!r} rules must be a list")
        for rule_id in rules:
            add(str(rule_id))

    walk(preset)
    return out


def cmd_list_packs(args: argparse.Namespace) -> int:
    root = Path(args.root)
    if not root.is_dir():
        return 1
    for manifest in sorted(root.glob("*/pack.yaml")):
        pack_dir = manifest.parent
        pack_id = scalar(load_yaml(manifest).get("id")) or pack_dir.name
        print(f"{pack_id}\t{pack_dir}")
    return 0


def cmd_pack_field(args: argparse.Namespace) -> int:
    print(scalar(pack_manifest(Path(args.pack_dir)).get(args.field)))
    return 0


def cmd_rules_for(args: argparse.Namespace) -> int:
    print("\n".join(rules_for_pack(Path(args.pack_dir))))
    return 0


def cmd_rule_field(args: argparse.Namespace) -> int:
    print(scalar(rule_manifest(Path(args.pack_dir), args.rule_id).get(args.field)))
    return 0


def cmd_preset_resolve(args: argparse.Namespace) -> int:
    try:
        print("\n".join(resolve_preset(Path(args.pack_dir), args.preset)))
    except KeyError:
        return 1
    return 0


def cmd_union_preset(args: argparse.Namespace) -> int:
    out: list[str] = []
    seen: set[str] = set()
    for pack_arg in args.pack_dirs:
        try:
            rules = resolve_preset(Path(pack_arg), args.preset)
        except KeyError:
            continue
        for rule_id in rules:
            if rule_id not in seen:
                seen.add(rule_id)
                out.append(rule_id)
    print("\n".join(out))
    return 0


def cmd_always_install(args: argparse.Namespace) -> int:
    pack_dir = Path(args.pack_dir)
    for rule_id in rules_for_pack(pack_dir):
        if rule_manifest(pack_dir, rule_id).get("always_install") is True:
            print(rule_id)
    return 0


def validate_pack_dir(pack_dir: Path) -> list[str]:
    errors: list[str] = []
    manifest_path = pack_dir / "pack.yaml"
    if not manifest_path.is_file():
        return [f"{pack_dir}: pack.yaml missing"]
    manifest = pack_manifest(pack_dir)
    pack_id = scalar(manifest.get("id"))

    for field in PACK_FIELDS:
        if field not in manifest or manifest.get(field) in (None, ""):
            errors.append(f"{pack_dir}: pack.yaml missing required field {field!r}")
    # Unscoped ids (e.g. `core`) must match the directory name. Scoped community
    # ids (`<author>/<slug>`) match against the slug portion — the author
    # namespace doesn't need to surface in the filesystem layout.
    if pack_id:
        expected = pack_id.split("/", 1)[-1] if "/" in pack_id else pack_id
        if expected != pack_dir.name:
            errors.append(
                f"{pack_dir}: pack id {pack_id!r} does not match directory name {pack_dir.name!r}"
            )

    min_kit = scalar(manifest.get("min_governance_kit"))
    if min_kit and not kit_supports(min_kit):
        errors.append(
            f"{pack_dir}: min_governance_kit {min_kit!r} is newer than installed kit {KIT_VERSION!r}"
        )

    rules_root = pack_dir / "rules"
    if not rules_root.is_dir():
        errors.append(f"{pack_dir}: rules/ directory missing")
        return errors

    rule_ids = set(rules_for_pack(pack_dir))
    for stray in sorted(path for path in rules_root.iterdir() if not path.is_dir()):
        errors.append(f"{pack_dir}: stray file under rules/ ({stray.name}) - rules must be folders")

    presets = manifest.get("presets") or {}
    if not isinstance(presets, dict):
        errors.append(f"{pack_dir}: presets must be a mapping")
        presets = {}
    for preset_name, node in presets.items():
        if not isinstance(node, dict):
            errors.append(f"{pack_dir}: preset {preset_name!r} must be a mapping")
            continue
        parent = node.get("extends")
        if parent and str(parent) not in presets:
            errors.append(f"{pack_dir}: preset {preset_name!r} extends unknown preset {parent!r}")
        rules = node.get("rules") or []
        if not isinstance(rules, list):
            errors.append(f"{pack_dir}: preset {preset_name!r} rules must be a list")
            continue
        for rule_id in rules:
            if str(rule_id) not in rule_ids:
                errors.append(f"{pack_dir}: preset {preset_name!r} references unknown rule {rule_id!r}")
        try:
            resolve_preset(pack_dir, str(preset_name))
        except Exception as exc:  # noqa: BLE001 - validation reports all manifest errors.
            errors.append(f"{pack_dir}: preset {preset_name!r} cannot resolve: {exc}")

    for rule_id in sorted(rule_ids):
        rule_path = rules_root / rule_id
        rule = rule_manifest(pack_dir, rule_id)
        for field in RULE_FIELDS:
            if field not in rule or rule.get(field) in (None, ""):
                errors.append(f"{pack_dir}/{rule_id}: rule.yaml missing required field {field!r}")
        hook = scalar(rule.get("hook") or "none")
        surface = scalar(rule.get("surface"))
        hook_strategy = scalar(rule.get("requires_hook_strategy"))
        if hook not in HOOKS:
            errors.append(f"{pack_dir}/{rule_id}: unknown hook value {hook!r}")
        if surface not in SURFACES:
            errors.append(f"{pack_dir}/{rule_id}: unknown surface value {surface!r}")
        if hook_strategy and hook_strategy not in HOOK_STRATEGIES:
            errors.append(
                f"{pack_dir}/{rule_id}: unknown requires_hook_strategy value {hook_strategy!r}"
            )
        if rule.get("always_install") is True and pack_id != "core":
            errors.append(f"{pack_dir}/{rule_id}: always_install: true is reserved to the core pack")
        for capability in CAPABILITY_FIELDS:
            if capability not in rule:
                continue
            value = rule.get(capability)
            if value is None:
                continue
            if not isinstance(value, list) or not all(isinstance(item, str) and item for item in value):
                errors.append(
                    f"{pack_dir}/{rule_id}: {capability!r} must be a list of non-empty path globs"
                )
        check = rule_path / "check.sh"
        constitution = rule_path / "constitution.md"
        if not check.is_file():
            errors.append(f"{pack_dir}/{rule_id}: check.sh missing")
        elif not os.access(check, os.X_OK):
            errors.append(f"{pack_dir}/{rule_id}: check.sh is not executable")
        if not constitution.is_file():
            errors.append(f"{pack_dir}/{rule_id}: constitution.md missing")
        else:
            text = constitution.read_text()
            expected = f"tests/governance/rules/{rule_id}/check.sh"
            if expected not in text:
                errors.append(f"{pack_dir}/{rule_id}: constitution.md must reference `{expected}`")
        eval_script = rule_path / "evals" / "test.sh"
        if not eval_script.is_file():
            errors.append(f"{pack_dir}/{rule_id}: evals/test.sh missing")
        elif not os.access(eval_script, os.X_OK):
            errors.append(f"{pack_dir}/{rule_id}: evals/test.sh is not executable")
        for hook_script in sorted((rule_path / "hooks").glob("*.sh")) if (rule_path / "hooks").is_dir() else []:
            if not os.access(hook_script, os.X_OK):
                errors.append(f"{pack_dir}/{rule_id}: hooks/{hook_script.name} is not executable")
    return errors


def cmd_validate_pack(args: argparse.Namespace) -> int:
    errors = validate_pack_dir(Path(args.pack_dir))
    if errors:
        print("\n".join(errors))
        return 1
    return 0


def cmd_validate_pack_set(args: argparse.Namespace) -> int:
    seen: dict[str, Path] = {}
    errors: list[str] = []
    for pack_arg in args.pack_dirs:
        pack_dir = Path(pack_arg)
        errors.extend(validate_pack_dir(pack_dir))
        for rule_id in rules_for_pack(pack_dir):
            if rule_id in seen:
                errors.append(f"duplicate rule id {rule_id!r}: {seen[rule_id]} and {pack_dir}")
            else:
                seen[rule_id] = pack_dir
    if errors:
        print("\n".join(errors))
        return 1
    return 0


def cmd_kit_version(_: argparse.Namespace) -> int:
    print(KIT_VERSION)
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("kit-version")
    p.set_defaults(func=cmd_kit_version)

    p = sub.add_parser("list-packs")
    p.add_argument("root")
    p.set_defaults(func=cmd_list_packs)

    p = sub.add_parser("pack-field")
    p.add_argument("pack_dir")
    p.add_argument("field")
    p.set_defaults(func=cmd_pack_field)

    p = sub.add_parser("rules-for")
    p.add_argument("pack_dir")
    p.set_defaults(func=cmd_rules_for)

    p = sub.add_parser("rule-field")
    p.add_argument("pack_dir")
    p.add_argument("rule_id")
    p.add_argument("field")
    p.set_defaults(func=cmd_rule_field)

    p = sub.add_parser("preset-resolve")
    p.add_argument("pack_dir")
    p.add_argument("preset")
    p.set_defaults(func=cmd_preset_resolve)

    p = sub.add_parser("union-preset")
    p.add_argument("preset")
    p.add_argument("pack_dirs", nargs="+")
    p.set_defaults(func=cmd_union_preset)

    p = sub.add_parser("always-install-rules")
    p.add_argument("pack_dir")
    p.set_defaults(func=cmd_always_install)

    p = sub.add_parser("validate-pack")
    p.add_argument("pack_dir")
    p.set_defaults(func=cmd_validate_pack)

    p = sub.add_parser("validate-pack-set")
    p.add_argument("pack_dirs", nargs="+")
    p.set_defaults(func=cmd_validate_pack_set)

    args = parser.parse_args(argv)
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
