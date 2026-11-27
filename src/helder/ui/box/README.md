# helder.ui.box

helder's CSS engine past the cascade: a helder.dom document's computed
styles (helder.css) made into a box tree, laid out into flat fragments
(helder.ui.flow), painted on a helder.canvas Painter and hit tested. The
plan is that helder.ui becomes this engine, for apps and for HTML to PDF
alike: blocks, lines (the inline lane's engine), tables, floats,
positioning, paint.

```haxe
import helder.ui.box.DocumentView;

var doc = helder.dom.Dom.parse('<!doctype html><p style="border: 2px solid">Hello');
var canvas = new helder.canvas.Canvas(800, 600);
var view = DocumentView.render(doc, 800, canvas, {
	url: "https://example.com/page.html",
	load: url -> sheets.get(url),        // <link rel=stylesheet>, @import
	image: url -> bitmaps.get(url),      // <img>, url() backgrounds
	font: url -> fontFiles.get(url)      // @font-face
});
view.hit(20, 12);                        // {node: the Text, offset: 1}
view.caret(text, 1);                     // {x, y, height}
view.selection({node: a, offset: 0}, {node: b, offset: 3});   // [{x, y, width, height}]
sys.io.File.saveBytes("page.png", canvas.toPng());
```

## The box tree

`BoxTree.build(doc, styles, {contexts, image})` (CSS 2.1 §9.2, Display
3 §2): each element's boxes by its display (`BoxStyle.outer`, `inner`,
`listItem`), `none` left out, `contents` its children in its place.

- `Box.kind`: `Block` (block-level block containers: block, list-item,
  flow-root, anonymous blocks), `Inline` (inline boxes), `InlineBlock`,
  `Container` (a table box and its parts; flex and grid, laid out as flow
  until their contexts come, noted in `BoxTree.pending`), `TableWrapper`, `Text` (a text node's
  run, its DOM text as is: white space is the inline layout's),
  `InlineReplaced` and `BlockReplaced` (`<img>`, an `<object>` of an image:
  its bitmap from the caller's loader; an SVG image, `Box.svg`, and an
  HTML document's outermost `<svg>`), `Break` (`<br>`).
- SVG (`BoxImages`): data: URLs decoded (rasters and SVG), a `.svg` file
  read as text by the view's `load`, inline `<svg>` built from the DOM
  with each element's paint as the cascade computed it (helder.css takes
  SVG 2's paint properties and their presentation attributes; an outer
  svg's width and height are CSS's). All are drawn by `Svg.paint` as paths,
  on whole pixels, clipped to the box: vectors in a PDF. An SVG image
  (`<img>`, `url()`) is its own document, so its currentColor is black.
  Sizes as Images 3 says: natural width, height and ratio where given,
  a ratio alone the available width (backgrounds: contained in the area),
  else 300 by 150. Outside list markers lay out an image as well as
  text, 7 before the line (Chromium's padding).
- Anonymous boxes (§9.2.1.1): an inline-level run beside a block goes in
  an anonymous block (a run of collapsible white space alone dropped);
  an inline box holding a block is split around it, its parts' start and
  end edges only where it starts and ends (`Box.NO_START`, `NO_END`). Text
  directly in a block is a run with its parent's style (the anonymous
  inline box's).
- Generated content: `::before` and `::after` with `content`, and list
  items' `::marker`, resolved by helder.css's `CssCounters` (entered and
  left per element and pseudo-element in tree order: Lists 3's counter
  scoping, `list-item`, HTML's ol start/reversed and li value, quotes'
  depth, @counter-style through `CssCounterStyles`) into text runs and
  images; a marker inside as an inline box, outside (`Box.OUTSIDE`) in
  the first line; a list-style-image that doesn't load falls back to
  list-style-type.
- `::first-letter` (CSS 2.1 §5.12.2, Pseudo-Elements 4 §2.3): the first
  letter of a block container's first formatted line (through inline boxes
  and first in-flow blocks; none when an atomic inline, a replaced element
  or a break comes first), with the punctuation before and after it
  (`Punctuation`: Unicode's Ps, Pe, Pi, Pf and Po, made by generate.mjs)
  and its combining marks, in a box of the element's ::first-letter style:
  an inline box, or a float when it floats. Its text run is split from the
  DOM text's (each part with its offset). `::first-line` is not done yet.
- Tables (CSS 2.1 §17.2.1): a table is its wrapper box (`TableWrapper`:
  its margins, its captions) around the table box; a table's parts are
  `Container`s by `BoxStyle.part` (row groups, rows, cells, columns,
  captions). Missing ones are made anonymous: a run of what is not a row
  in a row group goes in a row, of what is not a cell in a row in a cell,
  of what is not a table's part in a table in a row; parts outside a
  table in an anonymous table (inline-table in an inline). White space
  alone between parts is dropped.
- Floats and absolutely positioned boxes (`Box.floating`, `absolute`:
  blocks, by blockification) are out of flow: inline content around them
  stays in one inline formatting context, and an inline box holding one
  isn't split for it.
- `BoxStyle` is the one reader of computed values: typed (`Len`,
  colours as ARGB, the box model read once), an anonymous box's style its
  parent's inherited values and the initial ones. A new style storage
  changes that file alone.

## Fragments

`Fragments` is layout's output as struct-of-arrays, LayoutNG's fragment
tree without an object per fragment: a fragment is an id; its kind
(`BOX`, `LINE`, `SPAN`: an inline box's part on a line, `TEXT`), box,
parent, first child and next sibling, place in its parent's border box,
size, baseline, text range (a span's edges), glyph run. Glyph runs are
helder.canvas's `ShapedRun`s, what paint and PdfWriter draw. Each run's
text is its inline content's whole text, and each glyph has its cluster's
characters (a ligature's several), so PdfWriter sees a line's runs as one
text: a run of the other direction becomes an ActualText span, and a PDF
reader gets the characters in logical order (`ShapedRun.shown()`: a run's
own characters).

## Paint and hit testing

- `PaintOrder` (CSS 2.1 Appendix E): per stacking context (positioned
  with a z-index, opacity under 1, a transform) its background, negative
  z-index children, in-flow blocks' backgrounds and borders, inline
  content (inline boxes' backgrounds, text, atomic inlines whole,
  replaced content), positioned descendants and z-index 0 in tree order,
  positive z-index, outlines. Each step has a state: opacity layers,
  2D transforms (`Transforms`: about transform-origin) and overflow clips
  (the padding box).
- Floats paint after the in-flow blocks' backgrounds and before the
  inline content, each whole (step 5); a row's, a column's and their
  groups' backgrounds show in their cells only, not in the spacing.
- Tables paint in §17.5.1's layers by their fragments' order (the table,
  column groups, columns, row groups, rows, cells); rows, columns and
  their groups have no borders of their own; a collapsing table's borders
  are a step of their own after its cells (`PaintOrder.BORDERS`); an empty
  cell under `empty-cells: hide` paints nothing.
- `BoxPainter` replays it on any Painter: the canvas's background (the
  root's, else body's, §14.2, over the whole canvas), box shadows
  (outer, inset, blurred), backgrounds (`Backgrounds`: colour, url()
  images and gradients, layers, size with contain and cover, position,
  repeat with space and round, origin, clip, attachment fixed; `Gradients`:
  linear by angle, side or corner, radial circles and ellipses by extent
  or length, repeating, stops placed as Images 3 says), borders
  (`Borders`: per side, every style, border-radius, inset and outset
  shaded as Chromium shades them), text with its decorations from every
  decorating box (underline, overline, line-through; solid, double,
  dotted, dashed), images, outlines. Boxes are snapped to whole pixels,
  as browsers paint them; glyph origins to quarter pixels across and
  whole ones down, as Skia quantizes subpixel-positioned text
  (`BoxPainter.snap`, off for a PDF). Decorations as Chromium draws
  them: auto thickness a tenth of the font size; an underline around the
  post table's position (FreeType's centre), a line-through above the
  OS/2 table's strikeout position by that thickness. A list marker's
  disc, circle or square is laid out as its text and drawn as a shape of
  the font's ascent (Chromium's), inside at its text's start, outside
  before the line by two thirds of the ascent and 7.
- `HitTest.at` walks the same order backwards, through the transforms and
  clips: over text, the DOM position nearest the point from its block's
  lines (InlineLayout's hit testing: a glyph's nearer half by its
  direction, a ligature's parts; inline boxes' relative offsets undone),
  else an element. `DocumentView.caret` and `selection` are the lines'
  carets and selection rectangles in the document (blocks in the box
  tree's order; transforms aside).

## In a window

`DocumentNode` is a helder.ui node showing a document live, through the
window's renderer: put in a scroller, the compositor scrolls it.

```haxe
var page = new DocumentNode(Dom.parse(html), {url: url, load: load, image: image});
page.onLink = (url, a) -> open(url);
scroller.append(page);                   // laid out at its width, as tall as the document
```

- Paint: `UiPainter` is helder.canvas's Painter on helder.ui's Canvas,
  so BoxPainter stays the one painter: rectangles, rounded ones and
  their one-colour borders become the Canvas's `rect`, glyph runs its
  `text` (GlyphText: a RunParagraph from the glyph atlas), box shadows
  its GPU shadows (`ShadowPainter`, offered by Borders as GlyphText is
  by text), images images; the rest (gradients, other paths, strokes)
  is drawn on the CPU at the window's scale and kept by what it draws,
  so a repaint draws none again. Only what the scroller's layer is
  recorded over is painted (`BoxPainter.area`; PaintOrder's runs of 64
  steps with their bounds, `chunks`, skip what is out of view at once,
  for paint and hit testing).
- Live (`DocumentView.watch`, `update`): `DocumentChanges` is the
  document's observer, helder.css's CssRestyle beside what changes the
  box tree. Each element restyled is compared with its old style by
  impact (`CssStyle.impact`): a colour swaps its boxes' styles and
  repaints (PAINT); opacity, a transform, an outline or a shadow make the
  paint order again (ORDER); a size or text lays out again from the
  layout cache, the changed boxes' and their ancestors' caches let go
  (LAYOUT); a display, float, position or generated content makes the
  box tree again (TREE), as do children inserted or removed. A text
  changed in place is its run's. What children inherit restyles them
  too (`passesDown`).
- Input: the pointer sets `Element.state` (hover on the element under it
  and its ancestors, active while pressed); dragging selects text
  (`DocumentView.position`, `selection`); an `<a href>` clicked calls
  `onLink`; Tab moves the focus (`:focus-visible`), Enter follows a
  link; the wheel scrolls a scroll container in the document
  (`scrollBy`: `overflow: auto` and `scroll` boxes move what they hold at
  paint and hit testing by their offset, `BoxPainter.scrolls`) before
  the scrollers around the node.
- A resize lays out again from the cache, the styles kept unless a media
  query or a viewport unit reads the size (`CssStyles.holds`). The cache
  is keyed on the width, the containing block's height, a fixed height
  and whether the height is ignored: a flex or grid item's passes at the
  same sizes reuse their fragment.
- Not yet: `position: fixed` and sticky boxes against the window (they
  scroll with the page); a scroll container on the compositor (one in
  the document repaints the node as it scrolls); rounded clips other
  than a box's (their bounds); editing.

tests/bench/results/document.md measures it against helder.ui today and
Chromium.

## Pages

`PagedView` lays a document out on pages (CSS Paged Media 3, CSS
Fragmentation 3), for print and PDF; a program that never uses it has
none of it (it, `Breaks` and `BreakToken` are objects only it creates;
the css-paged lane checks a screen-only program's symbols).

```haxe
var view = new PagedView(doc, {url: url, load: load, image: image});
var count = view.layout();         // the pages, view.pages[i]
view.paint(0, canvas);             // a page on a Painter
File.saveBytes("doc.pdf", view.pdf());   // PdfWriter, real text, in points
```

- Each page's style is the @page cascade's (`styles.pageStyle(index,
  name, left, blank)`): its size and bleed, its margins (auto as none,
  percentages of the page's width and height), its border and padding
  around the page area. The first page is a right one (left to right);
  a forced break to the other side makes a blank page between.
- Its content is the root laid out in the page area as a fragmentainer
  (helder.ui.flow's `Breaks`), resuming where the page before ended (a
  `BreakToken`). Each page is painted on its own: the page box's
  background over it and its bleed, its border, then its content, the
  canvas's background over the page area, positioned in the root's box
  over all the pages (a background image goes on where the page before
  left it).
- @media sees the print medium (`media`, default an A4 page), not what
  @page makes of it; viewport units are the first page's area (the
  cascade's `viewport`), as browsers have them.
- Margin boxes (`PageMargins`, Paged Media 3 §6): the corners, and three
  along each side, those with content laid out in the page's margins.
  Along a side an auto size comes from content: without a centre box the
  two at the ends share the side by their max-content sizes (their
  min-content ones when those don't fit); with one it is centred, sized
  against twice the larger other, and they take what is left. Across, a
  box fills its margin; its content is placed by vertical-align. They
  are painted over the page's content, each its own background.
- Their content: strings, `counter(page)` (the page counter: one more
  each page, or as @page's counter-reset, -increment and -set say) and
  `counter(pages)`, `string()` (string-set's values, page by page in the
  pages' fragments' order, CssRunning), `element()` (a running element:
  `position: running()` takes it out of the flow, a holder where it was;
  laid out afresh in each margin box that shows it), images.
- Cross-references (`target-counter()` and the like) are resolved once the
  pages are known, and the pages laid out again when one's text changed.
  A `leader()` is its fill repeated to its line's room (BlockLines: the
  lines laid out once more). The PDF's page labels follow the page
  counter.
- All the pages' fragments are kept: `counter(pages)` (margin boxes, the
  next part) needs every page laid out before any margin box is. Painting
  a page and dropping its fragments once its margin boxes are known,
  keeping only the break tokens of a first pass, is a later optimisation;
  tokens hold boxes, never fragments, to keep it open.
- Tables break between rows (TableFlow): each page its header rows,
  its run of body rows and its footer rows (thead and tfoot repeated),
  a caption above on the first page, below on the last; not between rows
  a cell spans; a row group's or the table's break-inside: avoid ranks
  those breaks lower, a row's break-before and -after count.
- Named pages (Paged Media 3 §5.1): a box's used page name its `page`,
  auto its parent's; siblings of different names a forced break between
  (through block containers only: a flex, grid or table container's items
  don't give it theirs); each page its name's @page style and size (a
  blank page the next one's), so pages may differ in size.
- `box-decoration-break: clone`: each fragment its border and padding
  whole, room for the bottom ones kept below its content on each page
  (`Space.reserve`).
- The PDF: an outline from `bookmark-level` and `bookmark-label`
  (helder.css's CssCounters.bookmark, HTML's headings by default), links
  from `<a href>` (a URI resolved against the document's, or `#id`: to an
  anchor at that element), each at its element's first box.
- Not yet: a table row taller than a page broken inside its cells;
  floats and absolutely positioned boxes split across pages (they go
  where they start; the inline lane's resume entry point, #370, for floats
  beside lines across a break), fixed boxes repeated on every page; flex
  and grid lines and rows across pages; monolithic content taller than a
  page pushing what follows.

## Fonts

`FontMatch` matches a computed font to a helder.text face (Fonts 4 §5):
each family in turn: fonts registered under a name (`register`: Ahem for
WPT), the document's `@font-face` rules (`fontFaces`: their src loaded
through the caller, found by the rule's family alone; the last document's
taken out), generic families (serif, sans-serif, monospace, cursive,
fantasy, system-ui...), system families that are there. A family's faces
are helder.text's `FontFaces`: the nearest stretch, style and weight to
their descriptors' ranges, unicode-range's composite faces. Its `inlines`
(the inline layout's `InlineFonts`) match the same faces: variable fonts'
instances, synthesized bold and oblique. `metrics` is what the cascade
asks for ex, ch, cap, ic and `line-height: normal` (`CssStyles.metrics`,
DocumentView installs it): the first available font's x-height (OS/2's
sxHeight, else x's top), the advance of 0, the cap height (sCapHeight,
else H's top), the advance of 水 in the face that has it, and the line
height normal has. `palette` is a colour face's palette for an element's
`font-palette` (Fonts 4 §9): normal, light and dark (CPAL's flags), a
document's `@font-palette-values` for the face's family (`fontPalettes`:
base-palette, override-colors, each colour computed as `color` is), and
`palette-mix()` of two (srgb, srgb-linear or oklab, premultiplied, as
`color-mix()`). BlockLines puts it on each run of a colour face; BoxPainter
draws the runs through helder.canvas's `ColorGlyphs`. Ascent, descent and line
gap are rounded to pixels as Chromium rounds them.

## Tests

`BoxTree.test.hx`: displays, anonymous blocks, none and contents, split
inline boxes, generated content and counters, markers, replaced
elements; properties: a block container's children are all block-level
or all inline-level, and the text runs are the document's text in
order. helder.ui.flow's `BlockFlow.test.hx`: widths, heights, margin
collapsing, relative offsets, the cache; a property against a plain
model of §8.3.1's sibling margins. `TableFlow.test.hx`: anonymous table
objects, the grid, fixed layout, rows and vertical-align, captions, the
collapsing model; a property: the columns take the width given, each its
min-content at least. `DocumentView.test.hx`: backgrounds,
borders, the canvas's background, Appendix E's order, opacity, overflow
clips, transforms, hit testing. `PagedView.test.hx`: pages and their
page area, breaks between blocks and lines, forced breaks and a blank
page for a side, avoid, widows, margins truncated or kept, a block's
border sliced, content past a page's end. The css-reftests lane draws
WPT's print reftests on pages, and css-paged real documents
(tests/paged) against goldens of our own output.

## Measures

The css-reftests lane (tests/css) gates on WPT's CSS 2.1 reftests;
`bun run test css-render <page> <out.png> --tree` draws one page and
prints its boxes and fragments; `bun run test bench layout` times the
HTML Standard's page by phase and what its boxes and fragments take.
