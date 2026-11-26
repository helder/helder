# helder.ui.flow

Flow layout for helder's CSS engine: the inline formatting context (this
part) beside block layout. The box tree builds one `InlineContent` per
inline formatting context from its items and computed styles; laying it
out at a width gives line boxes and fragments in flat arrays.

```haxe
import helder.ui.flow.InlineContent;

var c = new InlineContent(blockStyle);      // the block container's InlineStyle
c.addText("Hello ", pStyle, textNode, 0);   // a DOM Text node's raw data
c.openBox(emStyle, emElement);
c.addText("world", emStyle, emText, 0);
c.closeBox(emElement);
c.addAtomic(40, 20, 16, imgStyle, img);     // laid out by its own context
c.addBreak(br);
c.finish();                                 // white space, bidi, breaks, shaping
c.text;                                     // "Hello world￼\n"
```

Inline boxes are `openBox` and `closeBox` around their content, atomic
inlines (inline-block, replaced elements, inline flex and grid) come laid
out, `addFloat` and `addAbspos` mark where a float or an absolutely
positioned box is in the content (its static position). `finish` processes
it all once; the content does not depend on the width, so a layout at
another width neither processes nor shapes it again.

## InlineStyle

What the IFC reads of a computed style: an interface the box tree's
styles implement (`InlineBasicStyle` is one of plain fields, CSS's
initial values). The values are typed (`InlineValues`: `InlineCollapse`,
`InlineWrap`, `InlineWordBreak`, `InlineVerticalAlign`...), lengths are
CSS pixels with percentages resolved by the implementer, except
vertical-align's (`verticalShift`: a fraction of the line height). Each
style is read once while the content is built; styles are compared by
identity, so interned styles share their fonts. An inline box's edges are
its inline-start and inline-end margin, border and padding, and its border
and padding above and below (its fragments' rectangles). The root (the
block container's) style gives text-align, text-align-last, text-justify,
text-indent, text-overflow and line-clamp.

`InlineFonts` matches font-family's list (`SystemFonts`: the first family
there is, the others' faces after it for the characters it lacks, then the
system's fallbacks), the weight and the italic asked for (drawn oblique
where the face is not italic), font-feature-settings, font-kerning and
font-variant-ligatures as OpenType features. A set is made once per font
description and numbered; its metrics are rounded to whole pixels as
Blink rounds them (ascent, descent, line gap: line-height: normal).

## Processing

`finish` does, in order:

- **White space** (CSS Text 3 §4.1.1, phase I): per white-space-collapse,
  collapsible spaces and tabs become one space, across inline box
  boundaries (the first kept, in its item; but a nowrap item's space
  before a wrapping item's: the second, so that the line may break there,
  as Blink keeps it); a collapsible segment break
  becomes a space, or nothing next to a zero width space or between two
  East Asian wide characters that are not Hangul; collapsible spaces at
  the start and after a forced break are dropped (the ones at a line's end
  are the line builder's: phase II). Preserved segment breaks and `<br>`
  are `Break` items (a `\n` in the text); preserve-breaks drops the spaces
  before and after them. Carriage returns are spaces.
- **text-transform**: capitalize (each word's first letter, words across
  items), uppercase, lowercase, full-width, full-size-kana. A unit's DOM
  offset (`domOffset`) is the offset of the character it came from.
- **Bidi** (UAX #9, helder.text's `Bidi`): over each paragraph of the
  content (a forced break ends one), its base the root's direction (per
  paragraph with unicode-bidi: plaintext); inline boxes with
  unicode-bidi embed, isolate, bidi-override, isolate-override and
  plaintext as their controls (opened again after a break inside them),
  atomic inlines as U+FFFC. A text item is cut where its level changes, so
  each item has one level. Content that is all left to right skips it.
- **Break opportunities** (`LineBreaks`, UAX #14 of Unicode 17 with
  CSS's tailorings): line-break (strict: CJ as NS; normal and loose: as
  ID; loose: iteration marks and the prolonged sound mark too; anywhere),
  word-break (break-all: letters and digits as ID; keep-all: none between
  them; and hyphens, as Blink has it), a break on both sides of an atomic
  inline (CSS Text 3 §5.1, even next to a no-break space). Then
  white-space's wrapping, by the item before the opportunity as Blink's
  line breaker decides it (CSS Text 3 §5.1 says the nearest common
  ancestor's; Chromium breaks after a pre-wrap box's spaces before nowrap
  text, and not after nowrap spaces before wrapping text; a wrapping item
  that ends in a space breaks at its end whatever starts the next), never
  before a forced break, break-spaces (after every space), hyphens (a soft
  hyphen's break shows a hyphen; none with hyphens: none). The
  opportunity at an inline box's edge is before the box (after the boxes
  that close there).
- **Pieces**: what the line builder places. Each word (text between
  opportunities), run of spaces and tab of a text item is a piece, shaped
  once; every other item is a piece of its own (an Open's width its start
  edges, a Close's its end ones, an atomic's its margin box). A piece's
  `pieceBreak` is the opportunity before it.

## Shaping

`InlineShaper` is the shaped-word cache (Blink's CachingWordShaper):
a word is shaped once per font, direction, letter and word spacing and
text, by helder.text's `TextLayout` (helder's shaping, or the platform's
for the scripts that need it), its glyphs copied into flat columns (face,
glyph, advance, offset, cluster). Looking a word up allocates nothing (a
hash of the key, the text compared in place); past a million glyphs it is
emptied, and a content shapes its pieces again (`ensureShaped`). Words
lose kerning across the spaces between them, as Blink's word cache does.

## Lines

```haxe
var l = new InlineLayout().layout(c, new InlineConstraints(700));
for (k in 0...l.lines)
	for (f in l.lineFragmentStart(k)...l.lineFragmentEnd(k))
		switch l.kind(f) {
			case TextRun: draw(l.glyphs, l.glyphRun(f), l.x(f), l.y(f) + l.ascent(f));
			case BoxSpan: background(l.item(f), l.x(f), l.y(f), l.fragmentWidth(f), l.fragmentHeight(f));
			case _:
		}
InlineLayout.minContent(c);                 // shrink-to-fit, flex, tables
InlineLayout.maxContent(c);
```

`InlineLayout.layout` lays a finished content out (`LineBuilder`).
`InlineConstraints` gives the available width, the containing block's
direction (-1: the root's), and where floats are: `lineWidth(y, height)`,
the offset and width of the line at y (asked at the strut's height, asked
again at the line's own when it is taller, the line built again where
that is narrower). Laid out again with the same content and constraints
it does nothing; at another width it places the same shaped pieces.

- **Breaking**: greedy, as LayoutNG's line breaker: a line takes pieces up
  to the last opportunity where it fits. What does not count: the spaces
  that hang at its end (collapsible ones removed, pre-wrap's and its tabs
  hanging; before a forced break or at the content's end only the part
  that overflows hangs, CSS Text 3 §4.1.3), and an inline box's end edges
  after them (Blink leaves them out). Collapsible spaces at a line's start
  are removed, and a line with nothing yet but boxes' edges does not
  break. A soft hyphen's break counts its hyphen (hyphenate-character
  auto: U+2010 where the font has it, else "-"); one that fits but for its
  hyphen is the break taken where all else overflows. A run that fits
  nowhere is cut where overflow-wrap (break-word, anywhere; word-break:
  break-word) lets it: at the last cluster that fits, else after its first
  one, or before a tab or a break-spaces space that overflows; else it
  overflows to the next opportunity. Tabs go to the next stop, tab-size
  spaces of the block's font apart (as Blink measures them), the stop
  after it when closer than half a space.
- **Line boxes** (CSS 2.1 §10.8): the root's strut and every inline box and
  atomic on the line, each with its layout bounds (a box's font's ascent
  and descent and its half-leading, the part above floored to a pixel as
  Blink's; an atomic's margin box, its baseline its own or its bottom
  margin edge). A box is aligned once its children are in it: its
  vertical-align shift from its parent's baseline (sub and super by the
  parent's size, text-top, text-bottom and middle by its subtree's
  extent, lengths and percentages of its line height; in Blink's
  LayoutUnit, 1/64 of a pixel), then its subtree into its parent's; top-
  and bottom-aligned subtrees are placed last, the line growing to hold
  them. A line with nothing in it (no text, preserved space, atomic, box
  edge or forced break: CSS 2.1 §9.4.2) is zero high.
- **Alignment**: text-align (start, end, left, right, center; justify is
  the next PR's), text-align-last on the last line and before forced
  breaks, text-indent (each-line, hanging); an overflowing line is start
  aligned.
- **Output**: per line its top, height, baseline, width used, left, the
  width it had, its text range and its fragments; per fragment its kind
  (`TextRun`: an item's text on a line, a tab its own; `BoxStart` and
  `BoxEnd`: a box's edges where it starts and ends; `BoxSpan`: its border
  box on the line, for backgrounds and borders; `Atomic`; `Hyphen`;
  `Float`, `Abspos`: their static positions), rectangle, ascent and
  descent, bidi level, item, text range and glyph run. `InlineGlyphs` holds
  the runs, per glyph its face, id, x from the fragment's left, y offset,
  advance and the text unit its cluster starts at: what paint and
  PdfWriter both read.
- **Intrinsic sizes**: `minContent` breaks at every opportunity
  (overflow-wrap: anywhere's cuts in, break-word's out), `maxContent` at
  forced breaks only; each the widest line's used width.

## Tests

- `LineBreaks.test.hx`: Unicode's LineBreakTest.txt (a sample in
  tests/flow/line-break-test.txt; the whole file where generate.mjs left
  it in bin/unicode-17.0.0), then CSS's tailorings.
- `InlineContent.test.hx`: white-space processing, transforms, offsets,
  opportunities, soft hyphens, bidi levels, shaping in Ahem
  (tests/flow/fixtures/Ahem.ttf: public domain, from WPT); properties:
  the items and pieces cover the text in order, the text has no
  collapsible spaces left in a row or at a line's start.
- `InlineLayout.test.hx`: lines, spaces at their ends, inline boxes'
  edges and spans, vertical-align, atomics, forced breaks, pre-wrap, soft
  hyphens, overflow-wrap, tabs, text-align and text-indent, floats'
  lineWidth, intrinsic sizes and glyph runs, in Ahem; properties: no line
  wider than its width unless it holds a piece that cannot break, a layout
  the same twice, min-content <= max-content, at max-content a line a
  forced break, the fragments' text in order the content's.
- `flow-differential` (tests/flow/differential.mjs): generated content
  (text in white-space's modes, nested inline boxes with margins, borders
  and padding, inline-blocks, vertical-align's values, line heights,
  forced breaks, letter and word spacing, overflow-wrap and word-break,
  text-align and text-indent) laid out by headless Chromium and by
  tests/flow/InlineDiffCheck.hx natively, in Ahem: each text node's
  Range.getClientRects, each inline box's getClientRects (each box given
  a faint background, so that Blink does not cull it), each inline-block's
  border box and the block's height, within 0.5px (a node's touching
  rectangles on a line as one: where a fragment ends is each engine's
  own). FLOW_CASES (300) from FLOW_SEED (0), then the kept cases
  (tests/flow/fixtures/differential; KEEP=1 keeps a new failure there);
  differential-known.json gives each case known to differ its reason, and
  a known case that passes fails the run. FLOW_ONLY=seed-12 prints one
  case's rectangles on both sides (its page: bin/flow/only.html);
  FLOW_NO=va,tab,bs,ow,ls,edges,atomic,br,tb,mid,tt,shift leaves features
  out. On Chromium 141: 276 of the first 300 seeds the same, the other 24
  known (17 of them top- and bottom-aligned subtrees that nest); a fresh
  range (FLOW_SEED=1000): 269 of 300, 290 with no top or bottom.
- `bench inline` (tests/bench/InlineBench.hx): the HTML Standard's 26,641
  paragraphs (3.3 MB) at 700px in Inter, natively: 146 ms per MB with the
  word cache empty, 133 with it full, 38 laid out again at 500px;
  TextLayout on the same texts: 135 made, 18 wrapped again.

`node src/helder/ui/flow/generate.mjs` makes LineBreakData.hx (each code
point's Line_Break class and the flags its rules read: East Asian width,
a quotation mark's Pi or Pf, unassigned pictographs) and the sample from
Unicode 17.0.0's files (manifest.json: their hashes).

## Formatting contexts (the box tree's part)

A `FormattingContext` lays out a box's contents: `layout(box, space)`
gives the box's fragment (helder.ui.box's `Fragments`) and leaves its
used margins and collapsing margins on the box; `intrinsic(box, space)`
its min-content and max-content widths. They are objects a program makes
(`Contexts`: one per inner display), so one it never makes is not in its
binary; the box tree gives each block container its context. Flex and
grid have none in this slice: they lay out as flow, noted.

`Space` is LayoutNG's constraint space: the containing block's width,
the height percentages resolve against (NaN: indefinite), a width the
box must take (shrink-to-fit's), and the `lineWidth(y, height)` hook
floats will narrow lines through. A box's last layout is cached on it,
keyed on its space: the same space, the same fragment.

## Block flow

`BlockFlow` (CSS 2.1 §9.4.1, §10.3, §10.6, §10.7, §8.3.1):

- Widths: §10.3.3's equation (auto margins centre, an over-constrained
  box gives up its end margin, the start one in right-to-left), min-width
  and max-width by laying the width out again, box-sizing, percentages of
  the containing block; inline blocks shrink to fit (§10.3.9), from
  `intrinsic`.
- Replaced elements (§10.3.2, §10.6.2): the image's size and ratio, or
  what width and height say, clamped.
- Heights: specified (a percentage of an indefinite height is auto), else
  the content's: the last line box's bottom, or the last child's bottom
  margin edge where that margin does not collapse through; min-height and
  max-height.
- Margin collapsing, whole: siblings; parent and first child (no top
  border or padding), parent and last child (and an auto height); empty
  boxes their margins collapse through, with what is before and after
  them, up to the parent's top when nothing came before; none across a
  new formatting context's root (flow-root, overflow, inline blocks,
  floats and absolutely positioned boxes, the root). Each box returns the
  largest positive and most negative margin of its top's and its
  bottom's sets, its parent places it from those.
- Relative positioning (§9.4.3) moves a box's fragment, and an inline
  box's, after its place is known.

## Floats and positioning

- `Exclusions`: a block formatting context's floats, their margin boxes
  in the layout's coordinates. `place` puts the next one by §9.5.1's
  rules (no higher than an earlier float, beside the floats there, at its
  side of the containing block, down past them until it fits); `band`
  gives the room across a line or a box; `clear` where clearance puts a
  box; `lowest` what a root's auto height takes in (§10.6.7).
- `Space` carries the context's floats, the containing block's left and
  the box's predicted top: a child's top margins are summed before it is
  laid out (`predict`: its own and its first in-flow descendants' while
  nothing parts them), so the floats and lines inside it know where they
  are. A prediction that misses (margins collapsing through an empty
  first child) leaves its floats off by that much.
- In block flow a float is laid out shrink-to-fit and placed at the
  current position; clearance (§9.5.2) puts a box's border edge below the
  floats it clears, its own top margin then not collapsing with what is
  before it; a formatting context's root (overflow, flow-root, a table)
  goes beside the floats in the room they leave, or down past them when
  its margins, set width or a table's min-content don't fit.
- In a line (`WordFlow`): a float met is placed by the block at the line's
  top (`Space.placeFloat`), the line's room taken again; `lineWidth` gives
  each line its room and how far down it widens, a line whose first word
  doesn't fit goes there.
- Absolutely positioned boxes wait in their containing block's list
  (`Positioned`: the nearest positioned box's, else the root's; fixed ones
  the root's), with their static place in the fragment they were met in
  (a block's next position, or where they are in a line). Once the
  containing block is sized each is laid out by §10.3.7 and §10.6.4's
  equations against its padding box (the root's: the initial containing
  block, the viewport): auto widths shrink to fit, auto margins centre
  (negative vertical ones too), top and bottom with an auto height
  stretch it. A layout that leaves such boxes outside itself isn't reused
  from the cache (`Box.ESCAPES`), nor one beside floats.
- Not yet: the static position of a box that was block-level before
  blockification is taken where it is met in a line, not below it;
  sticky positioning (as relative); floats' intrinsic contribution beyond
  their min- and max-content.

## Tables

`TableFlow` (CSS 2.1 §17, with CSS Tables 3 where they agree) lays out a
table's wrapper box: its captions above and below (caption-side), each a
block in the table's width, around the table box.

- The grid: row groups in order (the first header group first, the first
  footer group last, lone rows as groups of their own), each row's cells
  in the slots that rowspans above leave, HTML's colspan and rowspan
  (rowspan 0: to the group's end), columns and column groups with their
  span.
- Widths: `table-layout: fixed` with a width (§17.5.2.1: the columns'
  widths, else the first row's cells', the rest shared equally; content
  ignored), else the auto algorithm: each column's min-content and
  max-content from its single-column cells (a set width its max, a
  percentage kept), spanning cells' surplus spread over their columns by
  max-content, then Tables 3's guesses (min-content, percentages, set
  widths, max-content), a width between two of them shared linearly,
  past the last given to auto columns first (`distribute`). The table's
  width is its border box's under `box-sizing: border-box` (HTML's sheet
  gives `<table>` that), at least its min-content.
- border-spacing in the separated model; in the collapsing one (§17.6.2)
  each grid line's segment takes what wins of the cells', rows', row
  groups', columns', column groups' and table's borders (hidden, then
  none, width, style, origin: `TableGrid.wins`), split in whole pixels
  (floor(w/2) above and to the left), cells laid out with their parts
  (`Space.borders`), the table's own being the outer lines' other parts.
- Cells are laid out by flow at their columns' width (their fragment
  that width even where padding is wider); rows as tall as their own
  height, their cells and their baseline alignment need, a rowspan's
  surplus to its last row, a table's height's surplus shared by height;
  `visibility: collapse` rows of no height. Cells align by vertical-align
  (baseline: the first line's, top, middle, bottom).
- Fragments in the order their backgrounds paint (§17.5.1): the table box,
  column groups, columns, row groups, rows, cells; the grid
  (`Box.table`) for paint's collapsed borders.

Not yet: percentages in heights inside cells, `visibility: collapse`
columns, a table's header and footer repeated across pages (the paged
host's).

## The line builder's stand-in

`WordFlow` builds a block container's `InlineContent` from the box tree
(`addText` with each text run's DOM text, `openBox` and `closeBox`
around inline boxes, `addAtomic` with inline blocks and replaced
elements laid out first, `addBreak`; each item's style a `BoxInline`, one
per box, so an item's box is its style's) and, until the inline lane's
line builder lands, places its pieces in lines itself: filled greedily
at the content's opportunities, collapsible spaces at a line's ends
taking no room, line boxes as §10.8 builds them (each inline box's line
height around its font's rounded ascent and descent, the strut,
vertical-align's keywords, lengths and percentages, top and bottom),
text-align with justify, text-indent, inline boxes' edges, a line of
nothing of no height, outside markers before the first line; in logical
order (no visual reordering). Min-content and max-content break at every
opportunity and at forced ones. Its output is what the real builder's
will be: line, span and text fragments with glyph runs of the shaped
words.
