# issue-355: feat(kit): agent-adjudicated gates + native-cost accounting

Closes [#355](https://github.com/Duaility/governance-kit/issues/355).

## Checklist

- [x] Port the sub-agent attestation machinery in lib.sh to pure bash (Phase 0)
- [x] Ship `gate: verdict` — blocking adjudication log, freshness stamp, escalation ladder (Phase 1)
- [x] Wire the sweep engine to read `subagent:` declarations directly (Phase 2)
- [x] Add the executor abstraction — harness | cli:<adapter> | api:<provider> (Phase 3)
- [x] Generalize batching across the commit lane and the sweep engine (Phase 4)
- [x] Replace the hand-rolled accounting Python with identity-at-commit / measurement-at-rest accounting — Costs v6, snapshot sidecar, off-path resolver, seven runtime adapters (Track B)
- [x] Eliminate PyYAML and uv via a restricted-YAML stdlib parser; port managed-tree-integrity to bash (Q11)
- [x] Ship the dependency-posture directives — no-commit-path-python, stdlib-only-python, no-package-manager — as repo-local self-directives (Q11)
- [x] Unify the sweep lane onto the harness-pegged adapter judge — bash `sweep.sh` replaces `sweep.py` and GitHub Models; `surface: sweep` retired
- [x] Declare every bundled directive's intent as a sweep-lane rubric — 13 judge blocks beside their untouched `check.sh`
- [x] Collapse judge selection to a directly-named command; strip it from bundled packs in favor of one repo-level knob
- [x] Reduce the declaration vocabulary to what earns its place — delete `tiers`, `isolation`, `sink`, `contest`; rename the block to `judge:`
- [x] Strip the `group:` label from bundled packs — batching is the consuming repo's trade, not a pack author's

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

**Phase 2 — the `subagent:` declaration is the whole sweep contract.** The
sweep lane discovers any directive whose `subagent:` block resolves a sweep
tier other than `none`/`off` and derives the rubric from the declaration's
`checks:` — plus standing rubric lines for verdict-gated directives (a
missing, malformed, or pruned adjudication log is itself a violation;
CONTESTED verdicts are re-adjudicated on merits). `sink: none` declares a
sweep-only discovery directive with no commit-lane gate, no section, and no
`check.sh` at all — `packctl` exempts both `check.sh` and the `surface:`
field for it, because both describe commit-lane semantics it doesn't have.
The legacy `surface: sweep` / `triage.sh` contract is retired outright; see
the sweep-unification paragraph below.

**Phase 3 — executor abstraction.** A kit-level runtime adapter registry at
`kit/assets/dot-governance/runtimes/` — seven adapters: claude-code, codex,
pi, grok, cursor-agent, opencode, manual — is seeded into consumer repos as
`.governance/runtimes/<name>.sh`, managed and digest-guarded like lib.sh.
Each adapter speaks four verbs: `judge` (read a declaration-built prompt on
stdin, run the CLI non-interactively, answer `VERDICT: PASS|REFUTED` plus
`REASON:` lines — and, on sweep prompts, `FINDING:` and batched `DIRECTIVE:`
lines), `can-judge` (is the CLI invocable here — exit 0/2, no output),
`resolve` (report the session's cumulative usage from
declared surfaces only), and `emit` (accept the harness's own push payload
and append a snapshot; see Track B). `SUBAGENT_EXECUTOR=cli:<adapter>` (conf-resolved,
default `harness`) lets a different-vendor CLI adjudicate a verdict gate
in-hook — separation of duties against shared-model failure modes — with
per-tier model selection via `SUBAGENT_MODELS_LOW/MEDIUM/HIGH`. Every failure
path (missing CLI, transport error, malformed answer) degrades to the harness
remediation loop; a commit never hard-fails because a CLI is absent.

**Phase 4 — generalized batching.** The commit-lane orchestrator groups shared
judgments by executor as well as isolation (ledger rows carry an executor
field; legacy rows keep parsing), and the sweep driver batches every
`shared`-isolation directive onto one adapter judge call — same-receipt
attestations and same-range discovery directives alike — at the highest tier
any batched directive resolved, demultiplexed by per-directive `DIRECTIVE:`
blocks in the response. `isolated` opts a directive out into its own call,
the same knob the commit lane batches by. A batched response missing a
directive's block counts that directive un-adjudicated, never PASS; a
malformed batch counts the whole batch un-adjudicated. Neither lane retries
in-run: the sweep's next run is its retry, and the commit lane's cli executor
degrades to the harness remediation loop, which is its recovery path.

**Sweep unification — one judgment primitive, harness-pegged.** The vendored
Python sweep engine is deleted whole: `kit/assets/dot-governance/sweep.py`,
its GitHub Models transport (`TIER_MODELS`, the workflow's `models: read`
grant), the echo keyword-stub judge and its precision/recall calibration
harness, the `triage.sh` grep-prefilter contract, and `surface: sweep` as a
surface value. In their place `.governance/sweep.sh` — bash, sourcing
`lib.sh` — re-adjudicates `subagent:` declarations at rest through the same
adapter `judge` verb the commit lane's `cli:` executor already calls. Judges
never block where they run; gates block where they read: a high-tier round
appended to a not-yet-frozen receipt is read by the existing `gate: verdict`
commit/CI gate, while a frozen receipt's refutal or a `sink: none` discovery
finding routes to the `governance-sweep` digest issue (label, dedupe, footer,
end-SHA resume marker — ported from the Python engine to bash + `gh`; no
`gh` → the digest prints to stderr and the run exits 0). Adapter resolution
is pegged to the harness: `GOVERNANCE_SWEEP_ADAPTER`, else the live
harness's own environment announcement, else the first registered adapter
whose `can-judge` probe passes; none reachable → one honest line, exit 0,
retry next run. Entry points: manual, the rewritten `governance-sweep.yml`
cron (the consumer brings a harness CLI + credential via a repo variable and
secret; unconfigured, the workflow no-ops honestly rather than faking a
judge), and an opt-in `GOVERNANCE_SWEEP_ON_PUSH=1` pre-push stanza whose
exit status is always ignored. `GOVERNANCE_SWEEP_BUDGET` (default 20; 3 in
push mode) caps judge calls per run, with over-budget items reported
un-adjudicated, never silently dropped. The two repo-local sweep directives
— `no-legacy-fallbacks`, `no-path-bifurcation` — convert to
`subagent: { inputs: [range-diff], checks: [...], sink: none,
tiers: { sweep: high } }` declarations with their `triage.sh` files deleted;
the hand-authored `source: local` pack lands in full now per the #280
precedent, with the two CONSTITUTION.md Enforced-by lines and a second
Evolution Log entry updated in the same commit.

**Intent rubrics for every bundled directive.** A `check.sh` proves the
*letter* of a directive; the `subagent:` declaration is where its *spirit*
becomes adjudicable. The 13 bundled directives that carried no declaration —
audit's agent-token-accounting, commit-issue-receipt-match, doc-integrity,
issue-templates, issues-tracked, toolchain-config-protection; commits'
commit-message-format, no-orphan-todos, no-unjustified-suppressions;
foundation's internal-doc-links, managed-tree-integrity, repo-hygiene,
required-docs — each gain a sweep-only intent rubric
(`inputs: [range-diff]`, `sink: none`, `tiers: { sweep: high }`): three to
five adjudicable statements about what the mechanical check cannot see (the
honesty of waiver reasons, a subject line that names what the change
actually does, a frozen record whose *meaning* wasn't rewritten around the
byte rules, accounting rows that don't invent numbers). The rubric addition
edits `directive.yaml` and nothing else: no `check.sh`, constitution,
defaults, or eval changed *for a rubric's sake*, so the mechanical gates are
untouched. (Two of the 13 do carry other edits in this same change set for
unrelated reasons — `agent-token-accounting` from Track B and
`managed-tree-integrity` from Q11 — so a per-folder `git diff --stat` shows
more than one file for those two.) Per-commit cost is zero because
`sink: none` never enters the commit lane. Shared isolation batches the whole bundled set onto one judge
call per sweep run. `receipt-per-issue` and `agent-steering-accounting` keep
their existing attest+sweep declarations.

**Track B — accounting: identity at commit, measurement at rest.** The audit
pack's re-derivation layer is deleted twice over. First the Python:
`ledger.py`, `rates.py`, `endpoint.py`, `reconcile.py`, `validate.py`,
`receipt_io.py`, `argv.py`, `report.py` in agent-token-accounting and
`ledger.py` + `receipt_io.py` in agent-steering-accounting (~2,100 lines),
along with every rate row in the rate card. Then the design that made a
blocking pre-commit hook measure a live session: endpoint freezing,
per-session checkpoints, per-commit delta columns, and every newest-file
heuristic are gone. The commit path records identity only —
`detect_runtime_identity` reads the harness's own environment announcement
(claude-code, codex, pi, cursor-agent, opencode, manual via env; grok via a
hook-written identity file) and the pre-commit writer stamps one Costs v6
row (10 columns) per session per issue, folding in the freshest numbers from
a kit-owned snapshot sidecar under the worktree's git dir. Measurement
happens off the commit path: best-effort post-commit and pre-push sweeps
(`lib/resolve.sh`) ask each session's adapter to `resolve` from declared
surfaces only — a payload the harness itself pushed (`emit`, e.g. a
statusline command), a file the harness itself named, or a local server the
harness itself runs — with provenance recorded per row (`harness-feed` |
`session-file` | `server` | `manual` | `unresolved`). A session that cannot
be resolved honestly reads `unresolved`, never a guessed number; `cost-usd`
stays the harness's own figure verbatim or `-`. The kit never prices, and
now never guesses identity either. Rows are session-cumulative (the
squash-merge workflow discards per-intermediate-commit precision anyway);
v5 and older rows are tolerated as legacy by cell count and never re-judged.

**Q11 — dependency endgame.** New stdlib restricted-YAML parser/writer
`kit/assets/packs/lib/kityaml.py` replaces PyYAML across the lifecycle verbs
(`packctl.py`, `packverb.py` — with byte-for-byte `dump(load(x))` parity
against the real packs.lock); every `uv run --with PyYAML` incantation in
`packs.sh`, `install.sh`, scripts, and CI becomes a bare `python3` (the
setup-uv step is removed from `.github/workflows/tests.yml`).
`managed-tree-integrity` is ported to pure bash (`lib/digest.sh`, byte-pinned
to `digestlib.py` by `scripts/test-digestlib.py`); `lib/integrity.py` is
deleted. Three directives enforce the posture — `no-commit-path-python`,
`stdlib-only-python`, `no-package-manager` — and they are **repo-local
self-directives**, not kit-bundled ones: Q11's wording is that "the kit should
hold itself to them", and in a consumer repo they would police the vendored
`.governance/` tree, which is kit-authored content the consumer cannot repair
without a release. They live in the hand-authored `duaility/governance-kit`
dogfood pack and scan the trees this repo actually authors (`kit/`, `packs/`,
`skill/`, `.githooks/`), with Q11's one remaining sanctioned Python lane —
the lifecycle libs — and the never-shipped `scripts/` excluded by scope (the
sweep engine stopped being a Python lane when the sweep unification made it
bash). Each
matches at command position rather than by bare word, so prose and Markdown
never trip them. They run live here on every commit: a consumer repo needs
nothing but bash + git to commit; the kit's own tooling needs nothing but a
bare python3; nothing the kit ships needs a package manager.

**Install/update plumbing.** `applylib.py` gains the adapter enumeration and
narrows `_participates_in_sweep` to the `subagent:` declaration alone — a
live sweep tier vendors the sweep lane, and `SWEEP_ASSETS` now lays down
`.governance/sweep.sh` beside the workflow; `initapply.py`/`kitverb.py` seed
and inventory the registry; `digestlib.py` records adapter digests;
`eval-lib.sh` installs the registry into eval fixtures; `install.sh` reads
directive scalars with awk instead of a PyYAML heredoc and drops the
`triage.sh` handling with the contract.

**Tests.** New layers `scripts/test-subagent.sh` (140 assertions: parser
parity, remediation grouping, stamp, gate, ladder, executor dispatch) and
`scripts/test-kityaml.py` (grammar, coercion, byte parity, corpus walk);
`scripts/test.sh` runs every Python layer on bare python3;
`test-runtime.sh` (assertions across the seven adapters, including a
fixture proving two transcripts present with no identity yields exit 2 —
never a newest-file pick), `test-digestlib.py`, `test-init.py`,
`test-kitverb.py`, `test-packs.sh`, `test-schema-split.sh`
updated in place. `scripts/test-sweep.sh` replaces `test-sweep.py` outright:
stub-adapter fixtures covering adapter-resolution order, the range ladder,
round-append vs frozen-receipt routing, discovery findings, batching demux,
and budget honesty — no network, no vendor CLI. Directive evals rewritten for the bash stacks (token 51,
steering 18 assertions) including identity-ladder, sidecar-fold, and
resolve-sweep fixtures. Verified under bash 3.2 and both BSD awk and mawk.

**Docs.** `kit/references/JUDGE.md` — renamed from `SUBAGENT_ATTESTATION.md`
by the `judge:` rename below, and rewritten for the collapsed schema
(adjudicated gates, the `cmd`/`group` surface, the attest/sweep table),
`SWEEP_FLOW.md` (rewritten in
full around the unified harness-pegged lane), `DIRECTIVE_AUTHORING.md`
(authoring a sweep directive is authoring a `judge:` block),
`AGENTS.md`, `LIB_API.md`, `INSTALL_SCHEMA.md`
(new `emitters_wired` ledger field), `UNINSTALL_MATRIX.md`,
`UNINSTALL_FLOW.md` (emitter unwiring), `UPDATE_FLOW.md`, `INIT_FLOW.md`
(new Step 6b: emitter wiring, offered and ledgered), `NATIVE_TESTS.md`,
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
  in the post-release dogfood-sync PR, never by hand. That includes the
  installed sweep pair: `.governance/sweep.py` and
  `.github/workflows/governance-sweep.yml` are release-managed digests and
  stay pinned; the catch-up must also GC the orphaned `.governance/sweep.py`
  (the asset was renamed to `sweep.sh`, and the update verb does not GC
  renamed paths). Until then the old cron may read the converted repo-local
  declarations and file noisy-but-harmless digests — off the commit path by
  construction.
- **Version bumps and floors.** Version lines move only in `chore(release)`
  commits. Release-time notes: the audit pack's `min_governance_kit` must rise
  to the first kit tag shipping the adapter registry (its `lib/runtime.sh` now
  resolves `.governance/runtimes/`), and the kit/audit/foundation axes all
  have releasable changes here.
- **Migrating pre-#355 local caches.** Legacy endpoint/checkpoint files under
  `.git/` (JSON or flat key=value) are ignored, not migrated — disposable
  local state with no consumer left.
- **Wiring an emitter in this repo.** Emitter wiring is an install-time
  offered side effect (INIT Step 6b); this PR ships the mechanism and the
  flow text, and wires nothing into anyone's harness config.
- **CONSTITUTION.md subsections for the *bundled* packs.** The live
  constitution reflects the installed (pinned) directive set, so the reworked
  `governance-kit/*` pack snippets land in it at the next release via the real
  verbs. The three repo-local self-directives are the deliberate exception —
  their pack is `source: local` and not release-managed, so their subsections
  and the Evolution Log entry land in this commit (the #280 precedent). The
  same exception covers the sweep unification's constitution changes: the two
  repo-local sweep directives' Enforced-by lines and a second Evolution Log
  entry.

## Decisions

- **Judge selection collapsed to a named command, then out of packs
  entirely.** Three layers resolved who judged — an executor conf ladder, a
  `tiers:` capability vocabulary, and per-adapter model tables — so answering
  "what model renders this verdict?" meant reading three files. They collapse
  to one string. The first cut put that string in `directive.yaml`
  (`cmd: { attest, sweep }`, a shell command already encoding model and
  effort; the framework only pipes the prompt to stdin and parses the verdict
  off stdout). The second cut took it back out of every bundled pack: a pack
  shipping `claude -p` is wrong for a Codex shop, so bundled declarations name
  no harness at all. Attest defaults to `harness` — the live session spawning
  its own sub-agent, portable by construction because the yaml never says
  which harness. The sweep has no session to spawn from, so it resolves one
  repo-level `GOVERNANCE_SWEEP_CMD`; `cmd` survives only as a per-directive
  override for repo-local and third-party packs. Adapters kept `resolve`/
  `emit` for accounting identity and lost `judge`/`can-judge` — judging was
  never an adapter concern once a directive could name its own command.
- **Grouping is a label, not a boolean.** `isolation: shared|isolated` could
  only express "everything together" or "everything apart"; the real ask is a
  partition — three of these in one invocation, two in another. `group: <slug>`
  says exactly that: same label, same call; no label, solo. Batching by max
  tier is gone with the tiers it ranked, and with it the silent upgrade where
  a cheap directive rode a batch-mate's stronger model. A group whose members
  resolve to different commands is refused whole rather than split silently —
  one group is one invocation, one command.
- **The vocabulary shrank to what earns its place.** `sink` was deleted: it
  carried no information `section:` presence didn't already carry, and `none`
  misnamed a sink that files a GitHub issue — a louder destination than the
  receipt section it claimed to lack. `contest` folded into `gate`, which is
  now `record | verdict | verdict-contestable`; a boolean modifying another
  knob is one axis pretending to be two, and the common spelling `verdict`
  kept its exact meaning so no bundled behavior moved. What remains answers
  one question each: `checks` what to judge, `inputs` on what evidence,
  `section` where the verdict lands (and whether it lands at all), `gate` what
  blocks, `group` what shares a call.
- **`subagent:` renamed to `judge:`.** The block declares a judgment; a
  sub-agent is one of three ways to execute it (in-session spawn at commit,
  detached CLI, the at-rest driver) and after the collapse the executor is not
  declared in the block at all. Naming a contract after its default
  implementation is the same smell as `tiers` naming a model catalog. The
  rename is total — yaml key, `_judge_*` helpers, `judge_attest`,
  `JUDGE_ROUNDS`, and `SUBAGENT_ATTESTATION.md` to `JUDGE.md` — because a
  `judge:` key over `_subagent_*` code would trade a naming smell for a
  grep-ability smell. The word "sub-agent" survives where it accurately names
  the mechanism. v0 is the only cheap moment for this.
- **The audit refuted two receipt sentences and one of its own findings stood
  corrected.** An independent fresh-context pass caught this receipt
  over-claiming twice — "no `check.sh`, constitution, defaults, or eval
  changed" (false for 2 of the 13, from unrelated Track B / Q11 work in the
  same change set) and "`run` always exits 0" (false: digest-filing failure
  returns 1, though nothing consumes it). Both are corrected above. Its third
  finding — that 17 appendix paths were phantom — was itself wrong: those
  paths were added in the branch's first commit and deleted in the second, so
  they are in the change set even though neither endpoint tree contains them.
  `receipt-per-issue` flagged their removal, which is the file-coverage rule
  doing exactly its job.

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
- **Identity at commit, measurement at rest.** A pre-commit hook is the worst
  possible measurement point — synchronous, blocking, unretryable, racing a
  live session whose spend is not final yet — and the squash-merge workflow
  discards per-intermediate-commit precision anyway. So the commit path
  records only what is knowable at commit time (which harness, which session)
  and validates structure; measurement moves to non-blocking post-commit and
  pre-push resolve sweeps whose failures mean "retry later", never a blocked
  commit or a guessed number. This replaces the endpoint-freeze/checkpoint
  design from this PR's first iteration.
- **Resolve reads declared surfaces only.** An adapter may open a path it was
  explicitly handed, a file whose name contains the exact session id under
  the harness's documented state dir, or a server the harness runs — never
  `ls -t`, never an mtime window. Unidentifiable session → `unresolved` row.
- **cursor-agent ships honest-blank.** Cursor exposes no documented per-session
  usage surface, so its rows carry identity with `-` numbers until upstream
  ships usage in its hook or JSON output — blank pressure on upstream beats a
  fabricated figure.
- **`report.py` is deleted without a bash replacement.** It only parsed the
  retired delta schemas and its per-issue sum would double-count cumulative
  v6 rows; cross-issue totals are a grep away, and any future reporting tool
  belongs off the commit path.
- **Emitter wiring is a consented, ledgered side effect.** Wiring a harness's
  statusline/hook config to `.governance/runtimes/<name>.sh emit` touches
  user-owned config, so INIT offers it, records it under `emitters_wired` in
  install.yaml, and UNINSTALL reverses it.
- **The dependency-posture trio are self-directives, not product.** They were
  first authored as bundled `governance-kit/foundation` directives; that was
  wrong on the issue's own terms ("the kit should hold itself to them") and
  wrong in effect — in a consumer repo they scan `.governance/`, which is
  kit-authored vendored content the consumer cannot repair without a release,
  so the only available remedy would be a waiver. They moved to the
  hand-authored `duaility/governance-kit` pack, following the #280
  architecture-pack precedent exactly, including landing in full now because
  that pack is not release-managed.
- **The move required a re-scope, not just a relocation.** Pointed at the
  installed tree they would fail here immediately: this repo's `.governance/`
  is pinned to the last release and still full of Python by design. As
  self-directives they scan what this repo authors — `kit/`, `packs/`,
  `skill/`, `.githooks/` — with Q11's sanctioned Python lanes (the lifecycle
  libs; at the time also `sweep.py`, since retired by the sweep unification)
  and the never-shipped `scripts/` out of scope, and
  `.github/workflows/` excluded from the package-manager rule because the docs
  site legitimately runs npm.
- **Command-position matching beats word matching.** Bare `grep -w python`
  fired on prose and on the directives' own ids; both checks now match only at
  command position (start of line, after a pipe/semicolon/subshell, or a
  workflow `run:`), so shipped Markdown and docstrings never trip them and no
  file needs a blanket exemption. `no-commit-path-python` also fails on a
  `#!…python` shebang — the comment filter had been silently ignoring the most
  literal form of the violation.
- **One judgment primitive, harness-pegged — judges never block where they
  run; gates block where they read.** The sweep is not a second engine but
  the same `subagent:` declaration executed at rest through the same adapter
  `judge` verb as the commit lane's `cli:` executor. Its writes are its only
  outputs: a round the existing `gate: verdict` reader blocks on, or a digest
  finding entering the canonical issue → agent → PR door. Blocking therefore
  stays a property of the gates that read, never of the sweep that writes.
  `run`'s own exit status carries no verdict: it is nonzero only when the
  driver fails to *file* its digest, and nothing consumes it (the pre-push
  stanza discards it with `|| true`; the workflow is a cron job).
- **No zero-secret judge.** GitHub Models and the echo keyword stub are
  deleted, not abstracted over: a keyword grep is not a judge, and a
  fixed-vendor transport is not the harness. The scheduled workflow no-ops
  with one honest line until the consumer configures a harness CLI and its
  credential — the same honesty rule as the accounting lane, where no
  reachable surface means a blank, never a guess.
- **The declaration schema did not move.** `tiers`/`gate`/`sink` already
  encode both lanes; the unification is in the executor, not the YAML.
  Renaming fields would have churned every parser — lib.sh, applylib,
  packctl, the docs — for zero semantic gain.
- **Frozen receipts take findings; editable receipts take rounds.**
  doc-integrity freezes a receipt once it lands on the trunk, so the sweep
  appends rounds only while the branch is open (where a high-tier REFUTED
  reddens the PR through the existing gate) and files findings to the digest
  after merge. The write target follows the artifact's mutability, not the
  other way around.
- **Triage is deleted, not ported.** The grep prefilter existed to spoon-feed
  hunks to a tool-less, budget-capped vendor endpoint. A harness judge has
  git and the repo; it takes the range diff directly. Cost control moved to
  the lane declaration (which directives opt in, at what tier, batched by
  `isolation`) plus the per-run budget.
- **Batching is one knob across both lanes.** `isolation: shared` batches
  judgments in the commit lane's grouped instruction and onto one sweep judge
  call alike; `isolated` opts out in both. A batch runs at the highest tier
  any member resolved, and a response missing a member's `DIRECTIVE:` block
  counts that member un-adjudicated, never PASS — token savings must not
  manufacture verdicts. Two packs shipping the same directive id cannot share
  one `DIRECTIVE:` delimiter, so a homonym demotes to its own call. Building
  the batched round-writer also surfaced a latent stamp bug in the *single*
  path — `_subagent_append_round`'s blank-line insertion invalidated the
  stamp whenever the attested section wasn't last in the receipt — fixed
  uniformly with a two-phase write (append all rounds with placeholder
  stamps, hash the settled file once, fill them in), regression-tested for
  both cases.
- **Push-mode sweeping is opt-in.** A judgment costs minutes and a hook must
  not; `GOVERNANCE_SWEEP_ON_PUSH=1` is for operators who want a refutal to
  land while the receipt is still editable, and its exit status is ignored
  even then.
- **Every bundled directive declares its intent; none pays for it at commit.**
  The rubric lane composes with the mechanical gate instead of replacing it: a
  `check.sh` plus a sectionless `judge:` block means the grep still gates the
  commit and the model judges the spirit at rest. Sweep-only was chosen over
  attest sections deliberately — 13 new per-commit attestations would be
  receipt noise and sub-agent cost with no gate to serve.
- **A bundled pack declares no `group` either.** The label first shipped on all
  15 bundled judge blocks as `bundled-intent`, batching the set into one judge
  call. That is the same presumption Amendment 2 removed from `cmd`, and worse:
  `cmd` a consumer can override through the directive flow, but the vendored
  tree is digest-guarded, so a shipped label cannot be unshipped. Batching is
  also a real fidelity trade — one judge holding ~50 checks against one diff
  gives each less scrutiny, prior PASSes make the next cheaper to wave through,
  and a single malformed response loses every verdict in the group instead of
  one. The economics that justified it are weakest where it was applied: 15 of
  the 16 blocks are sweep-only, and the sweep is a scheduled off-commit-path
  job, not a hook. So bundled judgments are adjudicated solo; `group` stays in
  the schema for packs whose author is the repo owner (this repo's own
  `kit-architecture` pair). No repo-level batching knob was invented to
  compensate — that would be the same presumption one layer down, and nobody
  has asked for it.

## Verification

```sh
bash scripts/test.sh          # all 22 kit-internal layers
bash .governance/run.sh       # the dogfood suite (pinned release directives)
node scripts/docs-site/gen-reference.mjs --check
```

Results:

- Port the sub-agent attestation machinery in lib.sh to pure bash (Phase 0) — done; `grep python kit/assets/dot-governance/lib.sh` hits only a comment, and `scripts/test-subagent.sh` pins parser parity (140 assertions, green under bash 3.2 and mawk).
- Ship `gate: verdict` — blocking adjudication log, freshness stamp, escalation ladder (Phase 1) — done; gate end-to-end cases (missing log, stale stamp, scrubbed round, contested, ladder rendering) all covered in `scripts/test-subagent.sh`.
- Wire the sweep engine to read `subagent:` declarations directly (Phase 2) — done, and completed by the sweep unification: the declaration is now the *only* sweep contract, exercised end-to-end by `bash scripts/test-sweep.sh` against stub adapters (discovery → adjudicate → digest, and re-adjudication → round).
- Add the executor abstraction — harness | cli:<adapter> | api:<provider> (Phase 3) — done; registry seeding verified by `test-init.py`/`test-kitverb.py`, judge dispatch + degrade paths by `test-subagent.sh` (140 assertions) and `test-runtime.sh` (206 assertions).
- Generalize batching across the commit lane and the sweep engine (Phase 4) — done; executor-aware grouping and batch demux/retry covered in the same suites.
- Replace the hand-rolled accounting Python with identity-at-commit / measurement-at-rest accounting — Costs v6, snapshot sidecar, off-path resolver, seven runtime adapters (Track B) — done; token eval 51 assertions, steering eval 18, both green under BSD awk and mawk; an end-to-end smoke in a throwaway repo ran the post-commit resolve sweep against the real `manual.sh` adapter (sidecar snapshot appended), then the pre-commit stamp-and-fold produced a valid v6 row and `check.sh` passed; a two-transcripts-no-identity fixture proves the no-guessing rule (exit 2, no row).
- Eliminate PyYAML and uv via a restricted-YAML stdlib parser; port managed-tree-integrity to bash (Q11) — done; `git grep "import yaml"` over shipped code returns nothing, `scripts/test-kityaml.py` proves packs.lock byte parity, `scripts/test-digestlib.py` pins bash/python digest parity, and CI no longer installs uv.
- Unify the sweep lane onto the harness-pegged adapter judge — bash `sweep.sh` replaces `sweep.py` and GitHub Models; `surface: sweep` retired — done; `bash scripts/test-sweep.sh` is green (stub-adapter fixtures: adapter-resolution order incl. env override and honest no-adapter no-op, the range ladder, round appends with valid stamp grammar on editable receipts, frozen-receipt routing to the digest, discovery findings, `shared`/`isolated` batching demux, budget honesty, `FINDING:`/`DIRECTIVE:` passthrough in a real adapter's `emit_verdict`) — 125 assertions, including that a batched answer with no block structure un-adjudicates the whole batch rather than letting any member read PASS; `packctl` validation of the repo-local pack reports no `surface`/`check.sh` errors for the two converted directives; `bash .governance/run.sh` stays 19/19 with both now check.sh-less directives correctly skipped by commit-path discovery.
- Ship the dependency-posture directives — no-commit-path-python, stdlib-only-python, no-package-manager — as repo-local self-directives (Q11) — done; all three run live in `bash .governance/run.sh`, which passes 19/19 (16 before this change). They carry no `evals/`, matching the five pre-existing repo-local directives: nothing runs evals under `.governance/`, and executing against this repo on every commit is the stronger signal. Each was teeth-tested by perturbing a real in-scope file (a `python3 -c` in a hook, a python shebang on a `check.sh`, a third-party import in `skill/bootstrap.py`, an `os.system("uv run …")`, a workflow `- run: npx …`), confirming the failure, and restoring.
- Declare every bundled directive's intent as a sweep-lane rubric — 13 judge blocks beside their untouched `check.sh` — done; every edited directive.yaml parses under the repo's own `kityaml` with 3–5 checks, `bash scripts/test-packs.sh` stays green (3 packs, 15 directives, 15 evals), `python3 scripts/test-packctl-validate.py` 14/14, and the rubric edits themselves touch `directive.yaml` only — no `check.sh`/`constitution.md`/`defaults.conf`/eval was modified for a rubric's sake, so the mechanical gates are untouched by construction. Two of the 13 folders do show other files in a per-folder `git diff --stat` against `origin/main`, from unrelated work in this same change set: `agent-token-accounting` (Track B) and `managed-tree-integrity` (Q11).
- Collapse judge selection to a directly-named command; strip it from bundled packs in favor of one repo-level knob — done; `bash scripts/test-sweep.sh` is green at 103 assertions covering the resolution ladder end to end (a directive with no `cmd` judged via `GOVERNANCE_SWEEP_CMD`; a per-directive `cmd.sweep` overriding a deliberately broken knob; neither set → honest skip; missing binary → un-adjudicated), `grep -rn 'cmd:' packs/*/directives/*/directive.yaml .governance/packs/duaility/governance-kit/directives/*/directive.yaml` returns nothing (no bundled pack names a harness), and `scripts/test-subagent.sh` (159 assertions) pins the commit-lane arm: a shell-string `cmd.attest` judged inline, any failure degrading to the harness sub-agent path with a `+fallback`-marked ledger row.
- Reduce the declaration vocabulary to what earns its place — delete `tiers`, `isolation`, `sink`, `contest`; rename the block to `judge:` — done; `packvalidate.py` rejects all four retired keys with a message naming the replacement, and `python3 scripts/test-packctl-subagent.py` (20 fixtures) + `test-packctl-validate.py` (14) pin them alongside the three `gate` values, an unknown gate value, gate-without-section, and the section-absent exemptions (no `check.sh`, no `surface:` required). `grep -rn '^judge:' ` over every shipped `directive.yaml` shows 18 blocks and `grep -rn '_subagent\|subagent_attest\|SUBAGENT_'` over `kit/ packs/ scripts/` returns only past-tense mentions inside `SWEEP_FLOW.md`'s "what was deleted" section. `node scripts/docs-site/gen-reference.mjs --check` confirms the generated Reference pages match the renamed sources.

- Strip the `group:` label from bundled packs — batching is the consuming repo's trade, not a pack author's — done; `grep -rn '^  group:' packs/` returns nothing across all three bundled packs, and the one repo-local directive whose batch partner was bundled (`layer-boundaries`, formerly grouped with `receipt-per-issue`'s `## Audit`) drops its label too, leaving `kit-architecture` as the only live group in the tree. The mechanism itself is untouched and still pinned: `scripts/test-sweep.sh` and `scripts/test-subagent.sh` exercise batching, mixed-command group refusal, and `DIRECTIVE:` demux against synthetic fixtures that declare their own labels, so removing the bundled labels changed no test outcome — `bash scripts/test.sh`, `bash .governance/run.sh` (19/19), and `node scripts/docs-site/gen-reference.mjs --check` are all green.

`bash scripts/test.sh` → "✓ all kit-internal test layers passed" on the final
integrated tree.

## Audit

*(Third audit pass, fresh sub-agent context, against the **whole current change set** — commits `7fecf8e` + `0f0f5ec` versus `origin/main` **plus** the uncommitted worktree layer that carries the sweep unification and the bundled-directive intent rubrics. The two prior passes above this line are superseded: they predate the sweep unification entirely, and their statements that `python3 scripts/test-sweep.py` runs inside `scripts/test.sh`, that `kit/assets/dot-governance/sweep.py` is kit engine code, and that the transcript is 871 lines are all now false. Methodology note that mattered: two of the most load-bearing files in this change set — `kit/assets/dot-governance/sweep.sh` and `scripts/test-sweep.sh` — are **untracked**, so a bare `git diff origin/main` omits them from both stat and patch. The verified path set was assembled as the union of `git diff --name-only origin/main...HEAD`, `git diff --name-only HEAD` and `git ls-files --others --exclude-standard` = **134 paths**, and every claim below was checked by reading files and running commands, never by trusting the receipt's own citations.)*

1. **The sweep unification is real, complete, and does what `## What changed` says — PASS.** Every load-bearing deletion was confirmed absent from the worktree, not merely absent from a diff: `ls kit/assets/dot-governance/sweep.py scripts/test-sweep.py` returns "No such file or directory" for both, and `ls` on the two repo-local sweep directive folders shows exactly `constitution.md` + `directive.yaml` — both `triage.sh` files gone. `surface: sweep` is retired as a live surface value: `packctl.py:31` now reads `SURFACES = {"repo-state", "change-set"}`, and `git grep "surface: sweep"` over the whole repo returns **zero hits in source** — the only survivors are (a) the release-pinned consumed tree (`.governance/sweep.py:437`, `.github/workflows/governance-sweep.yml:12`), which the receipt's `## Out of scope` explicitly discloses as release-managed and catching up at the next release, (b) `kit/references/SWEEP_FLOW.md:252` and `packctl.py:27`, which name it in "what was removed" prose, and (c) pre-existing narrative in `receipt-per-issue`'s rationale and older receipts. No `engine:` / `model_tier:` scalar survives on any `directive.yaml` (`git grep "^engine:\|^model_tier:"` over `packs/**` and `.governance/packs/duaility/**` is empty). The GitHub Models transport is gone from shipped code, not abstracted: `grep -rn "models.github\|TIER_MODELS\|urllib\|GITHUB_MODELS"` over `kit/ packs/ skill/` returns nothing executable, `kit/assets/governance-sweep.yml` declares `permissions: contents: read` + `issues: write` with **no** `models: read`, and the only `keyword`/`calibrat`/`precision` hits left are the four comment lines that state the stub judge and its calibration harness were deleted (`sweep.sh:30`, `applylib.py:33`, `governance-sweep.yml:12`, `DIRECTIVE_AUTHORING.md:113`). `install.sh`, `hooks.sh` and `packapply.py` contain **no** `triage` reference at all.

2. **The sweep driver genuinely REUSES the commit lane's machinery rather than reimplementing it — PASS, and this is the claim I tried hardest to break.** `kit/assets/dot-governance/sweep.sh:79–97` resolves and `source`s `lib.sh` from a three-candidate ladder and exits 0 with one honest line if none is reachable. It then calls, from lib.sh: `_subagent_yaml` (declaration reader), `_subagent_tier_resolve` / `_subagent_model_resolve` (the same conf ladder the commit lane uses), `_subagent_adapter` (registry lookup), `_subagent_cli_prompt` (**the prompt builder**), `_subagent_ensure_section`, `_subagent_round_lines` and `_subagent_append_round` (**the round appender**). Critically, at `sweep.sh:519–526` **both** the single-directive and the batched call go through `_subagent_cli_prompt` — the single path passes `(receipt, section, checks, yaml, RANGE, sweep)`, the batch path passes an empty section/checks/yaml plus a batch-spec file as the 7th argument — so there is exactly one prompt builder, matching `lib.sh:882–929` where `_subagent_cli_prompt` accepts that same optional batch spec on the `_SUBAGENT_RS` (`\x1e`) separator that `sweep.sh:103` re-reads from lib.sh rather than redefining. The judge call is `bash "$ADAPTER_PATH" judge "$tier" "$model"` — the identical verb `lib.sh:1027–1038`'s `cli:<adapter>` executor invokes. There is no forked prompt builder, no forked round appender, and no second stamp implementation. This repo's own `no-path-bifurcation` directive applies to the kit itself and I could not find a violation of it here.

3. **Batching semantics match the receipt clause for clause — PASS.** All four sub-claims verified in `kit/assets/dot-governance/sweep.sh`: (a) `isolation: shared` batches in **both** lanes — `_sweep_lane_discovery:567` and `_sweep_lane_attest:601` both branch on `[[ "$isolation" == "isolated" ]]`, and `sweep.sh:747` resolves it through the same `conf_get "$id" SUBAGENT_ISOLATION` overlay `lib.sh:1120` uses, so it is one knob and not two; (b) `isolated` opts out into its own call (same two lines); (c) a batch runs at the **max** tier any member resolved — `_sweep_batch_tier:421–428` ranks `high > medium > low` across the batch and the run uses that tier, so batching can never silently downgrade a member's judge; (d) a missing or malformed `DIRECTIVE:` block never reads PASS — `_sweep_block:434–442` demuxes by "most recent `DIRECTIVE:` delimiter" and returns 1 on an empty block, whereupon `sweep.sh:551` calls `_sweep_unadj` for that member; an answer with no block structure at all therefore un-adjudicates **every** member of the batch, and `scripts/test-sweep.sh` asserts exactly that. Over-budget work is likewise reported un-adjudicated per member (`_sweep_run_batch:517–522`), never dropped. Two adjacent claims also hold: `GOVERNANCE_SWEEP_BUDGET` defaults to 20 and 3 in push mode (`sweep.sh:58–59`, `702–706`), and the opt-in pre-push stanza (`kit/assets/packs/lib/hooks.sh:485–518`) discards the driver's exit status with a literal `|| true` under a comment that says so.

4. **The 13 bundled intent rubrics are real, are `sink: none`, and — with two named exceptions — touched nothing but `directive.yaml` — PASS with a scoping caveat.** Parsing every shipped `directive.yaml` through the repo's own `kityaml` shows **15** `subagent:` blocks under `packs/`, i.e. every bundled directive now declares its intent: the 2 pre-existing attest+sweep declarations (`receipt-per-issue`, `agent-steering-accounting`) plus exactly the **13** the receipt names, each with `inputs: [range-diff]`, `sink: none`, `tiers: { sweep: high }` and 3–5 checks (measured: agent-token-accounting 5, commit-issue-receipt-match 4, doc-integrity 4, issue-templates 4, issues-tracked 3, toolchain-config-protection 3, commit-message-format 4, no-orphan-todos 3, no-unjustified-suppressions 3, internal-doc-links 3, managed-tree-integrity 3, repo-hygiene 3, required-docs 4) — matching "three to five adjudicable statements". `git diff --name-only origin/main` per directive folder returns **exactly one file** for 11 of the 13. **The caveat, stated plainly:** it returns 24 files for `agent-token-accounting` and 6 for `managed-tree-integrity`, whose `check.sh`, `constitution.md`, `defaults.conf` and `evals/test.sh` all changed in this same change set. Those changes come from Track B and Q11 respectively, not from the rubric work — but the receipt's sentence "No `check.sh`, constitution, defaults, or eval changed — the mechanical gates are untouched" is scoped to "the 13 bundled directives", and as written it is false for 2 of the 13. See finding 7.

5. **The repo-local conversion, the `packctl` exemption, and the CONSTITUTION.md mirror are all correct — PASS.** Both converted directives now carry `subagent: { inputs: [range-diff], checks: [5 statements], sink: none, tiers: { sweep: high } }` and, correctly, **no `surface:` field at all**. `packctl.py:299–316` exempts `surface` and `packctl.py:365–371` exempts `check.sh` when `subagent.sink == "none"`, each under a comment explaining that both fields describe commit-lane semantics a `sink: none` directive does not have. Running `packctl.validate_pack_dir` on `.governance/packs/duaility/governance-kit` directly returns **no `surface` and no `check.sh` error** for either converted directive — only the 8 pre-existing `evals/test.sh missing` notices that apply uniformly to every repo-local directive in that pack, which is the documented repo-local convention. `bash .governance/run.sh` reports "all **19** directive(s) passed" with `no-legacy-fallbacks` and `no-path-bifurcation` correctly **absent** from the executed list — commit-path discovery skips them because they now have no `check.sh`. On the constitution mirror I wrote a scripted comparison of all **21** subsections in `CONSTITUTION.md` against their `.governance/packs/**/constitution.md` bodies: **19 are byte-identical**, and the 2 that differ (`consumed-tree-integrity`, `layer-boundaries`) diverge at fixed byte offsets 1220 and 1853 on prose this change set never touches — I re-ran the same comparison against `origin/main` and both divergences are **pre-existing and identical there**, so nothing in this change set introduced drift. Every subsection this change set does touch — the two converted sweep directives' Enforced-by lines and the three dependency-posture directives — mirrors byte-for-byte, and the second Evolution Log entry for the unification is present at `CONSTITUTION.md:297`.

6. **The `## Files` appendix covers the change set completely — PASS on coverage, with an over-listing defect.** Mechanically diffed the appendix's 150 unique paths against the 134-path verified change set. **Nothing in the change set is missing from the appendix** except `receipts/issue-355-agent-adjudicated-gates.md` itself, which the appendix's own preamble excludes and which `receipt-per-issue` rule 6 exempts — so file coverage passes. The reverse direction is where it is imprecise: **17 listed paths are not in the change set at all.** Sixteen carry honest annotations, but the annotations are wrong about the reference frame: `packs/foundation/directives/{no-commit-path-python,no-package-manager,stdlib-only-python}/*` (15 paths) are annotated "(moved to .governance/…)" / "(deleted — …)", yet `git ls-tree -r --name-only origin/main` and `git ls-tree -r --name-only HEAD` both show they **never existed in either tree** — they were created and removed entirely inside the uncommitted worktree evolution, so nothing was moved *in the change set*, only in the session's history. `packs/audit/directives/agent-token-accounting/lib/endpoint.sh` is the one entry that states this correctly ("net absent vs main"). The seventeenth, **`packs/foundation/pack.yaml`, is listed with no annotation and has a completely empty diff** against `origin/main`. Over-listing does not fail `receipt-per-issue` (the rule is one-directional), and it errs toward disclosure rather than concealment, so this is a defect of precision, not of honesty — but the appendix should not be read as an accurate inventory of what this PR changes.

7. **Two receipt statements do not survive checking — REFUTED, both narrow.** (a) `## What changed`, intent-rubrics paragraph: "No `check.sh`, constitution, defaults, or eval changed — the mechanical gates are untouched" — **false as written** for `agent-token-accounting` and `managed-tree-integrity`, 2 of the 13 named directives, per finding 4. The intended claim ("no such file changed *because of the rubric addition*") is true and verifiable; the sentence as published overstates it, and a reader checking `git diff --stat` on those two folders will conclude the receipt is wrong. (b) `## Decisions`, "One judgment primitive, harness-pegged": "and `run` always exits 0" — **false**. `kit/assets/dot-governance/sweep.sh`'s `cmd_run` ends with a `gh issue create` failure branch that prints the digest to stderr and `return 1`, and the dispatcher at the bottom of the file is `run) cmd_run "$@"; exit $?`. So `sweep.sh run` exits 1 whenever digest filing fails. The *operational* claim around it survives intact — no gate consumes that status, because the pre-push stanza discards it with `|| true` and the workflow is a cron job — so "judges never block where they run" still holds; it is the absolute wording "always exits 0" that is wrong, and it is wrong in the direction of over-claiming. Every other verdict-bearing sentence I sampled in `## What changed` and `## Decisions` checked out.

8. **Every `- [x]` Checklist item is realized — PASS (10 of 10).** Items 1–8 were verified by the prior passes and re-confirmed here where the delta could have invalidated them: item 1 (`grep -n python kit/assets/dot-governance/lib.sh` hits only comments); item 2 (`_subagent_verdict_gate:648`, `_adjudication_stamp:572`, the round ERE at `lib.sh:485` covering `PASS|REFUTED|ESCALATED|CONTESTED`, the append-only protected ERE at `:646`, `SUBAGENT_ROUNDS`/`SUBAGENT_EXECUTOR`/`SUBAGENT_MODELS_{LOW,MEDIUM,HIGH}` at `:411/:434/:449–451`); item 3 now completed by the unification (the declaration is the *only* sweep contract, per findings 1–2); item 4 (7 adapters at `kit/assets/dot-governance/runtimes/`, each dispatching exactly `judge` / `can-judge` / `resolve` / `emit` — verified by grepping the case arms of all seven files, and there is **no `cost` arm** anywhere); items 5–7 unchanged and re-confirmed by the green suites; item 8 (all three dependency-posture directives run live in `.governance/run.sh`'s 19). The two items **new since the last pass** are both realized: item 9 ("Unify the sweep lane … `surface: sweep` retired") per findings 1–3 and 5, with `scripts/test-sweep.sh` running as its own layer inside `scripts/test.sh:137–139` and reporting "✓ sweep: **125** assertion(s) passed" — the exact figure the receipt's `## Verification` claims; item 10 ("Declare every bundled directive's intent … 13 `subagent:` blocks") per finding 4, with the caveat in finding 7(a).

9. **All three named suites re-run by me, green — PASS.** `bash scripts/test.sh` exits 0 with "✓ all kit-internal test layers passed" across **22** layers (counted from the run's own banner lines — matching the `## Verification` fence's "all 22 kit-internal layers"), including `test-runtime: 206 assertion(s)`, `sweep: 125 assertion(s)`, `test-install-sh: 77`, `test-hooks-sh: 84`, `test-schema-split: 28`, `test-digestlib: 19`, and "test-packs: 3 pack(s), 15 directive(s), 15 eval(s) passed". `bash .governance/run.sh` reports "✓ governance: all 19 directive(s) passed". `node scripts/docs-site/gen-reference.mjs --check` prints "docs reference pages are up to date with kit/references" and exits 0 — so the regenerated `docs/reference/*.mdx` pages genuinely track the rewritten `SWEEP_FLOW.md` / `DIRECTIVE_AUTHORING.md` / `PACK_AUTHORING.md` / `INSTALL_SCHEMA.md` sources rather than having been hand-edited.

10. **One shipped-code comment drifted behind the code it describes — flagged, not fatal.** `kit/assets/packs/lib/applylib.py:42–43` still reads: "One file per harness at `<tests_dir>/runtimes/<name>.sh`, answering two verbs — `cost` (what the accounting lane asks) and `judge` …". There is no `cost` verb on any adapter (finding 8) and there are four verbs, not two; the accounting lane asks `resolve`. The receipt's own prose is right and the code comment is wrong, so this is a stale-comment defect introduced by this change set rather than a receipt inaccuracy — worth a one-line fix before merge, since `applylib.py` is the file a future adapter author reads first. Note also that the `### Costs` rows in this receipt's own `## Accounting` are 16-column v5-era rows, not the v6 10-column shape this PR introduces: that is correct and expected, because those rows were written by the **pinned, pre-#355** hooks in the consumed `.governance/` tree, which this PR deliberately does not update.

## Layer boundaries

1. **Every changed file sits in the layer its role belongs to — PASS.** Kit engine and runtime code is under `kit/`: the new bash sweep driver at `kit/assets/dot-governance/sweep.sh`, the shared judgment helpers in `kit/assets/dot-governance/lib.sh`, the seven-adapter registry at `kit/assets/dot-governance/runtimes/`, the lifecycle libs at `kit/assets/packs/lib/*.py`, the seeded workflow template at `kit/assets/governance-sweep.yml`, and the normative flow docs at `kit/references/`. Pack-owned directive content is under `packs/<concern>/directives/<id>/` — the 13 intent rubrics are pure `directive.yaml` additions inside the directives that own them, and the accounting/integrity rewrites stay inside `agent-token-accounting`, `agent-steering-accounting` and `managed-tree-integrity`. Repo-local dogfood is under `.governance/packs/duaility/governance-kit/` — the two converted sweep directives and the three dependency-posture self-directives, all on the hand-authored `source: local` pack, the one tree under `.governance/` this repo's conventions carve out as legitimately hand-edited. Tests are under `scripts/` — `test-sweep.sh` replacing `test-sweep.py`, wired as its own layer in `scripts/test.sh`. No file crosses.

2. **The sweep driver's placement in the kit is the right call, judged on the merits — PASS.** The alternative placements are worth naming to see why. It cannot live in a pack: it is the at-rest executor for *any* directive's `subagent:` block regardless of which pack ships it, so a pack-owned driver would make every other pack depend on that pack. It cannot live under `scripts/`: `scripts/` is never shipped, and this file must be **vendored into consumer repos** — `applylib.py:37–40`'s `SWEEP_ASSETS` maps `.governance/sweep.sh` to `("dot-governance", "sweep.sh")` beside the workflow, `seed_sweep_assets` stamps it with the kit-version marker and chmods it 0755, and `managed-tree-integrity` digest-guards it (its eval now has explicit "sweep driver match / modified / waiver / seed-time marker" cases). Sitting in `kit/assets/dot-governance/` beside `lib.sh` and `run.sh` is precisely the layer for "a runtime file the kit ships into every consumer's `.governance/`", and putting it beside `lib.sh` is what makes the source-and-reuse in finding 2 of the Audit a same-layer call rather than a cross-layer reach. Correct, not merely defensible.

3. **Putting the rubric in `directive.yaml` rather than in a new sibling artifact is the right call — PASS.** The rubric is *metadata about the directive*, and `directive.yaml` is where this repo already puts per-directive metadata that both the commit lane and the install engine read. The counterfactual — a `rubric.md` or a revived `triage.sh` beside `check.sh` — would have meant a second file for every directive, a second parser in `lib.sh`, `applylib.py`, `packctl.py` and the sweep driver, and a second thing to keep in sync with `constitution.md`. The receipt's `## Decisions` entry "The declaration schema did not move" is the correct instinct and holds under checking: `tiers`/`gate`/`sink`/`isolation` already encoded both lanes, so no field was added, no parser churned, and the unification landed in the executor rather than the YAML. The layering consequence is also right: `constitution.md` states the directive's *rule* for humans, `check.sh` proves its *letter* mechanically, and the `subagent:` block declares its *spirit* for a judge — three artifacts, three audiences, one folder, and `packctl`'s `sink: none` exemptions keep a rubric-only directive from being forced to carry a commit-lane `check.sh` it has no use for.

4. **No dependency points the wrong way across a layer edge — PASS, with one residual duplication named.** Kit code references no pack path: `grep -rn "packs/audit\|packs/foundation\|packs/commits" kit/assets` finds nothing executable. The one direction that could have gone wrong did not: `sweep.sh` needs to know which harness is live, and `packs/audit/.../lib/runtime.sh:196`'s `detect_runtime_identity` already computes that — but importing it would make **kit code depend on a pack**, inverting the edge. The driver instead re-detects the same env signals inline (`_sweep_detect_adapter:126–153`) under a comment that states the reason: "deliberately re-detected here rather than imported, so this driver stays kit-level and does not depend on a pack." That is the correct trade — a wrong-way dependency is strictly worse than a duplicated five-branch env ladder — and the two ladders are honestly not identical in purpose (the pack's resolves *identity for accounting* including `manual`/`AGENT_NAME` and an identity-file fallback; the kit's resolves *a judge* and deliberately skips `manual`, because a human is not a CLI). **But it is a real duplication of the `CLAUDECODE` / `CODEX_THREAD_ID` / `PI_CODING_AGENT` / `CURSOR_AGENT` / `OPENCODE` signal set across two layers, and it will drift the day an eighth harness is added.** The receipt does not disclose it anywhere in `## Decisions`, and it should — this is exactly the kind of "two hand-kept copies of the same logic" that this repo's own `no-path-bifurcation` rubric asks a judge to flag. Recording it here rather than treating it as a blocking fault: the layer call is right, the cost is real and currently undocumented.

5. **New shared logic lives in the layer that owns it — PASS.** The judgment primitive was not duplicated into a second engine: the prompt builder, the declaration reader, the tier/model conf ladder, the stamp and the round appender all stayed in `lib.sh` and the sweep driver calls them (Audit finding 2). The one place logic *is* duplicated inside the pack layer — the verbatim-twin `lib/receipt.sh` under `agent-token-accounting` and `agent-steering-accounting` — remains labelled intentional in the file's own header on the documented "a directive folder installs as a self-contained unit" convention, and is judged on that convention's terms rather than faulted for not being hoisted into a shared kit lib.

## Steering

1. **The `## Accounting` → `### Steering` ledger is missing this session's steering events — REFUTED.** The ledger's 8 rows end at `ordinal 718` / `2026-08-04T14:31:37Z` (`steer-1419af64024c-1785853897-8`, "Challenged shipping repo-specific dependency-posture directives in the bundled packs"). That row is the last event of the *previous* work phase. The session transcript at `/Users/srikanth/.claude/projects/-Users-srikanth-gitspace-governance-kit--claude-worktrees-governance-kit-issue-355-d2b39d/1419af64-024c-4b9a-97ec-a471fe4c95b5.jsonl` has since grown from 871 to **2364 lines**, and a full pass over it — filtering tool-result envelopes, `/model` and `/compact` local-command echoes, the two auto-generated compaction summaries, and the post-compaction replays of already-recorded messages at lines 1730–2204 — finds **four further genuine human steering events, none of them recorded**:
   - **`2026-08-04T15:23:05Z`** (JSONL line 1255, `type: user`) — "let's rethink about sweep feature from scratch....w're in v0, so le't not worry about compat". A first-principles redesign demand that explicitly waives backward compatibility; it is the origin of the entire sweep-unification body of work under audit. Same class as the already-recorded row 7 ("Demanded a first-principles rethink instead of incremental patching").
   - **`2026-08-04T15:26:09Z`** (JSONL line 1266, `type: user`) — "wait, we need to move out of github models and judge...everything should be pegged to hanress (codex, claude-code, copilot, cursor etc)... in our PR, we already shipped a vaiant of sweep where we declare as non-blocking/blocking..let's unify the paradigm". The single most consequential correction in the change set: it is the direct cause of the GitHub Models deletion, the harness-pegged adapter judge, and the "one judgment primitive, two moments" framing that `## Decisions` now records as the PR's central design.
   - **`2026-08-04T16:09:10Z`** (JSONL lines 1469 / 1481) — "right now, we dont' have the concept of grouping as part of subagent sectiosn...for e.g. let's say couple of dirctives want to be executed simultaneously (to save token costs, share context), is that a good ask?". This is the event that caused batching to be restored to the new driver — i.e. it produced `_sweep_batch_tier`, `_sweep_block`, the batch-spec argument to `_subagent_cli_prompt`, and the whole "Batching is one knob across both lanes" decision.
   - **`2026-08-04T16:15:53Z`** (JSONL lines 1592 / 1601) — "okay, and for existing core dreictivies, I don't see directive sections for exsting directives...for e.g..for receipt related directive, I expecte subagent section...in fact, we need to add these to all existing core pack directives ....". This is the sole origin of checklist item 10 and the 13 intent rubrics; without it that entire body of work does not exist.

   The last two arrive in the JSONL as `type: queue-operation` / `type: attachment` records rather than as `type: user` message entries, because they were typed while a turn was in flight and were queued. That is a transport artifact, not a reason to exclude them: both attachment records carry `"origin": {"kind": "human"}`, `"commandMode": "prompt"`, `"userType": "external"` and the session's own `sessionId`, which is affirmative evidence that a human typed them. A steering ledger that silently drops human corrections because of how the harness serialized them would be exactly the failure mode the directive exists to prevent — and these two are not marginal: between them they produced the batching subsystem and 13 of the change set's directive edits.

2. **The events that were correctly *excluded* were excluded on consistent grounds — PASS.** Three post-row-8 user messages are genuine but legitimately not steering, and I checked each against the precedent the ledger already set with line 537: `2026-08-04T15:19:28Z` (line 1219) "okay, how is sweep configured for directives" is an information request that changed no direction — the session's own compaction summary independently classifies it as "an informational question"; `2026-08-04T15:28:46Z` (line 1272) "yes, fold all your changes ito this PR...act as orcehstrator and span opus/sonnet/haiku subagents" is an endorsement-plus-continuation, byte-for-byte the same shape as the already-excluded line 537 / line 2081 message; and every `/model` and `/compact` echo in the 1200–2364 range is a `<local-command-*>` artifact. Symmetrically, **no non-steering message is recorded as a steering event** — all 8 existing rows still resolve to genuine human corrections at their stated ordinals, `bash packs/audit/directives/agent-steering-accounting/lib/steering.sh validate-dir receipts` still exits 0 against the table (well-formed keys, valid type/tier enums, strictly increasing ordinals 418 < 481 < 484 < 490 < 504 < 520 < 527 < 718, `#355` on every row), and the pack's `check.sh` passes in `.governance/run.sh`. That is precisely why finding 1 needs stating here: the mechanical directive validates the *shape* of the rows that exist and structurally cannot detect rows that are **absent**, so completeness is this audit's job alone — and on completeness the ledger currently fails. Remedy is four appended rows (`ordinal` = 1255, 1266, 1469, 1592; `timestamp` = the four ISO values above; `type: correction`, `tier: classifier`; `idx` 9–12 continuing the per-session sequence, with strictly increasing epochs 1785856985 < 1785857169 < 1785859750 < 1785860153, each greater than row 8's 1785853897), after which this verdict flips to PASS.

## Files

Every path touched by this change set (excluding this receipt):

- .github/workflows/tests.yml
- .governance/packs.lock (repo-local pack's directive list only — `source: local`, no digest block)
- .governance/packs/duaility/governance-kit/directives/no-commit-path-python/check.sh
- .governance/packs/duaility/governance-kit/directives/no-commit-path-python/constitution.md
- .governance/packs/duaility/governance-kit/directives/no-commit-path-python/defaults.conf
- .governance/packs/duaility/governance-kit/directives/no-commit-path-python/directive.yaml
- .governance/packs/duaility/governance-kit/directives/no-legacy-fallbacks/constitution.md
- .governance/packs/duaility/governance-kit/directives/no-legacy-fallbacks/directive.yaml (converted to a `subagent:` declaration by the sweep unification)
- .governance/packs/duaility/governance-kit/directives/no-legacy-fallbacks/triage.sh (deleted — the triage contract is retired)
- .governance/packs/duaility/governance-kit/directives/no-package-manager/check.sh
- .governance/packs/duaility/governance-kit/directives/no-package-manager/constitution.md
- .governance/packs/duaility/governance-kit/directives/no-package-manager/defaults.conf
- .governance/packs/duaility/governance-kit/directives/no-package-manager/directive.yaml
- .governance/packs/duaility/governance-kit/directives/no-path-bifurcation/constitution.md
- .governance/packs/duaility/governance-kit/directives/no-path-bifurcation/directive.yaml (converted to a `subagent:` declaration by the sweep unification)
- .governance/packs/duaility/governance-kit/directives/no-path-bifurcation/triage.sh (deleted — the triage contract is retired)
- .governance/packs/duaility/governance-kit/directives/stdlib-only-python/check.sh
- .governance/packs/duaility/governance-kit/directives/stdlib-only-python/constitution.md
- .governance/packs/duaility/governance-kit/directives/stdlib-only-python/defaults.conf
- .governance/packs/duaility/governance-kit/directives/stdlib-only-python/directive.yaml
- AGENTS.md
- CONSTITUTION.md (three repo-local directive subsections, two sweep-directive Enforced-by lines, and two Evolution Log entries)
- docs/concepts/audit-chain.mdx
- docs/concepts/runtime.mdx
- docs/guide/quickstart.mdx
- docs/reference/authoring-directives.mdx (regenerated)
- docs/reference/authoring-packs.mdx (regenerated)
- docs/reference/directive-catalog.mdx (regenerated)
- docs/reference/native-tests.mdx (regenerated)
- docs/reference/schemas.mdx (regenerated)
- kit/assets/dot-governance/lib.sh
- kit/assets/dot-governance/runtimes/claude-code.sh
- kit/assets/dot-governance/runtimes/codex.sh
- kit/assets/dot-governance/runtimes/cursor-agent.sh
- kit/assets/dot-governance/runtimes/grok.sh
- kit/assets/dot-governance/runtimes/manual.sh
- kit/assets/dot-governance/runtimes/opencode.sh
- kit/assets/dot-governance/runtimes/pi.sh
- kit/assets/dot-governance/sweep.py (deleted — the sweep unification replaces the Python engine with the bash driver)
- kit/assets/dot-governance/sweep.sh
- kit/assets/governance-sweep.yml (rewritten — harness-pegged, no `models: read`)
- kit/assets/packs/lib/applylib.py
- kit/assets/packs/lib/digestlib.py
- kit/assets/packs/lib/eval-lib.sh
- kit/assets/packs/lib/hooks.sh
- kit/assets/packs/lib/initapply.py
- kit/assets/packs/lib/install.sh
- kit/assets/packs/lib/kityaml.py
- kit/assets/packs/lib/kitverb.py
- kit/assets/packs/lib/packapply.py
- kit/assets/packs/lib/packctl.py
- kit/assets/packs/lib/packs.sh
- kit/assets/packs/lib/packverb.py
- kit/assets/receipt.bootstrap.template.md
- kit/references/DIRECTIVES_CATALOG.md
- kit/references/DIRECTIVE_AUTHORING.md
- kit/references/INIT_FLOW.md
- kit/references/INSTALL_SCHEMA.md
- kit/references/LIB_API.md
- kit/references/NATIVE_TESTS.md
- kit/references/PACK_AUTHORING.md
- kit/references/JUDGE.md (renamed from kit/references/SUBAGENT_ATTESTATION.md)
- .governance/packs/duaility/governance-kit/directives/layer-boundaries/check.sh (judge_attest rename)
- .governance/packs/duaility/governance-kit/directives/layer-boundaries/constitution.md (judge: rename, mirrored into CONSTITUTION.md)
- .governance/packs/duaility/governance-kit/directives/layer-boundaries/directive.yaml (judge: rename)
- docs/concepts/limitations.mdx (judge: rename)
- docs/guide/introduction.mdx (judge: rename)
- kit/assets/dot-governance/run.sh (judge: rename in comments)
- kit/assets/packs/lib/packvalidate.py (split out of packctl.py for the 500-line repo-hygiene limit; owns validate_judge_cmd and the retired-key errors)
- packs/audit/directives/agent-steering-accounting/defaults.conf (retired SUBAGENT_ISOLATION/SUBAGENT_TIERS_* rows removed)
- packs/audit/directives/receipt-per-issue/check.sh (judge_attest rename)
- packs/audit/directives/receipt-per-issue/defaults.conf (retired SUBAGENT_ISOLATION/SUBAGENT_TIERS_* rows removed)
- packs/audit/directives/receipt-per-issue/directive.yaml (judge: rename)
- kit/references/SWEEP_FLOW.md
- kit/references/UNINSTALL_FLOW.md
- kit/references/UNINSTALL_MATRIX.md
- kit/references/UPDATE_FLOW.md
- packs/audit/pack.yaml (comment-only: sweep asset rename)
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
- packs/audit/directives/agent-token-accounting/hooks/post-commit.sh
- packs/audit/directives/agent-token-accounting/hooks/pre-commit.sh
- packs/audit/directives/agent-token-accounting/hooks/pre-push.sh
- packs/audit/directives/agent-token-accounting/lib/argv.py (deleted)
- packs/audit/directives/agent-token-accounting/lib/costs.sh
- packs/audit/directives/agent-token-accounting/lib/endpoint.py (deleted)
- packs/audit/directives/agent-token-accounting/lib/endpoint.sh (added by this PR's first iteration, deleted by the accounting redesign — net absent vs main)
- packs/audit/directives/agent-token-accounting/lib/ledger.py (deleted)
- packs/audit/directives/agent-token-accounting/lib/rates.py (deleted)
- packs/audit/directives/agent-token-accounting/lib/receipt.sh
- packs/audit/directives/agent-token-accounting/lib/receipt_io.py (deleted)
- packs/audit/directives/agent-token-accounting/lib/reconcile.py (deleted)
- packs/audit/directives/agent-token-accounting/lib/report.py (deleted)
- packs/audit/directives/agent-token-accounting/lib/resolve.sh
- packs/audit/directives/agent-token-accounting/lib/runtime.sh
- packs/audit/directives/agent-token-accounting/lib/validate.py (deleted)
- packs/audit/directives/agent-token-accounting/lib/validate.sh
- packs/audit/directives/agent-token-accounting/runtimes/claude-code.sh (moved to kit/assets/dot-governance/runtimes/)
- packs/audit/directives/agent-token-accounting/runtimes/codex.sh (moved to kit/assets/dot-governance/runtimes/)
- packs/audit/directives/commit-issue-receipt-match/directive.yaml (intent rubric)
- packs/audit/directives/doc-integrity/directive.yaml (intent rubric)
- packs/audit/directives/issue-templates/directive.yaml (intent rubric)
- packs/audit/directives/issues-tracked/directive.yaml (intent rubric)
- packs/audit/directives/receipt-per-issue/constitution.md
- packs/audit/directives/toolchain-config-protection/directive.yaml (intent rubric)
- packs/commits/directives/commit-message-format/directive.yaml (intent rubric)
- packs/commits/directives/no-orphan-todos/directive.yaml (intent rubric)
- packs/commits/directives/no-unjustified-suppressions/directive.yaml (intent rubric)
- packs/foundation/directives/internal-doc-links/directive.yaml (intent rubric)
- packs/foundation/directives/managed-tree-integrity/directive.yaml (intent rubric)
- packs/foundation/directives/repo-hygiene/directive.yaml (intent rubric)
- packs/foundation/directives/required-docs/directive.yaml (intent rubric)
- packs/foundation/directives/managed-tree-integrity/check.sh
- packs/foundation/directives/managed-tree-integrity/constitution.md
- packs/foundation/directives/managed-tree-integrity/evals/test.sh
- packs/foundation/directives/managed-tree-integrity/lib/digest.sh
- packs/foundation/directives/managed-tree-integrity/lib/integrity.py (deleted)
- packs/foundation/directives/no-commit-path-python/check.sh (moved to .governance/packs/duaility/governance-kit/directives/)
- packs/foundation/directives/no-commit-path-python/constitution.md (moved to .governance/packs/duaility/governance-kit/directives/)
- packs/foundation/directives/no-commit-path-python/defaults.conf (moved to .governance/packs/duaility/governance-kit/directives/)
- packs/foundation/directives/no-commit-path-python/directive.yaml (moved to .governance/packs/duaility/governance-kit/directives/)
- packs/foundation/directives/no-commit-path-python/evals/test.sh (deleted — repo-local directives carry no evals; they run live on this repo)
- packs/foundation/directives/no-package-manager/check.sh (moved to .governance/packs/duaility/governance-kit/directives/)
- packs/foundation/directives/no-package-manager/constitution.md (moved to .governance/packs/duaility/governance-kit/directives/)
- packs/foundation/directives/no-package-manager/defaults.conf (moved to .governance/packs/duaility/governance-kit/directives/)
- packs/foundation/directives/no-package-manager/directive.yaml (moved to .governance/packs/duaility/governance-kit/directives/)
- packs/foundation/directives/no-package-manager/evals/test.sh (deleted — repo-local directives carry no evals; they run live on this repo)
- packs/foundation/directives/stdlib-only-python/check.sh (moved to .governance/packs/duaility/governance-kit/directives/)
- packs/foundation/directives/stdlib-only-python/constitution.md (moved to .governance/packs/duaility/governance-kit/directives/)
- packs/foundation/directives/stdlib-only-python/defaults.conf (moved to .governance/packs/duaility/governance-kit/directives/)
- packs/foundation/directives/stdlib-only-python/directive.yaml (moved to .governance/packs/duaility/governance-kit/directives/)
- packs/foundation/directives/stdlib-only-python/evals/test.sh (deleted — repo-local directives carry no evals; they run live on this repo)
- packs/foundation/pack.yaml
- README.md
- scripts/release.sh (comment-only: sweep asset rename)
- scripts/test-digestlib.py
- scripts/test-init.py
- scripts/test-kityaml.py
- scripts/test-kitverb.py
- scripts/test-packctl-validate.py
- scripts/test-packs.sh
- scripts/test-packverb-apply.py
- scripts/test-runtime.sh
- scripts/test-schema-split.sh
- scripts/test-subagent.sh
- scripts/test-sweep.py (deleted — replaced by the bash test-sweep.sh)
- scripts/test-sweep.sh
- scripts/test.sh

## Accounting

<!-- Accounting rows are maintained by the agent-token-accounting and agent-steering-accounting pre-commit hooks. Keys are opaque — do not parse. -->

### Costs

| cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | cum-input | cum-cache-create | cum-cache-read | cum-output | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| claude-code-1419af64-024-1785848989-1 | claude-code | 1419af64-024c-4b9a-97ec-a471fe4c95b5 | #355 | claude-fable-5 | 276 | 748711 | 25049503 | 378484 | 1127471 | 53.3354 | 276 | 748711 | 25049503 | 378484 | feat(kit): agent-adjudicated gates + native-cost accounting (#355) -m Implements |
| claude-code-1419af64-024-1785856478-1 | claude-code | 1419af64-024c-4b9a-97ec-a471fe4c95b5 | #355 | claude-opus-5 | 374 | 1936919 | 31016482 | 347369 | 2284662 | 36.3001 | 650 | 2685630 | 56065985 | 725853 | feat(audit): identity at commit, measurement at rest (#355) -m Reworks this PR's |
| claude-code-1419af64-024-1785870384-1 | claude-code | 1419af64-024c-4b9a-97ec-a471fe4c95b5 | #355 | claude-opus-5 | 2659 | 10042140 | 156774292 | 1670968 | 11715767 | 182.9380 | 3309 | 12727770 | 212840277 | 2396821 |  |
| claude-code-1419af64-024-1785870556-1 | claude-code | 1419af64-024c-4b9a-97ec-a471fe4c95b5 | #355 | claude-opus-5 | 10 | 12448 | 1339529 | 3465 | 15923 | 0.8342 | 3319 | 12740218 | 214179806 | 2400286 |  |
| claude-code-1419af64-024-1785899162-1 | claude-code | 1419af64-024c-4b9a-97ec-a471fe4c95b5 | #355 | claude-opus-5 | 152 | 154986 | 8491116 | 31174 | 186312 | 5.9943 | 3471 | 12895204 | 222670922 | 2431460 | refactor(kit): bundled packs declare no batching label (#355)Strip `group: bundl |

### Steering

| steer-key | session | issue | type | tier | user-reason | commit | ordinal | timestamp |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| steer-1419af64024c-1785849236-1 | 1419af64-024c-4b9a-97ec-a471fe4c95b5 | #355 | correction | classifier | Reject fragile transcript parsing; add grok/cursor-agent/pi/opencode support | - | 418 | 2026-08-04T13:13:56Z |
| steer-1419af64024c-1785849711-2 | 1419af64-024c-4b9a-97ec-a471fe4c95b5 | #355 | interrupt | structural |  | - | 481 | 2026-08-04T13:21:51Z |
| steer-1419af64024c-1785849868-3 | 1419af64-024c-4b9a-97ec-a471fe4c95b5 | #355 | correction | classifier | Reject TS-plugin approach; keep repo self-contained, pure commit-time bash | - | 484 | 2026-08-04T13:24:28Z |
| steer-1419af64024c-1785850323-4 | 1419af64-024c-4b9a-97ec-a471fe4c95b5 | #355 | correction | classifier | Proposed triggering a native cost command via the harness session at hook time | - | 490 | 2026-08-04T13:32:03Z |
| steer-1419af64024c-1785850576-5 | 1419af64-024c-4b9a-97ec-a471fe4c95b5 | #355 | correction | classifier | Proposed using the session id to invoke each harness's own cost/resume CLI | - | 504 | 2026-08-04T13:36:16Z |
| steer-1419af64024c-1785850728-6 | 1419af64-024c-4b9a-97ec-a471fe4c95b5 | #355 | correction | classifier | Proposed encoding harness usage output in a fixed format the hook could read | - | 520 | 2026-08-04T13:38:48Z |
| steer-1419af64024c-1785850846-7 | 1419af64-024c-4b9a-97ec-a471fe4c95b5 | #355 | correction | classifier | Demanded a first-principles rethink instead of incremental patching | - | 527 | 2026-08-04T13:40:46Z |
| steer-1419af64024c-1785853897-8 | 1419af64-024c-4b9a-97ec-a471fe4c95b5 | #355 | correction | classifier | Challenged shipping repo-specific dependency-posture directives in the bundled packs | - | 718 | 2026-08-04T14:31:37Z |
