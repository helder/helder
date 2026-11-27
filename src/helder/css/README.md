# helder.css

CSS read as the specs define it, for helder's HTML and CSS to PDF
engine: CSS Syntax 3's tokens, rules and declarations, the properties and
their value grammars, in pure Haxe (native and wasm32-wasi). Its tests
gate on css-parsing-tests' and web-platform-tests' own cases (tests/css).

```haxe
import helder.css.Css;

for (rule in Css.sheet("a { color: red; &:hover { color: blue } }"))
	switch rule {
		case Qualified(prelude, declarations, rules): trace(Css.serialize(prelude), [for (d in declarations) d.name]);
		case At(name, prelude, block): trace('@$name');
		case Declarations(_):
	}
var style = Css.declarations("color: red; margin: 0 !important");  // a style attribute
var value = Css.values("1px solid rgb(0 0 0 / 50%)");            // a property's value
```

```haxe
import helder.css.CssGrammars;

var margin = CssGrammars.property("margin");   // margin.syntax: "<'margin-top'>{1,4}", margin.longhands, ...
var g = CssGrammars.of(margin.syntax);         // Repeat(Prop("margin-top"), 1, 4, false)
var rect = CssGrammars.type("rect()", ["clip"]); // clip's rect( <top>, <right>, <bottom>, <left> ), not a shape's
```

## Syntax

CSS read as CSS Syntax Level 3 reads it (the Editor's Draft of 20
October 2026, CSS Nesting's blocks included): tokens, component values,
rules and declarations, and text written back from them. The values,
selectors and the cascade above it give them meaning; this layer
accepts every input and gives each the structure a browser's parser
would.

### Entry points

The spec's parser entry points (§5.4) on text. None throws: a syntax
error is null, and what the spec drops (an invalid declaration, a rule
cut off by the end) is left out.

| | |
| --- | --- |
| `Css.tokens(text, ranges = false)` | every token (§4); `ranges`: unicode-range tokens, as the unicode-range descriptor is read |
| `Css.sheet(text)` | parse a stylesheet (and a stylesheet's contents): its rules, CDO and CDC dropped at the top level |
| `Css.decode(bytes, ?protocol, ?environment)` | a stylesheet's bytes as text (§3.2): the BOM, else the protocol's label (Content-Type's charset), the `@charset "...";` bytes, the environment's encoding, UTF-8; `{text, encoding}`, the encoding's WHATWG name |
| `Css.rule(text)` | parse a rule: one, whitespace around it |
| `Css.declaration(text)` | parse a declaration (@supports' condition) |
| `Css.declarations(text)` | parse a list of declarations (a style attribute): at-rules and bad declarations left out |
| `Css.block(text)` | a block's contents (§5.5.5): declarations, nested rules and at-rules, in order |
| `Css.value(text)`, `Css.values(text)` | parse a component value, a list of component values |
| `Css.list(text)` | parse a comma-separated list of component values |
| `Css.serialize(values)`, `Css.serializeTokens(tokens)` | text that tokenizes to the same tokens again (§9) |
| `Css.lower(s)` | ASCII lowercase: keywords match ASCII case-insensitively (`İmportant` is not `important`, which `toLowerCase` would make it) |
| `CssAnB.parse(values)` | An+B (§6): `a`, `b`, `matches(index)`, `toString()` (§9.1) |

### The tree

- **`CssToken`**: `kind`, a `CssTokenKind`, and `start`, `end`: where
  it was read, in the text's String units (UTF-16 code units natively and
  as wasm32-wasi). Kinds: `Ident`, `Function`,
  `AtKeyword`, `Hash(value, id)` (`id`: the "id" type flag), `Str`,
  `BadString`, `Url`, `BadUrl`, `Delim` (one code point), `Number`,
  `Percentage` and `Dimension` (value, integer: the type flag, text: the
  number as written, for serialization; a dimension's unit),
  `UnicodeRange(start, end)`, `Whitespace`, `Cdo`, `Cdc`, `Colon`,
  `Semicolon`, `Comma`, and the brackets.
- **`CssValue`**: `Token(token)`, `Function(name, values, open, close)`,
  `Block(open, values, close)` (`open`: the `{`, `[` or `(`; `close`:
  null when the text ended first, so serializing writes no closing
  bracket the text did not have).
- **`CssRule`**: `Qualified(prelude, declarations, rules)` (the block's
  first run of declarations, then its rules, later runs as
  `Declarations`, CSSOM's nested declarations rules), `At(name, prelude,
  block)` (`block`: null for a statement at-rule; its items as read, runs
  of declarations as `Declarations`: the at-rule says what they are),
  `Declarations(list)`.
- **`CssDeclaration`**: `name` (as written), `value` (without the
  whitespace around it nor `!important`), `important`, `text` (a custom
  property's value as written in the source, null for others), `start`,
  `end`. A declaration named `unicode-range` (any case) has its value
  tokenized again with unicode ranges allowed, as the spec says.

### How it reads

The tokenizer runs over the String as it is: the input's filtering
(§3.3) is done as each code point is read (CR, FF and CR LF one LF, NUL
and a lone surrogate U+FFFD, a surrogate pair one code point), so the
offsets are the text's own and a value without escapes is a substring.
Ident code points are this draft's: ASCII letters, digits, `-`, `_` and
HTML's custom element names' non-ASCII ranges (U+0080 is a delim).

The parser follows §5.5's algorithms over the token array, a mark
restored where a block's item reads as a declaration first and a rule
after. Every rule counts as valid in its context: validity is the
grammar's above this (selectors, the at-rules' own), so no "invalid rule
error" is ever returned. Two choices where the draft says less:

- **§5.5.5's erratum**: the draft returns a block's contents at `}` or
  the end without its last run of declarations (`a { color: red }` would
  have none). It is appended, as the drafts before did.
- **Limits**: functions and simple blocks nest as deep as the text (read
  without recursion), rules to 256 levels: a block deeper is read past
  as values and left empty. A declaration that can no longer be one
  (a `{}` block after other values, anything but `!important` after one)
  stops there, the implementation note's early exits: a nested rule is
  not read to its end as a declaration first.

Serializing writes whitespace as one space, quotes strings with `"`,
escapes what would read otherwise (an ident's leading digit, a unit `e3`
that would be an exponent, a `\` delim as `\` and a newline), and puts
`/**/` between two tokens that would read as one: §9's table, and two
pairs it leaves out (`<` `!` before an ident starting with `--` or a CDC,
which would read as a CDO; an ident `--` before `>`, which would read as
a CDC).

`Css.decode` reads UTF-8, UTF-16 and WHATWG Encoding's single-byte
encodings (windows-1252, ISO-8859-x, KOI8...: EncodingData.hx, made by
tests/css/make-encodings.mjs); the multi-byte CJK ones (GBK, gb18030,
Big5, EUC-JP, ISO-2022-JP, Shift_JIS, EUC-KR) are not decoded, so their
labels count as unknown ones and the next fallback applies.

helder.gfx's `CssColor` parses a colour written as a string (for SVG's
paints and helder.ui's styles); `<color>` on component values is the
values' layer.

### Tests

- `tests/css` (the `css` lane, natively): css-parsing-tests' 305 Syntax
  cases (CC0, pinned by tests/css/import-css-parsing-tests.mjs), all
  required, none pending. The fixtures follow the 2021 draft; 36 cases
  carry the current draft's expected result and why (blocks parsed as
  contents, a declaration's value trimmed and ended at `;`, no `~=`-style
  tokens, unicode-range tokens for the descriptor alone, at-rules out of a
  declaration list). Its colour files are skipped: `<color>` is CSS
  Color's grammar, not Syntax's.
- `Css.test.hx` (natively and as wasm32-wasi): examples, and properties:
  tokens serialized tokenize the same (whitespace runs one), tokens'
  offsets in order with only comments between them, any text parses and
  its values print back, mutated stylesheets (site/site.css, the
  fixtures) parse within a time and memory limit (soaked by the `fuzz`
  lane).

## Selectors

`CssSelector.list(prelude, ?namespaces)` reads a rule's prelude as a
selector list (Selectors 4's grammar: Level 3's, and `:is()`,
`:where()`, `:not()` of a list, `:has()`, `:nth-child(An+B of S)`); null
when any of it is invalid, as a rule with an invalid selector is
dropped. `CssSelector.parse(text)` on text, `relativeList` for relative
selectors (`> a, + b`).

```haxe
var list = CssSelector.parse("article > p:not(.note)::first-line");
list[0].compounds;     // [[Type("article", AnyNamespace)], [Type("p", AnyNamespace), Pseudo(Not([...]))]]
list[0].combinators;   // [Child]
list[0].pseudo;        // FirstLine
list[0].specificity;   // (0, 1, 3): a, b, c; compare() orders two
```

- A complex selector is its compounds left to right with a combinator
  between each two (`Descendant`, `Child`, `NextSibling`,
  `SubsequentSibling`), and the pseudo-element its subject is, apart
  (`Before`, `After`, `Marker`, `FirstLine`, `FirstLetter`,
  `Placeholder`, `Selection`, `Backdrop`, `FileSelectorButton`, GCPM's
  `FootnoteCall` and `FootnoteMarker`; `Slotted` and `Part` never
  match); `:before`, `:after`, `:first-line` and `:first-letter` with
  one colon too. After a pseudo-element only the user-action
  pseudo-classes may follow.
- Simple selectors: `Type` (as written), `Universal`, `Id`, `Class`,
  `Attribute(name, ns, op, value, sensitivity)` (`=`, `~=`, `|=`, `^=`,
  `$=`, `*=`, and the `i` and `s` flags), `Pseudo`.
- Namespaces: a prefix must be declared (`namespaces.prefixes`, as
  @namespace does), else the selector is invalid; a type selector
  without one is in the default namespace if declared, else any; an
  attribute without one in none.
- Pseudo-classes: the tree's (`:root`, `:empty`, `:first-child`...,
  `:nth-*()`, `:scope`), `:link` and `:any-link`, `:lang()`, `:dir()`,
  the input states (`:enabled`, `:disabled`, `:checked`,
  `:indeterminate`, `:default`, `:required`, `:optional`, `:read-only`,
  `:read-write`, `:placeholder-shown`), `:valid` and `:invalid` (basic: a
  required control with no value is invalid), `:defined`. The dynamic ones
  (`:hover`, `:active`, `:focus`, `:focus-visible`, `:focus-within`,
  `:target`) parse as `State(bits, name)` and match the element's state
  (helder.dom's `Element.state`, below), all off on a printed page.
  `:visited` (every link is unvisited), time's (`:current`, `:playing`...)
  and those not evaluated (`:in-range`, `:modal`...) parse as
  `Never(name)`: they never match. Any other name is invalid.
- `:is()` and `:where()` take forgiving lists (an invalid argument
  dropped); `:not()`, `:has()` and `of S` do not. Pseudo-elements are
  invalid inside them, and `:has()` inside `:has()`.
- Specificity (§17): IDs; classes, attributes and pseudo-classes; types
  and pseudo-elements. `:is()`, `:not()` and `:has()` count their most
  specific argument, `:where()` nothing, `:nth-child(An+B of S)` a
  pseudo-class and S's most specific. One Int, 10 bits a part.
- `toString()` prints a selector so it parses back to the same (a
  namespace's URI as `{uri}|`, which does not).

### Matching

`CssMatcher.matches(selector, element, ?scope)` matches on helder.dom's
elements, right to left; `matchesAny(list, element)`, and `query(list,
root)`: the elements under root any of the list matches, in tree order
(querySelectorAll's). A selector's pseudo-element is the cascade's to
handle: matching is its originating element's.

```haxe
var doc = Dom.parse(html);
var list = CssSelector.parse("article > p:not(.note)");
for (p in CssMatcher.query(list, doc)) ...
CssMatcher.matches(list[0], doc.body.firstElementChild);
```

- **Case**: in an HTML document an HTML element's type selectors and
  attribute names match ASCII case-insensitively, and so do the values of
  HTML's case-insensitive attributes (`type`, `lang`, `dir`, `rel`...:
  the HTML Standard's list) unless the selector says `s`. In quirks mode
  classes and IDs match ASCII case-insensitively too (the document's
  `mode`, from its doctype).
- **Namespaces**: a type selector's against the element's, an attribute
  selector's against the attribute's; `*|` any, `|` none.
- **:has()**: its relative selectors from the element: descendants for
  `>` and a space, later siblings and their descendants for `+` and `~`.
- **The tree's**: `:nth-*()` and `of S` count element siblings,
  `:empty` ignores comments and processing instructions (whitespace is
  text), `:root` is the document element, `:scope` the scope given (else
  `:root`).
- **Links and languages**: `:link` and `:any-link` are HTML's `a` and
  `area` with an href. `:lang()` uses the nearest `xml:lang`, else an
  HTML element's `lang`, by RFC 4647's extended filtering (`*-CH`).
  `:dir()` uses the nearest `dir` of `ltr` or `rtl` (auto reads as ltr).
- **Forms**: HTML's actually disabled (a disabled fieldset's descendants
  but its first legend's, an option in a disabled optgroup). `:checked`
  is a checkbox's or radio's `checked` attribute, an option's
  `selected`. `:default` is a `selected` or
  `checked` attribute (a form's default button is not), `:indeterminate`
  a `progress` without a value (radio groups are not), `:read-write` text
  inputs and textareas neither readonly nor disabled and contenteditable
  elements, `:placeholder-shown` an empty one with a placeholder.
  `:defined` is any element but an HTML one with a hyphen in its name (no
  custom element is ever defined).

### Fast matching

For a sheet's worth of rules, `CssRuleIndex<T>` holds selectors with a
value of the caller's (a rule, a declaration block) and matches an
element against the few that could match it, as browsers do:

```haxe
var index = new CssRuleIndex<Rule>();
for (r in rules) for (s in r.selectors) index.add(s, r);
index.walk(doc, (el, matched) -> cascade(el, matched));   // in tree order, the Bloom filter kept
index.matching(el, out);                                  // one element, no filter
```

- **Buckets**: a selector goes into one bucket, by its rightmost
  compound: its id, else a class, else its type, else an attribute's
  name (without a namespace), else the universal bucket. An element
  visits its id's bucket, each of its classes' (each once), its tag's,
  those of the attributes it has and the universal one. Keys are ASCII
  lowercased, so quirks mode's classes and IDs and SVG's camel-cased tags
  find their rules; CssMatcher decides the case. Matches come out in the
  order added (the cascade's order of appearance).
- **The ancestor Bloom filter** (`CssBloom`, WebKit's SelectorFilter):
  a counting filter of 4,096 one-byte counters, two per hash, of the
  ancestors' tags, ids and classes (`CssHash`: FNV-1a, ASCII lowercased).
  `walk` pushes an element before its children and pops it after;
  `CssBloom.of(el)` builds one for a single element. A selector's
  `hashes` (up to 4: the ids, classes and types of the compounds a child
  or descendant combinator follows, which are its subject's ancestors; in
  `div > p + * > li` the div, not the p, a sibling of the li's parent) must
  all be in it, or the selector cannot match and is skipped. A counter
  that reaches 255 stays there; the filter may say yes wrongly, never no.
- `visited`, `rejected` and `matched` count what matching did (the
  bench's rates).

### Tests

- `CssSelector.test.hx`: the specificity examples of Selectors 4,
  parses valid and invalid, and properties: a selector printed parses to
  the same print, any text parses or is null.
- `CssRuleIndex.test.hx`: the buckets, ASCII-lowercased keys, the
  order across buckets, the filter's hashes and rejections, and a
  property: on random documents and sheets, a walk matches what each
  selector matches, in the same order.
- `CssMatcher.test.hx`: `:has()` with each combinator, `:is()`,
  `:where()`, `:not()` of lists, `:nth-child(of S)`, HTML's case rules
  and quirks mode, SVG's namespace, the form states, `:lang()`
  wildcards.
- `CssRestyle.test.hx`: the marks of a hover, a class in the subject, a
  class before `~`, a class no selector reads, `:has()`, an insertion with
  and without sibling-counting selectors; `:hover`, `:focus-within`,
  dirty `:checked`, `:valid`; and a property over 1,000 cases: on random
  documents, sheets and 2 to 6 changes (classes, ids, attributes, state
  bits, inserts, removals, texts, form attributes), every element whose
  matched selectors changed, by matching everything again, is marked.
  Breaking `~`'s, `:has()`'s or `:is()`'s flags on purpose makes it fail
  within 300 cases; the guards' reading of the old class has a test of
  its own.
- `tests/css/CssSelectorsCheck.hx` (the css lane): WPT's
  dom/nodes/selectors.js. Its 34 invalid selectors don't parse and its
  279 valid and scoped ones do. Its valid ones are matched as
  ParentNode-querySelector-All.html runs them in its four contexts on
  selectors.html parsed by helder.dom: 791 of 793 as expected, the two
  pending being `:target` (never matched: a printed page has no URL
  fragment).

## Dynamic state and invalidation

A live document changes: a class toggled, a row hovered, a child
inserted. Restyling only what may have changed takes two parts, as
Blink's invalidation sets do:

```haxe
var sets = CssInvalidation.of(selectors);          // the sheets' selectors
var restyle = CssRestyle.attach(doc, sets);        // doc.observer: told of each change
row.setState(ElementState.HOVER, true);            // :hover's rules may now match
for (el in restyle.marked()) restyleOf(el);        // at least every element whose matches changed
restyle.clear();
```

- **State**: helder.dom's `Element.state` holds `ElementState` bits.
  `HOVER`, `ACTIVE`, `FOCUS`, `FOCUS_VISIBLE`, `FOCUS_WITHIN` (the engine
  sets it on the focused element and its ancestors) and `TARGET` are
  matched by their pseudo-classes. `CHECKED` with `CHECKED_DIRTY` is a
  checkbox's or radio's checkedness once clicked (HTML's dirty flag: the
  checked attribute counts until then), and `INDETERMINATE` is a
  checkbox's flag. `setState(bits, on)` tells the document's observer. An
  engine's extra, as the source offsets are: a printed page leaves every
  bit off.
- **`CssInvalidation`**: for each class, id, attribute name and state bit
  the selectors depend on, what to restyle when it changes on an element
  E:
  - E itself (`SELF`: the subject compound);
  - E's subtree (`SUBTREE`: a compound a child or descendant combinator
    follows);
  - E's next sibling (`NEXT`) or all its later siblings (`LATER`, each
    with its subtree: a compound a sibling combinator follows);
  - all its siblings (`SIBLINGS`: `:nth-child(of S)`'s counts);
  - the document (`DOCUMENT`).

  A feature of a top-level compound keeps a guard, the compound's other
  ids, classes and tag, as Blink's sets do. A change on an element
  without them invalidates nothing, so `:focus-within` set on `<body>`
  skips `.row:focus-within .actions` (the element's old class and id count
  too). `:is()`, `:where()` and `:not()` pass on where they sit, without a
  guard. Pseudo-classes
  read from attributes (`:checked`, `:disabled`, `:link`, `:lang()`...)
  depend on those, and the ones read from ancestors (`:lang()`, `:dir()`,
  a fieldset's `:disabled`, contenteditable's `:read-write`) restyle the
  subtree.
- **`CssRestyle`**: the tracker, a `DomObserver` on the document.
  helder.dom tells it of each insert, remove, attribute change, text
  change and state change. It marks elements, or a whole subtree as one
  mark, and `marked()`, `isMarked(el)`, `dirty()` and `clear()` read them
  out. An inserted subtree is marked whole, since it has no style yet. A
  class change marks by the classes that came or went, an id change by
  the old and the new id. With no tracker attached, each of the DOM's
  steps pays a null check.
- **Conservative, and what that costs**:
  - anything inside `:has()` restyles the document;
  - a child inserted or removed restyles its parent's subtree when a
    selector counts siblings (`:nth-*`, `:first-child`..., `+` and `~`)
    or reads `:empty`;
  - any attribute change restyles its element (presentational hints, the
    style attribute);
  - `:nth-child(of S)` with combinators in S restyles the document.

  `CssRestyle.test.hx`'s property checks that the marks are a superset of
  what changed.

## Properties

`CssData` (generated: `node src/helder/css/generate.mjs`) is
[@webref/css](https://github.com/w3c/webref/tree/main/packages/css)
8.7.10, the CSS specs' definitions as webref scrapes them, cut to
checkpoint 1's properties:

- `properties`: 222 `CssProperty`s, each with the module it is in scope
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
manifest.json has the package's hash and the counts. Out are 601:

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
| `image-rendering`, `image-resolution` and Images 5, ruby, MathML, line grids, color schemes, palettes, HDR, page floats past CSS 2.1's, zoom, the rest of the next levels | 37 |

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

Tests (`CssGrammars.test.hx`, natively and as wasm32-wasi): every property's,
type's and descriptor's grammar of the data parses and prints back to
itself, every reference it makes is defined (in its context), every
longhand and alias is in the table; the shapes of a few and the errors;
and a property: any tree prints to text that parses back to it. The css
lane checks the same data against the WPT fixtures (tests/css).

## Values

`CssValues` reads a declaration's value against its property's grammar,
writes it as CSSOM serializes it, and computes it as far as needs no
layout:

```haxe
import helder.css.CssValues;

var v = CssValues.parse("margin", "calc(1in + 1px) 1PX");  // null when it doesn't match
CssValues.serialize("margin", v);                         // "calc(97px) 1px"
CssValues.compute("margin", v);                           // "97px 1px"
CssValues.compute("width", CssValues.parse("width", "2em"), {fontSize: 20}); // "40px"
```

- `parse` gives a `CssSpecified`: `Wide(keyword)` (a CSS-wide keyword
  alone), `Unresolved(text)` (a var() or env() anywhere: checked once
  substituted, as Variables 1 says; a custom property's value too), or
  `Terms(terms)`: the grammar's parts typed (`CssTerm`): `Keyword`
  (lowercase), `Ident`, `Number`, `Percentage`, `Dimension` (a unitless 0
  where a length may be: px), `Str`, `Url` (and its modifiers), `Color`,
  `Calc` (a math function, simplified, with the type and range it stands
  for), `Func` and `Brackets` (what the grammar spells out), `Delim`,
  `Raw` (`<declaration-value>`'s tokens).
- `CssMatch` matches by backtracking: each node offers its matches to
  what follows, so a repetition or a `||` gives back values a later term
  needs; `||` and `&&` give their parts in the grammar's order; a comma
  beside an omitted term is left out (Values 4 §2.6). The primitives are
  matched by hand: numbers and dimensions within their ranges, math
  functions wherever a number or dimension may be (a percentage only
  where the type takes one), strings, identifiers (`<custom-ident>` not a
  CSS-wide keyword nor one of the property's own), url(), `<color>`.
  A search over 200,000 steps gives up (no match).
- `CssCalc`: Values 4's math functions (calc(), min(), max(), clamp(),
  round(), mod(), rem(), the trigonometric and exponential ones, abs(),
  sign(), the constants) parsed (whitespace around `+` and `-`), typed
  (§10.8: exponents of the base types, a percentage resolved against
  the context's), simplified (§10.10: units of fixed ratios to px, deg,
  s, hz, dppx; terms of a unit added; a function of values of one unit
  evaluated; Values 5's clamp() with none as min() or max()) and
  serialized (§10.12: a lone value in calc(), a sum's numbers, then
  percentages, then dimensions by unit).
- `CssColors`: Color 4's colours: hex, the 148 names, transparent,
  currentcolor, the system colours, rgb(), rgba(), hsl(), hsla() (legacy
  with commas and modern), hwb(), lab(), lch(), oklab(), oklch(), color()
  in its spaces; `none`; math functions in components. Serialized as
  Color 4 §15 and the browsers do: keywords as written (lowercase), the
  legacy forms as rgb() or rgba() rounded to integers (none kept in their
  own function; rgb()'s as color(srgb)), the others in their own function
  with lab()'s L clamped to its range, lch()'s C to at least 0 and a hue
  in [0, 360); a math function as calc() of its value there, and one to
  resolve when computed (sign(1em - 10px)) kept, the colour then in the
  modern syntax. color-mix(), relative colours, light-dark() and the rest
  of Color 5 match their grammar only.
- `CssCanonical`: the shortest of equivalent forms where the property's
  spec says: sides as few as say the same (`{1,4}`, `a b?`), Display 3's
  short displays, `first baseline` as `baseline`, a counter's default
  number, background-size's second `auto`, background-repeat's
  `repeat-x`, a one-value position as two, opacity's percentages as
  numbers, a feature's default 1 (`off` as 0), counter()'s default style,
  gradients' defaults (ellipse, farthest-corner, a centre, `from 0deg`),
  image-set()'s strings as url() and its default 1x, rotate(0) as 0deg,
  quoted family names of identifiers unquoted, grid areas' cells one
  space apart. And what a property's prose adds to its grammar (`valid`):
  feature tags of four ASCII letters, a language of one to four, rows of
  grid areas of one width, one auto repetition of tracks, a text shadow's
  three lengths, symbols()' two symbols, a circle's one length.
- `CssComputed`: lengths in px (the context's font size, root font size
  and viewport for em, rem and vw; 16px and 800x600 by default), math
  functions simplified, clamped to their range and rounded when integers
  (a NaN as 0), positions as percentages (`right 10px` as `calc(100% -
  10px)`, in gradients too), font-width's and font-size's keywords as
  theirs, line widths snapped to whole pixels, colours resolved
  (currentcolor to the context's), shadows' colour and blur filled in,
  feature settings deduplicated and sorted, `flex-start` as `flow-start`
  outside flex. What needs the cascade (inherit, bolder) or layout (grid
  tracks, url() against the document) gives null or stays as specified.
- `CssNumber.format`: numbers as browsers write them, six significant
  digits (`0.333333`, `1e+06`), an integer's every digit.

Shorthands match their grammar as a whole and serialize as written in
the grammar's order; their expansion to longhands (and serialization back
from them) is the cascade's, still to come.

Tests (`CssValues.test.hx`, natively and as wasm32-wasi):
examples of matching, rejecting, computing and numbers; and a property:
a value drawn from any property's grammar tree (each alternative, count
and primitive within its range) parses, and its serialization parses back
to a value that serializes the same. The css lane's CssValuesCheck runs
WPT's 19,000 value cases and css-parsing-tests' colours (tests/css).

## Cascade

`CssCascade.styles(doc, options)` cascades a helder.dom document (Cascade
5): its computed style per element, asked when needed, and shared by the
elements whose styles come out the same (Style storage, below).

```haxe
import helder.css.CssCascade;

var styles = CssCascade.styles(doc, {
	load: url -> files.get(url),       // <link rel=stylesheet>'s and @import's text, by absolute URL
	url: "https://example.com/report.html",
	media: {type: "print", width: 793.7, height: 1122.5, resolution: 1},  // CssMedia.PRINT: A4
	hints: true                        // HTML's presentational hints, as WeasyPrint's -p
});
var h1 = doc.getElementsByTagName("h1").item(0);
var s = styles.computed(h1);
s.spacing.marginTop.value;                 // 21.44 (px)
s.box.display.outer == Block;
s.length(Width).resolve(600);              // a percentage of 600, auto's NaN
s.text("font-size");                       // "32px", as getComputedStyle writes it
styles.computed(h1, "before").generated(); // null: content none
styles.pages;                              // @page rules: selectors, declarations, margin boxes
```

- **Sheets** (`CssSheet.parse(text, origin, {url, load})`), in cascade
  order: the user agent's (`CssUserAgent`: the HTML Standard's Rendering
  section's CSS, made by `ua.mjs` from whatwg/html at a pinned revision,
  `:heading` as h1 to h6; quirks mode's rules on top in quirks mode;
  print.css: an A4 page with 75px margins and headings as bookmarks, as
  WeasyPrint has them; `ua/*.css`, parsed when first asked;
  `CssUserAgentTheme` has them compiled at build time, for a program
  styled by compiled sheets alone with `CssCascade.themed`, which then
  links no parser; `ua/app.css` is helder.ui's defaults for app trees, a
  draft for the port: `ua/README.md`), the user's, then the document's `<style>` and
  `<link rel=stylesheet>` elements (their `media`, a `<base href>`), then
  `author`'s. A sheet's declarations are compiled once: validated against
  their grammars (invalid ones dropped), shorthands expanded to their
  longhands (`all` too), legacy names to their properties,
  `page-break-*` to `break-*`, each longhand its `CssProperty` id. @import
  is loaded through the caller's function (no I/O here), with its media,
  `supports()` and `layer`; @media is kept and evaluated against the
  media (`CssMedia`: Media Queries 4, types, `not`, `only`, `and`, `or`,
  ranges, a printed page's features: no hover, no pointer, no update);
  @supports is evaluated at once (`CssSupports`); @namespace for
  selectors; @layer blocks, statements and anonymous layers; @page
  (selectors, the page's properties, its descriptors as written, its
  margin boxes), @font-face and @counter-style kept as data for the later
  stages. Nested style rules (CSS Nesting) are past checkpoint 1: a
  rule's own declarations apply, its nested rules not.
- **Matching** (`CssStyles`): each element's rules found through an index
  of their rightmost compound (id, class, type, an `:is()` of types,
  links, the root, an attribute: `CssRuleIndex`, with the ancestors' Bloom
  filter, `CssBloom`, moved to each element; rules that can never match,
  `:visited`'s, left out), then matched by helder.css's selectors.
- **The style-sharing cache** (Stylo's and WebKit's), before matching.
  An element takes the style of one of the 32 elements styled last when
  all of these hold:
  - its parent is that element's parent, or that parent's twin (an
    element that took its own style from the cache the same way, so their
    ancestors match every selector alike);
  - its tag, namespace, classes, style attribute, hints and state are the
    same;
  - the attributes the sheets' local selectors read are the same: their
    values where a selector reads one, their presence where only
    `[attr]` or `:link` reads them;
  - it has no id a selector names (one no selector names can't tell it
    apart);
  - the selectors that are not local (`CssSelector.local`: sibling
    combinators, `:nth-*` and the like, `:has()`, `:empty`, other
    elements' form state) that the earlier element tried, past the Bloom
    filter, match it as they matched that one. This is Stylo's
    revalidation: only those few are matched again, and an element that
    tried more than 16 is not kept.

  `share: false` turns it off; `shares` counts it. `:has()`'s results are
  kept per element during the styles' pass (`CssHasCache`, which
  `CssMatcher.matches` takes; cleared by `forget`), so `.list:has(.x) .row`
  asks the list once, not once per row. On the HTML Standard
  (341,289 elements) it styles 235,786 elements without matching them.
  `forget(elements)` lets the styles of elements a change marked go
  (CssRestyle's), with the cache's candidates and twins. The Bloom filter
  follows the elements in tree order: a sibling changes nothing, a child
  pushes one, going back up pops (`CssBloom.moveTo`).
- **Sharing after matching**: an element whose parent's style, matched
  rules, style attribute, hints and place (the root, a flex or grid item)
  are an earlier element's gets that element's style. Otherwise its cascade is
  worked out (`CssResolver`): declarations sorted by origin and
  importance (user agent, user, author; then author, user, user agent
  `!important`), a style attribute's above every rule's, layer (later
  layers win for normal declarations, unlayered last; reversed for
  `!important`), specificity, order of appearance; presentational hints
  (opt-in): HTML's attributes mapped to properties (`CssHints`: bgcolor,
  width and height, cellspacing and cellpadding, border, font's color,
  face and size, hspace and vspace) and the ones HTML writes as CSS, as
  author rules of specificity zero before the author's own. `::before`,
  `::after`, `::marker` (and `::first-line`, `::first-letter`, GCPM's
  footnote ones) have their own rules, their style inheriting from their
  element's.
- **Logical properties** (Logical 1, horizontal-tb): the element's
  `direction` is worked out first, then each logical declaration takes
  its physical property's place in the cascade (inline-start is left in
  ltr, right in rtl; block-start top), so the later or more specific of a
  logical and a physical declaration wins. The user agent's sheet keeps
  HTML's logical properties, so an rtl list is indented on the right.
- **Computed values**: `initial`, `inherit`, `unset`, `revert` (the
  origin below), `revert-layer` (the layer below); inheritance (a group
  of inherited properties none of which is set is the parent's); var()
  and env() substituted (Variables 1: a missing name without a fallback,
  or a cycle, makes the value invalid at computed-value time, as `unset`;
  a fallback's `{}` block is its contents; a CSS-wide keyword substituted
  is that keyword where the declaration stands; a shorthand's longhands
  take their part once it is substituted), then the value computed as
  CssComputed does with the element's font size (font properties' em
  their parent's), the root's, the media's size and the colour
  (currentcolor in color itself the inherited colour); and what needs the
  tree: `justify-items: legacy`, `text-align: match-parent`, overflow's
  visible beside a scrolling axis; and what reads another property:
  `float: none` when absolutely positioned, and blockification (CSS 2.1
  §9.7, Display 3 §2.7: the root, floats, absolutely positioned boxes,
  flex and grid items, past `display: contents`; the display before it
  kept as `style.originalDisplay`, its own interned value), `font-weight: bolder`
  and `lighter` from the parent's weight (Fonts 4's table), and
  `content: normal` as `none` on ::before and ::after. `font-size:
  larger` and `smaller` step along the absolute-size table from the
  parent's size when it is one of the table's (Fonts 4 §2.5), else by
  1.2. lh and rlh are the element's and the root's line height when it
  is a length or a number (the parent's and the initial value's in
  font-size and line-height); `normal`'s is the first available font's.
  ex, ch, cap and ic (and rex, rch, rcap, ric: the root's) are that font's
  metrics too: `CssStyles.metrics`, a hook an engine with fonts installs
  (helder.ui's FontMatch.metrics), is asked once per element with its font
  properties' computed values (`CssFontQuery`: family, size, weight,
  style, stretch, variation settings, optical sizing) and gives
  `CssFontMetrics` (x-height, the advance of 0, the cap height, the advance
  of 水, line-height: normal); the font properties' own units take the
  parent's, as their em does. Without the hook they stay as written. rem
  and rlh on the root are its own.

### Themes compiled at build time

`CssTheme.sheet(text)` and `CssTheme.file(path)` are macros: the CSS (a
string constant, or a file beside the calling module or under a class
path, its `@import`s read beside it) is parsed when the program is
compiled, and the sheet becomes the expressions that make it again, one
static per sheet: selectors with their specificity, Bloom hashes and
bucket (`CssSelector.bucket`, `CssBucket`: where `CssRuleIndex` files
it), declarations as `CssProperty` ids with typed values, @media's
parsed queries, the at-rules' data. `CssCascade.themed(doc, sheets)`
cascades with those sheets alone: no user agent's sheet but one passed,
no `<style>` or `<link>`, no style attribute. A program styled so links
no CSS tokenizer or parser: the initial values are compiled too
(`CssInitial`), the shorthands' serialization reads longhands' texts
without one, and the serializer's code point classes are `CssChars`.
`var()` stays dynamic: custom properties are substituted when styles
are computed, on the component values the sheet kept. The sheets have
no URL (url()s stay as written); a string not constant is an error (use
`CssSheet.parse` for CSS known only when the program runs). The macro
parses on Eval, the compiler's interpreter, so the parsing half of
helder.css stays runnable there.

```haxe
var styles = CssCascade.themed(doc, [
	CssTheme.sheet("button { padding: 4px 8px; color: var(--accent) }"),
	CssTheme.file("theme.css")               // UserAgent, User or Author (the default) as a second argument
], {media: {type: "screen", width: 800, height: 600}});
```

`CssTheme.test.hx` compares a compiled sheet with the same text parsed
(every rule, selector with its specificity, hashes, locality and
bucket, declaration) and their styles, every longhand of every element
and its ::before; the css lane builds a probe styled by compiled sheets
alone (tests/css/ThemeProbe.hx, `-dce full` with symbols) and checks its
values and that its symbols hold no Tokenizer, Parser, SelectorParser or
sheet builder, and the same probe parsing one sheet when it runs, which
holds them all (2505 and 2695 KB with symbols, on macOS).

### CSS modules

A `*.module.css` file is a CSS module, as in css-loader and Vite. Its
class names and ids are scoped to the file as `<file>_<name>_<hash>`; the
hash is of its path from the project (`-D helder.root`, else the working
directory), so every build scopes alike.

- **`:global(...)`** leaves a selector's names as written, and
  **`:local(...)`** scopes them again. A bare `:global` is an error.
- **`composes`** adds classes to a class's name, in a rule of one class:
  `composes: a b` from the same file, `composes: a from
  "./other.module.css"`, or `composes: a from global` (as written).
  Composes declarations are taken out of the sheet.
- **Errors**, at their file, line and column: a missing name, a missing
  file, a cycle (across files too), composes outside a rule of one class.
- **`CssScope.compile(file)`** does the scoping. It is plain Haxe, run by
  the compiler and by dev builds; `CssScope.sheet(m)` compiles the result
  through the same path as `CssTheme`.
- **`CssModule.load("card.module.css")`** is a macro that returns the
  module's names, typed from the file: `{final card:String, final
  cardTitle:String}`, so a misspelt name is a type error. Dashed names are
  camelCased; collisions and names Haxe can't spell are errors. The file
  is found beside the calling module, else under a class path.
  - The sheet is compiled when the program is, so a program that only uses
    modules links no CSS parser.
  - The module's errors are the build's errors.
  - Its sheet is registered once, the first time it is loaded, after the
    sheets it composes from. `CssCascade.styles` takes the registered
    sheets after a document's own; `CssCascade.themed` takes them after the
    sheets passed. `CssModule.sheets()` lists them, `version` counts their
    changes and `watch(f)` hears of them.
- **Under `helder dev`**, an edited module file is sent to the running
  program as an asset (helder.asset's `Assets.changed`). The program scopes
  it again with the build's hash and swaps its sheet, nothing built; only
  dev builds link the parser for that. The log says what happened: `card.module.css swapped,
  nothing built`; or, when the names it exports changed, `swapped, but its
  names changed (+extra): rebuild to use them`; or, on an error, the error
  at its line and `not swapped: the last sheet stays`.

```haxe
final card = CssModule.load("card.module.css");
el.className = card.title;                     // "card_title_1a2b3c"
var styles = CssCascade.themed(doc, []);       // the modules' sheets alone
```

TypeScript imports a module (`import card from "./card.module.css"`)
through `CssScope.typescript(file)`, which helder.typescript's frontend
calls per imported file. It returns:

- `source`: the module's TypeScript, its names frozen;
- `declaration`: the same type as a `.d.ts`, `{readonly card: string;
  readonly "card-title": string}`, with names as written;
- `haxeType`: the Haxe class `CssModule.define(file)` makes, whose
  `install()` registers the sheets;
- `diagnostics`, with file, line, column, offsets and severity;
- `files`: every CSS file read, for the watcher.

`CssScope.test.hx` covers scoping, `:global` and `:local`, composes from
the same file, another and global, a cycle across files, each error at
its line and column, and TypeScript's module and declaration.
`CssModule.test.hx` covers the typed names, a sheet registered once and
after the one it composes from, the cascade, and dev's swap: the same
names, changed names, an error. The css lane checks the following:

- a probe styled through a module alone: its values, and no parser in its
  symbols (tests/css/ModuleProbe.hx);
- a misspelt name fails the build (tests/css/modules/Misspelt.hx), and a
  module's error fails it at `broken.module.css:2: characters 20-27`
  (Broken.hx);
- `tsc --strict` accepts a program against the declarations and rejects
  a misspelt name and a write (tests/css/modules/ts).

The cli lane's `css-module` mode edits a module under a running `helder
dev` (tests/cli/dev.mjs, tests/cli/cards). helder.ui.box's
DocumentView.test.hx draws a document styled through a module.

## Style storage

A computed style (`CssStyle`) is a pointer per group of properties,
immutable, shared: `styles.json` says the groups, and `generate.mjs`
writes from it and the property table:

- **`CssProperty`**: an id per in-scope longhand (an `enum abstract` of
  Int: `MarginTop`, `Display`...), the logical ones' too. No property
  names past the parser: declarations, the cascade and the groups go by
  id. `CssProperties`: each id's name, group, kind, keywords, impact, a
  logical one's physical ones, each group's members.
- **Groups** (`CssGroups`): font, inheritedText, list, table, ui (the
  inherited ones), and box, position, spacing, border, background,
  outline, decoration, container (flex and grid containers), item (flex
  and grid items), content (and counters), paged, effects (opacity,
  transforms, filters, blending, shadows), control (appearance,
  user-select, scrollbars, transitions). A group is inherited or not as
  all its properties are, so an element's inherited group is its
  parent's pointer unless something in it is set, and a reset group the
  document's initial one unless something in it is set (or its values
  depend on more: display at the root or in a flex container, ::before's
  content, justify-items' legacy).
- **Typed values**: a field per property, typed by its kind as its
  grammar says (`styles.json` corrects a few): a keyword as an
  `enum abstract` (`CssKeywords`: `CssPosition.Absolute`, `CssLineStyle`
  for the four border styles...), a number unboxed (`Float`, a keyword
  beside it where it has one: z-index's auto), a length, percentage,
  number or keyword as `CssLength` (kind, value in px or %, the unit of
  one not resolved here, a math function kept only where it can't be
  resolved: a percentage mixed with lengths), a colour as `CssRgba`
  (sRGB floats from any of Color 4's spaces, currentcolor kept as such),
  display as `CssDisplay` (outer, inner, list item), anything else
  (lists, shadows, transforms, grid templates, content) as its terms.
  What a field's type can't hold (a function where keywords go) is kept
  in the group's others, as terms.
- **Interning** (`CssIntern`, per document): equal lengths, colours,
  displays and term lists are one object, so a group compares its fields
  by identity, and equal groups are one object, and equal styles.
- **Impact** (`CssProperties.impact`): what a change to a property
  redoes, for restyling later: `Layout`, `Text` (inherited text that
  lays text out again: the fonts, spacing, white space), `Paint`,
  `Composite` (opacity and transforms), `None` (cursor, transitions...).

The typed reads layout will use (by id they return what the group holds,
allocating nothing; a keyword's terms are one shared array a keyword):

```haxe
var s = styles.computed(el);
s.box.position == Absolute;                  // CssKeywords
s.spacing.marginLeft.kind == Px;             // CssLength
s.resolve(PaddingTop, containingWidth);      // px, a percentage resolved
s.px(BorderTopWidth);                        // px (NaN when not a length)
s.color(BorderTopColor).r;                   // sRGB, currentcolor resolved
s.number(Opacity); s.position.zIndex;        // numbers
s.display.inner == Flex;                     // CssDisplay
s.originalDisplay.outer == Inline;           // before blockification
styles.hasPseudo(el, "first-letter");      // a ::first-letter rule matches el
s.fontSize(); s.lineHeight(); s.families();  // the font
s.backgrounds();                             // layers, lists repeated to the images'
s.generated();                               // content as items (Text, Counter, Quote...)
s.counters(CounterReset);                    // {name, value, reversed}
s.terms(GridTemplateColumns);                // anything, as terms
```

The run time's property data is `CssTable` (generated): the grammars,
initial values, inheritance, longhands, legacy names; `CssData` (the
specs' prose and links, for tests and tools) stays out of programs that
only cascade.

Checkpoint 1b's properties, in scope for helder.ui's port: aspect-ratio,
field-sizing, transition-* (computed values only), cursor, pointer-events,
user-select, accent-color, appearance, scrollbar-width, scrollbar-color,
line-clamp (and max-lines, block-ellipsis, continue), text-overflow,
text-wrap and text-wrap-style, text-underline-offset, filter,
backdrop-filter, mix-blend-mode, isolation, translate, rotate, scale, and
the logical properties (margin-, padding-, inset- and border-block and
-inline, their starts and ends, the sizes, the corner radii).

Tests (`CssCascade.test.hx`, natively and as wasm32-wasi):
origins and importance, specificity, order and the style attribute,
layers, the CSS-wide keywords, inheritance and em, widths without a
style, blockification, the relative font sizes and weights, lh, rlh and
rem, logical properties (ltr, rtl, inherited, against physical ones),
the typed values and bundles, styles and groups shared, var()
(fallbacks, cycles, shorthands), @media, @supports and @import,
pseudo-elements, the user agent's sheet and hints, the at-rules' data;
and properties: the result doesn't depend on the order of the sheets
when their declarations' cascade order is the same, an unset inherited
property is its parent's computed value, and equal groups of values are
one object (and one object one set of values). The css lane's
CssCascadeCheck runs WPT's css-cascade and css-variables tests that read
statically, CssValuesCheck the computed rows of WPT's value tests in
their own pages (tests/css); both check every value against #321's
cascade as it was merged, frozen in tests/css/reference.
`CssSharing.test.hx`: what the cache shares (siblings, cousins, an id
no selector names, links by their href's presence) and what it must not
(a named id, a positional rule, another state or class, cousins whose
parents a rule tells apart), and a property over 300 random documents
and sheets: every element's every longhand the same with the cache and
without it. `bun run test bench cascade` styles the HTML Standard's
page and checks it against #321's cascade and against no sharing cache:
0 values differ of 3,191,706 each.

## Counters and generated content

`CssCounters` keeps counters and quotes as the box tree walks a document
in tree order (Lists 3 §4, Content 3 §3): it enters each element, then
its ::marker, ::before, children and ::after, and exits them.

```haxe
var counters = new CssCounters(styles);
counters.enter(li);
counters.enter(li, "marker");
counters.marker(li);              // [Text("3. ")]: ::marker's content, list-style-image or list-style-type
counters.exit(li, "marker");
counters.enter(li, "before");
counters.content(li, "before");   // [Text("§2.1 "), Image(...)]: strings, counters, attr(), quotes, images
counters.exit(li, "before");
// ...the children...
counters.exit(li);
counters.value("list-item"); counters.values("section");  // counter() and counters()
```

- **Scopes**: a counter an element makes (by `counter-reset`, or by a
  `counter-increment`, `counter-set` or `counter()` of a name not in
  scope) is in scope for its descendants and its following siblings; a
  later sibling's counter of the name replaces it, a descendant's nests
  in it. On an element, resets apply first (only a name's last), then
  increments (a list item's implicit `list-item 1`, or -1 inside a
  reversed counter, unless it names list-item itself), then sets. An
  increment that would overflow 32 bits is left out, as browsers do. An
  element without a box of its own (`display: none` or `contents`) sets
  no counters, and its children count as its parent's.
- **Reversed counters**: `reversed(name)` without a value starts at the
  sum of its scope's increments negated plus its last non-zero one, a
  `counter-set` ending the sum (Lists 3 §4.4.2).
- **HTML**: `ol`'s `start` and `reversed` and `li`'s `value` apply as
  `counter-reset` and `counter-set` whether or not the cascade's `hints`
  are on, and so do the lists' `type` attributes: a list numbers wrongly
  without them.
- **Quotes**: `open-quote` and `close-quote` (and the no- ones) keep a
  depth through the document; `quotes: auto` gives English's pairs.
- **Typed counter properties**: `style.counters(CounterReset)` and the
  like give `{name, value, reversed}`, value null for `reversed()`
  without one.

## Counter styles

`CssCounterStyles` formats a number in a counter style (Counter Styles 3):
the predefined ones (`CssCounterStylesData`: §6's rules, from decimal to
the Armenian, Georgian, Hebrew, roman, Greek, kana and Indic ones, disc,
circle, square, the disclosure triangles, cjk-earthly-branch and
cjk-heavenly-stem; `CssCounterAlgorithms`: §7's Chinese, Japanese and
Korean longhands from -9999 to 9999, and ethiopic-numeric) and the
document's `@counter-style` rules, a later rule over an earlier one and
over a predefined style but decimal, disc, square, circle and the
disclosure ones (which can't be redefined). Each system (cyclic, fixed,
symbolic, alphabetic, numeric, additive, extends) as §3.1 says; a value
out of the range, or with no representation, takes the fallback's (an
extends loop extends decimal); then the pad, counted with the negative
sign, then the negative sign; a marker adds the prefix and suffix.
`symbols()` makes an anonymous style. `CssCounterDescriptors` reads and
writes the descriptors. Left out: §7.1.2's optional extended CJK forms
past 9999, and images as symbols (a marker's text can't be one).

```haxe
var formats = new CssCounterStyles(styles.counterStyles);
formats.format(14, "lower-roman");  // "xiv"
formats.marker(3, "cjk-decimal");   // "三、"
```

## Pages

`styles.pageStyle(index, name, left, blank)` cascades the `@page` rules
for a page (Paged Media 3 §4, §5): those whose selectors match its
context (`:first` the first page, a page type's name, `:left` or
`:right`, `:blank`), by origin and importance, then specificity (a page
type's name, then `:first` and `:blank`, then `:left` and `:right`),
then order. The page context's style inherits from the root element's;
`CssPage` has it and the page's size in px (`size`'s lengths, a page
size keyword and an orientation; auto: A4), `bleed` (auto: 6pt with crop
marks, else 0), `marks` and `page-orientation`.
`styles.marginBoxStyle(index, name, left, blank, box)` gives one of the
16 margin boxes' style, inheriting from its page's, Paged Media 3
§6.2's `text-align` and `vertical-align` beneath its rules, `content:
normal` as none. Data only: the paged host lays out.

On print, `@media` and viewport units see different sizes, as Chromium
and Paged Media 3 have them: a media query the medium's (the printer's
default page, `media`: unaffected by @page), vw, vh, vmin and vmax the
first page's area (`page.area()`: its size less its margins), unless
the cascade's `viewport` option gives one; `size: auto` is the medium's
page.

Tests (`CssCounters.test.hx`, natively and as wasm32-wasi): the
predefined styles, `@counter-style`'s systems and descriptors, their
syntax, lists (`start`, `reversed`, `value`, `type`), counters, scopes and
quotes, the @page cascade; and properties: decimal and lower-alpha are
the numbers they write, upper-roman's symbols sum back, and a list's
markers count its items as HTML's ordinal values say. The css lane's
CssCountersCheck renders WPT's css-counter-styles and css-lists reftests
and their references to text through CssCounters, and reads
`@counter-style`'s syntax tests.

## Generated content for paged media

GCPM 3's side in CSS, for the paged host (helder.css computes and resolves
what it can; the host, which knows the pages, fills the rest):

- **Content parts:** `CssItems.content` reads `string(name, which)`,
  `element(name, which)`, `leader()` (dotted `". "`, solid `"_"`, space
  `" "`, a string), `content(text | before | after | first-letter |
  marker)`, `target-counter()`, `target-counters()` and `target-text()`
  (a fragment as a string, `url()`, `attr(href)` or `attr(href url)`).
  `CssCounters.content` resolves them to `CssGeneratedPart`s:
  `StringValue`, `RunningElement` and `Leader` for the host to fill, and
  `Target(CssTarget)`.
- **Named strings:** `counters.strings(el, page, pages)` evaluates the
  element's `string-set` where it is: strings, counters, attributes,
  `content()` of the element (its text, white space collapsed; its
  ::before, ::after, marker; its first letter), quotes at their depth;
  `counter(page)` and `counter(pages)` as the host gives them.
  `CssRunning<T>` keeps the assignments page by page and answers
  `string()`'s and `element()`'s `first`, `start`, `last` and
  `first-except` (GCPM 3 §1.2).
- **Running elements:** `style.running()` is `position: running(name)`'s
  name; such an element leaves the flow for the margin boxes that name it.
- **Cross-references:** a `CssTarget` names its element (`#id` in the
  document), what it wants, and has no text until
  `counters.resolveTargets(pageOf)` runs once the pages are known: a
  page counter from `pageOf`, other counters as they were at the target
  (the walk keeps each element with an id's counters), its text, its
  ::before's or ::after's text, its first letter.
- **Bookmarks:** `counters.bookmark(el)` gives `bookmark-level` (h1 to h6
  1 to 6, WeasyPrint's UA rules in print.css), `bookmark-label` evaluated
  as a string's value (initial: the element's text) and `bookmark-state`.

```haxe
counters.enter(h1);
for (s in counters.strings(h1, page)) running.assign(s.name, s.value, atPageStart);
running.value("title", "first");               // a margin box's string(title)
counters.resolveTargets(el -> pageOf.get(el)); // then each Target(t): t.text
```

Tests (`CssCounters.test.hx`, `CssRunning.test.hx`): the parts, string-set
where its element is, running elements, bookmarks, cross-references
before and after resolveTargets, CssRunning's four values. The css lane's
CssGcpmCheck reads WPT's css-gcpm tests through this API.

## Interpolation and transitions

`CssInterpolate.values(property, a, b, p)` interpolates two computed
values p of the way (Web Animations 1, Values 4 §3), p below 0 or above
1 extrapolating, by the property's animation type (`CssProperties.
animation`: by computed value, discrete, repeatable list or not
animatable, from webref's tables, `styles.json`'s `animations` over
them). Null when the values don't interpolate.

- Lengths, percentages and their mix (a `calc()` of both), numbers,
  angles and the like; the same keywords and functions, argument by
  argument. The result is read back through the property's grammar, so
  it is clamped to the property's range and an integer's rounded.
- Colours: two legacy ones (`rgb()`, `hsl()`, `hwb()`, named) in sRGB,
  others in Oklab, premultiplied, a missing component the other's;
  system colours as a light page's.
- Lists by layer; a repeatable one (background-position, background-size,
  object-position, transform-origin) repeated to a common length.
- 2D transforms (Transforms 2 §10): none as the other list's identity
  functions, the shorter list padded with the longer's; the functions of
  the same primitive (translate, scale, rotate, skew) argument by
  argument; two matrices, and the rest of the lists from where they
  differ, as matrices decomposed (§12.2: translation, scale, skew, a
  quaternion), interpolated and composed again. `translate`, `scale` and
  `rotate` with none as their identities.
- Shadows, the shorter list padded with transparent ones; filters, none
  as each function's identity; `aspect-ratio` by its log; `visibility`
  visible between visible and hidden; `font-style` normal as `oblique
  0deg`; `letter-spacing` and `word-spacing` normal as 0.
- `CssInterpolate.discrete` flips a discrete value halfway (`display`
  keeps what isn't none until the end, Transitions 2 §3.3).

Not yet: 3D transforms, grid track lists, `calc-size()`, and the counter
properties, which are discrete as browsers have them.

`CssTransition.starts(before, after)` gives the transitions an element's
style change starts (Transitions 1 §3, 2 §3): the new style's
`transition-property` list (`all`: every animatable longhand; a shorthand:
its longhands; a later name over an earlier one), each with the
duration, delay, `transition-timing-function` (`CssEasing`: the keywords,
`cubic-bezier()`, `steps()`, `linear()`) and `transition-behavior` at its
index, the lists repeated. A property starts when its combined duration
is above 0, its value changed (currentcolor resolved), and it interpolates,
or it is discrete and allow-discrete. There is no clock: helder.ui's
motion asks for the value at a time.

```haxe
for (t in CssTransition.starts(before, after)) motion.start(t);
CssTransition.value(t, 0.25);  // the terms a quarter second in, eased
```

Tests (`CssInterpolate.test.hx`, `CssEasing.test.hx`,
`CssTransition.test.hx`): each kind of value, the easing functions, what
starts and its values over time. The css lane's CssInterpolationCheck
runs WPT's `test_interpolation`, `test_no_interpolation` and
`test_not_animatable` cases as CSS Transitions does.
