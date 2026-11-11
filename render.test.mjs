import assert from 'node:assert/strict';
import { LAYOUT, wrapText, fitText, layout, drawWallpaper, ensureFont } from './render.js';

// Fake metrics: Hangul/CJK = 1.0×size, space = 0.3×size, anything else = 0.55×size (per code point).
const wide = /[ᄀ-ᇿ　-鿿가-힯＀-￯]/;
const measureAt = size => s => Array.from(s).reduce((w, ch) => w + (ch === ' ' ? 0.3 : wide.test(ch) ? 1 : 0.55) * size, 0);
const m10 = measureAt(10); // latin 5.5, space 3, hangul 10

// --- wrapText
assert.deepEqual(wrapText('hello world', 1000, m10), ['hello world']);
assert.deepEqual(wrapText('hello world', 40, m10), ['hello', 'world'], 'break at space');
assert.deepEqual(wrapText('a\nb', 1000, m10), ['a', 'b'], 'forced newline');
assert.deepEqual(wrapText('a\n\nb', 1000, m10), ['a', '', 'b'], 'blank line preserved');
assert.deepEqual(wrapText('', 1000, m10), ['']);
assert.deepEqual(wrapText('  hi  ', 1000, m10), ['hi'], 'trim');
assert.deepEqual(wrapText('one  two', 1000, m10), ['one two']);
assert.deepEqual(wrapText('가나다라마바사', 30, m10), ['가나다', '라마바', '사'], 'long Korean run');
assert.deepEqual(wrapText('abcdefghij', 20, m10), ['abc', 'def', 'ghi', 'j'], 'long word');
assert.deepEqual(wrapText('hi abcdefghij', 20, m10), ['hi', 'abc', 'def', 'ghi', 'j'], 'long word after short');
assert.deepEqual(wrapText('가나다.', 30, m10), ['가나', '다.'], 'no line starting with closing punctuation');
assert.deepEqual(wrapText('😀😀😀', 6, m10), ['😀', '😀', '😀'], 'no split surrogate pairs');
assert.deepEqual(wrapText('👍🏽👍🏽', 6, m10), ['👍🏽', '👍🏽'], 'no split grapheme clusters');
assert.deepEqual(wrapText('a\r\nb', 1000, m10), ['a', 'b'], 'CRLF');

// --- fitText
const box = { width: 800, height: 1000, maxSize: 90, minSize: 35, lineHeight: 1.35 };
const fits = (size, lines) =>
  lines.length * size * box.lineHeight <= box.height && lines.every(l => measureAt(size)(l) <= box.width);

assert.deepEqual(fitText('hi', box, measureAt), { fontSize: 90, lines: ['hi'] }, 'short text hits maxSize');

{
  const long = '가'.repeat(100);
  const { fontSize, lines } = fitText(long, box, measureAt);
  assert.ok(fontSize < 90 && fontSize > 35, `long text shrinks (${fontSize})`);
  assert.ok(Number.isInteger(fontSize));
  assert.ok(fits(fontSize, lines), 'result fits');
  assert.ok(!fits(fontSize + 1, wrapText(long, box.width, measureAt(fontSize + 1))), 'largest size that fits');
  assert.equal(lines.join(''), long, 'no text lost');
}

{
  const huge = '가'.repeat(2000);
  const { fontSize, lines } = fitText(huge, box, measureAt);
  assert.equal(fontSize, 35, 'overflow uses minSize');
  assert.equal(lines.length, Math.floor(1000 / (35 * 1.35)), 'keeps as many lines as fit');
  assert.ok(lines.at(-1).endsWith('…'), 'last line ends with ellipsis');
  assert.ok(fits(fontSize, lines), 'truncated result fits');
}

assert.equal(fitText('hi', { ...box, maxSize: 90.7, minSize: 35.2 }, measureAt).fontSize, 90, 'integer size within fractional bounds');

// --- layout
{
  const W = 1000, H = 2000;
  const r = layout('hi', W, H, measureAt);
  assert.deepEqual(r.box, { x: 100, y: 700, w: 800, h: 2000 * (1 - LAYOUT.top - LAYOUT.bottom) });
  assert.equal(r.fontSize, 90);
  assert.equal(r.lines.length, 1);
  assert.equal(r.lines[0].text, 'hi');
  assert.equal(r.lines[0].x, 500);
  assert.ok(Math.abs(r.lines[0].y - (r.box.y + r.box.h / 2)) < 1e-9, 'single line vertically centered');

  const m = layout('가'.repeat(40) + '\n\n끝', W, H, measureAt);
  const lh = m.fontSize * LAYOUT.lineHeight;
  assert.ok(m.lines.length > 2);
  const first = m.lines[0].y, last = m.lines.at(-1).y;
  assert.ok(first - lh / 2 >= m.box.y - 1e-9 && last + lh / 2 <= m.box.y + m.box.h + 1e-9, 'lines inside box');
  assert.ok(Math.abs((first + last) / 2 - (m.box.y + m.box.h / 2)) < 1e-9, 'block centered');
  m.lines.forEach((l, i) => {
    assert.equal(l.x, 500);
    if (i) assert.ok(Math.abs(l.y - m.lines[i - 1].y - lh) < 1e-9, 'line spacing');
  });
}

// --- drawWallpaper (fake ctx)
function fakeCtx() {
  const calls = [];
  return {
    calls, font: '', fillStyle: '', textAlign: '', textBaseline: '',
    fillRect(...a) { calls.push(['fillRect', this.fillStyle, ...a]); },
    fillText(t, x, y) { calls.push(['fillText', t, x, y, this.font, this.fillStyle, this.textAlign, this.textBaseline]); },
    measureText(s) { return { width: measureAt(parseFloat(this.font.match(/([\d.]+)px/)[1]))(s) }; },
  };
}
{
  const ctx = fakeCtx();
  drawWallpaper(ctx, { text: 'hi', bg: '#000', fg: '#fff', font: { family: 'Noto Sans KR', weight: 700 }, W: 1000, H: 2000 });
  assert.deepEqual(ctx.calls[0], ['fillRect', '#000', 0, 0, 1000, 2000]);
  const texts = ctx.calls.filter(c => c[0] === 'fillText');
  assert.equal(texts.length, 1);
  assert.deepEqual(texts[0].slice(1, 3), ['hi', 500]);
  assert.deepEqual(texts[0].slice(4), ['700 90px "Noto Sans KR"', '#fff', 'center', 'middle']);

  const empty = fakeCtx();
  drawWallpaper(empty, { text: '  \n ', bg: '#123', fg: '#fff', font: { family: 'X', weight: 400 }, W: 10, H: 20 });
  assert.deepEqual(empty.calls, [['fillRect', '#123', 0, 0, 10, 20]], 'whitespace-only -> background only');
}

// --- ensureFont
await ensureFont({ family: 'X', weight: 400 }, 'hi'); // no document in Node: no-op, no throw
{
  const seen = [];
  globalThis.document = { fonts: { load: async (...a) => { seen.push(a); throw new Error('net'); } } };
  await ensureFont({ family: 'Gowun Dodum', weight: 400 }, '안녕');
  delete globalThis.document;
  assert.deepEqual(seen, [['400 64px "Gowun Dodum"', '안녕']], 'loads with text sample, swallows errors');
}

console.log('ok');
