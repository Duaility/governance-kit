#!/usr/bin/env python3
"""Pack manifest helper for governance-bootstrap.

Run via:
    uv run --with PyYAML python governance/assets/packs/lib/packctl.py ...
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path
from typing import Any

import yaml


HOOKS = {"pre-commit", "commit-msg", "prepare-commit-msg", "post-commit", "none"}
SURFACES = {"repo-state", "change-set"}
HOOK_STRATEGIES = {"githooks", "husky", "pre-commit"}
PACK_FIELDS = ("id", "name", "version", "min_governance_kit", "description", "author")
DIRECTIVE_FIELDS = ("category", "recommended", "summary", "surface", "hook")
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


def directive_manifest(pack_dir: Path, directive_id: str) -> dict[str, Any]:
    path = pack_dir / "directives" / directive_id / "directive.yaml"
    if not path.exists():
        return {}
    return load_yaml(path)


def scalar(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, bool):
        return "true" if value else "false"
    return str(value)


def directives_for_pack(pack_dir: Path) -> list[str]:
    directives_root = pack_dir / "directives"
    if not directives_root.is_dir():
        return []
    return sorted(
        path.name
        for path in directives_root.iterdir()
        if path.is_dir() and (path / "directive.yaml").is_file()
    )


def resolve_preset(pack_dir: Path, preset: str) -> list[str]:
    manifest = pack_manifest(pack_dir)
    presets = manifest.get("presets") or {}
    if not isinstance(presets, dict) or preset not in presets:
        raise KeyError(preset)

    out: list[str] = []
    seen: set[str] = set()

    def add(directive_id: str) -> None:
        if directive_id not in seen:
            seen.add(directive_id)
            out.append(directive_id)

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
        directives = node.get("directives") or []
        if not isinstance(directives, list):
            raise ValueError(f"preset {name!r} directives must be a list")
        for directive_id in directives:
            add(str(directive_id))

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


def cmd_directives_for(args: argparse.Namespace) -> int:
    print("\n".join(directives_for_pack(Path(args.pack_dir))))
    return 0


def cmd_directive_field(args: argparse.Namespace) -> int:
    print(scalar(directive_manifest(Path(args.pack_dir), args.directive_id).get(args.field)))
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
            directives = resolve_preset(Path(pack_arg), args.preset)
        except KeyError:
            continue
        for directive_id in directives:
            if directive_id not in seen:
                seen.add(directive_id)
                out.append(directive_id)
    print("\n".join(out))
    return 0


def cmd_always_install(args: argparse.Namespace) -> int:
    pack_dir = Path(args.pack_dir)
    for directive_id in directives_for_pack(pack_dir):
        if directive_manifest(pack_dir, directive_id).get("always_install") is True:
            print(directive_id)
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
    # Pack ids are always scoped `<author>/<slug>` so installed copies land at
    # `.governance/packs/<author>/<slug>/`, mirroring the pack's GitHub
    # `<owner>/<name>` identity. The directory name on the kit-source side is
    # the slug half — the author namespace lives only in the pack id and the
    # installed-target layout. Reject unscoped ids; they would install to a
    # one-segment path and silently keep the old pre-v2 namespace alive.
    #
    # The fetch cache (see packverb.fetch_ref) lays packs out at
    # `<author>__<slug>@<sha>/` (no subpath) or `<author>__<slug>@<sha>/<subpath>/`,
    # so `validate-pack` invoked directly against a cache root must accept
    # the slugified `__`-form too. Without this branch the validator
    # would reject every freshly fetched pack by dirname before any of
    # the fields-and-files checks run.
    if pack_id:
        if "/" not in pack_id:
            errors.append(
                f"{pack_dir}: pack id {pack_id!r} must be scoped as '<author>/<slug>' "
                f"(e.g. 'acme/{pack_dir.name}')"
            )
        else:
            slug = pack_id.split("/", 1)[-1]
            slugified = pack_id.replace("/", "__")
            cache_pattern = re.compile(rf"^{re.escape(slugified)}(@[0-9a-f]{{40}})?$")
            if (
                pack_dir.name != slug
                and pack_dir.name != slugified
                and not cache_pattern.match(pack_dir.name)
            ):
                errors.append(
                    f"{pack_dir}: pack id {pack_id!r} does not match directory name {pack_dir.name!r} "
                    f"(expected {slug!r}, {slugified!r}, or '{slugified}@<sha>')"
                )

    min_kit = scalar(manifest.get("min_governance_kit"))
    if min_kit and not kit_supports(min_kit):
        errors.append(
            f"{pack_dir}: min_governance_kit {min_kit!r} is newer than installed kit {KIT_VERSION!r}"
        )

    directives_root = pack_dir / "directives"
    if not directives_root.is_dir():
        errors.append(f"{pack_dir}: directives/ directory missing")
        return errors

    directive_ids = set(directives_for_pack(pack_dir))
    for stray in sorted(path for path in directives_root.iterdir() if not path.is_dir()):
        errors.append(f"{pack_dir}: stray file under directives/ ({stray.name}) - directives must be folders")

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
        directives = node.get("directives") or []
        if not isinstance(directives, list):
            errors.append(f"{pack_dir}: preset {preset_name!r} directives must be a list")
            continue
        for directive_id in directives:
            if str(directive_id) not in directive_ids:
                errors.append(f"{pack_dir}: preset {preset_name!r} references unknown directive {directive_id!r}")
        try:
            resolve_preset(pack_dir, str(preset_name))
        except Exception as exc:  # noqa: BLE001 - validation reports all manifest errors.
            errors.append(f"{pack_dir}: preset {preset_name!r} cannot resolve: {exc}")

    for directive_id in sorted(directive_ids):
        directive_path = directives_root / directive_id
        directive = directive_manifest(pack_dir, directive_id)
        for field in DIRECTIVE_FIELDS:
            if field not in directive or directive.get(field) in (None, ""):
                errors.append(f"{pack_dir}/{directive_id}: directive.yaml missing required field {field!r}")
        hook = scalar(directive.get("hook") or "none")
        surface = scalar(directive.get("surface"))
        hook_strategy = scalar(directive.get("requires_hook_strategy"))
        if hook not in HOOKS:
            errors.append(f"{pack_dir}/{directive_id}: unknown hook value {hook!r}")
        if surface not in SURFACES:
            errors.append(f"{pack_dir}/{directive_id}: unknown surface value {surface!r}")
        if hook_strategy and hook_strategy not in HOOK_STRATEGIES:
            errors.append(
                f"{pack_dir}/{directive_id}: unknown requires_hook_strategy value {hook_strategy!r}"
            )
        if directive.get("always_install") is True and pack_id != "governance-kit/core":
            errors.append(f"{pack_dir}/{directive_id}: always_install: true is reserved to the governance-kit/core pack")
        # Fork-not-patch amendments (#114 phase 5). A directive in a `local`
        # pack can declare `replaces: <pack-id>/<directive-id>` to suppress
        # the upstream version at runtime — see DIRECTIVE_AMEND_FLOW.md.
        # Validate the value's shape; runtime suppression lives in run.sh
        # (or its consumers) and is enforced separately.
        replaces = scalar(directive.get("replaces") or "")
        if replaces:
            parts = replaces.split("/")
            if len(parts) < 3:
                errors.append(
                    f"{pack_dir}/{directive_id}: replaces: {replaces!r} must be "
                    "<pack-owner>/<pack-name>/<directive-id> (3 segments)"
                )
            elif parts[-1] == directive_id:
                # OK — replacing the same directive id in another pack is the
                # canonical use case (forking a kit/community directive).
                pass
            elif parts[-1] != directive_id:
                # Cross-id replacements are allowed but flagged as a smell:
                # `replaces` is meant for forks of the same directive, not
                # arbitrary disable + add chains.
                pass
        for capability in CAPABILITY_FIELDS:
            if capability not in directive:
                continue
            value = directive.get(capability)
            if value is None:
                continue
            if not isinstance(value, list) or not all(isinstance(item, str) and item for item in value):
                errors.append(
                    f"{pack_dir}/{directive_id}: {capability!r} must be a list of non-empty path globs"
                )
        check = directive_path / "check.sh"
        constitution = directive_path / "constitution.md"
        if not check.is_file():
            errors.append(f"{pack_dir}/{directive_id}: check.sh missing")
        elif not os.access(check, os.X_OK):
            errors.append(f"{pack_dir}/{directive_id}: check.sh is not executable")
        if not constitution.is_file():
            errors.append(f"{pack_dir}/{directive_id}: constitution.md missing")
        else:
            text = constitution.read_text()
            expected = f".governance/packs/{pack_id}/directives/{directive_id}/check.sh"
            if expected not in text:
                errors.append(f"{pack_dir}/{directive_id}: constitution.md must reference `{expected}`")
        eval_script = directive_path / "evals" / "test.sh"
        if not eval_script.is_file():
            errors.append(f"{pack_dir}/{directive_id}: evals/test.sh missing")
        elif not os.access(eval_script, os.X_OK):
            errors.append(f"{pack_dir}/{directive_id}: evals/test.sh is not executable")
        for hook_script in sorted((directive_path / "hooks").glob("*.sh")) if (directive_path / "hooks").is_dir() else []:
            if not os.access(hook_script, os.X_OK):
                errors.append(f"{pack_dir}/{directive_id}: hooks/{hook_script.name} is not executable")
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
        for directive_id in directives_for_pack(pack_dir):
            if directive_id in seen:
                errors.append(f"duplicate directive id {directive_id!r}: {seen[directive_id]} and {pack_dir}")
            else:
                seen[directive_id] = pack_dir
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

    p = sub.add_parser("directives-for")
    p.add_argument("pack_dir")
    p.set_defaults(func=cmd_directives_for)

    p = sub.add_parser("directive-field")
    p.add_argument("pack_dir")
    p.add_argument("directive_id")
    p.add_argument("field")
    p.set_defaults(func=cmd_directive_field)

    p = sub.add_parser("preset-resolve")
    p.add_argument("pack_dir")
    p.add_argument("preset")
    p.set_defaults(func=cmd_preset_resolve)

    p = sub.add_parser("union-preset")
    p.add_argument("preset")
    p.add_argument("pack_dirs", nargs="+")
    p.set_defaults(func=cmd_union_preset)

    p = sub.add_parser("always-install-directives")
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
