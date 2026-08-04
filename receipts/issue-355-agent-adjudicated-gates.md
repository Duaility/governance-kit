# issue-355: feat(kit): agent-adjudicated gates + native-cost accounting

Closes [#355](https://github.com/Duaility/governance-kit/issues/355).

## Checklist

- [x] Port the sub-agent attestation machinery in lib.sh to pure bash (Phase 0)
- [x] Ship `gate: verdict` — blocking adjudication log, freshness stamp, escalation ladder (Phase 1)
- [x] Wire the sweep engine to read `subagent:` declarations directly (Phase 2)
- [x] Add the executor abstraction — harness | cli:<adapter> | api:<provider> (Phase 3)
- [x] Generalize batching across the commit lane and the sweep engine (Phase 4)
- [x] Replace the hand-rolled accounting Python with native-cost runtime adapters and Costs schema v5 (Track B)
- [x] Eliminate PyYAML and uv via a restricted-YAML stdlib parser; port managed-tree-integrity to bash (Q11)
- [x] Ship the dependency-posture directives — no-commit-path-python, stdlib-only-python, no-package-manager (Q11)

## What changed

One PR implements the whole #355 umbrella. Each phase below names its files; a
complete path list is in the Files appendix.

**Phase 0 — lib.sh goes pure bash.** The three python3 heredocs in
`kit/assets/dot-governance/lib.sh` (`_subagent_yaml`, `_subagent_tier`,
`attestation_remediation`) are ported to bash + POSIX awk with byte-identical
output (verified against an edge-case corpus and every shipped
`directive.yaml`). The commit path now contains zero Python.

**Phase 1 — `gate: verdict`.** The `subagent:` declaration gains author-owned
`gate: record|verdict` (record stays the default; no shipped directive is
flipped), `sink: section|none`, and `contest: forbid|allow`. A verdict-gated
section carries an append-only adjudication log — one line per round,
`- [round N] VERDICT tier=<t> stamp=<12-hex> — <reason>` — and the gate blocks
the commit unless the latest round is PASS with a fresh stamp.
`_adjudication_stamp` binds a verdict to the staged tree minus the receipt plus
the receipt's log-stripped content, so appending rounds never invalidates a
stamp but any other edit forces re-adjudication. A deterministic append-only
guard fails the commit if any REFUTED/ESCALATED/CONTESTED round present in the
base version of the receipt is scrubbed. The escalation ladder runs
`SUBAGENT_ROUNDS` (default 3, floor 2) rounds: attest tier, attest tier, then
high tier; a final refutal stalls the commit and surfaces the dispute to the
human via an ESCALATED terminal entry. Contested-proceed is a per-directive
opt-in (`contest: allow`), loudly flagged and re-adjudicated by sweep.

**Phase 2 — sweep reads `subagent:`.** `kit/assets/dot-governance/sweep.py`
discovers any directive whose `subagent:` block has a sweep tier other than
`none`/`off`, triages the receipts touched in range as whole-file hunks, and
derives the rubric from the declaration's `checks:` — plus standing rubric
lines for verdict-gated directives (a missing, malformed, or pruned
adjudication log is itself a violation; CONTESTED verdicts are re-adjudicated
on merits). Legacy `surface: sweep` directives (triage.sh + constitution.md)
are unchanged.

**Phase 3 — executor abstraction.** A kit-level runtime adapter registry at
`kit/assets/dot-governance/runtimes/` (claude-code.sh, codex.sh, manual.sh) is
seeded into consumer repos as `.governance/runtimes/<name>.sh`, managed and
digest-guarded like lib.sh. Each adapter speaks two verbs: `cost` (emit the
harness's own reported session usage) and `judge` (read a declaration-built
prompt on stdin, run the CLI non-interactively, answer `VERDICT: PASS|REFUTED`
plus `REASON:` lines). `SUBAGENT_EXECUTOR=cli:<adapter>` (conf-resolved,
default `harness`) lets a different-vendor CLI adjudicate a verdict gate
in-hook — separation of duties against shared-model failure modes — with
per-tier model selection via `SUBAGENT_MODELS_LOW/MEDIUM/HIGH`. Every failure
path (missing CLI, transport error, malformed answer) degrades to the harness
remediation loop; a commit never hard-fails because a CLI is absent.

**Phase 4 — generalized batching.** The commit-lane orchestrator groups shared
judgments by executor as well as isolation (ledger rows carry an executor
field; legacy rows keep parsing), and the sweep engine batches multiple
subagent-declared directives targeting the same receipt into one API call with
a per-violation `directive` field, demultiplexed back into per-directive digest
sections. The sweep lane retries a failed judgment once before counting it
un-adjudicated; the commit lane's cli executor does not retry — any failure
there degrades to the harness remediation loop, which is its recovery path.

**Track B — native-cost accounting.** The audit pack's re-derivation layer is
deleted: `ledger.py`, `rates.py`, `endpoint.py`, `reconcile.py`, `validate.py`,
`receipt_io.py`, `argv.py` in agent-token-accounting and `ledger.py` +
`receipt_io.py` in agent-steering-accounting (~1,900 lines of commit-path
Python), along with every `rate` row in the rate card. The commit path is now
bash/awk: `lib/costs.sh`, `lib/validate.sh`, `lib/endpoint.sh`,
`lib/receipt.sh` (token), `lib/steering.sh` + `lib/receipt.sh` (steering).
Adapters emit the harness's own reported usage; `cost-usd` is the
harness-reported figure verbatim or blank — the kit never prices, and the
unpriced-model-blocks-commit failure mode is gone. Receipt Costs schema is v5
(17 columns, new `source` column naming the adapter); v1–v4 rows still parse
under their own rules. Endpoint freezing keyed to `git write-tree` and
per-session checkpoints survive as flat key=value files. `report.py` stays as
an off-commit-path stdlib utility. macOS argv recovery falls back to
`ps -ww -o args=` (UTF-8 caveat documented inline).

**Q11 — dependency endgame.** New stdlib restricted-YAML parser/writer
`kit/assets/packs/lib/kityaml.py` replaces PyYAML across the lifecycle verbs
(`packctl.py`, `packverb.py` — with byte-for-byte `dump(load(x))` parity
against the real packs.lock); every `uv run --with PyYAML` incantation in
`packs.sh`, `install.sh`, scripts, and CI becomes a bare `python3` (the
setup-uv step is removed from `.github/workflows/tests.yml`).
`managed-tree-integrity` is ported to pure bash (`lib/digest.sh`, byte-pinned
to `digestlib.py` by `scripts/test-digestlib.py`); `lib/integrity.py` is
deleted. Three opt-in foundation directives (strict preset) enforce the
posture: `no-commit-path-python`, `stdlib-only-python`, `no-package-manager` —
a consumer repo needs nothing but bash + git to commit; the kit's own tooling
needs nothing but a bare python3; nothing needs a package manager.

**Install/update plumbing.** `applylib.py` gains the adapter enumeration and
widens `selects_sweep_directive` so a `subagent:` declaration with a live
sweep tier vendors the sweep lane; `initapply.py`/`kitverb.py` seed and
inventory the registry; `digestlib.py` records adapter digests;
`eval-lib.sh` installs the registry into eval fixtures; `install.sh` reads
directive scalars with awk instead of a PyYAML heredoc.

**Tests.** New layers `scripts/test-subagent.sh` (140 assertions: parser
parity, remediation grouping, stamp, gate, ladder, executor dispatch) and
`scripts/test-kityaml.py` (grammar, coercion, byte parity, corpus walk);
`scripts/test.sh` runs every Python layer on bare python3;
`test-runtime.sh`, `test-digestlib.py`, `test-init.py`, `test-kitverb.py`,
`test-sweep.py`, `test-packs.sh`, `test-schema-split.sh` updated in place.
Directive evals rewritten for the bash stacks (token 34, steering 18
assertions) including adapter-extraction fixtures pinning each harness's
native-output parsing. Verified under bash 3.2 and both BSD awk and mawk.

**Docs.** `SUBAGENT_ATTESTATION.md` (adjudicated gates, executors),
`SWEEP_FLOW.md` (subagent-declared path), `LIB_API.md`, `INSTALL_SCHEMA.md`,
`UNINSTALL_MATRIX.md`, `UPDATE_FLOW.md`, `INIT_FLOW.md`,
`DIRECTIVES_CATALOG.md`, `PACK_AUTHORING.md`, README dependency statement,
site concepts (`audit-chain.mdx`, `runtime.mdx`), directive constitution.md
snippets, and the regenerated `docs/reference/*` pages.

## Out of scope

- **Flipping any shipped directive to `gate: verdict`.** Existing declarations
  keep `gate: record` semantics untouched; the first adjudicated directive
  opts in later (and must then ship the SUBAGENT_ROUNDS/SUBAGENT_EXECUTOR/
  SUBAGENT_MODELS_* rows in its defaults.conf).
- **Updating the consumed `.governance/` tree.** It stays pinned at the last
  release and catches up via the real `pack update`/`governance update` verbs
  in the post-release dogfood-sync PR, never by hand.
- **Version bumps and floors.** Version lines move only in `chore(release)`
  commits. Release-time notes: the audit pack's `min_governance_kit` must rise
  to the first kit tag shipping the adapter registry (its `lib/runtime.sh` now
  resolves `.governance/runtimes/`), and the kit/audit/foundation axes all
  have releasable changes here.
- **Migrating pre-#355 local caches.** Legacy JSON endpoint/checkpoint files
  under `.git/` are ignored, not migrated — disposable local state; a stale
  one costs one zero-delta row.
- **CONSTITUTION.md.** This repo's live constitution reflects the installed
  (pinned) directive set; the updated pack `constitution.md` snippets land in
  it at the next release via the real verbs.

## Decisions

- **The stamp reads the worktree receipt, normalized.** Stamping the staged
  blob broke the bootstrap round (the section a sub-agent just wrote isn't in
  the index yet, so its own stamp was permanently stale); the stamp therefore
  hashes the staged tree minus the receipt, joined with the receipt's
  round-line-stripped content. Appending rounds never invalidates a verdict;
  editing any other receipt prose or any staged file does.
- **The append-only guard checks HEAD and the merge-base union.** lib.sh
  cannot detect Mode A vs Mode B; the union of both bases is strictly the
  safer reading and collapses to one rev in the common case.
- **`gate: record` never reaches a cli executor.** A record section is an
  authored narrative with an author, not a verdict with a judge; only
  verdict gates dispatch to `cli:<adapter>`.
- **Verbatim-or-blank beats estimated.** Where a harness reports tokens but no
  dollar figure, `cost-usd` stays blank. Receipts trade a kit-guessed number
  for an honest empty cell; the rate card and its stale-pricing and
  unknown-model-blocks-commit failure modes are deleted outright.
- **Full-bash lifecycle was rejected; restricted YAML was not.** The plan/apply
  engines stay stdlib Python (porting ~3k lines of structured-data logic to
  bash relocates complexity into quoting bugs), but every YAML file the kit
  itself writes is declared restricted — flat maps, block/flow lists, flow
  maps, no anchors or block scalars — so one small stdlib parser replaces
  PyYAML everywhere, enforced loud-failing on anything outside the grammar.
- **Adapters are eval-gated.** Each harness adapter ships fixtures pinning its
  native-output extraction, and the `manual` adapter is the deterministic eval
  seam for the judge verb — "no eval, no ship" extends to executors.

## Verification

```sh
bash scripts/test.sh          # all 22 kit-internal layers
bash .governance/run.sh       # the dogfood suite (pinned release directives)
node scripts/docs-site/gen-reference.mjs --check
```

Results:

- Port the sub-agent attestation machinery in lib.sh to pure bash (Phase 0) — done; `grep python kit/assets/dot-governance/lib.sh` hits only a comment, and `scripts/test-subagent.sh` pins parser parity (140 assertions, green under bash 3.2 and mawk).
- Ship `gate: verdict` — blocking adjudication log, freshness stamp, escalation ladder (Phase 1) — done; gate end-to-end cases (missing log, stale stamp, scrubbed round, contested, ladder rendering) all covered in `scripts/test-subagent.sh`.
- Wire the sweep engine to read `subagent:` declarations directly (Phase 2) — done; `python3 scripts/test-sweep.py` runs 33 tests including an end-to-end subagent-only directive discovery→triage→adjudicate→file.
- Add the executor abstraction — harness | cli:<adapter> | api:<provider> (Phase 3) — done; registry seeding verified by `test-init.py`/`test-kitverb.py`, judge dispatch + degrade paths by `test-subagent.sh` and `test-runtime.sh` (139 assertions).
- Generalize batching across the commit lane and the sweep engine (Phase 4) — done; executor-aware grouping and batch demux/retry covered in the same suites.
- Replace the hand-rolled accounting Python with native-cost runtime adapters and Costs schema v5 (Track B) — done; token eval 34 assertions, steering eval 18, both green under BSD awk and mawk; a real pre-commit smoke wrote a v5 row, froze the endpoint, advanced the checkpoint.
- Eliminate PyYAML and uv via a restricted-YAML stdlib parser; port managed-tree-integrity to bash (Q11) — done; `git grep "import yaml"` over shipped code returns nothing, `scripts/test-kityaml.py` proves packs.lock byte parity, `scripts/test-digestlib.py` pins bash/python digest parity, and CI no longer installs uv.
- Ship the dependency-posture directives — no-commit-path-python, stdlib-only-python, no-package-manager (Q11) — done; all three evals green inside `scripts/test-packs.sh` (18 directive evals total).

`bash scripts/test.sh` → "✓ all kit-internal test layers passed" on the final
integrated tree.

## Audit

1. **`## What changed` faithfully describes the diff — PASS.** The large majority of claims verify directly against the staged diff: `grep -n python kit/assets/dot-governance/lib.sh` hits only a comment (line 265); `git diff --cached --diff-filter=D -- packs/audit` shows exactly the eleven deleted files named (`ledger.py`×2, `rates.py`, `endpoint.py`, `reconcile.py`, `validate.py`, `receipt_io.py`×2, `argv.py`, and the two `runtimes/*.sh` under `agent-token-accounting`); `kit/assets/packs/lib/kityaml.py` exists (627 new lines) and both `packctl.py` and `packverb.py` `import kityaml` and call `kityaml.load`/`kityaml.dump`; `sweep.py` gained a full `subagent:`-block reader (`_subagent_block_lines`, `_subagent_gate`, `_subagent_rounds_resolve`, etc.) plus a batched-call path (`_build_batch_rubric`/`_demux_batch_violations`); the three new foundation directive folders (`no-commit-path-python`, `no-package-manager`, `stdlib-only-python`) exist fully populated (check.sh/constitution.md/defaults.conf/directive.yaml/evals); the runtime registry (`claude-code.sh`, `codex.sh`, `manual.sh`) exists at `kit/assets/dot-governance/runtimes/` with `cost`/`judge` verbs in each; `.github/workflows/tests.yml` lost exactly the `astral-sh/setup-uv` step (confirmed via `git diff --cached`); `git grep "import yaml"` over `kit/ packs/ skill/` returns nothing but a doc comment; `bash scripts/test.sh` (run fresh in this audit) exits 0 with "✓ all kit-internal test layers passed", including the 18 packs evals, 139 `test-runtime` assertions, and the full `test-subagent`/`test-kityaml`/`test-digestlib` suites named in the receipt. `node scripts/docs-site/gen-reference.mjs --check` also passes clean. The Phase 4 paragraph's retry sentence — now "The sweep lane retries a failed judgment once before counting it un-adjudicated; the commit lane's cli executor does not retry — any failure there degrades to the harness remediation loop, which is its recovery path." — matches the code exactly: sweep.py's `_adjudicate_retrying` (line 314) calls the judge function, and on `adjudicated: False` calls it exactly once more before the caller counts the hunk `un-adjudicated` (the docstring: "one retry on a transport/parse failure... before the caller counts the hunk as un-adjudicated"); the commit-lane analog, `_subagent_cli_adjudicate` in `lib.sh` (lines 903–963), is called exactly once from the `gate: verdict` path (lines 1053–1057) with no retry loop, and on any failure (missing adapter, exhausted round budget, transport error, or an unparseable `VERDICT:` line) returns 1 immediately, at which point the caller falls back straight to the harness sub-agent path (marking the row `executor+fallback`) — precisely the "degrades to the harness remediation loop" recovery path the corrected sentence now describes, and the commit lane correctly has no "un-adjudicated" bookkeeping (that concept, and the `unadjudicated`/`sub_unadjudicated` lists, remain sweep-only, which the sentence no longer claims otherwise). The underlying Phase 4 work (executor-keyed batching in `attestation_remediation`, verified directly by reading lines 1136–1300 of `lib.sh`) is real and correctly described.
2. **Each `- [x]` Checklist item is realized in the diff — PASS (8 of 8).** (1) lib.sh bash port — confirmed, zero python invocations left, `test-subagent.sh`'s "sub-agent judgment" suite (visible in the fresh `scripts/test.sh` run) exercises `_subagent_yaml`/`_subagent_tier`/`attestation_remediation` end to end. (2) `gate: verdict` — `_subagent_verdict_gate`, `_SUBAGENT_ROUND_RE`, `_adjudication_stamp`, `SUBAGENT_ROUNDS` ceiling, and the escalation-round logic (`eff_tier="high"` at `rounds >= ceiling-1`) are all present and covered by the "gate: verdict (end to end)" and "escalation ladder" test groups. (3) sweep reads `subagent:` — confirmed above; `python3 scripts/test-sweep.py` ran clean inside `scripts/test.sh`. (4) executor abstraction — `SUBAGENT_EXECUTOR` conf resolution (`harness | cli:?*` else degrade to harness), the registry-seeding tests (`test_apply_adds_the_runtime_registry_to_a_pre_registry_install`, `test_init_apply_seeds_the_runtime_adapter_registry`) and adapter-eval fixtures all present and green. (5) generalized batching — `attestation_remediation`'s executor-keyed grouping (`ekeys`/`group` loop, lines ~1136–1172) is real and matches the claim, and the retry-symmetry description now matches the code per finding 1. (6) native-cost accounting / Costs v5 — `packs/audit/directives/agent-token-accounting/lib/costs.sh` declares `COSTS_COLS_V5=17` and a `source` column; the old Python accounting libs are deleted as claimed. (7) PyYAML/uv elimination — `git grep -n "uv run\|astral-sh/setup-uv"` over `kit/ packs/ skill/ .github/ scripts/` returns only doc/comment/eval-fixture hits, none live; `managed-tree-integrity/lib/integrity.py` is deleted and `lib/digest.sh` added, parity-pinned by `scripts/test-digestlib.py` (19 assertions, both bash and python variants, all green in the fresh run). (8) the three posture directives ship with populated eval suites (18 total pack evals reported, matches `scripts/test.sh`'s "3 pack(s), 18 directive(s), 18 eval(s) passed" line from the fresh run).
3. **The `## Checklist` mirrors the issue's stated scope — PASS.** Issue #355 is a prose umbrella (Q1–Q11, no literal `- [ ]` list); its "Recommendation" call-outs under Q9 (Phasing) name Phase 0–4 exactly as the receipt's checklist items 1–5 do, Q10 is Track B (checklist item 6), and Q11 is the dependency endgame (checklist items 7–8, matching Q11's explicit `no-commit-path-python` / `stdlib-only-python` / `no-package-manager` naming and its PyYAML/uv elimination plan). No named phase, question recommendation, or Q11 deliverable is missing from the checklist. The receipt's own "Out of scope" section additionally discloses the two items a reader might expect but that the issue itself does not mandate for this PR (flipping any shipped directive to `gate: verdict`, and updating the consumed `.governance/` tree) — consistent with Q3's "existing directives are untouched until they opt in" and this repo's documented dogfood-lags-by-one-release convention.

## Layer boundaries

1. **Every changed file sits in the layer its role belongs to — PASS.** `kit/assets/dot-governance/{lib.sh,sweep.py,runtimes/*}` and `kit/assets/packs/lib/*.py` are kit engine/runtime code, correctly under `kit/`. The three new directives (`no-commit-path-python`, `no-package-manager`, `stdlib-only-python`) and the accounting/integrity rewrites are pack-owned directive content, correctly under `packs/foundation/directives/` and `packs/audit/directives/`. Tests live under `scripts/`. The one notable relocation — `packs/audit/directives/agent-token-accounting/runtimes/{claude-code,codex}.sh` moving to `kit/assets/dot-governance/runtimes/` — matches its own stated rationale, confirmed by reading `lib/runtime.sh`'s header comment verbatim: "Adapters are KIT-level, not pack-level (issue #355): one registry at `.governance/runtimes/<runtime>.sh`, shared by this directive's `cost` verb and lib.sh's `judge` verb, because 'which harness am I talking to' is one fact about the repo, not a per-directive one." That is a correct architectural call: the registry now serves two independent consumers (accounting's `cost` verb and the commit gate's `judge` verb via `cli:<adapter>`), so kit-level ownership is the right layer, not a leftover of one directive.
2. **No dependency points the wrong way across a layer edge — PASS.** `grep -rn "packs/audit\|packs/foundation\|packs/commits\|packs/docs" kit/` (excluding markdown) returns nothing — no kit code references a pack path. The reverse edge (pack → kit) is present but honest and floor-documented: `packs/audit/directives/agent-token-accounting/lib/runtime.sh`'s `_runtime_adapter_dir()` resolves the registry through an explicit fallback chain — `.governance/runtimes` (the installed, kit-managed location) first, falling through to the kit source tree (`.../kit/assets/dot-governance/runtimes`) only for the uninstalled-checkout case — exactly the "installed tree" resolution pattern every other directive in this repo already uses to reach `lib.sh`, and it is backed by `packs/audit/pack.yaml`'s `min_governance_kit: "0.12.0"` floor. This is the pack depending on an artifact the kit ships to every installed consumer, not the pack reaching into kit source at authoring time — consistent with `ARCHITECTURE.md`'s "kit consumes packs" arrow describing build/authoring dependencies, not the installed runtime layout every directive already assumes.
3. **New shared logic lives in the layer that owns it — PASS, including the deliberate exception.** The runtime registry (shared cost+judge logic) was correctly relocated to kit ownership per finding 1, not left duplicated per-pack. The one place logic *is* duplicated — `packs/audit/directives/agent-token-accounting/lib/receipt.sh` and `packs/audit/directives/agent-steering-accounting/lib/receipt.sh` (155 and 161 lines, near-identical `diff` shows only header-comment and directive-name differences) — is explicitly labelled as intentional in the steering copy's own header: "This file is deliberately a verbatim twin of the one in the sibling agent-token-accounting directive: a directive folder installs as a self-contained unit, so shared plumbing is duplicated rather than reached across directive boundaries... Keep the two in sync when either changes." This matches the task framing's instruction to judge the convention on its own terms (self-contained-directive-folder is a documented repo convention, confirmed in `AGENTS.md`'s "Directive folders are self-contained. Relocating a directive is one `git mv`" invariant and `ARCHITECTURE.md`'s "Invariants" section) rather than fault it for not being deduplicated into a shared kit lib.

## Steering

1. **Every human-steering event is recorded — PASS (none owed).** Extracting real user-authored text from the session transcript (`/Users/srikanth/.claude/projects/-Users-srikanth-gitspace-governance-kit--claude-worktrees-governance-kit-issue-355-d2b39d/1419af64-024c-4b9a-97ec-a471fe4c95b5.jsonl`, 325 lines) with a filter that drops any content starting with `<` (task-notification/system-block markup) yields exactly **one** genuine user message in the entire session, at 1-based line 3: the initial task assignment — "can you please work on the entire scope of https://github.com/Duaility/governance-kit/issues/355 and create PR ...no follow up issue splease unless really needed. Act as orcehstrator and span opus/sonnet/haiku subagents depending on your decision..." This is task-setting, not steering (explicitly excluded by the directive's own definition — an interrupt or a message that redirects/corrects the agent *mid-task*). Every other `type: user` entry in the transcript (checked at lines 45, 61, 70, 79, 141, 149, 159, 167, 178, 186, 255, 296, and all others found by a broader unfiltered scan) is a `<task-notification>` block — an automated "Agent X finished" completion event from a spawned sub-agent, not human input. No interrupt marker (`[Request interrupted by user for tool use]` or similar) and no second free-text human message appear anywhere in the file. Since the only real user message is the initial task assignment, no steering rows are owed, and the absent `### Steering` table (there is currently no `## Accounting` section at all, consistent with the accounting hook not having run yet on this staged commit) is correct as-is.
2. **No non-steering message is recorded as a steering event — PASS (vacuously; nothing is recorded).** No `## Accounting` / `### Steering` section exists yet in this receipt to check for false positives, and per finding 1 none should be added.

## Files

Every path touched by this change set (excluding this receipt):

- .github/workflows/tests.yml
- docs/concepts/audit-chain.mdx
- docs/concepts/runtime.mdx
- docs/guide/quickstart.mdx
- docs/reference/authoring-packs.mdx (regenerated)
- docs/reference/directive-catalog.mdx (regenerated)
- docs/reference/schemas.mdx (regenerated)
- kit/assets/dot-governance/lib.sh
- kit/assets/dot-governance/runtimes/claude-code.sh
- kit/assets/dot-governance/runtimes/codex.sh
- kit/assets/dot-governance/runtimes/manual.sh
- kit/assets/dot-governance/sweep.py
- kit/assets/packs/lib/applylib.py
- kit/assets/packs/lib/digestlib.py
- kit/assets/packs/lib/eval-lib.sh
- kit/assets/packs/lib/initapply.py
- kit/assets/packs/lib/install.sh
- kit/assets/packs/lib/kityaml.py
- kit/assets/packs/lib/kitverb.py
- kit/assets/packs/lib/packctl.py
- kit/assets/packs/lib/packs.sh
- kit/assets/packs/lib/packverb.py
- kit/assets/receipt.bootstrap.template.md
- kit/references/DIRECTIVES_CATALOG.md
- kit/references/INIT_FLOW.md
- kit/references/INSTALL_SCHEMA.md
- kit/references/LIB_API.md
- kit/references/PACK_AUTHORING.md
- kit/references/SUBAGENT_ATTESTATION.md
- kit/references/SWEEP_FLOW.md
- kit/references/UNINSTALL_MATRIX.md
- kit/references/UPDATE_FLOW.md
- packs/audit/directives/agent-steering-accounting/README.md
- packs/audit/directives/agent-steering-accounting/check.sh
- packs/audit/directives/agent-steering-accounting/constitution.md
- packs/audit/directives/agent-steering-accounting/directive.yaml
- packs/audit/directives/agent-steering-accounting/evals/test.sh
- packs/audit/directives/agent-steering-accounting/lib/ledger.py (deleted)
- packs/audit/directives/agent-steering-accounting/lib/receipt.sh
- packs/audit/directives/agent-steering-accounting/lib/receipt_io.py (deleted)
- packs/audit/directives/agent-steering-accounting/lib/steering.sh
- packs/audit/directives/agent-token-accounting/README.md
- packs/audit/directives/agent-token-accounting/check.sh
- packs/audit/directives/agent-token-accounting/constitution.md
- packs/audit/directives/agent-token-accounting/defaults.conf
- packs/audit/directives/agent-token-accounting/directive.yaml
- packs/audit/directives/agent-token-accounting/evals/test.sh
- packs/audit/directives/agent-token-accounting/hooks/pre-commit.sh
- packs/audit/directives/agent-token-accounting/lib/argv.py (deleted)
- packs/audit/directives/agent-token-accounting/lib/costs.sh
- packs/audit/directives/agent-token-accounting/lib/endpoint.py (deleted)
- packs/audit/directives/agent-token-accounting/lib/endpoint.sh
- packs/audit/directives/agent-token-accounting/lib/ledger.py (deleted)
- packs/audit/directives/agent-token-accounting/lib/rates.py (deleted)
- packs/audit/directives/agent-token-accounting/lib/receipt.sh
- packs/audit/directives/agent-token-accounting/lib/receipt_io.py (deleted)
- packs/audit/directives/agent-token-accounting/lib/reconcile.py (deleted)
- packs/audit/directives/agent-token-accounting/lib/report.py
- packs/audit/directives/agent-token-accounting/lib/runtime.sh
- packs/audit/directives/agent-token-accounting/lib/validate.py (deleted)
- packs/audit/directives/agent-token-accounting/lib/validate.sh
- packs/audit/directives/agent-token-accounting/runtimes/claude-code.sh (moved to kit/assets/dot-governance/runtimes/)
- packs/audit/directives/agent-token-accounting/runtimes/codex.sh (moved to kit/assets/dot-governance/runtimes/)
- packs/foundation/directives/managed-tree-integrity/check.sh
- packs/foundation/directives/managed-tree-integrity/constitution.md
- packs/foundation/directives/managed-tree-integrity/evals/test.sh
- packs/foundation/directives/managed-tree-integrity/lib/digest.sh
- packs/foundation/directives/managed-tree-integrity/lib/integrity.py (deleted)
- packs/foundation/directives/no-commit-path-python/check.sh
- packs/foundation/directives/no-commit-path-python/constitution.md
- packs/foundation/directives/no-commit-path-python/defaults.conf
- packs/foundation/directives/no-commit-path-python/directive.yaml
- packs/foundation/directives/no-commit-path-python/evals/test.sh
- packs/foundation/directives/no-package-manager/check.sh
- packs/foundation/directives/no-package-manager/constitution.md
- packs/foundation/directives/no-package-manager/defaults.conf
- packs/foundation/directives/no-package-manager/directive.yaml
- packs/foundation/directives/no-package-manager/evals/test.sh
- packs/foundation/directives/stdlib-only-python/check.sh
- packs/foundation/directives/stdlib-only-python/constitution.md
- packs/foundation/directives/stdlib-only-python/defaults.conf
- packs/foundation/directives/stdlib-only-python/directive.yaml
- packs/foundation/directives/stdlib-only-python/evals/test.sh
- packs/foundation/pack.yaml
- README.md
- scripts/test-digestlib.py
- scripts/test-init.py
- scripts/test-kityaml.py
- scripts/test-kitverb.py
- scripts/test-packs.sh
- scripts/test-runtime.sh
- scripts/test-schema-split.sh
- scripts/test-subagent.sh
- scripts/test-sweep.py
- scripts/test.sh

## Accounting

<!-- Accounting rows are maintained by the agent-token-accounting and agent-steering-accounting pre-commit hooks. Keys are opaque — do not parse. -->

### Costs

| cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | cum-input | cum-cache-create | cum-cache-read | cum-output | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| claude-code-1419af64-024-1785848989-1 | claude-code | 1419af64-024c-4b9a-97ec-a471fe4c95b5 | #355 | claude-fable-5 | 276 | 748711 | 25049503 | 378484 | 1127471 | 53.3354 | 276 | 748711 | 25049503 | 378484 | feat(kit): agent-adjudicated gates + native-cost accounting (#355) -m Implements |
