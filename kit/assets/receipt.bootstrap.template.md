# issue-<N> — adopt governance-kit

Closes [#<N>](https://github.com/<owner>/<repo>/issues/<N>).

## Checklist

- [x] Install the bundled governance-kit packs (preset `<preset>`)
- [x] Seed `CONSTITUTION.md` with the picked directives
- [x] Inject the Compliance snippet into `AGENTS.md`
- [x] Install the test runner at `.governance/run.sh`
- [x] Wire git hooks at `<hook-strategy-path>`
- [x] Install the CI workflow at `.github/workflows/governance.yml`
- [x] Resolve every dry-run finding inline before the install commit

## What changed

- **Installed the bundled governance-kit packs (preset `<preset>`).** Directives:
  `<comma-separated directive ids>`. Plus any additional packs the
  operator selected: `<list or "none">`.
- **Seeded `CONSTITUTION.md`** with the picked directives and a starter
  Principles section. Compliance section is the cardinal directive and
  was inserted verbatim from the template.
- **Injected the Compliance snippet into `AGENTS.md`** between the
  paired `<!-- governance: directives-to-follow -->` markers.
- **Installed the test runner at `.governance/run.sh`** and the
  shared helpers at `.governance/lib.sh`. Both stamped with the
  per-file `governance-kit:managed kit-version=<v>` marker.
- **Wired git hooks** under `<hook-strategy-path>` — five dispatchers
  (`pre-commit`, `commit-msg`, `prepare-commit-msg`, `post-commit`,
  `pre-push`) generated from the installed directive set. Each carries
  the line-2 ownership marker.
- **Installed the CI workflow at `.github/workflows/governance.yml`.**
  Runs `bash .governance/run.sh` on `push` to main and every
  `pull_request`.
- **Resolved every dry-run finding inline.** `<list each: directive →
  fix or waiver token, with reason>`. No `SKIP_GOVERNANCE` was used on
  the install commit.

## Out of scope

- Native test wrappers (pytest / jest / go test) — opt-in post-init via
  `kit/references/NATIVE_TESTS.md`.
- Migrating existing CI workflows beyond `governance.yml`.
- `<anything else the operator explicitly deferred>`.

## Verification

- `bash .governance/run.sh` after the install commit lands → all
  installed directives pass on the install commit.
- CI on the first PR confirms the same suite runs green in the
  enforced layer.
- When an agent runtime was detected, the install commit carries one
  `date | harness | session` row under `## Session` → `### Identifiers`,
  written by the pre-commit hook. No transcript, usage, cost, or steering
  data is collected. A legitimate out-of-band commit may use the
  `governance: allow-agent-session-identity <reason>` body waiver.
