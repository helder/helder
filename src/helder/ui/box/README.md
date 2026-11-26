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
  its bitmap from the caller's loader), `Break` (`<br>`).
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
helder.canvas's `ShapedRun`s, what paint and PdfWriter draw.

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
  as browsers paint them.
- `HitTest.at` walks the same order backwards, through the transforms and
  clips: a text node and the offset nearest the point, or an element.

## Fonts

`FontMatch` matches a computed font to a helder.text face (Fonts 4 §5):
each family in turn: fonts registered under a name (`register`: Ahem for
WPT), `@font-face` rules (`fontFaces`: their src loaded through the
caller), generic families (serif, sans-serif, monospace, cursive,
fantasy, system-ui...), system families that are there; then the nearest
style and weight. Ascent, descent and line gap are rounded to pixels as
Chromium rounds them.

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
clips, transforms, hit testing.

## Measures

The css-reftests lane (tests/css) gates on WPT's CSS 2.1 reftests;
`bun run test css-render <page> <out.png> --tree` draws one page and
prints its boxes and fragments; `bun run test bench layout` times the
HTML Standard's page by phase and what its boxes and fragments take.
