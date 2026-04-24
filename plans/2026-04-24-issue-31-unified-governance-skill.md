<!-- last-verified: 2026-04-24 -->


# 2026-04-24 — Collapse skills to one `governance` verb surface + community packs

## Goal

Rearchitect governance-kit's skill surface around spec-kit as the north
star. Collapse the current mutating skills (`governance-bootstrap`,
`governance-amend`, `governance-reset`, plus proposed `governance-pack`)
into a single `governance` skill with verbs, and make community packs
first-class via a catalog + SHA-pinned install model.

Closes [#31](https://github.com/Duaility/governance-kit/issues/31).

## Scope for this PR

The parent issue explicitly splits the rework into 7 follow-up issues.
This PR lands **steps 1 and 2**:

1. **Pack contract formalization** — `pack.yaml` schema, `rule.yaml`
   capability schema (`reads:` / `writes:`), `min_governance_kit`
   enforcement against a built-in `KIT_VERSION` constant.
2. **Scaffold the new `governance` skill** with `init` and `uninstall`
   verbs ported from `governance-bootstrap` and `governance-reset`.

Also lands the community-catalog scaffold (`extensions/catalog.community.json`)
so the follow-up PRs that implement `governance pack *` verbs have a
target to point at.

## Non-goals for this PR

- Pack-authoring UX and `governance pack *` verbs — follow-up.
- Moving `agent-governance` out-of-tree — follow-up.
- Retiring `governance-bootstrap` / `governance-amend` / `governance-reset`
  — keep them in place until the verb surface reaches parity.
- Rethinking `governance-gardener` for the new shape — deferred per the
  issue.
- Semantic enforcement of capability declarations (install-time refusal
  when a rule reaches outside declared globs) — schema lands now, runtime
  check lands with `governance pack add`.

## Implementation notes

- `KIT_VERSION = "0.2"` is defined in `packctl.py` and surfaced to bash
  via a new `kit-version` subcommand and the `kit_version` shell helper.
  Packs that declare `min_governance_kit` newer than `KIT_VERSION` fail
  validation with a clear error.
- Capability fields are optional. If present, they must be lists of
  non-empty strings. Existing in-tree rules do not yet declare them —
  adding declarations to `core` and `agent-governance` rules is a
  mechanical follow-up that does not block the schema landing.
- The new `governance` skill's `SKILL.md` is a verb dispatcher. For
  `init` and `uninstall` it points at the detailed flows already in
  `governance-bootstrap/SKILL.md` and `governance-reset/SKILL.md` rather
  than duplicating them. `pack` and `rule` verbs are stubbed with a
  pointer to the tracking issue.
- The community catalog file is empty (`packs: []`) — it exists so
  follow-up PRs can start filling it without churning schema in every
  one.

## Out of scope clarifications

- SHA pinning of community packs, `.governance/packs.lock`, and
  diff-before-exec UX land with the `governance pack *` follow-up.
- Shared `~/.governance-kit/packs/<pack-id>@<sha>/` cache likewise.

## Progress

- Pack contract formalized (`KIT_VERSION`, capability schema,
  `min_governance_kit` enforcement).
- Community pack catalog scaffolded under `extensions/`.
- `governance/` skill scaffolded with `init` and `uninstall` verbs that
  delegate to the existing `governance-bootstrap` / `governance-reset`
  flows. `pack` and `rule` verbs stubbed with follow-up pointer to #31.
- `AGENTS.md` updated to route newcomers at the unified skill while the
  legacy skills remain in-tree as the authoritative flows.
- **Step 6 — soft retirement of legacy skills:** `governance-bootstrap`,
  `governance-amend`, and `governance-reset` now declare
  `status: retirement-in-progress` and `superseded-by: governance` in
  frontmatter, narrow their descriptions to internal-delegation language
  (so the unified skill wins activation), and carry a retirement notice
  linking to the unified skill. `AGENTS.md` and `README.md` reframe the
  per-lifecycle skills as retired internals owned by the unified skill.
  Physical deletion + asset relocation (moving
  `governance-bootstrap/assets/` under `governance/assets/` and inlining
  the delegated-to flows) is a follow-up PR — doing it here would
  break the current delegation and the dogfood install simultaneously,
  with no intermediate reviewable state. `governance-gardener` is out
  of scope per the issue itself.
- **Step 5 — agent-governance as a monorepo-hosted community pack:**
  Rejected the original plan of extracting `agent-governance` into a
  separate repo. Instead, the pack moved to `extensions/packs/agent-governance/`
  and adopted the scoped id `duaility/agent-governance`, authored and
  validated exactly as if it were a standalone community pack. The
  catalog entry in `extensions/catalog.community.json` points at
  `Duaility/governance-kit` with `source.path: extensions/packs/agent-governance`
  — the monorepo layout is a publishing convenience, not a contract
  difference. `packctl.py`'s validator now accepts scoped ids whose
  slug half matches the directory name (so `id: duaility/agent-governance`
  in a folder named `agent-governance` validates), and
  `scripts/test-packs.sh` walks both pack roots. `core` stays kit-bundled
  under `governance-bootstrap/assets/packs/core/` because it is an
  invariant part of the bootstrap surface, not a community extension.
- **Step 4 — `governance rule *` verbs:** `references/RULE_VERBS.md`
  documents `rule add`, `rule modify`, `rule remove`, delegating to
  `governance-amend/SKILL.md` Steps 1–6 for the atomic-triple flow
  (rule folder + constitution subsection + Evolution Log entry landing
  as one commit). `SKILL.md` promotes these verbs from "coming soon"
  to active dispatch and adds them to the trigger table; the skill
  frontmatter now advertises rule-amendment aliases so the unified
  skill fires on "add a rule" / "amend the constitution" / "new
  invariant" without needing to mention `governance-amend` by name.
- **Step 7 — physical retirement of legacy skills:** `governance-bootstrap/`,
  `governance-amend/`, and `governance-reset/` are deleted. Their assets
  (`assets/packs/`, `assets/amend/`, plus each skill's `evals/`) moved under
  `governance/assets/` and `governance/evals/`; their `references/` merged
  into `governance/references/`; the per-lifecycle SKILL.md prose was
  ported into three flow references — `INIT_FLOW.md`, `UNINSTALL_FLOW.md`,
  `RULE_AMEND_FLOW.md` — that the unified `governance/SKILL.md` now
  points at directly (no more delegation). Every live reference to
  `governance-bootstrap/`, `governance-amend/`, `governance-reset/` paths
  has been rewritten; historical snapshots (`plans/*`, `CONSTITUTION.md`
  evolution log, `QUALITY.md` debt log) retain their original paths as
  frozen history. `AGENTS.md`, `README.md`, and `ARCHITECTURE.md` now
  describe only `governance/` and `governance-gardener/`. Both
  `scripts/test-packs.sh` and `tests/governance/run.sh` pass green after
  the move.
- **Step 3 — `governance pack *` verbs:** `packctl` now owns ref parsing
  (`gh:owner/repo[/subpath][@rev]`), shared-cache resolution
  (`${GOVERNANCE_KIT_HOME:-$HOME/.governance-kit}/packs/<id>@<sha>/`),
  shallow git fetch with SHA pinning, static capability-glob enforcement
  (`reads:`/`writes:` vs. paths referenced in `check.sh`), lockfile I/O
  on `.governance/packs.lock`, and catalog search. Per-verb flow recipes
  land in `governance/references/PACK_VERBS.md`; `SKILL.md` promotes the
  verbs from "coming soon" to live and points the dispatch table at them.
