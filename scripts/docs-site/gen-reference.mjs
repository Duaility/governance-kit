#!/usr/bin/env node
// gen-reference.mjs — generate the docs site's Reference tab from canonical
// markdown, so each reference page has ONE source of truth instead of a
// hand-authored copy that drifts (the openclaw `.generated` model; see
// scripts/docs-site/README.md → "What belongs here vs kit/references/").
//
// Each entry in PAGES declares the site page and the canonical source file(s)
// it is rendered from. Sources are repo-relative and may live in ANY folder —
// today they are all `kit/references/*.md` (the specs the kit ships and the
// agent executes at run time), but the mapping is source-path-agnostic.
//
// Usage:
//   node scripts/docs-site/gen-reference.mjs           # write docs/reference/*.mdx
//   node scripts/docs-site/gen-reference.mjs --check    # fail if committed output is stale
import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const REPO_BLOB = 'https://github.com/Duaility/governance-kit/blob/main';
const OUT_DIR = path.join(root, 'docs', 'reference');

// Site page ← canonical source(s). title/summary are curated here (they drive
// nav + SEO); the body is rendered from the source markdown.
const PAGES = [
  {
    slug: 'verbs',
    title: 'Verbs',
    summary:
      'The governance skill lifecycle surface — init, kit update, pack *, directive *, reset, and uninstall — and the design rules they all share.',
    sources: ['kit/references/VERBS.md'],
  },
  {
    slug: 'schemas',
    title: 'File schemas',
    summary:
      'The files that define a repo governance state — install.yaml and packs.lock — with every field and the ownership marker that threads through them.',
    sources: ['kit/references/INSTALL_SCHEMA.md', 'kit/references/LOCK_SCHEMA.md'],
  },
  {
    slug: 'authoring-directives',
    title: 'Authoring directives',
    summary:
      'The craft guide for writing a good directive — start from the bad merge, the qualities to aim for, anti-patterns to avoid, the check contract, and patterns by class.',
    sources: ['kit/references/DIRECTIVE_AUTHORING.md'],
  },
  {
    slug: 'authoring-packs',
    title: 'Authoring packs',
    summary:
      'How to build a self-contained, versioned bundle of directives — layout, pack.yaml, constitution snippets, per-directive config, what install does, and distribution.',
    sources: ['kit/references/PACK_AUTHORING.md'],
  },
  {
    slug: 'native-tests',
    title: 'Native tests & hook frameworks',
    summary:
      'Bash checks are the dependency-free baseline. How to optionally wrap them in pytest / jest / go test, and how to wire dispatchers into husky or pre-commit.com.',
    sources: ['kit/references/NATIVE_TESTS.md'],
  },
  {
    slug: 'directive-catalog',
    title: 'Directive catalog',
    summary:
      'Everything the three bundled governance-kit concern packs ship, organized by pack and preset.',
    sources: ['kit/references/DIRECTIVES_CATALOG.md'],
  },
];

// Cross-links: a link whose target resolves to one of these source files points
// at the generated site page instead. Built from PAGES so it stays in sync.
const SOURCE_TO_SITE = new Map();
for (const p of PAGES) {
  for (const src of p.sources) SOURCE_TO_SITE.set(src, `/reference/${p.slug}`);
}

// Rewrite a relative markdown link target (resolved against the source file's
// dir) to either a site path (if it targets another generated page) or a GitHub
// blob URL (everything else). Absolute and in-page links pass through.
function rewriteTarget(target, srcDir) {
  if (/^(https?:|mailto:|tel:|#)/.test(target) || target === '') return target;
  const hashIdx = target.indexOf('#');
  const pathPart = hashIdx === -1 ? target : target.slice(0, hashIdx);
  const hash = hashIdx === -1 ? '' : target.slice(hashIdx);
  const repoRel = path.posix.normalize(path.posix.join(srcDir, pathPart));
  if (SOURCE_TO_SITE.has(repoRel)) return SOURCE_TO_SITE.get(repoRel) + hash;
  return `${REPO_BLOB}/${repoRel}${hash}`;
}

// Apply `fn` to every line that is OUTSIDE a fenced code block (the fence
// delimiters and their contents pass through untouched). Shared by the
// escape and heading-bump passes so neither corrupts code fences.
function mapOutsideFences(body, fn) {
  let inFence = false;
  let fenceTok = '';
  return body
    .split('\n')
    .map((line) => {
      const fence = line.match(/^\s*(```+|~~~+)/);
      if (fence) {
        if (!inFence) {
          inFence = true;
          fenceTok = fence[1][0];
        } else if (line.trimStart().startsWith(fenceTok)) {
          inFence = false;
        }
        return line;
      }
      return inFence ? line : fn(line);
    })
    .join('\n');
}

// Escape angle brackets in non-code text. The renderer is markdown-it with
// html:true, so a bare <type> outside code is parsed as an (empty) HTML tag and
// vanishes. Code fences and inline `code` spans are left untouched.
function escapeAngles(body) {
  return mapOutsideFences(body, (line) => {
    // Split on backtick runs; escape only the non-code segments.
    let out = '';
    let i = 0;
    while (i < line.length) {
      if (line[i] === '`') {
        let ticks = '';
        while (line[i] === '`') {
          ticks += '`';
          i++;
        }
        const close = line.indexOf(ticks, i);
        if (close === -1) {
          out += ticks;
          continue;
        }
        out += ticks + line.slice(i, close) + ticks;
        i = close + ticks.length;
      } else {
        const next = line.indexOf('`', i);
        const seg = next === -1 ? line.slice(i) : line.slice(i, next);
        out += seg.replace(/</g, '&lt;').replace(/>/g, '&gt;');
        i = next === -1 ? line.length : next;
      }
    }
    return out;
  });
}

// Rewrite every [text](target) link's target via rewriteTarget. Image links
// ![alt](target) are handled by the same pattern.
function rewriteLinks(body, srcDir) {
  return body.replace(/(\]\()([^)\s]+)(\s+"[^"]*")?(\))/g, (m, open, target, title, close) => {
    return `${open}${rewriteTarget(target, srcDir)}${title ?? ''}${close}`;
  });
}

function stripFirstH1(body) {
  const lines = body.split('\n');
  const idx = lines.findIndex((l) => /^#\s+/.test(l));
  if (idx === -1) return { title: null, rest: body };
  const title = lines[idx].replace(/^#\s+/, '').trim();
  const rest = lines.slice(idx + 1).join('\n').replace(/^\n+/, '');
  return { title, rest };
}

function bumpHeadings(body) {
  // Demote every ATX heading one level (used for multi-source pages so each
  // source's structure nests under an injected section heading). Fence-aware so
  // `##` comments inside code blocks are not rewritten.
  return mapOutsideFences(body, (line) => line.replace(/^(#{1,5})(\s+)/, '#$1$2'));
}

function renderPage(page) {
  const srcLinks = page.sources
    .map((s) => `[\`${s}\`](${REPO_BLOB}/${s})`)
    .join(' and ');

  const bodies = page.sources.map((src) => {
    const srcDir = path.posix.dirname(src);
    let raw = fs.readFileSync(path.join(root, src), 'utf8');
    raw = rewriteLinks(raw, srcDir);
    raw = escapeAngles(raw);
    if (page.sources.length === 1) {
      return stripFirstH1(raw).rest;
    }
    // Multi-source: turn the source's H1 into a section heading, demote the rest.
    const { title, rest } = stripFirstH1(raw);
    return `## ${title}\n\n${bumpHeadings(rest)}`;
  });

  const note =
    `<Note>\n` +
    `  **Canonical spec, rendered here.** This page is generated from ${srcLinks} — ` +
    `the spec the kit ships and the agent executes at run time. Edit the source and run ` +
    `\`npm run docs:gen\`; do not edit this file.\n` +
    `</Note>`;

  return (
    `---\n` +
    `title: '${page.title}'\n` +
    `summary: '${page.summary}'\n` +
    `---\n\n` +
    `<!-- GENERATED FILE — do not edit. Sources: ${page.sources.join(', ')}. Regenerate: npm run docs:gen -->\n\n` +
    `# ${page.title}\n\n` +
    `${note}\n\n` +
    `${bodies.join('\n\n')}\n`
  );
}

const check = process.argv.includes('--check');
let stale = [];
fs.mkdirSync(OUT_DIR, { recursive: true });
for (const page of PAGES) {
  const out = renderPage(page);
  const dest = path.join(OUT_DIR, `${page.slug}.mdx`);
  if (check) {
    const current = fs.existsSync(dest) ? fs.readFileSync(dest, 'utf8') : '';
    if (current !== out) stale.push(`docs/reference/${page.slug}.mdx`);
  } else {
    fs.writeFileSync(dest, out);
    // process.stdout.write (not console.log) keeps this out of the repo-hygiene
    // debug-statement check, matching scripts/docs-site/source-index.mjs.
    process.stdout.write(`generated docs/reference/${page.slug}.mdx <- ${page.sources.join(', ')}\n`);
  }
}

if (check) {
  if (stale.length) {
    process.stderr.write(
      `docs reference pages are stale (regenerate with \`npm run docs:gen\`):\n  ${stale.join('\n  ')}\n`,
    );
    process.exit(1);
  }
  process.stdout.write('docs reference pages are up to date with kit/references\n');
}
