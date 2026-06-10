# governance-kit docs site

Static-site renderer for the governance-kit documentation. Plain-Node ESM build that turns Mintlify-flavored MDX in [`/docs`](../../docs/) into the HTML you see at `dist/docs-site/`, deployed to **GitHub Pages**.

> Adapted from [openclaw/docs](https://github.com/openclaw/docs) (MIT) via [centraid](https://github.com/srikanthsrungarapu/centraid). The Mintlify `docs.json` schema describes the content; this renderer produces the static site.

## Build locally

```sh
npm install
npm run docs:build              # render → source index → pagefind → normalize
npm run docs:smoke              # static checks on dist/docs-site
npm run docs:serve              # http.server on 127.0.0.1:4173
```

Build **without** `DOCS_SITE_BASE_PATH` for local serving (served at `/`). CI sets the base path for the GitHub Pages project subpath — see below.

## Source layout

```
docs/
├── docs.json           # site config (Mintlify schema): theme, navigation, redirects
├── index.mdx           # landing page
├── **/*.mdx            # all other pages
└── assets/             # logo, favicon, any image referenced by content
```

Anything in `docs/` that isn't `.md` / `.mdx` / `.json` is copied verbatim to the deploy root.

## Renderer layout

```
scripts/docs-site/
├── build.mjs           # entry — collects pages, renders, writes dist/docs-site/
├── mdx-ish.mjs         # Mintlify-flavored MDX → HTML
├── assets.mjs          # bundled site CSS + JS (the look)
├── config.mjs          # locale + ignore lists
├── elements-fixture.mjs # /__elements component review page
├── og-card-template.mjs # per-page OG image template
├── og-render-worker.mjs # worker thread for resvg PNG rendering
├── source-index.mjs    # writes .md alternates for every HTML page
├── pagefind-normalize.mjs # post-process Pagefind output
├── llms-full.mjs       # generate llms-full.txt corpus (optional)
└── smoke.mjs           # static checks on dist/docs-site
```

## Environment variables

| Var | Default | Purpose |
|---|---|---|
| `DOCS_SITE_CANONICAL_ORIGIN` | `https://docs.governance-kit.dev` | Absolute URL baked into canonical links, sitemap, OG tags. For GitHub Pages, set to `https://<owner>.github.io/<repo>`. |
| `DOCS_SITE_BASE_PATH` | `""` | Path prefix when serving under a subdirectory. For a GitHub project Pages site this is `/<repo>` (e.g. `/governance-kit`). |
| `DOCS_SITE_LEGACY_BASE_PATH` | `/docs` | Legacy prefix that emits compatibility redirects. |
| `DOCS_SITE_ARTIFACT_MODE` | `full` | `full` builds content, `shell` builds just the chrome. |
| `DOCS_SITE_SHELL_ASSET_VERSION` | (auto sha256) | Override the asset-fingerprint hash. |

## Deploy: GitHub Pages

Deployment is automated by [`.github/workflows/docs.yml`](../../.github/workflows/docs.yml):

1. In the repo's **Settings → Pages**, set **Source** to **GitHub Actions**.
2. Every push to `main` that touches `docs/`, `scripts/docs-site/`, or the workflow rebuilds and deploys.
3. The build runs with `DOCS_SITE_BASE_PATH=/<repo>` so links and assets resolve under the project Pages subpath (`https://<owner>.github.io/<repo>/`).

For a **user/org root site** or a **custom domain**, drop `DOCS_SITE_BASE_PATH` (serve at `/`) and set `DOCS_SITE_CANONICAL_ORIGIN` to the domain (add a `CNAME` if using a custom domain).

## Smoke locally before pushing

```sh
npm run docs:build
npm run docs:smoke
```

## Customizing the look

- **Brand colors / fonts**: top of `assets.mjs` — `:root` and `:root[data-theme="light"]` CSS variables (`--brand`, `--soft`, …).
- **Logo**: `docs/assets/governance-mark.svg`. Used by the header brand, OG card, and favicon.
- **Header links**: edit the `topLink(...)` calls in `build.mjs` (search for `header-links`).
- **OG card design**: `og-card-template.mjs`.
