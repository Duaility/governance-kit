### no-large-files

- **Rule**: No tracked file exceeds 5 MB. Override via `GOVERNANCE_MAX_FILE_SIZE_MB`.
- **Rationale**: Binary blobs in git are a one-way street — history retains them forever, clone times swell, and mirroring slows. Keep large assets in object storage and track the pointer.
- **Enforced by**: `tests/governance/rules/no-large-files.sh`
- **Exceptions**: Raise the threshold via `GOVERNANCE_MAX_FILE_SIZE_MB` for repo-wide tuning.
