<!-- last-verified: 2026-06-11 -->

# governance directive * — verb flows

Authoritative flow for the hand-authored directive verbs: `governance directive add`, `governance directive modify`, `governance directive remove`.

> **Routed verb — runs from the repo-pinned kit (issue #194).** The thin `governance` skill does not run `directive *` from its own machine copy. Resolve the kit the repo pins via `kit-current` (see [`../SKILL.md`](../SKILL.md) "Step R — Resolve the pinned kit") first, then run every engine and read every template from the resolved kit's `<lib_dir>` / `<assets_dir>`. See [DIRECTIVE_AMEND_FLOW.md](DIRECTIVE_AMEND_FLOW.md) for the full flow. When `kit-current` falls back to the installed skill, those paths are this machine copy.

## The atomic triple

Every directive amendment is **three logical changes, committed atomically**:

1. A directive folder at `.governance/packs/<pack-owner>/<pack-name>/directives/<directive-id>/` — `directive.yaml`, `check.sh`, `constitution.md` (+ optional `hooks/`, `lib/`, `runtimes/`, `install-assets/`).
2. A **Directives** subsection in `CONSTITUTION.md` — the human-readable directive + rationale + enforcement pointer.
3. A new entry in the `CONSTITUTION.md` **Evolution Log** — dated, one line per amendment.

A commit that touches the directive folder without the matching constitution edits (or vice versa) is a broken amendment. The atomic-triple flow refuses to finish with partial state on disk; `directive *` inherits that discipline.

## Pack targeting

`directive {add,modify,remove}` operate on a single pack. Two ways to specify the target:

- **`--pack <owner>/<name>`** — operate on the named pack. The pack must already exist at `.governance/packs/<owner>/<name>/` (use `governance pack create <name>` to scaffold a new repo-local pack first).
- **No `--pack`** — defaults to the **repo's own local pack** at `.governance/packs/<owner>/<repo>/` where `<owner>/<repo>` is read from the top-level `owner:` and `repo:` fields in `.governance/install.yaml` (set at `governance init` from the GitHub origin remote). The default pack is auto-created on first `directive add` if it doesn't exist yet.

`directive *` cannot target an *installed* community pack — those are owned by their lockfile entry; edit them by forking the upstream pack or by running `governance pack update`. The verbs detect installed-pack ownership via `.governance/packs.lock` (`source: gh`) and refuse to mutate them.

## `directive add <directive-id>`

- **Aliases a user might type:** "add a governance directive", "new directive", "amend the constitution", "add directive X", "add a frontend directive" (→ `--pack <owner>/frontend`).
- **Authoritative flow:** [DIRECTIVE_AMEND_FLOW.md](DIRECTIVE_AMEND_FLOW.md) Steps 1–7.
- **Assets used:**
  - [`../assets/amend/directive.template.sh`](../assets/amend/directive.template.sh) — `check.sh` skeleton.
  - [`../assets/amend/directive-section.template.md`](../assets/amend/directive-section.template.md) — constitution subsection skeleton.
  - [DIRECTIVE_AUTHORING.md](DIRECTIVE_AUTHORING.md) — naming conventions, check patterns, smoke-test guidance.
- **Config:** if the drafted directive needs tuning, ship a `config.conf` (overlay template) and, for a list-valued check, a `defaults.conf` in the directive folder, and seed `.governance/conf/<directive-id>.conf` from `config.conf` unless it already exists. Read both via the `lib.sh` helpers (`conf_get`, `conf_list`).
- **Preconditions:** governance-kit must already be installed (`CONSTITUTION.md` present with `Directives` + `Evolution Log` headings, `.governance/install.yaml` present with `owner:` and `repo:` set, `.governance/packs.lock` present). If the kit is missing, stop and route to `governance init`.
- **Smoke test before commit:** the drafted `check.sh` must pass against the current tree. If it fails on pre-existing violators, ask the single blocking question — **loosen** (which threshold), **grandfather** (add waivers to specific violators), or **block** (commit as-is, user fixes tree separately) — then act. Never ship a directive that red-lights HEAD.

## `directive modify <directive-id>`

- **Aliases a user might type:** "modify directive X", "tighten directive X", "loosen directive X", "update the check logic for X".
- **Authoritative flow:** same as `directive add`, but the existing directive folder and directive subsection are edited in place (preserving rationale unless the policy intent itself is changing). The owning pack is detected automatically by walking `.governance/packs/*/*/directives/<directive-id>/`; if the directive lives in more than one pack, require `--pack` to disambiguate.
- **Evolution Log requirement:** a modification is still an amendment — append a new log entry describing what changed and why. A directive whose check logic changes without a log entry is opaque to future maintainers.

## `directive remove <directive-id>`

- **Aliases a user might type:** "remove directive X", "retire directive X", "drop the directive about X".
- **Authoritative flow:** [DIRECTIVE_AMEND_FLOW.md](DIRECTIVE_AMEND_FLOW.md) — the removal branch at the end of Step 5.
- **Mechanics:**
  1. Resolve the owning pack (from `--pack`, the default `<owner>/<repo>`, or by scanning `.governance/packs/*/*/directives/<directive-id>/`) and delete `.governance/packs/<pack-owner>/<pack-name>/directives/<directive-id>/`, plus the directive's `.governance/conf/<directive-id>.conf` overlay if present.
  2. If that was the pack's last directive AND the pack is repo-local (`source: local` in the lockfile), also remove the pack's `pack.yaml` and the now-empty `<owner>/<name>/` directory, plus its lockfile entry via `packverb lock-remove .governance/packs.lock <pack-id>`.
  3. Remove the directive's **Directives** subsection from `CONSTITUTION.md`.
  4. Append an **Evolution Log** entry recording the removal date and reason.
  5. Surface any dangling references (mentions in `README.md`, `AGENTS.md`, CI config) so the user can clean them up.
  6. If the directive belongs to a `source: gh` (community) pack in `.governance/packs.lock`, this verb is the wrong tool — use `governance pack remove <pack-id>` instead so the lockfile stays consistent.

## Boundaries

- `directive *` mutates **repo-local** directives: things the user wrote for their own repo or for a hand-authored pack created via `governance pack create`. Directives installed via `governance pack add <community-pack>` are owned by the lockfile; edit them with `governance pack update` or by forking the upstream pack.
- `directive *` does **not** run CI. The atomic-triple flow commits the three artifacts; CI runs on the PR.
- When the user asks to "review" or "audit" directives rather than change one, answer directly rather than mutating files.
