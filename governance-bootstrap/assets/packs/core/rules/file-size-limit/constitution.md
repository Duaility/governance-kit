### file-size-limit

- **Rule**: No source file exceeds 500 lines. Override via `GOVERNANCE_FILE_SIZE_LIMIT`.
- **Rationale**: Files that grow without bound become irreplaceable — nobody wants to refactor a 3000-line module. The limit is a soft signal that it is time to split.
- **Enforced by**: `tests/governance/rules/file-size-limit/check.sh`
- **Exceptions**: Raise the threshold via `GOVERNANCE_FILE_SIZE_LIMIT` for repo-wide tuning, or append `governance: allow-file-size-limit <reason>` as a comment inside the file for per-file exceptions.
