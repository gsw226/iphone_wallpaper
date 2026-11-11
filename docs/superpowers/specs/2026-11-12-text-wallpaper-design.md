# Text Wallpaper — Design

iPhone lock-screen wallpaper from a sentence the user types. Fixed layout; user picks
background color, text color, font.

## Shape

- Static site, no build step, hosted on GitHub Pages. Files:
  - `index.html` — UI (markup + style + glue script, `<script type="module">`).
  - `render.js` — ES module: pure layout math + canvas drawing. No DOM queries, no globals.
  - `render.test.mjs` — `node render.test.mjs`, plain `assert`, no framework.
  - `README.md` — usage + how to install the Shortcut.
  - `shortcut/` — the iOS Shortcut (signed `.shortcut` if buildable) + manual build steps.
- iOS Shortcut "문장 배경화면": accepts Images from share sheet → Set Wallpaper (lock screen,
  Show Preview off).

## Flow

1. Type sentence (multi-line allowed; `\n` is a forced break).
2. Pick bg / fg (presets + `<input type="color">`) and font (4 Korean web fonts).
3. Live preview at phone aspect ratio with a translucent overlay marking the clock zone
   and the bottom button zone.
4. "배경화면으로 설정" → render full-res PNG → `navigator.share({ files: [png] })` →
   user picks the Shortcut. If `navigator.canShare({files})` is false → download the PNG.
5. Last text + settings persist in `localStorage` (wrapped in try/catch).

## Layout (fixed)

Fractions of canvas size:
- Top 0.35 reserved (lock-screen clock + widgets).
- Bottom 0.14 reserved (flashlight / camera).
- Side margin 0.10 each side → text box width 0.80.
- Text centered horizontally and vertically inside the remaining box, center-aligned lines.
- Font size: largest size in [minSize, maxSize] whose wrapped lines fit the box.
  maxSize = 0.09 × width, minSize = 0.035 × width, lineHeight = 1.35.
  If even minSize overflows, use minSize and truncate trailing lines with "…".

Output resolution: `screen.width × devicePixelRatio` by `screen.height × devicePixelRatio`
(e.g. 1179×2556 on iPhone 15/16). Fallback 1179×2556 when not on a phone.

## render.js contract

```js
export const LAYOUT = { top: 0.35, bottom: 0.14, side: 0.10, maxSize: 0.09, minSize: 0.035, lineHeight: 1.35 };

// measure(str) -> width in px at the current font size.
// Splits on "\n" first. Within a paragraph: break between words (spaces) when possible;
// a single word longer than maxWidth is broken per character (needed for long Korean
// runs without spaces and for long URLs). Leading/trailing spaces of each line trimmed.
// Empty paragraph -> "" line (preserves blank lines).
export function wrapText(text, maxWidth, measure) -> string[]

// measureAt(size) -> measure function for that font size.
// Returns { fontSize, lines } — largest integer size that fits box {width,height}.
export function fitText(text, { width, height, maxSize, minSize, lineHeight }, measureAt) -> { fontSize, lines }

// Pure: computes text box + fitted lines + baseline y per line for a canvas of size W×H.
export function layout(text, W, H, measureAt) -> { box:{x,y,w,h}, fontSize, lines:[{text, x, y}] }

// Draws bg fill + lines onto ctx (ctx.canvas sized W×H by caller).
// font = { family, weight }. Uses textBaseline "middle", textAlign "center".
export function drawWallpaper(ctx, { text, bg, fg, font, W, H }) -> void

// Ensures the web font is loaded for the given text before drawing.
export async function ensureFont(font, text) -> void   // document.fonts.load(`${weight} 64px "${family}"`, text)
```

Fonts (Google Fonts, Korean): Noto Sans KR (700), Noto Serif KR (700), Gowun Dodum (400),
Nanum Pen Script (400).

## Testing

- `node render.test.mjs`: wrapText (spaces, forced newline, blank line, long Korean run,
  long word), fitText (short text hits maxSize, long text shrinks, overflow → minSize + "…"),
  layout (lines inside box, centered).
- Manual: iPhone Safari → share → Shortcut → lock screen updates.

## Out of scope

Accounts, saved sentence list, daily auto-change, multiple layouts, server rendering.
