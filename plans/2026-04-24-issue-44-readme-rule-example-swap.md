<!-- last-verified: 2026-04-24 -->
# Plan — issue-44: Swap README rule example to doc-freshness

Closes [#44](https://github.com/Duaility/governance-kit/issues/44).

## Goal

The README's "What a rule looks like" section uses `conventional-commits`
as its worked example. The rationale it carries ("scannable changelogs,
audit trail") is something any plain commitlint config delivers, so a
reader walks away thinking governance-kit is a hook runner with extra
ceremony. That undercuts the README's own thesis — *rationale is
alignment data; rule + test + rationale ship together* — which needs
an example where the rationale is the load-bearing part.

Swap the worked example to `doc-freshness`, where the rationale (an
agent reading a doc with a stale marker knows not to trust it as
ground truth) is exactly the kind of generalizable principle the
philosophy section claims rationale unlocks.

## Scope

- Replace the rule-folder tree, `constitution.md` snippet, and
  surrounding prose in the "What a rule looks like" section of
  [README.md](../README.md).
- Add one closing sentence tying the rationale directly to the
  agent-steering thesis ("a bare hook can enforce the date format;
  only the co-located rationale tells the next agent what the date
  *means*").
- Keep the quickstart bad-commit demo on `conventional-commits` —
  it fires on any commit with no setup, which `doc-freshness`
  cannot match.

## Non-goals

- The `core` pack catalog table — `conventional-commits` stays
  listed there.
- Any change to the rules themselves or their `check.sh` /
  `constitution.md` files.
- Re-recording or adding a demo GIF (deferred from #42).

## Validation

- `bash .governance/run.sh` passes — in particular
  `no-broken-internal-doc-links` confirms the new
  `.governance/rules/doc-freshness/check.sh` reference
  resolves.
- Visual pass that the rule-folder tree and the
  `constitution.md` snippet render cleanly on GitHub.
