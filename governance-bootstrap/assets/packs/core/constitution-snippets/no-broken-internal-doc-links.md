### no-broken-internal-doc-links

- **Rule**: Every relative-path markdown link in a tracked `.md` file resolves to an existing file.
- **Rationale**: Broken links rot silently — the doc still renders, just incorrectly. A link that once pointed at a real file and now doesn't signals that the doc has drifted from the code it describes.
- **Enforced by**: `tests/governance/rules/no-broken-internal-doc-links.sh`
- **Exceptions**: none.
