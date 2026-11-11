export const LAYOUT = { top: 0.35, bottom: 0.14, side: 0.10, maxSize: 0.09, minSize: 0.035, lineHeight: 1.35 };

const segmenter = typeof Intl !== 'undefined' && Intl.Segmenter ? new Intl.Segmenter() : null;
const graphemes = s => (segmenter ? Array.from(segmenter.segment(s), x => x.segment) : Array.from(s));
const CLOSING = /^[.,!?;:)\]}'"’”…、。，．！？」』〉》）]/;

export function wrapText(text, maxWidth, measure) {
  const out = [];
  for (const para of text.split('\n')) {
    let line = '';
    for (const word of para.split(/\s+/).filter(Boolean)) {
      const joined = line ? `${line} ${word}` : word;
      if (measure(joined) <= maxWidth) { line = joined; continue; }
      if (line) out.push(line);
      if (measure(word) <= maxWidth) { line = word; continue; }
      // Word wider than the box: break per grapheme.
      let cur = [];
      for (const g of graphemes(word)) {
        if (cur.length && measure(cur.join('') + g) > maxWidth) {
          // Don't start a line with closing punctuation: carry the previous grapheme along.
          const carry = CLOSING.test(g) && cur.length > 1 ? [cur.pop()] : [];
          out.push(cur.join(''));
          cur = carry;
        }
        cur.push(g);
      }
      line = cur.join('');
    }
    out.push(line);
  }
  return out;
}

export function fitText(text, { width, height, maxSize, minSize, lineHeight }, measureAt) {
  const fits = (size, lines, m) => lines.length * size * lineHeight <= height && lines.every(l => m(l) <= width);
  let lo = Math.ceil(minSize), hi = Math.floor(maxSize), best = null;
  // ponytail: binary search assumes fit is monotonic in size; wrapping makes that near-true, not exact.
  while (lo <= hi) {
    const size = (lo + hi) >> 1, m = measureAt(size), lines = wrapText(text, width, m);
    if (fits(size, lines, m)) { best = { fontSize: size, lines }; lo = size + 1; } else hi = size - 1;
  }
  if (best) return best;

  const fontSize = Math.ceil(minSize), m = measureAt(fontSize);
  const lines = wrapText(text, width, m).slice(0, Math.max(1, Math.floor(height / (fontSize * lineHeight))));
  const gs = graphemes(lines.at(-1));
  while (gs.length && m(gs.join('').trimEnd() + '…') > width) gs.pop();
  lines[lines.length - 1] = gs.join('').trimEnd() + '…';
  return { fontSize, lines };
}

export function layout(text, W, H, measureAt) {
  const L = LAYOUT;
  const box = { x: W * L.side, y: H * L.top, w: W * (1 - 2 * L.side), h: H * (1 - L.top - L.bottom) };
  const { fontSize, lines } = fitText(text, {
    width: box.w, height: box.h, maxSize: L.maxSize * W, minSize: L.minSize * W, lineHeight: L.lineHeight,
  }, measureAt);
  const lh = fontSize * L.lineHeight;
  const top = box.y + (box.h - lines.length * lh) / 2;
  return { box, fontSize, lines: lines.map((t, i) => ({ text: t, x: box.x + box.w / 2, y: top + lh * (i + 0.5) })) };
}

export function drawWallpaper(ctx, { text, bg, fg, font, W, H }) {
  ctx.fillStyle = bg;
  ctx.fillRect(0, 0, W, H);
  if (!text || !text.trim()) return;
  const fontAt = size => `${font.weight} ${size}px "${font.family}"`;
  const { fontSize, lines } = layout(text, W, H, size => s => { ctx.font = fontAt(size); return ctx.measureText(s).width; });
  ctx.font = fontAt(fontSize);
  ctx.fillStyle = fg;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  for (const l of lines) ctx.fillText(l.text, l.x, l.y);
}

export async function ensureFont(font, text) {
  if (typeof document === 'undefined' || !document.fonts) return;
  try {
    await document.fonts.load(`${font.weight} 64px "${font.family}"`, text || ' ');
  } catch {
    // Font failed to load: draw with the fallback rather than block the user.
  }
}
