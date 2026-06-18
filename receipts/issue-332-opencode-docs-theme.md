# Issue #332 — adopt opencode-inspired theme for the docs site

Restyle the docs-site generator (`scripts/docs-site/`) to match the
developer-focused look and feel of opencode.ai/docs, keeping our monospace
body. Design tokens were adapted from `sst/opencode`'s `custom.css`.

## Checklist

- [x] Adopt opencode warm-grayscale palette and lime accent in assets.mjs
- [x] Retune brand surfaces (logo mark, docs.json, OG card, theme-color) to lime
- [x] Apply opencode typographic scale, flat lists, hairline borders, GitHub code colors
- [x] Replace stale search recommendations with governance-relevant chips and aliases

## What changed

- **Adopt opencode warm-grayscale palette and lime accent in assets.mjs** —
  rewrote both `:root` token blocks in `scripts/docs-site/assets.mjs`. The dark
  theme moves from cool blue-slate (`#0b0d12`) to opencode's warm near-grayscale
  (`#130f0f` background, low-saturation warm grays). The accent (`--brand`,
  `--brand-2`) moves from emerald green to a lime/chartreuse (`#dce052` dark,
  `#727f12` light). The monospace body font is unchanged (deliberate).
- **Apply opencode typographic scale, flat lists, hairline borders, GitHub code
  colors** — in `scripts/docs-site/assets.mjs`: headings dropped to weight 500 on
  opencode's 26/22/18/16px scale and `strong` to 600; content lists are now flat
  with muted em-dash markers; the `--tok-*` syntax colors switched to the GitHub
  dark/light palettes; code blocks, cards, and callouts use 6px radii with the
  code shadow removed; the header is flat (no blur) and the language-trigger /
  search-button gradient-and-glow hovers were flattened; the active nav item uses
  a lime left-edge indicator over a weak background.
- **Retune brand surfaces (logo mark, docs.json, OG card, theme-color) to lime**
  — recolored the logo mark `docs/assets/governance-mark.svg` to the lime family;
  updated the `colors` block in `docs/docs.json`; recolored the social card
  gradients and marks in `scripts/docs-site/og-card-template.mjs`; and changed
  the `theme-color` meta tag in `scripts/docs-site/build.mjs` (set to the dark
  background `#130f0f` — not lime — so the mobile browser chrome matches the
  page rather than the accent).
- **Replace stale search recommendations with governance-relevant chips and
  aliases** — in `scripts/docs-site/build.mjs` the search popup chips and
  placeholder dropped opencode's terms (telegram, gateway, plugins, channels) for
  governance ones (install, directives, packs, audit); in
  `scripts/docs-site/assets.mjs` the `searchAliases` map and the "no results" hint
  were rebuilt around governance concepts.

## Out of scope

- The published skill, kit, packs, and the `.governance/` consumed tree — this
  is a docs-site presentation change only; no version lines or directive code
  are touched.
- The raster banner images (`docs/assets/banner-*.png`) — they cannot be
  recolored in CSS and would need regenerating separately.
- Semantic callout colors (tip/warning/info) were intentionally left as-is.

## Decisions

- **Kept the monospace body** instead of switching to opencode's sans-serif
  system stack. opencode's `custom.css` keeps Starlight's default sans body; we
  diverge here at the user's explicit direction, because our monospace body
  leans harder into the terminal/dev aesthetic.
- **Lists** keep a muted em-dash marker rather than opencode's fully
  marker-less lists (`list-style:none`), so nested governance lists stay
  parseable. Minor faithful-copy deviation for legibility.
- **`strong`** is weight 600 rather than opencode's 500, because medium-weight
  monospace reads too thin.
- **Accent saturation** was raised vs. opencode's very pale interactive lime
  (`hsl(62,100%,90%)`), because our theme uses the accent as a visible text /
  indicator color, not only as a faint highlight background; the pale opencode
  lime survives as `--soft` (the tinted active-item background).

## Verification

Built the static site clean and confirmed the new tokens and chips landed in
the emitted output; visually verified dark + light themes and the search popup
via a local preview.

```sh
npm install
npm run docs:build            # exits 0
grep -o 'dce052' dist/docs-site/assets/docs-site.css        # lime accent present
grep -o 'data-search-suggestion="[a-z]*"' dist/docs-site/index.html | sort -u
# -> audit / directives / install / packs
grep -c 'telegram\|gateway\|>plugins<' dist/docs-site/index.html   # -> 0 (stale terms gone)
```

## Audit

Verdict from a fresh-context sub-agent that read the staged diff, this receipt,
and `gh issue view 332`:

**Verdict: PASS.**

- **Check 1 — `## What changed` faithful to the diff: PASS.** All five
  non-receipt files are described and map to real hunks: `governance-mark.svg`
  fill `#0B8A5C`→`#A7AB3D`; `docs.json` colors block to lime; `assets.mjs` both
  `:root` token blocks (bg `#0b0d12`→`#130f0f`, brand emerald→lime, GitHub
  `--tok-*` palette) plus typography (h1 500/26px, h2 500/22px, `strong` 600),
  flat lists (`list-style:none` + muted `–` marker), flat header (blur removed),
  lime nav indicator, rebuilt `searchAliases`/no-results hint; `build.mjs`
  theme-color + search chips/placeholder; `og-card-template.mjs` gradients/marks
  to lime. No material change omitted. The original draft's "theme-color … to
  lime" label was imprecise (its real value is the dark background `#130f0f`);
  the receipt has since been corrected to state this explicitly.
- **Check 2 — each `- [x]` realized in the diff: PASS.** All four checklist
  items are confirmed present in the diff.
- **Check 3 — receipt `## Checklist` mirrors the GitHub issue: PASS.** Issue
  #332 and the receipt checklist are identical word-for-word, all four `- [x]`.

## Accounting

<!-- Accounting rows are maintained by the agent-token-accounting and agent-steering-accounting pre-commit hooks. Keys are opaque — do not parse. -->

### Costs

| cost-key | agent | session | issue | model | input | cache-create | cache-read | output | new-work | cost-usd | cum-input | cum-cache-create | cum-cache-read | cum-output | note |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| claude-code-6efcb5b0-0bc-1781759037-1 | claude-code | 6efcb5b0-0bc5-4bec-8183-edda99401eaa | #332 | claude-opus-4-8 | 41518 | 516965 | 20077968 | 159916 | 718399 | 17.4755 | 41518 | 516965 | 20077968 | 159916 | feat(docs): adopt opencode-inspired theme for the docs site (#332)Restyle the do |
| claude-code-6efcb5b0-0bc-1781759284-1 | claude-code | 6efcb5b0-0bc5-4bec-8183-edda99401eaa | #332 | claude-opus-4-8 | 9143 | 31509 | 1427136 | 11827 | 52479 | 1.2519 | 50661 | 548474 | 21505104 | 171743 | feat(docs): adopt opencode-inspired theme for the docs site (#332)Restyle the do |

## Layer boundaries

Verdict from a fresh-context sub-agent that read the staged diff and
`ARCHITECTURE.md`. The change set touches only the docs-site presentation surface
— `docs/` (the published Mintlify site assets) and `scripts/docs-site/` (the
static-site generator) — plus this receipt. None of the three governance layers
in the layer map (`skill/` → `kit/` → `packs/`) is touched.

**Verdict: PASS.**

- **Check 1 — every file sits in the layer its role belongs to: PASS.** All five
  non-receipt files are docs-site presentation: `docs/assets/governance-mark.svg`
  (logo recolor), `docs/docs.json` (Mintlify color config), and the generator
  files `scripts/docs-site/{assets.mjs,build.mjs,og-card-template.mjs}` (CSS
  tokens, theme-color meta, OG-card template). No kit/engine logic was placed
  under a pack and no pack-specific content was placed in the kit — neither
  `kit/`, `packs/`, nor `.governance/` is touched at all.
- **Check 2 — no dependency points the wrong way across a layer edge: PASS.** The
  docs-site generator and published site sit outside the skill→kit→packs spine;
  the diff is self-contained styling within `docs/` and `scripts/docs-site/` and
  introduces no import or reference from a lower governance layer up into a higher
  one (the arrows in the layer map are untouched and no new cross-layer edge is
  added).
- **Check 3 — new shared logic lives in the layer that owns it: PASS.** The
  changes are presentation tokens and template strings local to the docs-site
  generator; no shared logic was introduced, and nothing was duplicated into a
  consumer layer (the search aliases / chips live once in `scripts/docs-site/` and
  are emitted into the build output, not copied across layers).

## Steering

Verdict from a fresh-context sub-agent that read the session transcript
(`6efcb5b0-0bc5-4bec-8183-edda99401eaa.jsonl`) and this receipt, applying the
`agent-steering-accounting` definition (an interrupt, or a user message that
redirects/corrects the agent mid-task; ordinary task requests, questions, and
tool-permission denials are **not** steering).

**Verdict: PASS.**

- **Check 1 — every steering event in the transcript is recorded as a row:
  PASS.** No human-steering events were found. The transcript contains six user
  turns: (a) the initial styling task, (b) "is it possible to produce preview"
  (a question/new request after the styling work completed), (c) "use preview
  tools" (selecting an option the agent had just offered), (d) "can you change
  the recommendations for search popup" (a new sub-task request), (e) "what is
  the primary color you are using" (a question), and (f) the create-PR command (a
  new task). None is an interrupt (no `Request interrupted by user` marker
  exists) and none redirects or corrects the agent mid-task — each is a new task,
  a question, or a selection among offered options. Zero steering rows appended.
- **Check 2 — no non-steering message was recorded: PASS.** No rows were added to
  `### Steering`, so no ordinary task message, question, or denial was mistakenly
  recorded as a steering event.
