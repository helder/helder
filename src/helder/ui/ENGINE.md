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
| 1 | Size gate: binary sizes with a per-class map | parked; a CI-only lane later |
| 2 | Style storage: property ids, interned groups, typed reads, impact classes | done (#339, #346 sharing: the HTML Standard styled in 238 ms) |
| 3 | Box tree, block and inline flow, paint, hit testing; the WPT reftest gate | done (#341–#348, #358, #360); flex and grid in the engine (#391, grid's PR) |
| 4 | Live styling: rule index, Bloom filter, state, invalidation, compiled sheets, CSS modules | done (#332, #337, #352, #354); unsupported-CSS diagnostics next |
| 5 | The port: helder.ui on helder.dom, the app UA sheet (src/helder/css/ua/app.css), the codemod | not started; gated on sizes and benches |
| 6 | Floats, positioning, tables, lists, generated content | done (#349, #351, #355, #363, #366) |
| 7 | Paged media: fragmentation, PagedView, margin boxes, GCPM | in progress (#375; #384 margin boxes) |
| 8 | HTML→PDF end to end | `helder pdf` and `PagedView.toPdf()` |

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
