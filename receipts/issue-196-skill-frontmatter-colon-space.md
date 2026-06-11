# issue-196 — fix SKILL.md frontmatter parse failure breaking install discovery

Closes [#196](https://github.com/Duaility/governance-kit/issues/196).

`#195` rewrote the `governance` skill `description:` and introduced a `: `
(colon-space) inside the unquoted YAML scalar (`...thin router: \`governance
pack {...}\``). That sequence is illegal in a plain YAML scalar, so the
`gray-matter`/`js-yaml` parser used by `npx skills` throws and the installer
reports "No valid skills found." All GitHub-repo installs of the kit were
broken.

## Checklist

- [x] Remove the colon-space from the description so the frontmatter parses
- [x] Verify the fixed SKILL.md loads via the installer's parser (gray-matter)

## What changed

- [governance/SKILL.md](../governance/SKILL.md) line 3 — Remove the colon-space
  from the description so the frontmatter parses: the phrase `thin router:` is
  rephrased to `thin router —`, eliminating the only internal `: ` in the
  scalar. No other content changed; this is a one-character class of fix.

## Out of scope

- A mechanical guard (a `foundation`-pack directive that asserts every
  `SKILL.md` frontmatter loads through a YAML parser) would catch this class of
  bug at commit time. Filed as a follow-up thought, not implemented here to keep
  the fix minimal.

## Verification

- Verify the fixed SKILL.md loads via the installer's parser (gray-matter):
  ran `node -e 'require("gray-matter")(fs.readFileSync("governance/SKILL.md"))'`
  against the patched file — parses OK, `name: governance`, `description`
  present (1121 chars). Before the fix the same parser failed with
  `incomplete explicit mapping pair ... line 3, column 288`.

## Decisions

- Chose to rephrase the colon to an em-dash rather than wrap the whole
  description in quotes. Quoting a ~1100-char single-line scalar is brittle (any
  future literal `"` silently breaks it) and inconsistent with the repo's other
  unquoted frontmatter; removing the offending `: ` keeps the scalar plain and
  matches house style.
