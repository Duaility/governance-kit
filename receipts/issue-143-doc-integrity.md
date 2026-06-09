# Receipt: enforce document integrity (append-only system-of-record docs)

Closes [#143](https://github.com/Duaility/governance-kit/issues/143).

The issue began as "receipts should be immutable," but the real concern is
**document integrity**: the repo's durable records are only evidence of what was
true when they landed if their history can't be quietly rewritten. That spans
more than receipts — the token/steering ledgers, the resolved-issues log, and
the constitution's own Evolution Log are all system-of-record documents whose
*historical* portion was unprotected (the accounting directives only validate
that new rows are well-formed, never that old ones survive). This change adds a
single config-driven `doc-integrity` directive with three modes covering all of
them, measured against the default-branch baseline so the current branch's own
in-flight content stays editable.

## Checklist

- [x] Author a config-driven doc-integrity directive with frozen-files, append-only, and frozen-section modes
- [x] Measure integrity against the default-branch baseline so branch-authored content stays editable
- [x] Add a path-scoped waiver `governance: allow-doc-integrity <path> <reason>`
- [x] Ship the integrity.conf asset template and opt this repo's four document classes in
- [x] Register doc-integrity in the standard preset and bump the pack version
- [x] Make doc-integrity always-install and ship integrity.conf with all rules enabled by default
- [x] Mirror the directive into CONSTITUTION.md and add an Evolution Log entry
- [x] Update the DIRECTIVES_CATALOG.md and README.md tables
- [x] Add a pack eval covering all three modes across Mode A and Mode B

## What changed

- **Author a config-driven doc-integrity directive with frozen-files,
  append-only, and frozen-section modes**: new directive folder at
  `packs/core/directives/doc-integrity/` (`directive.yaml`, `check.sh`,
  `constitution.md`, `evals/test.sh`). `check.sh` reads `.governance/integrity.conf`
  (no-op when absent, like `doc-freshness`) and dispatches each `<mode> <path>
  [arg]` rule. `frozen-files <glob>` freezes each baseline file byte-for-byte
  (new files OK); `append-only <file>` requires the baseline blob to be an exact
  byte-prefix of the current blob; `frozen-section <file> <heading>` requires
  every baseline line under a heading to still appear verbatim.
- **Measure integrity against the default-branch baseline so branch-authored
  content stays editable**: the baseline is `merge-base(HEAD, default branch)`;
  content absent there (a new receipt, a freshly appended ledger row) is the
  current change set's own work and is unconstrained. Once content is on the
  trunk it is frozen. When no default branch resolves (a commit on the trunk),
  the baseline falls back to HEAD. Same `commit-msg` hook + change-set surface as
  `commit-issue-receipt-match`: Mode A compares the baseline to the staged tree,
  Mode B walks `base..HEAD` in CI.
- **Add a path-scoped waiver `governance: allow-doc-integrity <path> <reason>`**:
  a reason-required line in a commit body (Mode A: the pending body; Mode B: any
  commit in range) exempts that path, for a coordinated reviewed rewrite.
- **Ship the integrity.conf asset template and opt this repo's four document
  classes in**: `governance/assets/integrity.conf` documents the schema, and the
  dogfood `.governance/integrity.conf` opts in `receipts/*.md` (frozen-files),
  `COSTS.md` + `STEERING.md` (append-only), and `QUALITY.md` Resolved +
  `CONSTITUTION.md` Evolution Log (frozen-section).
- **Register doc-integrity in the standard preset and bump the pack version**:
  `packs/core/pack.yaml` adds the directive to `standard` and bumps `version`
  0.3.3 → 0.3.4.
- **Make doc-integrity always-install and ship integrity.conf with all rules
  enabled by default**: `directive.yaml` gains `always_install: true` (joining
  `repo-hygiene` and `agent-steering-accounting`), so the directive installs in
  every repo regardless of preset. The shipped `governance/assets/integrity.conf`
  now has all four standard rules active (not commented examples), each a no-op
  until its document exists, so document integrity is on by default. `INIT_FLOW.md`
  seeds `integrity.conf` on every install; `UNINSTALL_FLOW.md`,
  `UNINSTALL_MATRIX.md`, and `UPDATE_FLOW.md` track it alongside `freshness.conf`;
  the `pack.yaml` comment, the `constitution.md` mirrors, the catalog, and the
  README note the `always_install` status.
- **Mirror the directive into CONSTITUTION.md and add an Evolution Log entry**:
  the root `CONSTITUTION.md` gains a `### doc-integrity` subsection matching the
  pack `constitution.md`, plus a dated Evolution Log entry — the cardinal rule
  (constitution change lands with its enforcing test) is satisfied in this commit.
- **Update the DIRECTIVES_CATALOG.md and README.md tables**: catalog row + the
  `standard` preset row, and the README core-directive table, now describe
  `doc-integrity`.
- **Add a pack eval covering all three modes across Mode A and Mode B**:
  `packs/core/directives/doc-integrity/evals/test.sh` drives eighteen assertions.

## Out of scope

- The existing corpus (receipts, `COSTS.md`, `STEERING.md`, `QUALITY.md`,
  `CONSTITUTION.md`) is untouched and not retroactively validated — the directive
  is forward-looking and freezes whatever is on the trunk from here on.
- Bumping `.governance/packs.lock` / re-materializing the dogfood so this repo
  *enforces* `doc-integrity` on itself is a separate release step (as with the
  `## Decisions` rule in #139, not yet in this repo's pinned pack). The dogfood
  `.governance/integrity.conf` is shipped now so it is ready when the lock bumps.
- Seeding `integrity.conf` automatically during `governance init` is left to a
  follow-up; the asset exists and a target repo can copy it.
- A `conservation` check for `QUALITY.md` (proving an item that left `Open`
  actually arrived in `Resolved`) is not attempted — entries have no stable IDs,
  so a move and a deletion are mechanically indistinguishable. `frozen-section`
  on `Resolved` is the achievable guarantee.

## Verification

- `bash packs/core/directives/doc-integrity/evals/test.sh` is green — eighteen
  assertions: frozen-files add (pass) / modify / delete (fail) / waiver (pass);
  append-only append (pass) / edit-row / remove-row (fail) / waiver (pass);
  frozen-section append-resolved / edit-open (pass) / edit-resolved /
  delete-resolved (fail), all in Mode A; and in Mode B: additions (pass),
  editing a branch-authored receipt (pass), a violation in each of the three
  modes (fail), and a waived rewrite (pass).
- `bash scripts/test-packs.sh` validates the pack manifest and runs every
  directive eval, including the new one.
- `bash scripts/test.sh` (the kit-internal umbrella) is green.

## Decisions

- **Generalized from receipts to a single document-integrity directive.** The
  first implementation was a receipts-only `receipt-immutable` directive. On
  review the underlying concern was broader — any system-of-record document needs
  append-only history — so it was reframed into one config-driven `doc-integrity`
  engine. This avoids 3-4 near-identical directives sharing one engine and lets
  target repos protect their own docs (`CHANGELOG.md`, ADRs) with a config line.
- **Three modes because the documents need genuinely different granularities.**
  Receipts are a *directory of independently-frozen files* (`frozen-files`);
  ledgers are *one growing file* (`append-only`, byte-prefix); `QUALITY.md` and
  the Evolution Log are *mutable files with a frozen sub-section*
  (`frozen-section`). A single mode could not express all three honestly.
- **`QUALITY.md` freezes only its `Resolved` section, not the whole file.** Its
  whole purpose is that items move `Open` → `Resolved` and get annotated, so
  whole-file append-only would break the intended workflow. Freezing only the
  historical `Resolved` half leaves `Open` as the live worklist. Conservation
  ("nothing silently vanishes from Open") was considered and dropped — entries
  lack stable IDs, so it isn't mechanically decidable.
- **Baseline is the default-branch merge-base, not HEAD.** This is the
  load-bearing decision (carried over from the receipts design): freezing against
  HEAD would make a branch's own in-flight receipt/ledger immutable the moment it
  was first committed, conflicting with `commit-issue-receipt-match`'s
  every-commit-touches-the-receipt rule. Scoping to the merge-base freezes only
  trunk history; reuses the base-resolution pattern the sibling directives use.
- **`frozen-files` matches the glob with a bash pattern, not a git pathspec.**
  `git ls-tree -- 'receipts/*.md'` returned nothing (git's pathspec wildcard
  semantics differ from what's wanted), so the engine lists all baseline files
  and filters with `[[ "$f" == $glob ]]`, where `*` crosses `/` predictably.
  Caught by the eval's frozen-files modify case failing to fire before the fix.
- **`append-only` compares a byte-prefix, not lines.** Using `git cat-file -s`
  for the baseline size and `head -c` on the current blob is robust to
  trailing-newline edge cases that a line-count prefix would mishandle.
- **The waiver is path-scoped (`allow-doc-integrity <path> <reason>`), not
  whole-directive.** A single change set might legitimately touch a frozen file
  while leaving the others protected, so the waiver names the exact path rather
  than disabling the directive for the commit.
- **Made `doc-integrity` `always_install: true` and shipped the conf enabled by
  default.** The directive belongs to the same audit chain as the other
  always-install directives and protects that chain's own artifacts, so gating it
  behind preset selection would let a repo keep the ledgers/receipts while leaving
  their history rewritable — the exact gap this closes. Shipping
  `integrity.conf` with all rules active (rather than commented examples like
  `freshness.conf`) makes integrity the default rather than an opt-in; the
  no-op-when-absent semantics keep that safe for repos that don't use a given file.
- **Fixed the stale `agent-steering-accounting` "opt-in" note in `README.md`**
  (both the table row and the prose) as part of this branch — it was wrong
  (mandatory since #101) and adjacent to the table I was already editing.
