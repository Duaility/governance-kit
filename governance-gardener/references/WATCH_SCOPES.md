# Watch scopes

Canonical resolution model for the gardener's "watched scope" concept.

The gardener uses watched scopes in two places:

- **doc drift** — what code or docs a markdown doc is describing
- **rule dormancy** — what files or paths a governance rule is meaningfully watching

When a watched scope is explicit, trust it. When it is inferred, lower confidence and say so.

## Resolution order

### For docs

Resolve watched scope in this order:

1. Explicit `<!-- gardener-watches: ... -->` annotations
2. `tests/governance/freshness.conf` entries, if the doc is opt-ed in there
3. File references in fenced code blocks or inline code
4. Well-known defaults for docs like `README.md`, `SECURITY.md`, `CONSTITUTION.md`
5. Directory-sibling inference as a last resort

Canonical annotation syntax and examples live in [WATCH_ANNOTATIONS.md](WATCH_ANNOTATIONS.md).

### For rule scripts

Resolve watched scope in this order:

1. An explicit comment near the top of the rule script:
   `# gardener-watches: src/, docs/api.md`
2. Path literals or globs embedded in the script
3. A named config file the script reads
4. The repo-wide governance surface if the rule is clearly global

If none of the above yields a credible scope, do **not** guess. Skip scope-dependent signals like `F2` for that rule.

## Confidence guidance

- **high** — explicit annotation or explicit config entry
- **medium** — path literals or well-known defaults
- **low** — sibling inference or broad repo-level approximation

## Scope hygiene

- Prefer narrow, durable paths over broad directories.
- Include tests when the doc or rule describes externally observable behavior.
- Avoid generated files and vendor trees.
- If a doc or rule keeps surfacing low-confidence findings, add an explicit watched scope instead of tuning thresholds forever.
