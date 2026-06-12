# Receipt: move cost + steering accounting into per-issue receipts (#201)

Refactor that moves the accounting **write target** out of the central
`COSTS.md` / `STEERING.md` ledgers and into each issue's receipt, under a
`## Accounting` section. Keys, trailers, and the row↔trailer join are unchanged
— only where the rows live changed.

## Checklist

- [x] Cost rows append under ## Accounting in the issue's receipt
- [x] Steering rows append under ## Accounting in the issue's receipt
- [x] The hook creates the receipt with a ## Accounting section when absent
- [x] Both check.sh scripts validate receipt rows against trailers
- [x] COSTS.md and STEERING.md are sealed as frozen-files
- [x] Per-issue receipts make accounting writes conflict-free
- [x] A steering event with no issue is rejected
- [x] Cost-key gains a per-prefix counter suffix
- [x] An aggregation script reports per-issue and total spend across receipts
- [x] receipt-per-issue exempts accounting-only stubs and accepts slugless filenames

## What changed

- **Cost rows append under ## Accounting in the issue's receipt.**
  `packs/audit/directives/agent-token-accounting/lib/ledger.py` is rewritten to
  parse / append / validate the 12-column cost schema inside a receipt's
  `## Accounting` → `### Costs` sub-table instead of a central `COSTS.md`. The
  generic Markdown section/table plumbing lives in a new sibling
  `lib/receipt_io.py`. `hooks/pre-commit.sh` resolves the issue's receipt and
  appends there; `lib/trailers.py` cross-checks each commit trailer block
  against the matching row found across all `receipts/*.md`.
- **Steering rows append under ## Accounting in the issue's receipt.**
  `packs/audit/directives/agent-steering-accounting/lib/ledger.py` (plus its own
  `lib/receipt_io.py`) homes the 7-column steering schema in the receipt's
  `### Steering` sub-table; the pre-commit hook, `check.sh`, and `trailers.py`
  read and write there.
- **The hook creates the receipt with a ## Accounting section when absent.**
  `receipt_io.insert_table_row` creates the file, the `## Accounting` heading,
  and the relevant sub-table on demand, so the first accounted commit on a fresh
  issue just works.
- **Both check.sh scripts validate receipt rows against trailers**, including
  the multi-block squash path, and validate every receipt's sub-table shape plus
  global key uniqueness across `receipts/*.md`.
- **COSTS.md and STEERING.md are sealed as frozen-files.** `doc-integrity`'s
  `defaults.conf` flips the two ledgers from `append-only` to `frozen-files` and
  relies on `frozen-files receipts/*.md` for go-forward accounting history; the
  `config.conf` example and the directive summary are updated to match.
- **Per-issue receipts make accounting writes conflict-free** — only an issue's
  own PR branch writes its receipt, so two in-flight PRs never collide on a
  shared file tail (the central-ledger problem this refactor exists to fix).
- **A steering event with no issue is rejected**: the steering pre-commit hook
  refuses to write events it cannot attribute to an issue (issue #201, decision
  6), and the receipt steering validator rejects any issue-less row.
- **Cost-key gains a per-prefix counter suffix** (`<agent>-<session-short>-<epoch>-<n>`),
  minted via a new `next-cost-index` CLI, closing the same-second collision
  window; the schema docs note the key is opaque.
- **An aggregation script reports per-issue and total spend across receipts**:
  `agent-token-accounting/lib/report.py` walks every receipt's Accounting
  section and prints per-issue and grand totals (text or `--json`).
- **receipt-per-issue exempts accounting-only stubs and accepts slugless
  filenames**: the filename slug is now optional (`issue-<N>.md` is valid), and
  a receipt whose only `## ` heading is `## Accounting` is treated as a
  hook-created stub, exempt from the four-section / crosswalk / Decisions /
  Verification rules until the agent adds narrative.
- Documentation: both directive deep-dive `README.md`s, all four directive
  `constitution.md`s, `kit/references/DIRECTIVES_CATALOG.md`, `INIT_FLOW.md`,
  `PHILOSOPHY.md`, `INSTALL_SCHEMA.md`, the uninstall references, and the public
  `README.md` are de-staled to the receipt-homed model. The now-orphaned
  `kit/assets/COSTS.template.md` and the two `install-assets/{COSTS,STEERING}.md`
  ledger seeds are removed.

## Out of scope

- Migrating historical rows out of `COSTS.md` / `STEERING.md` (they remain as
  immutable history; no migration, no waiver).
- Editing this repo's live `COSTS.md` / `STEERING.md` headers. Under the
  two-lane dogfood (#200) the committed `.governance/` runs the *last released*
  directives, which still append to the live ledgers; sealing them and flipping
  doc-integrity on the live tree happens at the next release's `pack update`,
  which is exactly when the receipt-homed behavior activates here. See Decisions.
- Collapsing the audit directives or adding enable/disable config gates; a
  `requires:` directive-dependency field; period-sharding; CONSTITUTION.md
  Evolution Log growth (same disease, separate proposal).

## Verification

Full pack eval suite (all 19 directive evals, including the new receipt-homed
fixtures, the cost-key counter, the issueless-row rejection, and the
stub-exemption cases):

```sh
bash scripts/test-packs.sh
```

This repo's own governance suite (Lane 1) and the HEAD-sourced dogfood smoke
(Lane 2) both green:

```sh
bash .governance/run.sh
bash scripts/dogfood-smoke.sh
```

Manual: two branches for different issues, one accounted commit each, merge both
in either order — zero conflicts on the accounting files — and aggregate:

```sh
cd "$(mktemp -d)" && git init -q && git config user.email t@t.co && git config user.name t
mkdir receipts && git commit -q --allow-empty -m base
LB=<repo>/packs/audit/directives/agent-token-accounting/lib
git switch -cq a; python3 "$LB/ledger.py" append-row receipts/issue-10.md ckA claude-code sA '#10' claude-sonnet-4-5 1000 0 0 500 a; git add -A; git commit -qm 'feat: a (#10)'
git switch -q -; git switch -cq b; python3 "$LB/ledger.py" append-row receipts/issue-11.md ckB claude-code sB '#11' claude-sonnet-4-5 2000 0 0 800 b; git add -A; git commit -qm 'feat: b (#11)'
git switch -q -; git merge -q --no-edit a; git merge -q --no-edit b   # no conflicts
python3 "$LB/report.py" receipts                                       # per-issue + grand totals
```

## Decisions

- **Did not seal this repo's live `COSTS.md` / `STEERING.md` in this PR, despite
  the issue listing it in scope.** This is a directive PR and, under the
  two-lane dogfood retired-dual-edit model (#200), the committed `.governance/`
  tree runs the *last released* directives — whose hooks still append to the
  live ledgers and whose `doc-integrity` still treats them as `append-only`.
  Editing the live ledger headers now would fight the active hooks and the
  active append-only rule. The pack-level flip (`defaults.conf` → `frozen-files`)
  ships in `packs/`; the live ledgers seal at the next release's `pack update`,
  which is the same moment the receipt-homed hooks go live here. This keeps the
  PR honestly scoped to `packs/` (no `.governance/` consumed-tree edits, which
  `consumed-tree-integrity` forbids).
- **Open question — hook-created thin receipt vs `receipt-per-issue`'s required
  sections:** chose to **exempt accounting-only stubs** rather than have the
  hook stub the four narrative sections. Hook-stubbing would write placeholder
  prose the hook cannot truthfully fill, and would let a TODO-filled receipt
  pass the shape check; the stub-exemption keeps the receipt visibly incomplete
  while the accounting tables are still validated by the accounting directives.
  Documented in `receipt-per-issue`'s `constitution.md`.
- **`sum-by-session` / dedup scan all receipts, not just the current issue's**,
  so a session that ever spans issues still computes the right per-commit delta
  and dedup boundary. The read is at commit time only and over small per-issue
  files, so it does not reintroduce the central-file read cost the refactor
  targets.
- **Extracted `receipt_io.py` per directive** (rather than waiving the
  500-line `repo-hygiene` file-size limit on a large `ledger.py`). The kit's own
  `lib/*.py` ship into consumer repos and `.governance/packs/` is not excluded
  from the limit, so a portable, well-factored split was preferable to an
  embedded waiver. Token `ledger.py` 660→425, steering 557→382 lines.
- **No-issue steering events are rejected, not re-homed to a catch-all** (issue
  decision 6), consistent with `commit-issue-receipt-match` already requiring
  `#N` on every commit. Enforced both in the hook (refuse to write) and in the
  receipt validator (reject an issue-less row).
