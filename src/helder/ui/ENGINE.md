# One CSS engine: the plan

helder is growing one CSS engine for apps and documents alike. There is one
tree, helder.dom, and helder.ui becomes the engine that styles, lays out,
paints and handles input for helder.dom documents: an app's screens, an HTML
page in a window, an HTML document printed to PDF. In the end there is no
separate ui Node. Backward compatibility isn't kept; the goal is spec
compliance, measured by web-platform-tests, with apps staying small (DCE)
and fast.

## The pipeline

    helder.dom Document
      → CSS cascade (helder.css): UA sheet, compiled theme sheets, author CSS, inline styles
      → computed styles (typed, interned style groups by property id)
      → box tree (helder.ui.box): display → boxes, anonymous boxes, ::before/::after/::marker, text runs
      → layout per formatting context (helder.ui.flow): block, inline, table, flex, grid; floats; positioned
        into a fragmentainer: a window (endless) or pages (PagedView: @page, margin boxes)
      → fragments (flat struct-of-arrays)
      → paint on a helder.canvas Painter (CPU canvas → PNG, Recorder → PdfWriter;
        helder.ui's DisplayList at the port), hit testing, selection

## Steps

| Step | What | State |
| --- | --- | --- |
| 1 | Size gate: binary sizes with a per-class map | done: the `size` lane (#459), CI-only, per-OS baselines |
| 2 | Style storage: property ids, interned groups, typed reads, impact classes | done (#339; #346 sharing: the HTML Standard styled in 238 ms) |
| 3 | Box tree, block and inline flow, paint, hit testing; the WPT reftest gate | done (#341–#348, #358, #360); flex and grid in the engine (#391, #395), aspect-ratio and grid tracks (#403) |
| 4 | Live styling: rule index, Bloom filter, state, invalidation, compiled sheets, CSS modules | done (#332, #337, #352, #354); unsupported-CSS diagnostics and the support table open |
| 5 | The port, now **fast nodes**: the box tree is the base layer; a fast node is a box made from code with a typed `Style` (no DOM, no cascade), DOM documents build the same boxes; one tree for selection, hit testing, focus and accessibility | 5a done (#447–#503: a live document in a window, its benches, exact layout); fast nodes steps 1–4 done (#498 bench, #499 Box off the DOM, #500/#506/#511 typed BoxStyle, #503 paint reuse, #516 `Style`/`Node`/`Tree` and the `fast-probe` lane); step 5 (the real todo through markup) in progress |
| 6 | Floats, positioning, tables, lists, generated content, containment | done (#349, #351, #355, #363, #366, #414, #417) |
| 7 | Paged media: fragmentation, PagedView, margin boxes, GCPM | done for checkpoint 1 (#375–#442): pages, margin boxes, running heads, cross-references, tables, floats, flex and grid across pages, monolithic overflow |
| 8 | HTML→PDF end to end | done: `helder pdf` and `PagedView.toPdf()`; real text, outline, links, colour fonts, SVG as vectors, deduplicated images |

## Where it stands (2026-11-27, evening)

- **WPT gate (`css-reftests`):** 7,509 of 9,047 pass, 1,538 pending with reasons, 149 skipped; box conformance (Taffy) 4,671 of 5,232.
- **Values:** 19,924 of 20,206 WPT value rows; interpolation 3,500 of 4,456.
- **Against WeasyPrint** (tests/pdf-docs): 98.5–100% per document with exact metrics (#453), identical page breaks.
- **Documents in a window, against browsers** (tests/bench/results/document.md, measured on one Mac, pages served locally): the HTML Standard loads in 1.9 s (Chromium 1.8, Ladybird 4.2), relayouts at a new width in ~207 ms (Chromium 139, Ladybird 294), and holds 843 MB RSS (Chromium 1,176, Ladybird 2,298). On the ECMAScript spec, War and Peace and Japanese pitch accent helder uses less memory than both browsers; load is faster than both on the first two.
- **Apps:** fast nodes are within 1.43× of helder.ui on every todo/mail operation (most at or under 1.35×), and a fast-only todo is +15% in size over helder.ui's (6.31 MB native); the same screens through the DOM are +45% / +53% wasm.
- **Size work** (#456 sheets as data, #458 tables as data, #462 no run-time parsers, #474–#478 layouts, counters and the matcher only when used) ended at the engine's core; the rest is hxmc's code generation.

## Next

1. **Fast nodes (step 5 onward; the design: decisions recorded in the 2026-11-27 PRs #498–#516)**: the real todo through its markup, with focus, keys, accessibility and selection on fast boxes, then mail; `Style.of` and CSS modules resolved at build time, static subtrees as templates; CSS transitions on helder.ui's motion clock (deterministic for scenarios); then fast nodes become `helder.ui.Node` and helder.ui's own Layout goes.
2. **Owed with an unlocked screen**: the real-input `document-window` run (six pages) and SystemLayersWindowCheck.
3. **Engine gaps by stage** (the gate's pending reasons): tables (~580), generated content and positioning tails, inline and bidi, floats, the rest of paged, SVG (`<text>`, patterns, masks, filters).
4. **WeasyPrint features still missing**: footnotes, multi-column layout (also ~1,100 css-break tests), http(s) resources in `helder pdf`, PDF/UA and PDF/A.
5. **CSS animations**: `@keyframes` and `animation-*` (transitions first, with fast nodes' motion).
6. **Async scrolling ahead**: the compositor scrolls at most a viewport past what was recorded while the program is busy; Chromium records a larger interest area.

## Decisions

- **One tree, helder.dom**, modelled on the WHATWG DOM spec's names and
  algorithms (as Ladybird and Quaxe do). Engine state lives beside nodes;
  helder.dom keeps only small extras (source offsets, `Element.state`,
  `Document.observer`).
- **Formatting contexts are objects picked by display**, so programs link only
  the ones they create; paged code (Breaks, BreakToken, PagedView, PageMargins)
  is linked only by programs that use PagedView, which the `css-paged` lane
  checks with `nm`.
- **CSS modules for TypeScript and Haxe** (`import s from './card.module.css'`,
  `CssModule.load`): compiled at build time, exactly typed, and unsupported
  CSS is a build error with file:line:col.
- **Targets:** native and wasm32-wasi. Eval only for code that runs inside
  macros (helder.css's parsing half, for compiled sheets).
- **No hxmc.unsafe** in parsers of untrusted input (helder.dom, helder.css,
  WOFF/Brotli); hxmc.kernel and hxmc.simd where measured.
- **Flex and grid are ported, not shared.** helder.ui's Layout lays out its
  own retained Nodes (per-node caches, pools, in-place relayout, its Style
  model); the engine's FlexFlow and GridFlow are its algorithms ported to the
  box tree (items with block, inline and table layout inside, fragments
  out). Both copies coexist until the port (step 5), both held to Taffy's
  Chrome fixtures (`layout-conformance` for helder.ui, `box-conformance` for
  the engine); the port removes helder.ui's.
- **The app UA sheet** reproduces helder.ui's defaults, so the port changes no
  look: `<text>` is a block (nested runs stay inline), and the window's
  background stays the window's clear colour, not the root's.

## Gates

- `css`: syntax, values (WPT), cascade, selectors, counters, GCPM, interpolation.
- `css-reftests`: WPT CSS2, css-page, css-break, css-fonts and css-values
  reftests, plus noref tests against Chromium goldens, plus print reftests on
  pages; bundled fonts only, one manifest for every OS.
- `dom`: html5lib and WPT tree construction, parse5 differential, XML.
- `flow-differential`: the inline engine against Chromium with Ahem.
- `layout-conformance`: helder.ui's flex and grid against Taffy's Chrome fixtures.
- `box-conformance`: the same fixtures through the engine (FlexFlow,
  GridFlow); part of the `css-reftests` whole run.

Any PR touching helder.css, helder.dom or helder.ui runs `css-reftests`
before it's pushed; font or asset changes also run `web`.

## Performance

Interned and shared style groups, a style-sharing cache, property ids, flat
fragments, a layout cache keyed on constraints, break opportunities once per
text, a shaped-word cache, glyph runs shared by layout, paint and PdfWriter.
References: Chromium LayoutNG, Ladybird LibWeb, Servo/Stylo, WeasyPrint, Taffy.
