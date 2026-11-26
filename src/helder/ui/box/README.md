# helder.ui.box

helder's CSS engine past the cascade: a helder.dom document's computed
styles (helder.css) made into a box tree, laid out into flat fragments
(helder.ui.flow), painted on a helder.canvas Painter and hit tested. The
plan is that helder.ui becomes this engine, for apps and for HTML to PDF
alike; this is its first slice: the box tree and block layout (paint,
hit testing and the reftests come next).

```haxe
import helder.css.CssCascade;
import helder.ui.box.*;
import helder.ui.flow.*;

var doc = helder.dom.Dom.parse('<!doctype html><p style="border: 2px solid">Hello');
var tree = BoxTree.build(doc, CssCascade.styles(doc, {hints: true}), {image: url -> bitmaps.get(url)});
var fragments = new Fragments();
var root = tree.root.context.layout(tree.root, new Space(fragments, new FontMatch(), 800, 600));
fragments.width(root);                   // 800: the html element's border box
```

## The box tree

`BoxTree.build(doc, styles, {contexts, image})` (CSS 2.1 §9.2, Display
3 §2): each element's boxes by its display (`BoxStyle.outer`, `inner`,
`listItem`), `none` left out, `contents` its children in its place.

- `Box.kind`: `Block` (block-level block containers: block, list-item,
  flow-root, anonymous blocks), `Inline` (inline boxes), `InlineBlock`,
  `Container` (flex, grid, table and its parts: laid out as flow until
  their contexts come, noted in `BoxTree.pending`), `Text` (a text node's
  run, its DOM text as is: white space is the inline layout's),
  `InlineReplaced` and `BlockReplaced` (`<img>`, an `<object>` of an image:
  its bitmap from the caller's loader), `Break` (`<br>`).
- Anonymous boxes (§9.2.1.1): an inline-level run beside a block goes in
  an anonymous block (a run of collapsible white space alone dropped);
  an inline box holding a block is split around it, its parts' start and
  end edges only where it starts and ends (`Box.NO_START`, `NO_END`). Text
  directly in a block is a run with its parent's style (the anonymous
  inline box's).
- Generated content: `::before` and `::after` with `content`'s strings,
  `attr()`, `counter()` and `counters()` (Lists 3's counters: reset,
  increment, set, list items' `list-item`; an instance lasts until its
  element's parent ends), quotes, `url()` images; `::marker` of list
  items: its `content`, else `list-style-type`'s symbol or number
  (`Counters`: decimal, roman, alphabetic, greek, disc, circle, square),
  inside as an inline box, outside (`Box.OUTSIDE`) in the first line.
- Floats and absolutely positioned boxes are kept, laid out in flow for
  now (`pending`).
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
model of §8.3.1's sibling margins.
