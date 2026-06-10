#!/usr/bin/env python3
"""Argparse registration for the deterministic lifecycle plan/apply commands.

The `governance` skill invokes these as `packverb.py <verb> …`; packverb.py
delegates the subparser wiring here so it stays focused on the fetch/lockfile/
capability plumbing the engines compose. Each engine lives in its own module
(pack{plan,apply}.py, reset{plan,apply}.py, uninstall{plan,apply}.py) and is
imported lazily at registration time — the engines import packverb/packctl, so a
top-level import here would be a cycle. Issue #172.
"""

from __future__ import annotations

import argparse


def register_lifecycle(sub: argparse._SubParsersAction) -> None:
    # pack-plan / pack-apply — `governance pack {add,update,remove}`.
    p = sub.add_parser("pack-plan")
    p.add_argument("mode", choices=["add", "update", "remove"])
    p.add_argument("root")
    p.add_argument("target", nargs="?", default=None)
    p.add_argument("--diff", action="store_true")
    from packplan import cmd_pack_plan
    p.set_defaults(func=cmd_pack_plan)

    p = sub.add_parser("pack-apply")
    p.add_argument("mode", choices=["add", "update", "remove"])
    p.add_argument("root")
    p.add_argument("target", nargs="?", default=None)
    p.add_argument("--decisions", default=None)
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--force", action="store_true")
    from packapply import cmd_pack_apply
    p.set_defaults(func=cmd_pack_apply)

    # reset-plan / reset-apply — restore directives to the SHA pinned in packs.lock.
    p = sub.add_parser("reset-plan")
    p.add_argument("scope", choices=["directive", "pack", "all"])
    p.add_argument("root")
    p.add_argument("target", nargs="?", default=None)
    p.add_argument("--drop-handauthored", action="store_true")
    p.add_argument("--diff", action="store_true")
    from resetplan import cmd_reset_plan
    p.set_defaults(func=cmd_reset_plan)

    p = sub.add_parser("reset-apply")
    p.add_argument("scope", choices=["directive", "pack", "all"])
    p.add_argument("root")
    p.add_argument("target", nargs="?", default=None)
    p.add_argument("--drop-handauthored", action="store_true")
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--force", action="store_true")
    p.add_argument("--date", default=None)
    p.add_argument("--author", default=None)
    from resetapply import cmd_reset_apply
    p.set_defaults(func=cmd_reset_apply)

    # uninstall-plan / uninstall-apply — reverse every init side-effect.
    p = sub.add_parser("uninstall-plan")
    p.add_argument("root")
    p.add_argument("--mode", choices=["dry-run", "soft", "hard"], default="soft")
    from uninstallplan import cmd_uninstall_plan
    p.set_defaults(func=cmd_uninstall_plan)

    p = sub.add_parser("uninstall-apply")
    p.add_argument("root")
    p.add_argument("--mode", choices=["dry-run", "soft", "hard"], default="soft")
    p.add_argument("--allow-heuristic", action="store_true")
    from uninstallapply import cmd_uninstall_apply
    p.set_defaults(func=cmd_uninstall_apply)
