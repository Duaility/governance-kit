# Require Issue-Linked Commit Subjects

## Goal

Amend the existing `conventional-commits` governance rule so commit subjects must end with a parenthesized GitHub issue reference such as `(#123)`, and keep the live repo plus bootstrap assets aligned with that policy.

## Steps

1. Update the live `conventional-commits` rule and tracked `commit-msg` hook text to require the issue suffix.
2. Mirror the same rule shape into the bootstrap assets and rule catalog so newly bootstrapped repos install the same policy.
3. Amend `CONSTITUTION.md` and add an Evolution Log entry describing the strengthened commit-traceability requirement.
4. Run syntax checks and the governance suite, then stage only the amendment files.
