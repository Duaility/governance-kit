# issue-<N> — adopt governance-kit

Closes [#<N>](https://github.com/<owner>/<repo>/issues/<N>).

## What changed

Installed governance-kit (preset `<preset>`) for issue #<N>. Directives:
`<comma-separated directive ids>`. Additional packs: `<list or "none">`.
Seeded `CONSTITUTION.md`, injected the Compliance snippet into `AGENTS.md`
when that file existed, installed `.governance/run.sh` / `lib.sh`, wired
hooks under `<hook-strategy-path>`, and added `.github/workflows/governance.yml`.
Dry-run findings: `<list each: directive → fix, or "none">`.

## Verification

```sh
bash .governance/run.sh
```

Expected: exit 0 after the install commit lands. CI on the first PR confirms
the same suite. This recorded command is not itself proof of execution.

## Audit

- Record a fresh-context PASS/REFUTED verdict against the install diff and issue #<N>.
