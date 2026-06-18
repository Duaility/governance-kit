const TITLE_SIZES = [96, 82, 70, 60, 52];
const TITLE_MAX_LINES = 2;
const TITLE_MAX_WIDTH = 1044;
const SUMMARY_SIZE = 26;
const SUMMARY_MAX_LINES = 2;
const SUMMARY_MAX_WIDTH = 1044;
const GLYPH_RATIO_TITLE = 0.55;
const GLYPH_RATIO_SUMMARY = 0.52;
const ASCENT_RATIO = 0.78;
const LINE_HEIGHT_RATIO = 1.06;

const PAD_X = 78;
const KICKER_BASELINE_Y = 192;
const TITLE_BLOCK_TOP = 218;
const FOOTER_TOP = 524;

export function renderPageOgSvg({ title, kicker, summary }) {
  const safeTitle = (title || 'Documentation').trim();
  const safeKicker = (kicker || 'governance-kit').trim();
  const safeSummary = (summary || '').trim();

  const titleFit = fitText(
    safeTitle,
    TITLE_SIZES,
    TITLE_MAX_WIDTH,
    TITLE_MAX_LINES,
    GLYPH_RATIO_TITLE,
  );
  const titleLetterSpacing = titleFit.size >= 88 ? -2.5 : titleFit.size >= 70 ? -2 : -1.4;
  const titleBlockBottom =
    TITLE_BLOCK_TOP + titleFit.lines.length * titleFit.size * LINE_HEIGHT_RATIO;

  const summaryAvailable = FOOTER_TOP - 18 - (titleBlockBottom + 22);
  const summaryMaxLines = Math.max(
    0,
    Math.min(SUMMARY_MAX_LINES, Math.floor(summaryAvailable / (SUMMARY_SIZE * 1.4))),
  );
  const summaryFit =
    safeSummary && summaryMaxLines > 0
      ? fitText(
          safeSummary,
          [SUMMARY_SIZE],
          SUMMARY_MAX_WIDTH,
          summaryMaxLines,
          GLYPH_RATIO_SUMMARY,
        )
      : { lines: [], size: SUMMARY_SIZE };
  const summaryBlockTop = titleBlockBottom + 22;

  return `<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="630" viewBox="0 0 1200 630" role="img" aria-label="${escapeXml(`${safeTitle} — governance-kit documentation`)}">
${defs()}
  <rect width="1200" height="630" fill="url(#bg)"/>
  <rect width="1200" height="630" fill="url(#dots)"/>
  <rect width="1200" height="630" fill="url(#glow)"/>
  <rect width="1200" height="630" fill="url(#glow2)"/>
  <rect x="0" y="0" width="1200" height="4" fill="url(#bar)"/>

  <g transform="translate(${PAD_X} 78)">
    <rect width="22" height="22" rx="4" fill="#C9D141"/>
    <text x="36" y="17" font-family="ui-monospace, SFMono-Regular, Menlo, Consolas, monospace" font-size="18" font-weight="700" fill="#E9EFB0" letter-spacing="0.18em">DOCS.GOVERNANCE-KIT.DEV</text>
  </g>

  <g transform="translate(940 56)">
    <use href="#mark" width="200" height="200"/>
  </g>

  <text x="${PAD_X}" y="${KICKER_BASELINE_Y}" font-family="ui-monospace, SFMono-Regular, Menlo, Consolas, monospace" font-size="20" font-weight="700" fill="#E9EFB0" letter-spacing="0.18em">${escapeXml(safeKicker.toUpperCase())}</text>

  ${titleFit.lines.map((line, i) => `<text x="${PAD_X}" y="${baselineY(TITLE_BLOCK_TOP, titleFit.size, i)}" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', 'Helvetica Neue', Helvetica, Arial, sans-serif" font-size="${titleFit.size}" font-weight="800" fill="#ffffff" letter-spacing="${titleLetterSpacing}">${escapeXml(line)}</text>`).join('\n  ')}

  ${summaryFit.lines.map((line, i) => `<text x="${PAD_X}" y="${baselineY(summaryBlockTop, SUMMARY_SIZE, i)}" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', 'Helvetica Neue', Helvetica, Arial, sans-serif" font-size="${SUMMARY_SIZE}" font-weight="500" fill="#a8aebd" letter-spacing="-0.2">${escapeXml(line)}</text>`).join('\n  ')}

  <g transform="translate(${PAD_X} ${FOOTER_TOP})">
    <rect width="10" height="10" rx="2" fill="#C9D141"/>
    <text x="22" y="9" font-family="ui-monospace, SFMono-Regular, Menlo, Consolas, monospace" font-size="20" font-weight="600" fill="#ffffff">docs.governance-kit.dev</text>
    <text x="22" y="40" font-family="ui-monospace, SFMono-Regular, Menlo, Consolas, monospace" font-size="16" font-weight="500" fill="#7a8194">Governance-driven development · every rule ships with a test</text>
  </g>

  <g transform="translate(960 ${FOOTER_TOP})" opacity="0.85">
    <text font-family="ui-monospace, SFMono-Regular, Menlo, Consolas, monospace" font-size="14" font-weight="600" fill="#E9EFB0" letter-spacing="0.18em">v0 · MIT</text>
    <text y="28" font-family="ui-monospace, SFMono-Regular, Menlo, Consolas, monospace" font-size="14" font-weight="500" fill="#7a8194">github.com/Duaility/governance-kit</text>
  </g>
</svg>`;
}

function baselineY(blockTop, size, lineIndex) {
  return Math.round(blockTop + size * ASCENT_RATIO + lineIndex * size * LINE_HEIGHT_RATIO);
}

function defs() {
  return `<defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#131310"/>
      <stop offset="1" stop-color="#1a1a10"/>
    </linearGradient>
    <radialGradient id="glow" cx="0.82" cy="0.18" r="0.85">
      <stop offset="0" stop-color="#C9D141" stop-opacity="0.55"/>
      <stop offset="0.35" stop-color="#C9D141" stop-opacity="0.18"/>
      <stop offset="0.7" stop-color="#C9D141" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="glow2" cx="0.05" cy="0.95" r="0.6">
      <stop offset="0" stop-color="#8A8F19" stop-opacity="0.30"/>
      <stop offset="1" stop-color="#8A8F19" stop-opacity="0"/>
    </radialGradient>
    <pattern id="dots" x="0" y="0" width="28" height="28" patternUnits="userSpaceOnUse">
      <circle cx="1.2" cy="1.2" r="1.2" fill="#ffffff" fill-opacity="0.045"/>
    </pattern>
    <linearGradient id="bar" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="#C9D141"/>
      <stop offset="0.6" stop-color="#E9EFB0"/>
      <stop offset="1" stop-color="#C9D141" stop-opacity="0.2"/>
    </linearGradient>
    <linearGradient id="markGrad" x1="0" y1="0" x2="64" y2="64" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#8A8F19"/>
      <stop offset="1" stop-color="#C9D141"/>
    </linearGradient>
    <symbol id="mark" viewBox="0 0 24 24" overflow="visible">
      <path d="M23 12l-2.44-2.79.34-3.69-3.61-.82-1.89-3.2L12 2.96 8.6 1.5 6.71 4.69 3.1 5.5l.34 3.7L1 12l2.44 2.79-.34 3.7 3.61.82L8.6 22.5l3.4-1.47 3.4 1.46 1.89-3.19 3.61-.82-.34-3.69L23 12z" fill="url(#markGrad)"/>
      <path d="M10.09 16.72l-3.8-3.81 1.48-1.48 2.32 2.33 5.85-5.87 1.48 1.48-7.33 7.35z" fill="#ffffff"/>
    </symbol>
  </defs>`;
}

function fitText(text, sizes, maxWidth, maxLines, glyphRatio) {
  for (const size of sizes) {
    const maxChars = Math.max(8, Math.floor(maxWidth / (size * glyphRatio)));
    const lines = wrapWords(text, maxChars);
    if (lines.length <= maxLines) return { lines, size };
  }
  const size = sizes[sizes.length - 1];
  const maxChars = Math.max(8, Math.floor(maxWidth / (size * glyphRatio)));
  const lines = wrapWords(text, maxChars).slice(0, maxLines);
  if (lines.length === maxLines) {
    const last = lines[maxLines - 1];
    lines[maxLines - 1] =
      last.length > maxChars - 1
        ? last.slice(0, maxChars - 1).replace(/\s+\S*$/, '') + '…'
        : last + '…';
  }
  return { lines, size };
}

function wrapWords(text, maxChars) {
  const words = text.split(/\s+/).filter(Boolean);
  const lines = [];
  let current = '';
  for (const word of words) {
    if (!current) {
      current = word;
      continue;
    }
    if (current.length + 1 + word.length <= maxChars) {
      current += ' ' + word;
    } else {
      lines.push(current);
      current = word;
    }
  }
  if (current) lines.push(current);
  return lines.length ? lines : [text];
}

function escapeXml(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}
