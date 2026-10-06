---
name: nvsinner-image-rendering
description: >
  How NvSinner turns an image into terminal cells with zero runtime
  dependencies — the pipeline behind the dashboard wallpaper
  (lua/core/wallpaper.lua), written down as a reusable recipe. Load this
  BEFORE building any feature that shows pixels inside Neovim: a new
  wallpaper or splash image, a logo or avatar drawn in cells, image previews,
  thumbnails, sprites, pixel art, a heatmap or chart drawn as colored cells,
  or any "paint a picture behind/under buffer text" effect. Also load it when
  asked to change the wallpaper asset, to author a new PPM, or when a picture
  painted with extmarks looks blurred, tinted, boxed-in behind text, or cut
  around the hover pill. Covers authoring the asset offline (Python/PIL →
  binary P6 PPM), decoding and cover-fit bilinear resampling in pure Lua, the
  `▄` half-block two-pixels-per-cell trick, painting as extmarks rather than a
  float or an image protocol, the black-is-transparent key, text-cell rules,
  repainting after a host that clears every namespace, the highlight-group
  budget, and the dead ends that were tried and rejected. Do NOT load it for
  opening image FILES (lua/core/image-open.lua hands those to macOS Quick
  Look), for the carbon palette rules themselves (nvsinner-contract), or for
  the minimap's braille encoder (lua/core/minimap.lua — a different cell
  trick, documented in lua/core/CLAUDE.md).
---

# Image → terminal cells (the wallpaper pipeline)

The dashboard wallpaper is the first NvSinner feature that draws a real
picture. It was built in one session (PR #35, commit `5101de0`, released in
v3.10.0) and the approach is meant to be reused: the next feature that needs
pixels on screen should start from this pipeline, not from scratch.

The contract for the shipped module (its knobs, paint rules, seams) lives in
`lua/core/CLAUDE.md` § *Dashboard wallpaper*. This skill is the **why and the
how-to-repeat-it**: the pipeline as a recipe, the decisions that are
load-bearing for any similar feature, and what was tried and dropped.

## When NOT to use this skill

| You want… | Go to |
|---|---|
| Open a PNG/JPG the user `:e`-ed | `lua/core/image-open.lua` (Quick Look; iTerm2 has no Kitty graphics protocol) |
| The wallpaper's current knobs and paint rules | `lua/core/CLAUDE.md` § *Dashboard wallpaper* |
| Palette roles, the no-hardcoded-hex rule | `nvsinner-contract` |
| Proving a redraw/extmark behavior before relying on it | `nvsinner-empirical-verification` |

## 1. The pipeline at a glance

```
source image (any format)
  │  OFFLINE, once, by the author — Python/PIL (scripts/make-wallpaper.py)
  ▼
assets/<feature>/<name>.ppm      binary P6, maxval 255, raw RGB, committed
  │  RUNTIME, pure Lua — no process, no plugin, no image protocol
  ▼
M.parse_ppm(raw)                 → { w, h, data }           (decoded once, memoized)
M.sample(img, cols, rows)        → grid of { ch = "▄", bg = top px, fg = bottom px }
                                   cover-fit + bilinear, memoized per window size
M.paint_grid(win, buf, grid, …)  → extmarks: virt_text glyphs on blank cells,
                                   bg-only hl under text, nothing on keyed cells
```

Read the live implementation, not a copy of it:

```bash
grep -n '^function M\.\|^M\.[A-Z_]* =' lua/core/wallpaper.lua
make test-file FILE=tests/core/wallpaper_spec.lua
```

## 2. Decisions that carry over to any similar feature

### Ship raw pixels, resample at runtime — not pre-rendered ANSI

The first version used chafa to pre-render `.ansi` art. An ANSI file is frozen
to ONE window size (~300 KB each), so every terminal size needs its own file,
or a runtime chafa dependency. A PPM is just pixels: pure Lua resamples it to
whatever the window is. P6 was chosen because the header is four tokens and the
body is `w*h*3` raw bytes — the decoder is ~20 lines and needs no zlib (PNG) or
DCT (JPEG). The trade-off is size on disk; the spec caps the shipped asset
(`grep -n 'KB\|1024' tests/core/wallpaper_spec.lua`).

**Asset resolution rule:** ship at least the screen's half-block pixel size
(columns × 2·rows of a full-screen window). A smaller asset is UPscaled and
looks blurred; that was observed, not theorized.

### Two pixels per cell with `▄`

Each cell is the lower-half block `▄`: **bg = the top pixel, fg = the bottom
pixel**. That doubles vertical resolution and makes terminal cells (roughly
1:2) close to square pixels. `M.sample` therefore samples `rows * 2` pixel
rows. Any cell-art feature should start here; quadrant/sextant glyphs give
more resolution but only two colors per cell, which smears photographs.

### Cover-fit, centred, bilinear — with separable weights

Scale to FILL the window (`max(tw/iw, th/ih)`), crop the overflow evenly, and
sample bilinearly. The per-column and per-pixel-row source coordinates and
weights are separable, so they are computed once per axis rather than per
pixel — measured 17 ms → 5 ms at 210×59 cells. A paint is ~4–8 ms headless.
Cover-fit crops the sides on narrow windows: compose the asset knowing that
(see §3).

### Paint with extmarks into the existing buffer — no float, no protocol

The picture is laid onto the host buffer (alpha's) as extmarks in its own
namespace:

- **Blank cells** → an overlay `virt_text` chunk at `virt_text_win_col`, runs of
  adjacent cells batched into one extmark (`flush()`).
- **Text cells** keep their character; they only get a bg = the average of
  the cell's two pixels, so the host's own fg highlights still apply.
- A float was never considered viable: it would sit above the menu and steal
  clicks. Kitty/iTerm image protocols are out (iTerm2 ≠ Kitty, and a
  dependency on the terminal is exactly what "native" rules out).

The buffer is **padded with empty lines up to the window height**, otherwise
rows below the host's last line have nothing to anchor an extmark on.

### Black is transparent (the color key)

A pixel at or below `M.KEY_MAX` on every channel means "no image". A cell keyed
on BOTH halves gets **no extmark at all**, so the window's real `Normal` bg —
whatever theme, variant or transparency mode is active — shows through. This
is what makes one asset correct under every background theme. The asset therefore
stores its backdrop as pure black, and the figure must be lifted clear of the
key (see §3).

### Fade toward the theme and quantize — the highlight budget

Every color is mixed toward carbon `base00` by `M.STRENGTH`, then quantized to
`M.STEP` per channel. The mix keeps the picture a backdrop rather than content;
the quantization bounds how many `NvWallpaper_*` highlight groups a paint can
create (an unquantized photo would create one per distinct pixel pair). The
group cache is dropped on `ColorScheme`, because `:hi clear` wipes them.
Image pixels are user data, not config colors, so they are exempt from the
no-hex rule — but the **mix target is a role**, never a literal.

### Text-cell rule: a lone space between two characters is text

Otherwise the gap in "Find file" gets an image glyph, cutting the label's bg
patch in two and slicing through the hover pill. Generalize this for any host
with labels: decide "is this cell text" at the word level, not per character.

### Layer under the host's own decorations

`M.PRIORITY` is low so the hover pill (priority 1000) stays on top. Any new
feature painting under interactive chrome must pick a priority below it.

### Repaint after a host that clears every namespace

`alpha.draw` runs `nvim_buf_clear_namespace(buf, -1, …)` — ALL namespaces —
and rewrites its lines on start, redraw, resize and every version-spinner
frame. `M.attach_alpha(alpha)` wraps the **`alpha.draw` field**; alpha's own
autocmds look the field up at call time, so every path lands on the wrapper.
For another host: find the one function every redraw goes through and wrap
that field, idempotently (`alpha._nvsinner_wallpaper` guard).

### Settings shape

On/off is one persisted key written through `core/settings`, exposed as a
`:NvSinnerMenu` row and a `:NvSinner<Feature> [on|off]` command (no argument
toggles). The command writes the setting, the setting's applier repaints —
so the two can never disagree (the `inlay_hints` / `minimap` pattern).

## 3. Authoring an asset

The original authoring was done ad hoc in Python/PIL and not committed. The
steps it took are recorded in `lua/core/CLAUDE.md` and were rebuilt as
`scripts/make-wallpaper.py` in this skill, which reproduces the shipped
format exactly (same P6 header, same 320×180 byte count as
`assets/wallpapers/angel.ppm`) and whose output decodes with `M.parse_ppm`.
It does NOT reproduce `angel.ppm` bit-for-bit — the source portrait is not in
the repo.

```bash
python3 -I .claude/skills/nvsinner-image-rendering/scripts/make-wallpaper.py \
  <source-image> assets/wallpapers/<name>.ppm --cx 0.79 --cy 0.74 --fig-h 0.9
python3 -I .claude/skills/nvsinner-image-rendering/scripts/make-wallpaper.py -h   # all knobs
```

What it does, and why each step exists:

1. **Grayscale (`L`) first.** The first `angel` build ran `autocontrast` on RGB;
   per-channel stretching tinted the image blue.
2. **Threshold the backdrop to pure 0** (source ≤ `--bg-max`) so it lands on the
   transparency key.
3. **Lift the figure into `[--lo, 255]`** so no part of the subject is mistaken
   for the key and punched through.
4. **Place the figure off-centre on a black 16:9 canvas.** The dashboard's
   centre is where the logo and menu sit; `angel` is at 79% across, 74% down.
   Cover-fit crops the sides on narrow windows, so the figure drifts toward the
   menu there — check a narrow window before committing.
5. **Save as binary P6.** PIL's `PPM` writer emits exactly what `parse_ppm`
   accepts (`P6`, one whitespace byte after `255`).

Color images work through the same decoder; skip step 1 and accept that the key
must still be pure black.

## 4. Verifying a new image feature

- **Pure parts are specced headless**: `parse_ppm` (P6 only, comments, truncation),
  `sample` (any grid size, bg = top / fg = bottom), `mix`, and `paint_grid`
  against a synthetic grid — glyph on blank cells, bg-only under text, the
  lone-space rule, keyed cells getting NO mark, priority under the pill.
  `tests/core/wallpaper_spec.lua` is the template; it pins
  `vim.g.nvsinner_theme` because the mix target comes from the palette.
- **Spec the shipped asset**: it parses, and its size stays under a cap — an
  accidental full-resolution export is the likeliest regression.
- **Look at it in a real terminal** at two widths and in a light theme before
  claiming it works; the bluish-panel bug (§5) passed every headless assertion.

## 5. Dead ends (do not retry without a new reason)

| Tried | Why it was dropped |
|---|---|
| chafa-rendered `.ansi` art | frozen to one window size, ~300 KB each; or a runtime dependency |
| User-chosen images through chafa, a per-size ANSI cache, a strength setting, several built-ins | removed on purpose to keep one knob; do not reintroduce without asking the owner |
| Remapping the backdrop onto `base00` inside the asset | fits one theme only; showed as a bluish panel around the figure |
| `autocontrast` on RGB | per-channel stretch tinted the picture blue |
| Darkening the bg under text for legibility | painted a dark box behind every word |
| `ok and s.get(k) or nil`, `transparent(x) and nil or x` | Lua `and/or` with a `false`/`nil` middle falls through; both caught by the spec — use plain `if` |
| An asset smaller than the screen's half-block size | upscaled → blurred |

## Provenance and maintenance

**Facts verified: 2026-10-06** — by reading `lua/core/wallpaper.lua`,
`tests/core/wallpaper_spec.lua`, `lua/core/CLAUDE.md` § *Dashboard wallpaper*
and commit `5101de0`'s message; `scripts/make-wallpaper.py` was run on a
synthetic 640×1138 source and its output decoded and sampled by
`require("core.wallpaper")` headless. The timings (17 → 5 ms, ~4–8 ms per
paint) are quoted from the code comment and the commit, not re-measured.

Re-verification:

```bash
grep -n 'KEY_MAX\|STRENGTH\|STEP\|PRIORITY\|IMAGE' lua/core/wallpaper.lua
head -c 15 assets/wallpapers/angel.ppm | xxd
make test-file FILE=tests/core/wallpaper_spec.lua
python3 -I .claude/skills/nvsinner-image-rendering/scripts/make-wallpaper.py -h
```
