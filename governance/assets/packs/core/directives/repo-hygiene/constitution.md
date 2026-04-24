### repo-hygiene

- **Directive**: No tracked file violates any of the following hygiene sub-checks. Each is enabled by default and can be opted out of individually via `GOVERNANCE_REPO_HYGIENE_DISABLE` (comma-separated list of sub-check keys):
    - `merge-markers` — no `<<<<<<<`, `=======`, or `>>>>>>>` at line start in any tracked file.
    - `large-files` — no tracked file exceeds 5 MB (override via `GOVERNANCE_MAX_FILE_SIZE_MB`).
    - `build-artifacts` — no tracked file matches the artefact denylist (`*.pyc`, `__pycache__/`, `*.class`, `*.o`, `node_modules/`, `dist/`, `build/`, `target/`, `out/`, `.DS_Store`, `Thumbs.db`, editor swap files).
    - `debug-statements` — no stray `console.log`, `debugger`, `breakpoint()`, `import pdb`, `dbg!`, or `fmt.Println` in non-test source (line-level waiver: `# governance: allow-repo-hygiene <reason>`).
    - `file-size-limit` — no source file exceeds 500 lines (override via `GOVERNANCE_FILE_SIZE_LIMIT`), excluding vendor / generated / migrations / protobuf / node_modules.
- **Rationale**: Merge markers, oversized binaries, build output in the tree, leftover debug prints, and god-files all corrupt the history in slightly different ways, but they share one property: they are almost always accidental. Rolling them into a single directive keeps the catalog honest about how much work each check is doing — none of them is a load-bearing axis on its own, so `minimal` / `standard` / `strict` do not need three separate entries to pick from.
- **Enforced by**: `tests/governance/directives/repo-hygiene/check.sh`
- **Exceptions**: Disable individual sub-checks via `GOVERNANCE_REPO_HYGIENE_DISABLE="key1,key2,..."`. The `debug-statements` sub-check supports line-level waivers (`# governance: allow-repo-hygiene <reason>`). Marked `always_install: true` — the merge-marker sub-check is high-signal and zero-false-positive, and bundling the siblings alongside it keeps hygiene coverage consistent regardless of preset.
