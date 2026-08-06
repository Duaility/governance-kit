#!/usr/bin/env python3
"""Pack manifest helper for governance-bootstrap.

Run via:
    python3 kit/assets/packs/lib/packctl.py ...
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Any

import kityaml


HOOKS = {"pre-commit", "commit-msg", "prepare-commit-msg", "post-commit", "none"}
# The scheduled lane (issue #142, harness-pegged per #355; renamed from
# "sweep" by the scheduled-triggers redesign) is no longer a `surface` value.
# There is exactly one semantic-judgment primitive — a rubric-framed model
# judgment declared once in a directive's `judge:` block (see
# JUDGE.md) and executed directly through the declared judge command. A
# scheduled run is just that same declaration re-adjudicated off the
# commit path by `.governance/schedule.sh`: no second engine, no vendor
# transport, no `triage.sh` contract, no `engine:`/`model_tier:` scalar
# fields. A directive opts into the scheduled lane by carrying `schedule` in
# its effective `triggers:` (see TRIGGER_VALUES below) — validated below via
# `validate_triggers`, not via a surface value.
SURFACES = {"repo-state", "change-set"}
HOOK_STRATEGIES = {"githooks", "husky", "pre-commit"}
PACK_FIELDS = ("id", "name", "version", "min_governance_kit", "description", "author")
DIRECTIVE_FIELDS = ("category", "recommended", "summary", "surface", "hook")
CAPABILITY_FIELDS = ("reads", "writes")

# The optional `triggers:` field (scheduled-lane redesign, replaces the sweep
# lane): a flow or block list naming every lane a directive's `check.sh`/
# `judge:` runs under. Allowed values are the five git-hook kinds, `none`
# (matches `hook: none`), and `schedule` (eligibility for the at-rest
# scheduled lane, `.governance/schedule.sh`; see SCHEDULE_FLOW.md).
# `TRIGGER_HOOK_VALUES` is the git-hook subset, used by the hook-consistency
# rule in packvalidate.validate_triggers.
TRIGGER_HOOK_VALUES = {"pre-commit", "commit-msg", "prepare-commit-msg", "post-commit", "pre-push"}
TRIGGER_VALUES = TRIGGER_HOOK_VALUES | {"none", "schedule"}

# Issue #355 (cmd collapse): a directive's `judge:` block names the judge
# COMMAND directly instead of resolving it through a tier vocabulary. `cmd` is
# an optional map with exactly these two lanes; anything else under `cmd` is
# an error. There is no `tiers:` vocabulary anymore — it is a forbidden key
# (v0, no deprecation lane), not merely unrecognized. The `sweep` lane is
# renamed `schedule` (the sweep lane's retirement, no compat alias — V0).
JUDGE_CMD_LANES = {"attest", "schedule"}

# Issue #355 amendment 3: `gate` is a three-valued scalar that now also
# carries what used to be the separate `contest` boolean. `record` (default)
# never blocks; `verdict` blocks on REFUTED/missing and a CONTESTED verdict
# does NOT ride through (yesterday's `gate: verdict` + `contest: forbid`);
# `verdict-contestable` blocks the same way but lets a CONTESTED round ride
# through (yesterday's `gate: verdict` + `contest: allow`). `contest` is now
# a forbidden key — folded entirely into this one axis.
JUDGE_GATE_VALUES = {"record", "verdict", "verdict-contestable"}

# Governance-kit version — the kit (framework) axis. The single source of truth
# is kit/assets/kit.yaml; this module reads it so packs, the release
# script, and the version-consistency directive all agree on one value. Packs
# declare `min_governance_kit` to express the minimum kit they need; validation
# refuses packs whose minimum is newer than KIT_VERSION. The comparison uses a
# lexicographic SemVer-ish tuple (split on `.`, numeric segments compared as
# ints, non-numeric segments as strings) — see `_version_tuple`. See
# kit/references/VERSIONING.md for the full policy.
_KIT_YAML = Path(__file__).resolve().parents[2] / "kit.yaml"


def _load_kit_version() -> str:
    try:
        data = kityaml.load(_KIT_YAML) or {}
    except (OSError, kityaml.YAMLError) as exc:  # pragma: no cover - kit is malformed
        raise RuntimeError(f"cannot read kit version from {_KIT_YAML}: {exc}") from exc
    version = data.get("version")
    if not version:
        raise RuntimeError(f"{_KIT_YAML} is missing a top-level 'version' field")
    return str(version)


KIT_VERSION = _load_kit_version()


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
        data = kityaml.load(path) or {}
    except kityaml.YAMLError as exc:
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


# Manifest validation (`validate_judge_cmd`, `validate_pack_dir`,
# `validate_pack_dir_with_warnings`) lives in the sibling module
# packvalidate.py — split out to keep this file under the repo-hygiene
# 500-line limit. The two wrappers below re-export the public entry points so
# existing importers (`from packctl import validate_pack_dir`, `pkt.validate_
# pack_dir` in tests, packverb.py, packplan.py) keep working unchanged.
#
# The `import packvalidate` is deliberately INSIDE each wrapper's body, not
# at this module's top level. packctl.py is routinely executed directly
# (`python3 packctl.py ...`, see packs.sh's `_packctl()`), which registers it
# in `sys.modules` as `__main__` rather than `packctl`. packvalidate.py's own
# top-level does a normal `from packctl import (...)`, which — when packctl
# is only known as `__main__` — forces Python to load packctl.py a *second*
# time under the literal name `packctl` to satisfy that import. If this file
# also imported packvalidate at module scope, that second load would race
# packvalidate's own still-in-progress import and fail with a circular-import
# error. Deferring the import to call time sidesteps this: by the time either
# wrapper actually runs, both modules have finished loading under whatever
# names they ended up with.
def validate_pack_dir(pack_dir: Path) -> list[str]:
    import packvalidate

    return packvalidate.validate_pack_dir(pack_dir)


def validate_pack_dir_with_warnings(pack_dir: Path) -> tuple[list[str], list[str]]:
    import packvalidate

    return packvalidate.validate_pack_dir_with_warnings(pack_dir)


def cmd_validate_pack(args: argparse.Namespace) -> int:
    errors, warnings = validate_pack_dir_with_warnings(Path(args.pack_dir))
    if warnings:
        print("\n".join(warnings), file=sys.stderr)
    if errors:
        print("\n".join(errors))
        return 1
    return 0


def cmd_validate_pack_set(args: argparse.Namespace) -> int:
    # A bare directive id is a *given name*, not a global claim. Once a second
    # pack exists, two packs may legitimately ship same-named directives that
    # check different things — they coexist and both run (suppression is only
    # ever explicit, via `replaces:`). So a cross-pack short-id collision is an
    # informational notice (printed to stderr, surfaced by `governance pack
    # add`), not a hard error. Only genuine per-pack validation problems fail.
    seen: dict[str, Path] = {}
    errors: list[str] = []
    notices: list[str] = []
    warnings: list[str] = []
    for pack_arg in args.pack_dirs:
        pack_dir = Path(pack_arg)
        pack_errors, pack_warnings = validate_pack_dir_with_warnings(pack_dir)
        errors.extend(pack_errors)
        warnings.extend(pack_warnings)
        for directive_id in directives_for_pack(pack_dir):
            if directive_id in seen:
                notices.append(
                    f"notice: directive id {directive_id!r} appears in more than one pack "
                    f"({seen[directive_id]} and {pack_dir}); both will run — "
                    f"use `replaces:` to suppress one explicitly"
                )
            else:
                seen[directive_id] = pack_dir
    if notices:
        print("\n".join(notices), file=sys.stderr)
    if warnings:
        print("\n".join(warnings), file=sys.stderr)
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
