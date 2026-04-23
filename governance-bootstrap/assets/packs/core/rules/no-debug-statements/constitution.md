### no-debug-statements

- **Rule**: No tracked source file outside of tests contains a stray `console.log`, `debugger`, `breakpoint()`, `import pdb`, `dbg!`, or `fmt.Println`.
- **Rationale**: Debug statements that slip into production at best add log noise and at worst leak sensitive state. The cheapest catch is before the commit lands.
- **Enforced by**: `tests/governance/rules/no-debug-statements/check.sh`
- **Exceptions**: Append `// governance: allow-no-debug-statements <reason>` (or language equivalent) to the offending line.
