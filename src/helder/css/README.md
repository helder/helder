# helder.css

CSS read as the specs define it, for helder's HTML and CSS to PDF
engine: the properties and their value grammars, in pure Haxe (native
and wasm32-wasi). Its tests gate on web-platform-tests' own cases
(tests/css).

```haxe
import helder.css.CssGrammars;

var margin = CssGrammars.property("margin");   // margin.syntax: "<'margin-top'>{1,4}", margin.longhands, ...
var g = CssGrammars.of(margin.syntax);         // Repeat(Prop("margin-top"), 1, 4, false)
var rect = CssGrammars.type("rect()", ["clip"]); // clip's rect( <top>, <right>, <bottom>, <left> ), not a shape's
```

## Properties

`CssData` (generated: `node src/helder/css/generate.mjs`) is
[@webref/css](https://github.com/w3c/webref/tree/main/packages/css)
8.7.10, the CSS specs' definitions as webref scrapes them, cut to
checkpoint 1's properties:

- `properties`: 219 `CssProperty`s, each with the module it is in scope
  for (`module`), its spec's anchor (`href`), its grammar (`syntax`, the
  spec's text), `initial`, `inherited` (null for a shorthand), `appliesTo`,
  `percentages`, `computed` (the computed value's prose), `animation`,
  `longhands` and `alias` (a legacy name's property: `word-wrap`,
  `font-stretch`, `grid-gap`).
- `types`: the 274 named types and functions the grammars reference, all
  the way down (`<color>` to `<color-base>` to `<rgb()>` to
  `<legacy-rgb-syntax>`), and `<'p'>`s of properties out of scope
  (`<'overflow-block'>`). A name defined again for some properties or types
  (webref's `for`: clip's `rect()`, transform's `scale()`) has its `scope`;
  `CssGrammars.type(name, context)` takes the one of the context (the
  property, then the types and functions a reference is inside), else the
  general one. 21 have no grammar: Values 4's and Syntax 3's own
  (`<length>`, `<custom-ident>`, `<declaration-value>`), matched by hand,
  each named in scope.json's `primitives`.
- `descriptors`: the 69 of `@page`, `@font-face` and `@media` (its
  features).

The grammars are each spec's latest level, as webref keeps them, so some
take more than checkpoint 1 renders (`width`'s `anchor-size()`, `<color>`'s
`light-dark()`); what of it is matched is the matcher's conformance to
say. Where checkpoint 1's module and the latest differ, scope.json's
`overrides` keep the module's: `string-set` is GCPM 3's (a content list),
not CSS Content 3's (strings). Its `types` give the grammars the specs say
in prose: CSS 2.1's `<top>` to `<left>` (`<length> | auto`), Fonts 4's
`<font-src-list>`.

scope.json lists the properties in scope under their module, and every
other webref property is out, by its spec (`outSpecs`) or by name (`out`),
each with why; the generator fails on a property it can't place, a
longhand or alias out of scope, or a type no definition gives.
manifest.json has the package's hash and the counts. Out are 604:

| Out | Properties |
| --- | --- |
| -webkit- aliases and WebKit's compat properties | 68 |
| logical properties, writing modes (deferred) | 72 |
| animation, transitions, view transitions, will-change: a page is still | 55 |
| scrolling, line clamping, overflow 4 | 56 |
| SVG's presentation properties, fill and stroke | 52 |
| Borders 4 (corner shapes, partial borders), Backgrounds 4, Gaps 1's decorations | 86 |
| interaction (UI 4's carets, cursors, appearance; spatial navigation; reading order; the top layer) | 27 |
| masking (CSS 2.1's `clip` is in), filters, blending, containment | 30 |
| multicol, footnotes, regions, shapes and exclusions, forms, `@container` (deferred) | 29 |
| speech | 19 |
| Text 4 and 5, Text Decoration 4, Inline 3 past `line-height` and `vertical-align` | 37 |
| Sizing 4, Transforms 2 (3D, `translate`/`rotate`/`scale`), anchor positioning, motion paths | 33 |
| replaced content (Images 3 to 5: `object-fit`, `image-orientation`), ruby, MathML, line grids, color schemes, palettes, HDR, page floats past CSS 2.1's, zoom, the rest of the next levels | 40 |

## Value grammars

`CssGrammars.parse(text)` reads the value definition syntax (CSS Values 4
§2) into a `CssGrammar`, and `print` writes it back:

- `Keyword(name)`, `Delim(text)` (`,` and `/` as written, others quoted:
  `'+'`), `Named(name, range)` (`<length>`, `<rgb()>`, `<length [0,∞]>`:
  `{min, max, unit}`, `<angle [-90deg,90deg]>`), `Prop(name)`
  (`<'margin-top'>`), `Func(name, args)` (`rect( ... )`), `Block(open,
  inner)` (`( ... )`, `'[' ... ']'`);
- `Sequence`, `All` (`&&`), `Any` (`||`), `One` (`|`), binding in that
  order, tightest first; brackets group and keep their node, so `a || [ b
  || c ]` is not `a || b || c` (any order of three);
- `Repeat(item, min, max, comma)`: `?`, `*`, `+`, `{A}`, `{A,B}`, `{A,}`,
  `#` and `#{A,B}` (comma: a comma list; max -1: no limit), stacked as
  written (`<length>#?`); `Required(item)`: `[ ... ]!`.

A text that is not a grammar throws, with where. `of(syntax)` parses a
definition once and keeps it.

Tests (`CssGrammars.test.hx`, natively, as wasm32-wasi and on Eval): every property's,
type's and descriptor's grammar of the data parses and prints back to
itself, every reference it makes is defined (in its context), every
longhand and alias is in the table; the shapes of a few and the errors;
and a property: any tree prints to text that parses back to it. The css
lane checks the same data against the WPT fixtures (tests/css).
