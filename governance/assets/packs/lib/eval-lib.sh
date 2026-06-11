#!/usr/bin/env bash
# eval-lib.sh — shared harness for pack evals.
#
# Each eval at `packs/<pack>/evals/<directive>/test.sh` sources this library,
# spins up a temp git repo, installs the directive under test into
# `.governance/packs/<pack-id>/directives/<directive>/check.sh`, then drives pass + fail
# fixtures through `expect_pass` / `expect_fail`.
#
# The harness is intentionally small. The contract:
#
#   fixture_init
#       Creates a fresh temp git repo, `cd`s into it, seeds a minimal
#       tree that satisfies the standard-baseline directives (README, LICENSE,
#       CONSTITUTION, AGENTS, ARCHITECTURE, SECURITY, `.gitignore`,
#       `.env.example`, a dummy CI workflow, `.githooks/pre-commit`).
#       Individual evals mutate this baseline for their pass/fail cases.
#
#   install_directive <pack-dir> <directive-id>
#       Copies `assets/dot-governance/lib.sh` into `.governance/lib.sh`
#       and the entire directive folder (`<pack-dir>/directives/<id>/`) into
#       the fixture's `.governance/packs/<pack-id>/directives/<id>/`. Idempotent.
#
#   stage_all
#       git add -A in the fixture.
#
#   commit_quiet <subject>
#       Make a non-empty commit so HEAD exists. Used by directives that
#       inspect git history. Uses `--no-verify` so fixture repos don't
#       need governance hooks.
#
#   expect_pass <check-path> [args...]
#       Runs the check script, asserts exit 0. Prints ✓ on success,
#       ✗ + check stderr/stdout on failure, and bumps `eval_failures`.
#
#   expect_fail <check-path> [args...]
#       Runs the check script, asserts non-zero exit. Symmetric.
#
#   fixture_cleanup
#       `rm -rf` the fixture. Called automatically on EXIT via trap.
#
# Evals exit 0 when every assertion matches; non-zero otherwise.

set -u

EVAL_LIB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# ^ governance/  (not the repo root — the pack is under assets/)
# Actually resolve the tests-bash lib.sh path directly:
_EVAL_LIB_SH="$EVAL_LIB_ROOT/assets/dot-governance/lib.sh"

FIXTURE_DIR=""
eval_failures=0
eval_assertions=0

fixture_init() {
    FIXTURE_DIR="$(mktemp -d)"
    cd "$FIXTURE_DIR" || exit 1
    for var in $(git rev-parse --local-env-vars 2>/dev/null || true); do
        unset "$var"
    done

    git init --quiet --initial-branch=main .
    git config user.email eval@example.com
    git config user.name "Eval Harness"

    cat > README.md <<'EOF'
# Fixture repo

Minimal seed for the governance pack eval harness. Every eval under
governance/assets/packs/\*/evals/\*/test.sh spins up a copy of
this tree, installs exactly one directive under test, and then mutates the
parts of the fixture the directive cares about — pass then fail assertions
run through the same harness.

This README intentionally carries enough words and structure to clear
the readme-exists directive's word-count and heading checks without any
per-eval tuning.
EOF

    cat > LICENSE <<'EOF'
MIT License

Copyright (c) 2026

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software.
EOF

    cat > CONSTITUTION.md <<'EOF'
# Constitution

## Principles

Placeholder principle.

## Guidelines

Placeholder guideline.

## Directives

Placeholder directive.

## Evolution Log

Placeholder entry.
EOF

    cat > AGENTS.md <<'EOF'
# AGENTS.md

Index for agents working in this fixture repo. This file is shaped as a
link-heavy entry point rather than a standalone manual — the real detail
lives in the documents it links to.

## Quick links

- [README](README.md) — public-facing overview of the fixture
- [CONSTITUTION](CONSTITUTION.md) — the governance directives in force here
- [Architecture](ARCHITECTURE.md) — top-level layering and domains
- [Security](SECURITY.md) — how to report a vulnerability
- [LICENSE](LICENSE) — terms this code is distributed under

## Working in this repo

Every change must satisfy the directives in `CONSTITUTION.md`. The mechanical
directives are enforced by the governance test suite; the principles
are enforced by human and agent review.

## Notes

More placeholder body so the file clears the minimum line count for the
agents-md-exists directive. Governance directive tests care about shape and
length, not about the actual prose of this file.

Every eval copies this baseline and then mutates only what the directive
under test cares about. Downstream directives (internal-doc-links,
agents-md-exists itself) depend on the shape of this document, so extend
it here rather than in per-directive evals.
EOF

    cat > ARCHITECTURE.md <<'EOF'
# Architecture

## Overview

Placeholder architecture doc for the fixture repo. Describes the top-level
map of domains and package layering expected by the architecture-doc-exists
directive. The real content does not matter for the eval — only that the file
is present, non-empty, has a top-level heading, and clears the minimum
line count.

## Layers

- data — durable storage, migrations, schema evolution
- service — domain logic, transaction boundaries, invariants
- api — HTTP transport, authentication, rate limiting

## Directives

Domain objects do not cross layer boundaries in the wrong direction. The
api layer depends on service; service depends on data; data has no
inbound dependencies from above. Breaking this triggers a review.

## Further reading

- [README](README.md)
- [CONSTITUTION](CONSTITUTION.md)
EOF

    cat > SECURITY.md <<'EOF'
# Security

Report vulnerabilities to security@example.com.
EOF

    cat > .gitignore <<'EOF'
.env
*.log
node_modules/
EOF

    cat > .env.example <<'EOF'
DATABASE_URL=
API_KEY=
EOF

    mkdir -p .github/workflows
    cat > .github/workflows/ci.yml <<'EOF'
name: CI
on: [push, pull_request]
permissions:
  contents: read
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: echo test
EOF

    mkdir -p .githooks
    cat > .githooks/pre-commit <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x .githooks/pre-commit
    git config core.hooksPath .githooks

    # Stage and commit the baseline so directives that use `git ls-files` see it
    # (hooks-configured, dotenv-gitignored, no-secrets, etc.).
    git add -A
    git commit --quiet --no-verify -m "chore: baseline fixture"
}

install_directive() {
    local pack_dir="$1" directive_id="$2"
    local pack_id
    pack_id="$(awk '
        $1 == "id:" {
            sub(/^[[:space:]]*id:[[:space:]]*/, "")
            gsub(/^"|"$/, "")
            print
            exit
        }
    ' "$pack_dir/pack.yaml")"
    mkdir -p .governance
    cp "$_EVAL_LIB_SH" .governance/lib.sh
    local src="$pack_dir/directives/$directive_id"
    local dest=".governance/packs/$pack_id/directives/$directive_id"
    rm -rf "$dest"
    mkdir -p "$dest"
    # Copy the entire directive folder so siblings (lib/, hooks/, runtimes/) come
    # with the directive. Skip evals/ — the fixture shouldn't run eval fixtures.
    for entry in "$src"/*; do
        [[ -e "$entry" ]] || continue
        case "$(basename "$entry")" in
            evals) continue ;;
        esac
        cp -R "$entry" "$dest/"
    done
    chmod +x "$dest/check.sh"
    if [[ -d "$dest/hooks" ]]; then
        chmod +x "$dest/hooks/"*.sh 2>/dev/null || true
    fi
    if [[ -d "$dest/runtimes" ]]; then
        chmod +x "$dest/runtimes/"*.sh 2>/dev/null || true
    fi
}

stage_all() {
    git add -A
}

commit_quiet() {
    local subject="${1:-chore: eval fixture}"
    git commit --quiet --no-verify --allow-empty -m "$subject"
}

_run_check() {
    local check="$1"
    shift
    bash "$check" "$@"
}

expect_pass() {
    eval_assertions=$(( eval_assertions + 1 ))
    local check="$1"
    shift
    local label="${EVAL_LABEL:-$(basename "$check" .sh)}"
    local out
    if out=$(_run_check "$check" "$@" 2>&1); then
        printf '    ✓ %s — pass case\n' "$label"
    else
        printf '    ✗ %s — expected PASS, got FAIL\n' "$label"
        printf '%s\n' "$out" | sed 's/^/        /'
        eval_failures=$(( eval_failures + 1 ))
    fi
}

expect_fail() {
    eval_assertions=$(( eval_assertions + 1 ))
    local check="$1"
    shift
    local label="${EVAL_LABEL:-$(basename "$check" .sh)}"
    local out
    if out=$(_run_check "$check" "$@" 2>&1); then
        printf '    ✗ %s — expected FAIL, got PASS\n' "$label"
        printf '%s\n' "$out" | sed 's/^/        /'
        eval_failures=$(( eval_failures + 1 ))
    else
        printf '    ✓ %s — fail case\n' "$label"
    fi
}

fixture_cleanup() {
    if [[ -n "$FIXTURE_DIR" && -d "$FIXTURE_DIR" ]]; then
        cd /
        rm -rf "$FIXTURE_DIR"
    fi
    FIXTURE_DIR=""
}

eval_done() {
    if [[ $eval_failures -ne 0 ]]; then
        printf '    %d assertion(s) failed\n' "$eval_failures" >&2
        exit 1
    fi
    exit 0
}

trap 'fixture_cleanup' EXIT
