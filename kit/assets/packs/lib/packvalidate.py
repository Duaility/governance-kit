#!/usr/bin/env python3
"""Pack/directive manifest validation for packctl.py.

Split from packctl.py to keep both files under the repo-hygiene 500-line
limit (issue #355 cmd collapse landed the judge.cmd/group validation that
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
    DIRECTIVE_FIELDS,
    HOOK_STRATEGIES,
    HOOKS,
    PACK_FIELDS,
    JUDGE_CMD_LANES,
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


def judge_section_absent(judge: Any) -> bool:
    """True when a `judge:` block carries no `section:` — the schedule-only
    discovery lane (issue #355 amendment 3, renamed sweep->schedule per the
    scheduled-lane redesign). `section:` presence is now the ONLY thing that
    puts a declaration on the attest lane; the old `sink` field is deleted (a
    forbidden key, see `validate_judge_cmd`) because it carried no information
    `section` didn't already carry. Schedule-only declarations need no
    `check.sh` and no `surface:` (see callers below)."""
    return isinstance(judge, dict) and not scalar(judge.get("section"))


def validate_judge_cmd(
    pack_dir: Path, directive_id: str, judge: dict[str, Any]
) -> tuple[list[str], list[str], str | None, str | None]:
    """Validate a directive's `judge.cmd` map, `gate`, and lane-derivation
    fields (issue #355, cmd lane renamed sweep->schedule by the scheduled-lane
    redesign). Returns `(errors, warnings, group, schedule_cmd)`. `cmd` is
    optional; when present it is a map whose keys are exactly a subset of
    {attest, schedule} with non-empty scalar values. `schedule: harness` is
    an error — there is no live session at rest to spawn an in-session
    sub-agent. `tiers:` is a forbidden leftover of the retired tier
    vocabulary (v0, no deprecation lane). `isolation:` is likewise forbidden
    — batching is now expressed by the optional `group: <slug>` scalar
    instead of `isolation: shared|isolated`.

    Amendment 3: `sink:` is deleted — the lane is derived purely from whether
    `section:` is present (present = attest lane; absent = schedule-only
    discovery), so `sink` is now a forbidden key. `contest:` is folded into a
    three-valued `gate:` (`record` default, `verdict`,
    `verdict-contestable`) and is likewise forbidden. A `gate:` other than
    `record` requires `section:` — a verdict with nowhere to land is a
    declaration error. A schedule-only declaration carrying no `cmd.schedule`
    is the NORM, not a defect — bundled packs name no judge at all, and the
    scheduled workflow resolves one from its own `GOVERNANCE_JUDGE_CMD` env
    (exported by the generated `governance-schedule-<lane>.yml`) — so that
    case is silent. `group` and the resolved `cmd.schedule` string are
    returned so the caller can enforce the cross-directive "one group, one
    command" rule."""
    errors: list[str] = []
    warnings: list[str] = []
    prefix = f"{pack_dir}/{directive_id}"

    if "tiers" in judge:
        errors.append(
            f"{prefix}: judge.tiers is no longer supported — replace `tiers:` with `cmd:` "
            "(the tier vocabulary was retired in favor of a directly-named judge command, issue #355)"
        )
    if "isolation" in judge:
        errors.append(
            f"{prefix}: judge.isolation is no longer supported — replace `isolation: shared|isolated` "
            "with an optional `group: <slug>` scalar (batching is now keyed on byte-identical "
            "judge.cmd.schedule values within a shared group, issue #355)"
        )
    if "sink" in judge:
        errors.append(
            f"{prefix}: judge.sink is no longer supported — the lane is now derived from "
            "whether `section:` is present (present = attest lane, absent = sweep-only "
            "discovery); delete `sink:` (issue #355 amendment 3)"
        )
    if "contest" in judge:
        errors.append(
            f"{prefix}: judge.contest is no longer supported — it has been folded into "
            "`gate:`, which now accepts record (default), verdict, or verdict-contestable "
            "(issue #355 amendment 3)"
        )

    section = scalar(judge.get("section"))
    if "gate" in judge:
        gate = scalar(judge.get("gate"))
        if gate not in JUDGE_GATE_VALUES:
            errors.append(
                f"{prefix}: judge.gate has unknown value {gate!r} "
                f"(allowed: {', '.join(sorted(JUDGE_GATE_VALUES))})"
            )
        if gate != "record" and not section:
            errors.append(
                f"{prefix}: judge.gate: {gate} requires judge.section — a verdict with "
                "nowhere to land is a declaration error"
            )

    group: str | None = None
    if "group" in judge:
        raw_group = judge.get("group")
        if not isinstance(raw_group, str) or not raw_group.strip():
            errors.append(f"{prefix}: judge.group must be a non-empty string")
        else:
            group = raw_group.strip()

    cmd = judge.get("cmd")
    has_schedule_cmd = False
    schedule_cmd: str | None = None
    if cmd is not None:
        if not isinstance(cmd, dict):
            errors.append(f"{prefix}: judge.cmd must be a mapping")
        else:
            for key, value in cmd.items():
                if key not in JUDGE_CMD_LANES:
                    errors.append(
                        f"{prefix}: judge.cmd has unknown key {key!r} "
                        f"(allowed: {', '.join(sorted(JUDGE_CMD_LANES))})"
                    )
                    continue
                if not isinstance(value, str) or not value.strip():
                    errors.append(f"{prefix}: judge.cmd.{key} must be a non-empty string")
                    continue
                if key == "schedule":
                    if value.strip() == "harness":
                        errors.append(
                            f"{prefix}: judge.cmd.schedule cannot be 'harness' — the scheduled "
                            "lane runs at rest with no live session, so there is nobody to spawn "
                            "an in-session sub-agent"
                        )
                    else:
                        has_schedule_cmd = True
                        schedule_cmd = value.strip()

    return errors, warnings, group, schedule_cmd


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

    # group -> [(directive_id, schedule_cmd), ...] within THIS pack. A `group`
    # is a batching label: at schedule time every directive sharing a group is
    # meant to ride in the same call, so two directives in one group naming
    # different `cmd.schedule` strings is a contradiction — "a group is one
    # invocation, one command" (issue #355 amendment).
    group_schedule_cmds: dict[str, list[tuple[str, str | None]]] = {}

    for directive_id in sorted(directive_ids):
        directive_path = directives_root / directive_id
        directive = directive_manifest(pack_dir, directive_id)
        # A schedule-only discovery directive — a `judge:` block with no
        # `section:` (issue #355 amendment 3) — has no commit-lane script, so
        # the fields that describe commit-lane semantics (`surface`, and
        # check.sh below) don't apply to it. Resolved once, up front, because
        # both the required-field loop and the check.sh rule key off it.
        judge = directive.get("judge")
        schedule_only = judge_section_absent(judge)
        if isinstance(judge, dict):
            cmd_errors, cmd_warnings, group, schedule_cmd = validate_judge_cmd(pack_dir, directive_id, judge)
            errors.extend(cmd_errors)
            warnings.extend(cmd_warnings)
            if group is not None:
                existing = group_schedule_cmds.setdefault(group, [])
                existing.append((directive_id, schedule_cmd))
        for field in DIRECTIVE_FIELDS:
            if field == "surface" and schedule_only:
                continue
            if field not in directive or directive.get(field) in (None, ""):
                errors.append(f"{pack_dir}/{directive_id}: directive.yaml missing required field {field!r}")
        hook = scalar(directive.get("hook") or "none")
        surface = scalar(directive.get("surface"))
        hook_strategy = scalar(directive.get("requires_hook_strategy"))
        if hook not in HOOKS:
            errors.append(f"{pack_dir}/{directive_id}: unknown hook value {hook!r}")
        errors.extend(validate_triggers(pack_dir, directive_id, directive.get("triggers"), hook))
        if surface not in SURFACES and not (schedule_only and not surface):
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
        # exemption (issue #355 amendment 3): a schedule-only discovery
        # directive (the hoisted `schedule_only` above, i.e. `section:`
        # absent) has no commit-lane gate and no section to attest, so there
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

    for group, members in sorted(group_schedule_cmds.items()):
        distinct_cmds = {cmd for _directive_id, cmd in members if cmd is not None}
        if len(distinct_cmds) > 1:
            member_desc = ", ".join(f"{did}={cmd!r}" for did, cmd in members)
            errors.append(
                f"{pack_dir}: group {group!r} mixes different judge.cmd.schedule values "
                f"({member_desc}) — a group is one invocation, one command"
            )

    return errors, warnings
