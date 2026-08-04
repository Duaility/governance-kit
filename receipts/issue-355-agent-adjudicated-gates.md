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
`kit/assets/dot-governance/runtimes/` — seven adapters: claude-code, codex,
pi, grok, cursor-agent, opencode, manual — is seeded into consumer repos as
`.governance/runtimes/<name>.sh`, managed and digest-guarded like lib.sh.
Each adapter speaks three verbs: `judge` (read a declaration-built prompt on
stdin, run the CLI non-interactively, answer `VERDICT: PASS|REFUTED` plus
`REASON:` lines), `resolve` (report the session's cumulative usage from
declared surfaces only), and `emit` (accept the harness's own push payload
and append a snapshot; see Track B). `SUBAGENT_EXECUTOR=cli:<adapter>` (conf-resolved,
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
`skill/`, `.githooks/`), with Q11's sanctioned Python lanes — `sweep.py`, the
lifecycle libs — and the never-shipped `scripts/` excluded by scope. Each
matches at command position rather than by bare word, so prose and Markdown
never trip them. They run live here on every commit: a consumer repo needs
nothing but bash + git to commit; the kit's own tooling needs nothing but a
bare python3; nothing the kit ships needs a package manager.

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
`test-runtime.sh` (206 assertions across the seven adapters, including a
fixture proving two transcripts present with no identity yields exit 2 —
never a newest-file pick), `test-digestlib.py`, `test-init.py`,
`test-kitverb.py`, `test-sweep.py`, `test-packs.sh`, `test-schema-split.sh`
updated in place. Directive evals rewritten for the bash stacks (token 51,
steering 18 assertions) including identity-ladder, sidecar-fold, and
resolve-sweep fixtures. Verified under bash 3.2 and both BSD awk and mawk.

**Docs.** `SUBAGENT_ATTESTATION.md` (adjudicated gates, executors),
`SWEEP_FLOW.md` (subagent-declared path), `LIB_API.md`, `INSTALL_SCHEMA.md`
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
  in the post-release dogfood-sync PR, never by hand.
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
  and the Evolution Log entry land in this commit (the #280 precedent).

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
  `skill/`, `.githooks/` — with Q11's sanctioned Python lanes (`sweep.py`, the
  lifecycle libs) and the never-shipped `scripts/` out of scope, and
  `.github/workflows/` excluded from the package-manager rule because the docs
  site legitimately runs npm.
- **Command-position matching beats word matching.** Bare `grep -w python`
  fired on prose and on the directives' own ids; both checks now match only at
  command position (start of line, after a pipe/semicolon/subshell, or a
  workflow `run:`), so shipped Markdown and docstrings never trip them and no
  file needs a blanket exemption. `no-commit-path-python` also fails on a
  `#!…python` shebang — the comment filter had been silently ignoring the most
  literal form of the violation.

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
- Add the executor abstraction — harness | cli:<adapter> | api:<provider> (Phase 3) — done; registry seeding verified by `test-init.py`/`test-kitverb.py`, judge dispatch + degrade paths by `test-subagent.sh` (140 assertions) and `test-runtime.sh` (206 assertions).
- Generalize batching across the commit lane and the sweep engine (Phase 4) — done; executor-aware grouping and batch demux/retry covered in the same suites.
- Replace the hand-rolled accounting Python with identity-at-commit / measurement-at-rest accounting — Costs v6, snapshot sidecar, off-path resolver, seven runtime adapters (Track B) — done; token eval 51 assertions, steering eval 18, both green under BSD awk and mawk; an end-to-end smoke in a throwaway repo ran the post-commit resolve sweep against the real `manual.sh` adapter (sidecar snapshot appended), then the pre-commit stamp-and-fold produced a valid v6 row and `check.sh` passed; a two-transcripts-no-identity fixture proves the no-guessing rule (exit 2, no row).
- Eliminate PyYAML and uv via a restricted-YAML stdlib parser; port managed-tree-integrity to bash (Q11) — done; `git grep "import yaml"` over shipped code returns nothing, `scripts/test-kityaml.py` proves packs.lock byte parity, `scripts/test-digestlib.py` pins bash/python digest parity, and CI no longer installs uv.
- Ship the dependency-posture directives — no-commit-path-python, stdlib-only-python, no-package-manager — as repo-local self-directives (Q11) — done; all three run live in `bash .governance/run.sh`, which passes 19/19 (16 before this change). They carry no `evals/`, matching the five pre-existing repo-local directives: nothing runs evals under `.governance/`, and executing against this repo on every commit is the stronger signal. Each was teeth-tested by perturbing a real in-scope file (a `python3 -c` in a hook, a python shebang on a `check.sh`, a third-party import in `skill/bootstrap.py`, an `os.system("uv run …")`, a workflow `- run: npx …`), confirming the failure, and restoring.

`bash scripts/test.sh` → "✓ all kit-internal test layers passed" on the final
integrated tree.

## Audit

*(Re-audited fresh, from a clean sub-agent context, against the full change set — commit `7fecf8e` plus the uncommitted worktree layer, i.e. `git diff origin/main` — after Track B was redesigned mid-PR from an endpoint/checkpoint freeze scheme to identity-at-commit / measurement-at-rest. The prior audit below this line covered only `7fecf8e` in isolation and is superseded; its "Costs v5 / 17 columns" and "eleven deleted files" findings no longer hold against current code, and its "one user message" `## Steering` finding covered a transcript that has since grown from 325 to 711 lines.)*

1. **`## What changed` faithfully describes the diff — PASS.** Re-verified independently, not by trusting the receipt's own citations. Zero-Python commit path: `grep -n python kit/assets/dot-governance/lib.sh` hits only a comment. Deletions: `git diff origin/main --diff-filter=D --name-only -- packs/audit` returns exactly 12 paths — `ledger.py`×2 (token + steering), `receipt_io.py`×2, `rates.py`, `endpoint.py`, `reconcile.py`, `validate.py`, `argv.py`, `report.py`, and `runtimes/{claude-code,codex}.sh` (relocated to `kit/`) — matching the receipt's "the audit pack's re-derivation layer is deleted twice over" paragraph precisely (`report.py` is now in the deleted list too, unlike the stale prior audit). Track B / identity-at-commit: `detect_runtime_identity` is a real function in `packs/audit/directives/agent-token-accounting/lib/runtime.sh:196`, whose header states the split verbatim ("identity at commit, measurement at rest... the commit path resolves WHO is committing and nothing else"); `grep -rn -i "endpoint\|checkpoint" packs/audit/directives/agent-token-accounting/{lib,hooks,check.sh}` returns nothing live (only historical mentions in README/evals discussing the retired design) — and, decisively, `lib/endpoint.sh` and `lib/report.py`, both present in the committed tree at `7fecf8e` (`git show 7fecf8e:.../lib/endpoint.py` resolves), are confirmed **deleted** in the uncommitted layer (`git status --short` shows `D` for both; absent from the worktree). `lib/costs.sh` declares `COSTS_COLS_V6=10` with the exact `date|harness|session|model|input|cache-create|cache-read|output|cost-usd|source` header the receipt claims, and `lib/validate.sh:69` enforces exactly that 10-cell shape ("expected 10 (v6: ...)"), tolerating 17/16/12-cell legacy rows by cell count only, never re-validating them — matches "v5 and older rows are tolerated as legacy... and never re-judged." `lib/resolve.sh` and `hooks/{post-commit.sh,pre-push.sh}` exist with the documented `resolve_candidates`/`resolve_session`/`resolve_sweep` functions, and `hooks/pre-commit.sh`'s own header states verbatim: "It never reads a harness file, never parses a transcript, never sums a token... measurement lives in hooks/post-commit.sh and hooks/pre-push.sh" — exactly the stamp/fold split the receipt describes. The seven adapters at `kit/assets/dot-governance/runtimes/` (`claude-code`, `codex`, `cursor-agent`, `grok`, `manual`, `opencode`, `pi`) each dispatch `judge`/`resolve`/`emit` and nothing else — `grep -n '^\s*cost)' kit/assets/dot-governance/runtimes/*.sh` is empty, confirming the receipt's "three verbs... no `cost` verb" framing, and `grep -rn -- "ls -t\|-mmin" kit/assets/dot-governance/runtimes/ packs/audit/directives/agent-token-accounting/` hits only comments/docs/the eval's own forbidding regex, never live code — matching "no `ls -t`, no `-mmin`... those heuristics are deleted, not just avoided" in `claude-code.sh`'s own header. `bash scripts/test.sh` (re-run fresh for this delta pass) exits 0 with "✓ all kit-internal test layers passed," now including "3 pack(s), **15** directive(s), 15 eval(s) passed" — down from the 18/18 this same finding reported one pass ago, because the three dependency-posture directives no longer live under a pack-evaluated tree (see finding 2 item (8) and the `## Layer boundaries` update below). Independently, `bash .governance/run.sh` (also re-run fresh) now reports "✓ governance: all **19** directive(s) passed" — up from 16 before this delta — confirming the relocated trio is registered and passing live against this repo, not just present on disk. One methodology note, not a receipt defect, carried forward unchanged: `lib/resolve.sh`, `hooks/post-commit.sh`, `hooks/pre-push.sh`, and four of the seven adapters (`cursor-agent.sh`, `grok.sh`, `opencode.sh`, `pi.sh`) are still **untracked** (`git status --short` shows `??`), so a bare `git diff origin/main` silently omits them from its stat/patch output — this audit verified their existence and content directly via `ls`/`grep`/`Read` rather than trusting that diff. The receipt's own `## Files` section already lists all of them correctly, so nothing there needs correction.
2. **Each `- [x]` Checklist item is realized in the diff — PASS (8 of 8).** (1) lib.sh bash port — zero python invocations left, confirmed above. (2) `gate: verdict` machinery (`_subagent_verdict_gate`, `_adjudication_stamp`, the round-log ERE, the escalation ladder) is present in `lib.sh` and covered by `scripts/test-subagent.sh`, run clean inside `scripts/test.sh`; no shipped `directive.yaml` sets `gate: verdict` (`grep -rn "gate:" packs/*/directives/*/directive.yaml` is empty), matching the receipt's own "Out of scope" disclosure that no existing directive opts in yet. (3) sweep reads `subagent:` directly — `python3 scripts/test-sweep.py` runs inside `scripts/test.sh`. (4) executor abstraction — `SUBAGENT_EXECUTOR` conf resolution and the seven-adapter `judge` verb are real, per finding 1. (5) generalized batching — `attestation_remediation`'s executor-keyed grouping is unchanged from the prior audit's verified reading and still exercised by the same suites. (6) **the checklist item's own wording has changed since the prior audit** — it now reads "Replace the hand-rolled accounting Python with identity-at-commit / measurement-at-rest accounting — Costs v6, snapshot sidecar, off-path resolver, seven runtime adapters (Track B)," and every clause of that updated wording is independently verified true in finding 1 (v6/10-cell schema, the sidecar under `<git-dir>/governance/costs/<harness>-<session>` documented in `runtime.sh`'s header, the off-path `resolve.sh`, and the seven adapters). (7) PyYAML/uv elimination — `git grep -n "uv run\|astral-sh/setup-uv"` over `kit/ packs/ skill/ .github/ scripts/` returns only doc/comment/eval-fixture hits; `managed-tree-integrity/lib/integrity.py` is deleted and `lib/digest.sh` added, parity-pinned by `scripts/test-digestlib.py`. (8) **re-verified against the relocation delta, location updated.** The three posture directives no longer live under `packs/foundation/directives/` — `ls packs/foundation/directives/ | grep -E "no-commit-path-python|no-package-manager|stdlib-only-python"` returns nothing, and `git status --short` shows all fifteen of their old files (`check.sh`/`constitution.md`/`defaults.conf`/`directive.yaml`/`evals/test.sh` × 3) as `D`. They now live at `.governance/packs/duaility/governance-kit/directives/{no-commit-path-python,no-package-manager,stdlib-only-python}/` (confirmed present via `ls`), each carrying `check.sh`/`constitution.md`/`defaults.conf`/`directive.yaml` and, correctly, **no** `evals/` — matching the shape of the five pre-existing repo-local directives in the same pack (`architecture-map-holds`, `consumed-tree-integrity`, `layer-boundaries`, `no-legacy-fallbacks`, `no-path-bifurcation`, none of which ship evals either) and CONSTITUTION.md's Evolution Log entry's own claim that "these three now get their signal by running live on this repo every commit" rather than from fixtures. All three ids are registered in `.governance/packs.lock`'s `duaility/governance-kit` entry (`source: local`, no `digest:` block — consistent with every other directive on that entry) — confirmed by reading the lock directly. `bash .governance/run.sh` (re-run fresh) passes all three live, part of the "all 19 directive(s) passed" total in finding 1. The pack-eval count in finding 1 (now 15/15, was 18/18) reflects exactly this move — the trio's coverage relocated from `scripts/test-packs.sh` fixtures to live execution, it did not disappear.
3. **The `## Checklist` mirrors issue #355's Track B/Q10 intent — PASS**, judged against what the user actually redirected the work toward rather than Q10's original literal text (which specified "Endpoint semantics survive, implementation shrinks" — a scheme this PR itself superseded mid-flight). The session transcript's genuine steering events (cross-referenced against the fresh `## Steering` audit below) show the redirect explicitly: at transcript line 418 the user says "figure out creative way of extractig cost without falling back to transcript parsing..it is highly fragile," and at line 527, after a round of brainstorming, "take a step back, rethink from first principle, come up with elegant solution for the problem" — the `## Decisions` section's "Identity at commit, measurement at rest... This replaces the endpoint-freeze/checkpoint design from this PR's first iteration" entry is the direct record of that redirect. Judged against Q10's actual mandate ("the kit stops re-deriving session cost from transcripts and pricing tables... the harness's own number is strictly more reliable than anything the kit can reconstruct... All hand-rolled accounting Python goes away") and Q11's dependency endgame, every checklist item is realized: the kit still resolves a transcript path only where a harness (Claude Code, Codex) exposes no non-interactive cost surface — a documented transport constraint, not a re-derivation — and it never prices and never guesses identity via mtime (finding 1). No named phase, Q10 deliverable, or Q11 posture directive is missing.

## Layer boundaries

1. **Every changed file sits in the layer its role belongs to — PASS, including the mid-audit relocation.** `kit/assets/dot-governance/{lib.sh,sweep.py,runtimes/*}` and `kit/assets/packs/lib/*.py` are kit engine/runtime code, correctly under `kit/`. The accounting/integrity rewrites (including the new `lib/resolve.sh` and `hooks/{post-commit,pre-push}.sh` under `agent-token-accounting`) are pack-owned directive content, correctly under `packs/audit/directives/`. Tests live under `scripts/`. The one notable adapter relocation — `packs/audit/directives/agent-token-accounting/runtimes/{claude-code,codex}.sh` moving to `kit/assets/dot-governance/runtimes/`, now joined by four more adapters that were never pack-owned in the first place (`cursor-agent.sh`, `grok.sh`, `opencode.sh`, `pi.sh`) — matches its own stated rationale, confirmed by reading `lib/runtime.sh`'s header comment: the registry is kit-level "because 'which harness am I talking to' is one fact about the repo, not a per-directive one." That is a correct architectural call: the registry now serves three independent consumers per adapter (accounting's `resolve`/`emit` verbs and the commit gate's `judge` verb via `cli:<adapter>`), so kit-level ownership is the right layer, not a leftover of one directive. **The three dependency-posture directives, re-judged after their relocation, are now correctly placed too — PASS, not a wrong layer corrected to another wrong layer.** They no longer sit under `packs/foundation/directives/` (verified absent, per the Audit update) but under `.governance/packs/duaility/governance-kit/directives/{no-commit-path-python,no-package-manager,stdlib-only-python}/` — the repo-local, hand-authored (`source: local`) dogfood pack, the one location under `.governance/` this repo's own conventions carve out as legitimately hand-edited (AGENTS.md: "the one place under `.governance/` that is legitimately hand-authored"; confirmed structurally by `consumed-tree-integrity/check.sh`'s own comment: "For `source: local` packs it checks the vendored directive set matches the lock," i.e. no digest-byte-matching against an upstream release the way `gh`-sourced packs get). Judged on the merits against the CONSTITUTION.md Evolution Log's 2026-06-15 `#280` precedent (re-read directly, not taken on faith): `#280` relocated `no-legacy-fallbacks`, `no-path-bifurcation`, and `layer-boundaries` out of a bundled `governance-kit/architecture` pack into this exact same `duaility/governance-kit` pack for the identical reason — "architectural-*shape* invariants for *this* repo's own codebase... belong with the repo that declares the layer model, not in the published kit every consumer installs." The dependency-posture trio fits that test precisely: `no-commit-path-python`/`stdlib-only-python`/`no-package-manager` encode what *governance-kit itself* may ship, not a rule a consumer's own commit path should be judged against — and unlike a true consumer-facing rule, the previous placement was structurally unfixable in the field (it policed the vendored `.governance/` tree, kit-authored content a consumer cannot repair without a release). Relocating to the pack that is re-evaluated on every commit of *this* repo, rather than shipped for consumers to run against content they didn't write, is the correct layer call, not merely a defensible one.
2. **No dependency points the wrong way across a layer edge — PASS.** `grep -rn "packs/audit\|packs/foundation\|packs/commits\|packs/docs" kit/assets kit/references` returns nothing outside markdown prose (`DIRECTIVES_CATALOG.md`, `LOCK_SCHEMA.md`, `PACK_VERBS.md`, `VERSIONING.md` mention pack paths only in narrative text, never in executable code) — no kit code references a pack path. The reverse edge (pack → kit) is present but honest and floor-documented: `packs/audit/directives/agent-token-accounting/lib/runtime.sh`'s `_runtime_adapter_dir()` resolves the registry through an explicit fallback chain — `GOVERNANCE_RUNTIMES_DIR` override, `$GOVERNANCE_ROOT/runtimes`, `.governance/runtimes` (the installed, kit-managed location), then the kit source tree only for the uninstalled-checkout case — exactly the "installed tree" resolution pattern every other directive in this repo already uses to reach `lib.sh`, backed by `packs/audit/pack.yaml`'s `min_governance_kit: "0.12.0"` floor (re-confirmed unchanged). This is the pack depending on an artifact the kit ships to every installed consumer, not the pack reaching into kit source at authoring time.
3. **New shared logic lives in the layer that owns it — PASS, including the deliberate exception.** The runtime registry (shared resolve+judge logic) was correctly relocated to kit ownership per finding 1, not left duplicated per-pack. The one place logic *is* duplicated — `packs/audit/directives/agent-token-accounting/lib/receipt.sh` and `packs/audit/directives/agent-steering-accounting/lib/receipt.sh` — is explicitly labelled intentional in the steering copy's own header: "This file is deliberately a verbatim twin of the one in the sibling agent-token-accounting directive: a directive folder installs as a self-contained unit, so shared plumbing is duplicated rather than reached across directive boundaries... Keep the two in sync when either changes." This is judged on the convention's own documented terms (a self-contained-directive-folder invariant this repo already applies elsewhere), not faulted for failing to be deduplicated into a shared kit lib.

## Steering

*(Re-audited fresh, twice now. The session transcript at `/Users/srikanth/.claude/projects/-Users-srikanth-gitspace-governance-kit--claude-worktrees-governance-kit-issue-355-d2b39d/1419af64-024c-4b9a-97ec-a471fe4c95b5.jsonl` has grown again, from 711 to 871 lines, since the seven-row pass below this note — the user steered once more, post-relocation-request, and that event is now row 8. The original audit's "exactly one genuine user message, no steering owed" finding remains superseded by the seven-row pass; this update only adds the eighth row and re-confirms the count.)*

1. **Every human-steering event is recorded — PASS.** A full pass over every `type: user` entry across all 871 lines (re-run in full, not just the new tail, to catch anything the two prior passes might have missed — none found), filtered to drop tool-result envelopes, `<task-notification>` blocks, `<local-command-*>` markup (the `/model` and `/compact` command echoes), and the auto-generated post-compaction continuation summary (system-synthesized, not human-typed), leaves the initial task assignment (line 3, correctly excluded — task-setting) plus **eight genuine steering events**, all recorded as v2 rows under `## Accounting` → `### Steering`:
   - **line 418** (correction/classifier) — "take a step back...figure out creative way of extractig cost without falling back to transcript parsing..it is highly fragile...we need to add support for grok, cursor-agent, pi, opencode to...!" — the opening redirect of the Track B rework.
   - **line 481** (interrupt/structural) — the literal `[Request interrupted by user]` sentinel.
   - **line 484** (correction/classifier) — "...didn't like the option of creating TS plugin....as long as the repo is self-contained and pure commit time bash, i'm okay" — explicitly rejects a TS-plugin direction and re-scopes to bash-only.
   - **line 490** (correction/classifier) — proposes triggering a harness cost command via the session id the hook already receives.
   - **line 504** (correction/classifier) — "wait...there is one more thing...." — extends the previous proposal (each harness's resume CLI).
   - **line 520** (correction/classifier) — proposes a fixed usage-output format the hook could consume.
   - **line 527** (correction/classifier) — "take a step back, rethink from first pirinciple, come up with elegant solution for the problem!" — the explicit first-principles-rethink demand that produced the identity-at-commit design in `## Decisions`.
   - **line 718** (correction/classifier, new) — "there are fe more changs here...why are we inclduing repo sepcific directives into packs....the repo sepcific directives hould go into [/.governance/packs/duaility/governance-kit/directives](...)" — the exact correction that caused the relocation the coordinator flagged: it names the wrong destination (`packs/foundation/directives/`, a bundled pack) and the right one (`.governance/packs/duaility/governance-kit/directives/`, the repo-local dogfood pack), which is precisely where the trio now lives per the fresh `## Audit`/`## Layer boundaries` findings above.

   Each row's `ordinal` is the event's 1-based JSONL line number and `timestamp` is the entry's own ISO timestamp truncated to seconds, consistent across all eight rows including the new one (`ordinal=718`, `timestamp=2026-08-04T14:31:37Z`). `steer-key` for row 8 (`steer-1419af64024c-1785853897-8`) follows the same `session-short`/epoch/idx convention as the first seven — `idx=8`, continuing the per-session sequence rather than restarting it, and `1785853897` is the event's own timestamp converted to epoch seconds, confirmed strictly greater than row 7's `1785850846` (append-only epoch order holds). `bash packs/audit/directives/agent-steering-accounting/lib/steering.sh validate-dir receipts` passes (exit 0) against the eight-row table — well-formed keys, correct type/tier enums, strictly increasing per-session ordinals (418 < 481 < 484 < 490 < 504 < 520 < 527 < 718), and a receipt-homed `#355` issue on every row. Line 537 remains excluded for the reason given in the prior pass (endorsement/continuation, not a correction); no other candidate turned up between line 537 and line 718, or after line 718 through the end of the transcript.
2. **No non-steering message is recorded as a steering event — PASS.** Every `<task-notification>`, every `[TOOL_RESULT]` envelope, every `/model`/`/compact` local-command echo, and the auto-generated compaction summary were excluded by construction (finding 1) — none of them is a row in the table. Line 537 remains deliberately excluded. The new `/model claude-opus-5` echo immediately preceding line 718 (a local-command artifact, not a message) was checked and correctly excluded on the same grounds as the earlier `/model`/`/compact` echoes. Tool denials do not appear anywhere in the filtered candidate set for this session.

## Files

Every path touched by this change set (excluding this receipt):

- .github/workflows/tests.yml
- .governance/packs.lock (repo-local pack's directive list only — `source: local`, no digest block)
- .governance/packs/duaility/governance-kit/directives/no-commit-path-python/check.sh
- .governance/packs/duaility/governance-kit/directives/no-commit-path-python/constitution.md
- .governance/packs/duaility/governance-kit/directives/no-commit-path-python/defaults.conf
- .governance/packs/duaility/governance-kit/directives/no-commit-path-python/directive.yaml
- .governance/packs/duaility/governance-kit/directives/no-package-manager/check.sh
- .governance/packs/duaility/governance-kit/directives/no-package-manager/constitution.md
- .governance/packs/duaility/governance-kit/directives/no-package-manager/defaults.conf
- .governance/packs/duaility/governance-kit/directives/no-package-manager/directive.yaml
- .governance/packs/duaility/governance-kit/directives/stdlib-only-python/check.sh
- .governance/packs/duaility/governance-kit/directives/stdlib-only-python/constitution.md
- .governance/packs/duaility/governance-kit/directives/stdlib-only-python/defaults.conf
- .governance/packs/duaility/governance-kit/directives/stdlib-only-python/directive.yaml
- CONSTITUTION.md (three repo-local directive subsections + one Evolution Log entry)
- docs/concepts/audit-chain.mdx
- docs/concepts/runtime.mdx
- docs/guide/quickstart.mdx
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
- kit/references/NATIVE_TESTS.md
- kit/references/PACK_AUTHORING.md
- kit/references/SUBAGENT_ATTESTATION.md
- kit/references/SWEEP_FLOW.md
- kit/references/UNINSTALL_FLOW.md
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
| claude-code-1419af64-024-1785856478-1 | claude-code | 1419af64-024c-4b9a-97ec-a471fe4c95b5 | #355 | claude-opus-5 | 374 | 1936919 | 31016482 | 347369 | 2284662 | 36.3001 | 650 | 2685630 | 56065985 | 725853 | feat(audit): identity at commit, measurement at rest (#355) -m Reworks this PR's |

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
