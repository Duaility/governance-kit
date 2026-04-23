### no-committed-build-artifacts

- **Rule**: No tracked file matches the build-artifact denylist: `*.pyc`, `__pycache__/`, `*.class`, `*.o`, `node_modules/`, `dist/`, `build/`, `target/`, `out/`, `.DS_Store`, `Thumbs.db`, editor swap files.
- **Rationale**: Build output in git is noise — it rots fast, conflicts often, and obscures real changes in diffs. If a build artifact must ship, publish it as a release asset, not a tracked file.
- **Enforced by**: `tests/governance/rules/no-committed-build-artifacts/check.sh`
- **Exceptions**: none.
