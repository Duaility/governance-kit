### no-merge-conflict-markers

- **Rule**: No tracked file contains a merge-conflict marker (`<<<<<<<`, `=======`, or `>>>>>>>` at line start).
- **Rationale**: Merge markers committed to the tree are almost always an accident — the author ran `git add .` before finishing the conflict resolution. Zero-false-positive check, installed unconditionally.
- **Enforced by**: `tests/governance/rules/no-merge-conflict-markers/check.sh`
- **Exceptions**: none.
