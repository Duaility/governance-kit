# Native tests & alternative hook frameworks

The bash directives in `tests/governance/directives/` are the baseline — they work in any repo without dependencies. This doc shows how to **also** run governance directives through the project's native test framework so they show up in the normal test report, and how to wire the pre-commit hook into frameworks the repo may already use.

## When to add native tests

Add native tests when:

- The repo already runs `pytest` / `jest` / `go test` in CI — governance violations should appear in the same report.
- A directive is easier to express in code than in bash (e.g. AST checks on Python imports, TypeScript type assertions).

The bash directives stay either way. Native tests are additive, not a replacement.

## pytest (Python)

Create `tests/governance/test_governance.py`:

```python
import subprocess
from pathlib import Path

DIRECTIVES_DIR = Path(__file__).parent / "directives"

def _directives():
    return sorted(p for p in DIRECTIVES_DIR.glob("*/check.sh"))

def test_directives_exist():
    assert _directives(), "no governance directives defined"

def test_each_directive(tmp_path, pytestconfig):
    failures = []
    for directive in _directives():
        result = subprocess.run(["bash", str(directive)], capture_output=True, text=True)
        if result.returncode != 0:
            failures.append(f"{directive.name}:\n{result.stdout}{result.stderr}")
    if failures:
        raise AssertionError("\n\n".join(failures))
```

For AST-level directives, skip the bash wrapper and write a direct pytest test. Example — no wildcard imports:

```python
import ast
from pathlib import Path

def test_no_wildcard_imports():
    offenders = []
    for py in Path(".").rglob("*.py"):
        if any(part.startswith(".") or part in {"node_modules", "venv", ".venv"} for part in py.parts):
            continue
        tree = ast.parse(py.read_text())
        for node in ast.walk(tree):
            if isinstance(node, ast.ImportFrom) and any(a.name == "*" for a in node.names):
                offenders.append(f"{py}:{node.lineno}")
    assert not offenders, "wildcard imports: " + ", ".join(offenders)
```

## jest / vitest (Node)

Create `tests/governance/governance.test.js`:

```javascript
const { execSync } = require('node:child_process');
const { readdirSync } = require('node:fs');
const { join } = require('node:path');

const DIRECTIVES_DIR = join(__dirname, 'directives');

describe('governance directives', () => {
  const directives = readdirSync(DIRECTIVES_DIR).map(f => join(DIRECTIVES_DIR, f, 'check.sh'));

  test('at least one directive is defined', () => {
    expect(directives.length).toBeGreaterThan(0);
  });

  test.each(directives)('%s passes', (directive) => {
    expect(() => {
      execSync(`bash ${directive}`, { stdio: 'pipe' });
    }).not.toThrow();
  });
});
```

## go test (Go)

Create `tests/governance/governance_test.go`:

```go
package governance_test

import (
    "os/exec"
    "path/filepath"
    "testing"
)

func TestGovernanceDirectives(t *testing.T) {
    directives, err := filepath.Glob("directives/*/check.sh")
    if err != nil || len(directives) == 0 {
        t.Fatal("no governance directives defined")
    }
    for _, directive := range directives {
        directive := directive
        t.Run(filepath.Base(directive), func(t *testing.T) {
            out, err := exec.Command("bash", directive).CombinedOutput()
            if err != nil {
                t.Fatalf("%s\n%s", err, out)
            }
        })
    }
}
```

## Alternative hook frameworks

### husky

If `package.json` has `husky` configured, don't write to `.git/hooks/pre-commit` directly. Instead:

```bash
npx husky add .husky/pre-commit "bash tests/governance/run.sh"
```

Add the `SKIP_GOVERNANCE` guard at the top of `.husky/pre-commit`:

```bash
#!/usr/bin/env bash
. "$(dirname -- "$0")/_/husky.sh"

[[ "${SKIP_GOVERNANCE:-0}" == "1" ]] && exit 0
bash tests/governance/run.sh
```

### pre-commit framework (pre-commit.com)

Add to `.pre-commit-config.yaml`:

```yaml
repos:
  - repo: local
    hooks:
      - id: governance
        name: governance
        entry: bash tests/governance/run.sh
        language: system
        pass_filenames: false
        stages: [commit]
```

Users can skip with `SKIP=governance git commit ...` (the framework's native skip mechanism).

### lefthook

```yaml
pre-commit:
  commands:
    governance:
      run: bash tests/governance/run.sh
      skip_empty: true
```

## Where to put complex directives

- **Bash** — filesystem, grep, regex. Fast to add, portable.
- **pytest / jest / go test** — AST inspection, type checks, cross-file reasoning.
- **External tools in CI only** — `gitleaks`, `trufflehog`, `semgrep`, dependency scanners. Don't run these in the pre-commit hook (too slow); wire them into `.github/workflows/governance.yml` as additional steps.

Layer them: fast directives on commit, heavier directives in CI. Both are enforcement, just at different cadences.
