#!/usr/bin/env python3
"""Pack/directive manifest validation for packctl.py.

Split from packctl.py to keep both files under the repo-hygiene 500-line
limit (issue #355 cmd collapse landed the judge.cmd validation that
pushed packctl.py over). This module owns `validate_judge_cmd`,
`validate_pack_dir`, and `validate_pack_dir_with_warnings`; packctl.py keeps
the argparse dispatch and small manifest accessors, and re-exports the two
public validate functions (as thin wrappers, imported here lazily inside
their bodies) so existing importers (`from packctl import validate_pack_dir`,
etc.) keep working unchanged.

Import direction is one-way — this module imports from packctl, never the
reverse at module scope — because packctl.py is routinely executed directly
(`python3 packctl.py ...`, see packs.sh's `_packctl()`), which registers it
in `sys.modules` as `__main__`, not `packctl`. A module-scope `import
packvalidate` inside packctl.py would then force Python to load packctl.py a
second time under the name `packctl` to satisfy this file's `from packctl
import ...`, and if that second load also tried to import this
still-mid-import module at module scope, it would hit a genuine circular
import (partially initialized module) error. packctl.py sidesteps this by
importing packvalidate only inside its wrapper functions' bodies, deferred
past both modules' own load time — see `validate_pack_dir` /
`validate_pack_dir_with_warnings` there.
"""

from __future__ import annotations

import os
import re
from pathlib import Path
from typing import Any

from packctl import (
    CAPABILITY_FIELDS,
    CONFIG_TYPES,
    DIRECTIVE_FIELDS,
    HOOK_STRATEGIES,
    HOOKS,
    PACK_FIELDS,
    JUDGE_GATE_VALUES,
    SURFACES,
    KIT_VERSION,
    TRIGGER_VALUES,
    TRIGGER_HOOK_VALUES,
    directive_manifest,
    directives_for_pack,
    kit_supports,
    pack_manifest,
    resolve_preset,
    scalar,
)


_CONFIG_NAME_RE = re.compile(r"^[A-Z][A-Z0-9_]*$")
_REMOVED_CONFIG_NAMES = {"JUDGE_GROUP"}


def config_entries(config: Any) -> list[dict[str, Any]]:
    return config if isinstance(config, list) else []


def config_entry(config: Any, name: str) -> dict[str, Any] | None:
    return next((e for e in config_entries(config) if e.get("name") == name), None)


def validate_config(pack_dir: Path, directive_id: str, config: Any) -> list[str]:
    """Validate the issue #366 self-contained config registry.

    Strictness here is what keeps the commit-path reader small: entries are a
    flat sequence and every list default is one scalar item per YAML row.
    """
    if config is None:
        return []
    prefix = f"{pack_dir}/{directive_id}"
    if not isinstance(config, list) or not config:
        return [f"{prefix}: directive.yaml config must be a non-empty list"]
    errors: list[str] = []
    seen: set[str] = set()
    required = {"name", "type", "doc", "default", "tunable"}
    for index, entry in enumerate(config, start=1):
        ep = f"{prefix}: config entry {index}"
        if not isinstance(entry, dict):
            errors.append(f"{ep} must be a mapping")
            continue
        missing = sorted(required - set(entry))
        extra = sorted(set(entry) - required)
        if missing:
            errors.append(f"{ep} missing required fields {missing!r}")
        if extra:
            errors.append(f"{ep} has unknown fields {extra!r}")
        name = entry.get("name")
        if not isinstance(name, str) or not _CONFIG_NAME_RE.fullmatch(name):
            errors.append(f"{ep} name must match [A-Z][A-Z0-9_]*")
        elif name in seen:
            errors.append(f"{prefix}: duplicate config name {name!r}")
        else:
            seen.add(name)
        if isinstance(name, str) and name in _REMOVED_CONFIG_NAMES:
            errors.append(f"{ep} config name {name!r} was removed; judge directives run independently")
        kind = entry.get("type")
        if kind not in CONFIG_TYPES:
            errors.append(f"{ep} type must be one of {sorted(CONFIG_TYPES)!r}")
        doc = entry.get("doc")
        if not isinstance(doc, str) or not doc.strip() or "\n" in doc:
            errors.append(f"{ep} doc must be a non-empty one-line string")
        if not isinstance(entry.get("tunable"), bool):
            errors.append(f"{ep} tunable must be true or false")
        default = entry.get("default")
        if kind == "scalar" and isinstance(default, (dict, list)):
            errors.append(f"{ep} scalar default must be a scalar (null is allowed)")
        if kind == "list":
            if not isinstance(default, list):
                errors.append(f"{ep} list default must be a list")
            elif any(not isinstance(item, str) or not item.strip() or "\n" in item for item in default):
                errors.append(f"{ep} list default items must be non-empty one-line strings")
    return errors


def validate_judge(
    pack_dir: Path, directive_id: str, judge: dict[str, Any]
) -> tuple[list[str], list[str]]:
    """Validate lane-independent judgment semantics (issue #366)."""
    errors: list[str] = []
    warnings: list[str] = []
    prefix = f"{pack_dir}/{directive_id}"
    allowed = {"inputs", "checks", "gate"}
    extra = sorted(set(judge) - allowed)
    if extra:
        errors.append(
            f"{prefix}: judge has lane-specific or unknown keys {extra!r}; only inputs, checks, and gate belong in judge"
        )
    for key in ("inputs", "checks"):
        value = judge.get(key)
        if not isinstance(value, list) or not value or any(not isinstance(v, str) or not v.strip() for v in value):
            errors.append(f"{prefix}: judge.{key} must be a non-empty list of strings")
    if "gate" in judge:
        gate = scalar(judge.get("gate"))
        if gate not in JUDGE_GATE_VALUES:
            errors.append(
                f"{prefix}: judge.gate has unknown value {gate!r} "
                f"(allowed: {', '.join(sorted(JUDGE_GATE_VALUES))})"
            )
    return errors, warnings


def validate_triggers(pack_dir: Path, directive_id: str, triggers: Any, hook: str) -> list[str]:
    """Validate a directive's optional `triggers:` field (scheduled-lane
    redesign, replaces the sweep lane's implicit hook-only eligibility).

    `triggers:` is a flow or block list of non-empty strings, each one of
    `TRIGGER_VALUES` (the five git-hook kinds, `none`, or `schedule`).
    Absent is fine — a directive's effective triggers are then derived as
    `[<hook>]` (or `[]` when `hook: none`) by the runner/verb, not written
    out here.

    When `triggers:` IS present and `hook:` != `none`, two consistency rules
    apply (both must hold, or the directive's declared eligibility disagrees
    with its own commit-lane wiring): the list MUST contain the `hook:`
    value, and it may contain AT MOST ONE git-hook value overall — which,
    combined with the first rule, means that one value must be `hook:`
    itself. A `hook: none` directive is unconstrained here (nothing to be
    consistent with)."""
    errors: list[str] = []
    prefix = f"{pack_dir}/{directive_id}"
    if triggers is None:
        return errors
    if not isinstance(triggers, list) or not triggers:
        errors.append(f"{prefix}: directive.yaml triggers must be a non-empty list")
        return errors

    hook_values_seen: list[str] = []
    for item in triggers:
        if not isinstance(item, str) or not item.strip():
            errors.append(f"{prefix}: directive.yaml triggers entries must be non-empty strings")
            continue
        value = item.strip()
        if value not in TRIGGER_VALUES:
            errors.append(
                f"{prefix}: directive.yaml triggers has unknown value {value!r} "
                f"(allowed: {', '.join(sorted(TRIGGER_VALUES))})"
            )
            continue
        if value in TRIGGER_HOOK_VALUES:
            hook_values_seen.append(value)

    if hook != "none":
        if hook not in triggers:
            errors.append(
                f"{prefix}: directive.yaml triggers must contain the hook: value {hook!r} "
                "when triggers: is present and hook: is not 'none'"
            )
        distinct_hook_values = sorted(set(hook_values_seen))
        if len(distinct_hook_values) > 1 or (distinct_hook_values and distinct_hook_values != [hook]):
            errors.append(
                f"{prefix}: directive.yaml triggers may contain at most one git-hook value, "
                f"and it must equal hook: {hook!r} (found {distinct_hook_values!r})"
            )

    return errors


def validate_pack_dir(pack_dir: Path) -> list[str]:
    errors, _warnings = validate_pack_dir_with_warnings(pack_dir)
    return errors


def validate_pack_dir_with_warnings(pack_dir: Path) -> tuple[list[str], list[str]]:
    errors: list[str] = []
    warnings: list[str] = []
    manifest_path = pack_dir / "pack.yaml"
    if not manifest_path.is_file():
        return [f"{pack_dir}: pack.yaml missing"], []
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
        judge = directive.get("judge")
        triggers = directive.get("triggers")
        hook = scalar(directive.get("hook") or "none")
        schedule_only = (
            isinstance(judge, dict) and hook == "none"
            and isinstance(triggers, list) and triggers == ["schedule"]
        )
        config = directive.get("config")
        errors.extend(validate_config(pack_dir, directive_id, config))
        if (directive_path / "defaults.conf").exists():
            errors.append(
                f"{pack_dir}/{directive_id}: defaults.conf is no longer supported; "
                "move its values and docs into directive.yaml config"
            )
        evidence = config_entry(config, "SCHEDULE_EVIDENCE")
        if evidence and scalar(evidence.get("default")) not in {"range", "commits"}:
            errors.append(f"{pack_dir}/{directive_id}: SCHEDULE_EVIDENCE default must be 'range' or 'commits'")
        cron = config_entry(config, "SCHEDULE_CRON")
        if cron:
            if cron.get("type") != "scalar":
                errors.append(f"{pack_dir}/{directive_id}: SCHEDULE_CRON must be a scalar config entry")
            default_cron = scalar(cron.get("default"))
            if default_cron and len(default_cron.split()) != 5:
                errors.append(
                    f"{pack_dir}/{directive_id}: SCHEDULE_CRON default must contain five space-separated cron fields"
                )
        stale = config_entry(config, "SCHEDULE_STALENESS_DAYS")
        if stale and (not isinstance(stale.get("default"), int) or stale.get("default") <= 0):
            errors.append(f"{pack_dir}/{directive_id}: SCHEDULE_STALENESS_DAYS default must be a positive integer")
        if isinstance(judge, dict):
            cmd_errors, cmd_warnings = validate_judge(pack_dir, directive_id, judge)
            errors.extend(cmd_errors)
            warnings.extend(cmd_warnings)
            if not isinstance(triggers, list):
                errors.append(f"{pack_dir}/{directive_id}: a judge declaration requires explicit triggers")
            section = config_entry(config, "ATTEST_SECTION")
            if section and (section.get("type") != "scalar" or section.get("tunable") is not False or not scalar(section.get("default"))):
                errors.append(
                    f"{pack_dir}/{directive_id}: ATTEST_SECTION must be a non-empty fixed scalar"
                )
            if scalar(judge.get("gate") or "record") in {"verdict", "verdict-contestable"} and not section:
                errors.append(
                    f"{pack_dir}/{directive_id}: judge.gate {scalar(judge.get('gate'))!r} "
                    "requires a fixed ATTEST_SECTION config entry"
                )
            if section:
                attest_cmd = config_entry(config, "ATTEST_CMD")
                if not attest_cmd or attest_cmd.get("type") != "scalar" or attest_cmd.get("tunable") is not False or not scalar(attest_cmd.get("default")):
                    errors.append(
                        f"{pack_dir}/{directive_id}: an attest lane requires a non-empty fixed ATTEST_CMD scalar"
                    )
            if isinstance(triggers, list) and "schedule" in triggers:
                schedule_cmd = config_entry(config, "SCHEDULE_CMD")
                if not schedule_cmd or schedule_cmd.get("type") != "scalar" or schedule_cmd.get("tunable") is not False or not scalar(schedule_cmd.get("default")):
                    errors.append(
                        f"{pack_dir}/{directive_id}: a schedule trigger requires a non-empty fixed SCHEDULE_CMD scalar"
                    )
        for field in DIRECTIVE_FIELDS:
            if field not in directive or directive.get(field) in (None, ""):
                errors.append(f"{pack_dir}/{directive_id}: directive.yaml missing required field {field!r}")
        surface = scalar(directive.get("surface"))
        hook_strategy = scalar(directive.get("requires_hook_strategy"))
        if hook not in HOOKS:
            errors.append(f"{pack_dir}/{directive_id}: unknown hook value {hook!r}")
        errors.extend(validate_triggers(pack_dir, directive_id, triggers, hook))
        if surface not in SURFACES:
            errors.append(f"{pack_dir}/{directive_id}: unknown surface value {surface!r}")
        if hook_strategy and hook_strategy not in HOOK_STRATEGIES:
            errors.append(
                f"{pack_dir}/{directive_id}: unknown requires_hook_strategy value {hook_strategy!r}"
            )
        if directive.get("always_install") is True and not pack_id.startswith("governance-kit/"):
            errors.append(
                f"{pack_dir}/{directive_id}: always_install: true is reserved to the "
                "governance-kit/* bundled packs"
            )
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
        # A directive's `check.sh` is the commit/CI-lane pass/fail test. The one
        # exemption: a schedule-only discovery directive selected explicitly
        # by `triggers: [schedule]` has no commit-lane gate, so there
        # is nothing for a commit-path script to test; it is judged only by
        # the at-rest scheduled driver re-adjudicating its `checks` against
        # the range diff. Every other directive still requires an executable
        # check.sh.
        script = directive_path / "check.sh"
        constitution = directive_path / "constitution.md"
        if script.is_file():
            if not os.access(script, os.X_OK):
                errors.append(f"{pack_dir}/{directive_id}: check.sh is not executable")
        elif not schedule_only:
            errors.append(f"{pack_dir}/{directive_id}: check.sh missing")
        if not constitution.is_file():
            errors.append(f"{pack_dir}/{directive_id}: constitution.md missing")
        elif script.is_file():
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

    return errors, warnings
