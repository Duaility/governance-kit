# Architecture

This fixture stands in for a fresh polyglot repo that the governance skill
will bootstrap. The shape mirrors a typical small product checkout: a Python
backend slice and a TypeScript frontend slice, both empty, sitting beside the
documents the kit's `required-docs` directive expects to find at the root.

## Layout

- `pyproject.toml` — Python project manifest. Real projects would list runtime
  and dev dependencies here.
- `package.json` — TypeScript / Node project manifest. Real projects would
  carry workspace configuration and scripts here.
- `src/` — placeholder for source code. Empty in the fixture so the eval can
  observe what the skill does on a clean slate.
- `.github/workflows/ci.yml` — non-governance workflow demonstrating CI is
  the backstop the kit's directives expect to see in any repo that takes
  governance seriously.

## Why this shape

The eval grader needs a deterministic baseline: enough of a real repo to
exercise polyglot detection inside the init flow, but not so much that the
test ends up auditing project content rather than governance behavior.

## Out of scope

Real source code, real dependency closures, real tests. Anything the kit's
directives would have to grade in a production repo lives outside this
fixture by design.
