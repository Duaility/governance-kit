# Architecture

This fixture stands in for a small Go service that the governance skill will
bootstrap. It is intentionally minimal: one binary entry point, a Go module
manifest, and the documents the kit's `required-docs` directive expects.

## Layout

- `main.go` — entry point. Real services would split this across packages and
  pull in net/http, a logger, and config loading.
- `go.mod` — module manifest. No transitive dependencies in the fixture.
- `.github/workflows/ci.yml` — non-governance workflow demonstrating CI is the
  backstop the kit's directives expect.

## Why this shape

The eval grader needs a deterministic Go-flavored baseline so the init flow
can pick Go-appropriate directives and surface why JS/Python-only checks were
deliberately dropped. The fixture stays small enough that the test grades
governance behavior rather than service correctness.

## Out of scope

A real service would have config, secrets handling, an HTTP surface, metrics,
and a deployment pipeline. None of that is necessary to exercise the init
verb's preset selection.
