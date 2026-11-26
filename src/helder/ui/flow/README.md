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
  boundaries (the first kept, in its item); a collapsible segment break
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
  them), a break on both sides of an atomic inline (CSS Text 3 §5.1, even
  next to a no-break space). Then white-space's wrapping by the nearest
  common ancestor of the two sides (a `<nobr>` ends with an opportunity
  its parent allows), break-spaces (after every space), hyphens (a soft
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

## Tests

- `LineBreaks.test.hx`: Unicode's LineBreakTest.txt (a sample in
  tests/flow/line-break-test.txt; the whole file where generate.mjs left
  it in bin/unicode-17.0.0), then CSS's tailorings.
- `InlineContent.test.hx`: white-space processing, transforms, offsets,
  opportunities, soft hyphens, bidi levels, shaping in Ahem
  (tests/flow/fixtures/Ahem.ttf: public domain, from WPT); properties:
  the items and pieces cover the text in order, the text has no
  collapsible spaces left in a row or at a line's start.

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
binary; the box tree gives each block container its context. Flex, grid
and table have none in this slice: they lay out as flow, noted.

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
