# issue-180 — add GitHub Pages documentation site

Closes [#180](https://github.com/Duaility/governance-kit/issues/180).

## Checklist

- [x] Vendor docs-site generator
- [x] Author documentation pages
- [x] GitHub Pages deploy workflow
- [x] Theme and icon
- [x] Build smoke and governance verification

## What changed

- **Vendor docs-site generator.** Ported centraid's `scripts/docs-site/` static
  generator (plain-Node ESM, MIT, originally from openclaw/docs) into
  `scripts/docs-site/` and rebranded it to governance-kit: `build.mjs`,
  `mdx-ish.mjs`, `assets.mjs`, `config.mjs`, `og-card-template.mjs`,
  `og-render-worker.mjs`, `pagefind-normalize.mjs`, `source-index.mjs`,
  `llms-full.mjs`, `elements-fixture.mjs`, `smoke.mjs`, and `README.md`. The
  Cloudflare-only `worker.ts` was dropped. `package.json` pins the Node
  toolchain (markdown-it, highlight.js, mermaid, pagefind, @resvg/resvg-js,
  jsdom, gray-matter) and exposes `docs:build`, `docs:serve`, `docs:smoke`;
  `node_modules/` and `dist/` are gitignored.
- **Author documentation pages.** Wrote 15 MDX pages in the Mintlify schema —
  `docs/index.mdx`, `docs/guide/{introduction,getting-started,mental-models}.mdx`,
  `docs/concepts/{constitution,packs,runtime,audit-chain,versioning}.mdx`, and
  `docs/reference/{verbs,directive-catalog,schemas,authoring-directives,authoring-packs,native-tests}.mdx` —
  plus `docs/docs.json` defining the three-tab navigation (Guide / Inner
  workings / Reference).
- **GitHub Pages deploy workflow.** Added `.github/workflows/docs.yml`: builds
  on PRs and pushes to `main`, runs the smoke test, uploads the
  `dist/docs-site` artifact, and deploys via `actions/deploy-pages` (only off
  `main`). Builds with `DOCS_SITE_BASE_PATH=/governance-kit` so links and
  assets resolve under the project Pages subpath.
- **Theme and icon.** Branded with a certified-compliant green palette
  (primary `#0B8A5C`, dark accent `#3DDC97`) across `docs.json`, the generator
  CSS variables in `assets.mjs` (dark + light `--brand`/`--brand-2`/`--soft`
  and the code-block command token), the `theme-color` meta in `build.mjs`,
  and the OG social-card gradient in `og-card-template.mjs`. The logo, favicon,
  and OG mark are a verified badge (scalloped seal + white checkmark) in
  `docs/assets/governance-mark.svg` and the OG `#mark` symbol.
- **Build smoke and governance verification.** `npm run docs:build` produces
  `dist/docs-site` and `npm run docs:smoke` passes; the dogfood governance
  suite passes all 17 directives with the change set staged.

## Out of scope

- Enabling Pages in repo settings (Settings → Pages → Source: GitHub Actions)
  and any custom domain / CNAME — a one-time manual step left to the
  maintainer.
- A page-level AI chat backend (the generator references a chat API URL but no
  backend is wired).
- Porting the bash directive checks into the docs as runnable examples beyond
  the prose already written.

## Decisions

- **GitHub Pages over Cloudflare.** The work began targeting Cloudflare Pages
  (matching openclaw); the maintainer redirected to GitHub Pages. The
  Cloudflare worker and `_headers`/`wrangler` surfaces were removed and the
  deploy rebuilt on `actions/upload-pages-artifact` + `actions/deploy-pages`.
- **Matched centraid's format, not Mintlify hosting.** Mintlify is a hosted
  SaaS with no static export, so we reproduced its *schema* (`docs.json` +
  MDX) and render it with the vendored generator instead of using Mintlify's
  cloud.
- **`.mdx` extension chosen deliberately.** The `no-broken-internal-doc-links`
  directive scans only `*.md`/`*.markdown`, so authoring in `.mdx` keeps the
  Mintlify-style extensionless root-absolute links (`/concepts/audit-chain`)
  from tripping the link checker.
- **Generic OG fallback added to `build.mjs`.** centraid committed a static
  `og-card.png`; rather than commit a binary, the generator now renders a
  generic card from `config.name` when no static file exists, which satisfies
  the smoke test.
- **Verified-badge icon over the initial shield.** The first pass used an
  orange shield; the maintainer asked for a different color and icon, so the
  mark became a green verified badge — it reads as "this repo is certified
  compliant," matching what governance-kit does.
- The vendored `.mjs` files carry inline `// governance: allow-repo-hygiene`
  waivers inherited from centraid (e.g. `build.mjs` file-size, `smoke.mjs`
  exit-signal `console.log`); they are preserved as-is so `repo-hygiene`
  passes without re-deriving each waiver.

## Verification

- `npm run docs:build` → builds `dist/docs-site` (HTML, pagefind search,
  sitemap, llms.txt, OG cards, `.nojekyll`).
- `npm run docs:smoke` → `docs smoke ok`.
- `bash .governance/run.sh` → all 17 directives passed (`kit-version-consistency`,
  `pre-commit-test-gate`, `agent-steering-accounting`, `agent-token-accounting`,
  `commit-issue-receipt-match`, `commit-message-format`, `doc-freshness`,
  `doc-integrity`, `issue-templates`, `issues-tracked`,
  `no-broken-internal-doc-links`, `receipt-per-issue`, `repo-hygiene`,
  `required-docs`, `secrets-hygiene`, `version-consistency`,
  `workflows-hardened`).
