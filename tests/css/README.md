# CSS tests

helder.css's checks, natively: its tables and grammars against cases of
[web-platform-tests](https://github.com/web-platform-tests/wpt) read
statically, its syntax against css-parsing-tests (below):

```sh
bun run test css
```

- `fixtures/values.json`: WPT's calls of its parsing, computed and
  inheritance helpers (`test_valid_value`, `test_invalid_value`,
  `test_computed_value`, `test_shorthand_value`, the fuzzy color ones,
  `assert_inherited` and `assert_not_inherited`), for checkpoint 1's
  properties (src/helder/css/scope.json; `--*` for custom properties),
  grouped by property and kind, each row with its file (`files`); the
  header names each kind's row.
- `fixtures/selectors.json`: dom/nodes/selectors.js's invalid, valid and
  scoped selectors, each with the ids it matches, its level and its test
  types; the document they run on is `fixtures/selectors.html`
  (`selectors.xht` its XHTML twin), with the elements `setup` says
  ParentNode-querySelector-All.js adds.
- `fixtures/reftests.json`: the tests of css/CSS2, css/css-page,
  css/css-break and css/css-gcpm, by directory: in scope, each with its
  references (match or mismatch, and theirs), help links (the spec's
  section), flags, fuzzy annotations and needs (Ahem, script, print,
  reftest-wait, images, SVG, XML); out, each with why. A test without a
  reference (WPT's visual tests) is in scope as `noref`: it is to be
  checked against a golden Chromium draws, a tier the reftest runner adds.
  Out: testharness.js tests and those with a script (no JavaScript),
  manual and `interact` ones, flags past a page (`animated`,
  `history`, `userstyle`, `http`, `scroll`), and those of deferred features
  (multicol, writing modes, footnotes, `@layer`, `@container`, shapes,
  regions, forms, 3D transforms), by their help links or their CSS.
- `CssCheck.hx`: the lane's first check. values.json's properties are the table's, every
  row has its shape and file, the other fixtures their fields, and every
  grammar of the table parses.

`import-wpt.mjs` makes the fixtures from a WPT checkout at its pinned
REVISION (bin/wpt, a sparse clone of css/ and dom/nodes/, made when
missing), and writes the report below; WPT itself is not vendored. It runs
nothing of WPT's: wpt-js.mjs reads each script's calls statically, their
arguments as literals and expressions of them, names bound once to one,
`for (... of list)` and `list.forEach` loops over a list it can read (a
call taken once per item), and the file's own helpers inlined at their
calls. What it can't read so is counted with why:

```sh
node tests/css/import-wpt.mjs [wpt checkout]
```

The fixtures are WPT's, BSD-3-Clause licensed (`WPT-LICENSE.md`).

## css-parsing-tests

helder.css's syntax against
[css-parsing-tests](https://github.com/SimonSapin/css-parsing-tests), the
css lane's second check (BLESS=1: manifest.json's pending cases from the
results):

- `fixtures/css-parsing-tests/*.json`: its files as they are, a JSON
  array of input and expected result pairs for each of the spec's entry
  points (`component_value_list`, `one_component_value`,
  `declaration_list`, `one_declaration`, `blocks_contents`, `one_rule`,
  `rule_list`, `stylesheet`, `stylesheet_bytes`, `An+B`), CC0 (`LICENSE`).
- `manifest.json`: the coverage gate, a case a line (file, index, its
  input). Every case is run and required to pass unless `pending` gives
  its reason; a pending case that passes fails the run too, until BLESS=1
  requires it. A file in `files` with a `skip` (and why) is neither
  copied nor run: the colour files, CSS Color's `<color>`.
- `CssConformanceCheck.hx`: the runner. Each input goes through its
  file's entry point, the result in the fixtures' JSON form against the
  expected one: upstream's, less the parse errors it lists in lists (this
  parser reports none and returns nothing for an invalid construct), or
  the case's own `expected` where the current Editor's Draft reads it
  otherwise than the 2021 draft the fixtures follow, with `why`;
  `ranges`: the case tokenized with unicode ranges allowed. A rule's
  block is its parsed contents in order, runs of declarations among the
  rules. SHOW=1 prints each result that differs, DUMP=1 every result.

`import-css-parsing-tests.mjs` copies the fixtures again from a checkout
at its pinned revision (none given: cloned into bin/css), keeping the
manifest's cases; new ones come in pending:

```sh
node tests/css/import-css-parsing-tests.mjs [checkout]
BLESS=1 bun run test css
```

`make-encodings.mjs` makes src/helder/css/EncodingData.hx from WHATWG
Encoding's encodings.json and indexes.json.

## Values

helder.css's values against WPT's value cases (fixtures/values.json) and
css-parsing-tests' colours, natively (`bun run test css`; BLESS=1:
values-manifest.json and the counts below; SHOW=1: each case that doesn't
pass):

- `fixtures/colors`: css-parsing-tests' 13 colour files (CC0, `LICENSE`),
  each a list of inputs and their computed colours (null: invalid), copied
  by `import-colors.mjs` at the revision manifest.json pins: `<color>` is
  this lane's, CSS Color 4, not the syntax lane's.
- `CssValuesCheck.hx`: the values' coverage gate, as the layout
  conformance's. Every case of values.json and the colour files is run.
  valid: the value parses and serializes to the expected text (any of a
  list; numbers within the row's epsilon); invalid: it doesn't parse;
  computed: it computes to the expected text in the default context
  (16px fonts, an 800x600 viewport, black text); inherits: the table's
  flag, the initial value computed; shorthand: each longhand's value.
  `values-manifest.json` sorts those that don't pass, each group with why:
  - `skip`: not checkpoint 1's: out of scope (Color 5 and 6, Values 5's
    functions, url()'s request modifiers, Transforms 2, Grid 3, Flexbox 2,
    drafts' values), whether they pass or not; and an outdated fixture,
    css-parsing-tests where it and WPT (and the current Color 4) disagree:
    lab()'s L unclamped, rgb()'s fractions kept, none resolved in hsl().
  - `pending`: our gaps, each tagged with the stage that clears it:
    `values` (this layer: each group's reason written), `cascade`
    (shorthands to and from their longhands, the test's own sizes and
    colour, var(), inherit) or `layout` (grid tracks, getComputedStyle's
    resolved values, percentages of the containing block). A pending case
    that passes fails the run too, until BLESS=1 requires it.
  - Every other case is required. The headline below is required over
    required and pending: checkpoint 1's progress.


<!-- values -->
17035 of 17960 required (94.8%): checkpoint 1's progress; 925 pending, our gaps; 9499 skipped, not checkpoint 1's.

| Pending, by the stage that clears them | Cases |
| --- | --- |
| cascade | 638 |
| layout | 263 |
| values | 24 |

| Pending because | Cases |
| --- | --- |
| cascade: shorthands serialize from their longhands | 295 |
| layout: grid tracks' sizes | 207 |
| cascade: shorthands expand to their longhands | 167 |
| cascade: the test's own sizes (font size, container) | 131 |
| layout: getComputedStyle's resolved value (the used one) | 36 |
| cascade: currentcolor, the element's color | 19 |
| cascade: var() and env() substituted | 16 |
| layout: percentages of the containing block | 14 |
| values: box-shadow's longhands (Borders 4): WPT has a draft's expectations, no browser the longhands | 9 |
| layout: the font's own metrics | 6 |
| cascade: the writing mode's default shape | 5 |
| values: Align 3's `[ first | last ]? && baseline` takes `baseline last` | 5 |
| values: Images 3's grammar still has `<angle> || flip`, which browsers dropped and WPT rejects | 5 |
| values: rgb() with none as color(srgb): WPT wants 8 digits here, 6 everywhere else (followed) | 3 |
| cascade: inherit, the parent's value | 2 |
| cascade: justify-items' legacy, the parent's | 2 |
| cascade: url() made absolute against the document | 1 |
| values: WPT disagrees with itself: translateX() as written in one file, scalex() lowercase in the others (followed) | 1 |
| values: its initial value: WPT has Text Decoration 4's auto, checkpoint 1's table 3's over right | 1 |

| Skipped because | Cases |
| --- | --- |
| out of scope: Color 5 and 6 (color-mix(), relative colours, light-dark(), contrast-color()); checkpoint 1 is Color 4 | 5028 |
| outdated fixture: css-parsing-tests leaves lab() and lch() unclamped (WPT and Color 4: L in its range, C at least 0) | 2760 |
| out of scope: drafts past checkpoint 1 (Values 5's functions, custom functions, -webkit-image-set()) | 590 |
| outdated fixture: css-parsing-tests resolves none in hsl() and hwb() (WPT: kept) | 488 |
| outdated fixture: css-parsing-tests keeps rgb()'s fractions (WPT: rounded) | 468 |
| out of scope: url()'s request modifiers and param() (Values 5) | 78 |
| out of scope: Transforms 2 (3D functions, percentages in scale()) | 28 |
| out of scope: Flexbox 2's balance | 20 |
| out of scope: a draft's value past checkpoint 1's modules | 18 |
| out of scope: Grid 3's grid-lanes (masonry) | 12 |
| out of scope: Images 5's object-fit pairs | 9 |

| Module | Required | Pending | Skipped |
| --- | --- | --- | --- |
| colors | 4326 | 0 | 3735 |
| css-align-3 | 675 | 78 | 8 |
| css-backgrounds-3 | 1420 | 106 | 252 |
| css-box-3 | 186 | 22 | 6 |
| css-break-3 | 96 | 0 | 0 |
| css-cascade-4 | 10 | 0 | 0 |
| css-color-4 | 5820 | 31 | 4999 |
| css-content-3 | 235 | 0 | 12 |
| css-display-3 | 281 | 0 | 12 |
| css-flexbox-1 | 177 | 96 | 29 |
| css-fonts-4 | 797 | 44 | 54 |
| css-grid-1 | 876 | 329 | 2 |
| css-images-3 | 123 | 5 | 9 |
| css-inline-3 | 130 | 25 | 0 |
| css-lists-3 | 210 | 23 | 0 |
| css-masking-1 | 11 | 1 | 0 |
| css-overflow-3 | 49 | 6 | 0 |
| css-page-3 | 21 | 0 | 0 |
| css-page-floats-3 | 31 | 0 | 0 |
| css-position-3 | 111 | 14 | 131 |
| css-sizing-3 | 353 | 29 | 218 |
| css-tables-3 | 43 | 2 | 0 |
| css-text-3 | 426 | 54 | 2 |
| css-text-decor-3 | 263 | 28 | 2 |
| css-transforms-1 | 237 | 24 | 28 |
| css-ui-3 | 106 | 8 | 0 |
| css-writing-modes-3 | 22 | 0 | 0 |
<!-- /values -->

## Differential

`differential.mjs` (the css-differential lane, not in CI: it fetches)
compares helder.css with @csstools/css-tokenizer and
css-parser-algorithms (pinned devDependencies, spec-conformant) on real
stylesheets (`sheets.mjs`: pinned npm builds of Bootstrap, Tailwind 2,
Bulma, GitHub's Primer, Foundation, Font Awesome, animate.css and
normalize.css, fetched into bin/css/sheets) and 2,000 generated inputs
made of CSS's edges (`FUZZ_SEED`). It checks every token's kind,
offsets and value and the component values' tree; `CssDump.hx` writes
helder.css's side. A NUL is filtered to U+FFFD before @csstools reads
the text, as Syntax 3 §3.3 filters it: @csstools reads a NUL in an
unquoted url as non-printable (a bad url), which css-parsing-tests'
component_value_list #26 says it is not.

## Selectors

`CssSelectorsCheck.hx` reads `fixtures/selectors.json` (WPT's
dom/nodes/selectors.js, BSD-3-Clause: `WPT-LICENSE.md`; extracted by
`import-wpt.mjs`): its invalid selectors must not parse, its valid and
scoped ones must (querySelector's: no @namespace declared). Matching them
on `selectors.html` comes with helder.dom.

## Report

<!-- report -->
At WPT bc5ea7a9006b, made by import-wpt.mjs.

### Values

44341 calls of the helpers read in 97 directories of css/ (a loop's items and a helper's calls each one); 19398 rows for 216 in-scope properties from 738 files (368 duplicates dropped), 17358 calls on 421 properties out of scope (most: position-area 2925, filter 365, clip-path 341, shape-outside 271, backdrop-filter 260, offset-path 208, font-palette 180, will-change 171), and 296 not read statically:

| Why not read | Calls |
| --- | --- |
| a name not bound to a literal | 262 |
| in a helper | 19 |
| a loop over what it can't read | 14 |
| undefined in a template | 1 |

| Module | Properties | Valid | Invalid | Computed | Shorthand | Inherits |
| --- | --- | --- | --- | --- | --- | --- |
| css-align-3 | 15 | 245 | 242 | 240 | 22 | 12 |
| css-backgrounds-3 | 48 | 489 | 729 | 485 | 43 | 32 |
| css-box-3 | 10 | 97 | 75 | 26 | 8 | 8 |
| css-break-3 | 6 | 35 | 18 | 37 | 0 | 6 |
| css-cascade-4 | 1 | 3 | 7 | 0 | 0 | 0 |
| css-color-4 | 2 | 2028 | 1113 | 7707 | 0 | 2 |
| css-content-3 | 4 | 88 | 113 | 43 | 0 | 3 |
| css-display-3 | 2 | 117 | 57 | 117 | 0 | 2 |
| css-flexbox-1 | 8 | 103 | 77 | 88 | 28 | 6 |
| css-fonts-4 | 26 | 322 | 321 | 233 | 0 | 19 |
| css-grid-1 | 15 | 375 | 338 | 424 | 60 | 10 |
| css-images-3 | 3 | 60 | 38 | 36 | 0 | 3 |
| css-inline-3 | 5 | 59 | 34 | 58 | 0 | 4 |
| css-lists-3 | 7 | 93 | 59 | 75 | 1 | 5 |
| css-masking-1 | 1 | 3 | 4 | 4 | 0 | 1 |
| css-overflow-3 | 3 | 15 | 9 | 29 | 0 | 2 |
| css-page-3 | 1 | 5 | 9 | 6 | 0 | 1 |
| css-page-floats-3 | 2 | 11 | 5 | 11 | 0 | 4 |
| css-position-3 | 7 | 97 | 103 | 46 | 4 | 6 |
| css-sizing-3 | 7 | 222 | 282 | 89 | 0 | 7 |
| css-tables-3 | 5 | 12 | 14 | 14 | 0 | 5 |
| css-text-3 | 17 | 167 | 151 | 147 | 0 | 17 |
| css-text-decor-3 | 11 | 128 | 61 | 95 | 1 | 8 |
| css-transforms-1 | 3 | 63 | 192 | 31 | 0 | 3 |
| css-ui-3 | 5 | 44 | 44 | 23 | 1 | 2 |
| css-writing-modes-3 | 2 | 8 | 4 | 8 | 0 | 2 |

### Selectors

selectors.json: 34 invalid, 207 valid, 198 scoped selectors.

### Reftests

10897 tests (references and support files left out), 8413 in scope: 6053 reftests, 10 crash tests and 2350 noref (no reference yet: checked later against goldens Chromium draws, a tier the reftest runner adds):

| Suite | Tests | In scope | Reftests | Noref | Crash | Of them Ahem | Of them print |
| --- | --- | --- | --- | --- | --- | --- | --- |
| css/CSS2 | 9208 | 8105 | 5790 | 2310 | 5 | 1459 | 43 |
| css/css-page | 283 | 223 | 199 | 20 | 4 | 9 | 202 |
| css/css-break | 1386 | 65 | 64 | 0 | 1 | 4 | 61 |
| css/css-gcpm | 20 | 20 | 0 | 20 | 0 | 0 | 0 |

| Out of scope because | Tests |
| --- | --- |
| deferred: multicol | 1178 |
| script: needs JavaScript | 470 |
| interact: needs a person | 362 |
| testharness.js: needs JavaScript | 156 |
| deferred: writing-mode (its help) | 84 |
| deferred: writing-mode | 71 |
| http: needs an HTTP server's headers | 57 |
| animated: a page is still | 53 |
| userstyle: needs a user style sheet set by hand | 23 |
| deferred: forms | 10 |
| scroll: a page doesn't scroll | 6 |
| deferred: @layer | 4 |
| history: :visited | 3 |
| deferred: 3D transforms | 3 |
| deferred: ruby (its help) | 3 |
| deferred: multicol (its help) | 1 |

By directory (CSS2: its chapters; the others: their sections, from the first `<link rel=help>`):

| Directory or section | Tests | In scope: reftests and crash | In scope: noref |
| --- | --- | --- | --- |
| CSS2 (top level) | 16 | 5 | 2 |
| CSS2/abspos | 33 | 25 | 0 |
| CSS2/backgrounds | 625 | 333 | 61 |
| CSS2/bidi-text | 108 | 34 | 0 |
| CSS2/borders | 762 | 504 | 255 |
| CSS2/box | 9 | 9 | 0 |
| CSS2/box-display | 139 | 86 | 11 |
| CSS2/cascade | 101 | 31 | 37 |
| CSS2/cascade-import | 19 | 1 | 10 |
| CSS2/colors | 22 | 19 | 3 |
| CSS2/css1 | 262 | 164 | 82 |
| CSS2/css21-errata | 9 | 9 | 0 |
| CSS2/csswg-issues | 3 | 3 | 0 |
| CSS2/floats | 163 | 113 | 0 |
| CSS2/floats-clear | 249 | 203 | 20 |
| CSS2/fonts | 324 | 159 | 164 |
| CSS2/generate | 17 | 0 | 17 |
| CSS2/generated-content | 316 | 205 | 83 |
| CSS2/i18n | 57 | 0 | 28 |
| CSS2/linebox | 250 | 192 | 48 |
| CSS2/lists | 286 | 155 | 130 |
| CSS2/margin-padding-clear | 740 | 683 | 57 |
| CSS2/media | 17 | 17 | 0 |
| CSS2/normal-flow | 868 | 696 | 71 |
| CSS2/other-formats | 4 | 0 | 4 |
| CSS2/page-box | 36 | 0 | 36 |
| CSS2/pagination | 103 | 43 | 60 |
| CSS2/positioning | 579 | 513 | 32 |
| CSS2/sec5 | 28 | 23 | 1 |
| CSS2/selectors | 552 | 467 | 46 |
| CSS2/stacking-context | 7 | 3 | 0 |
| CSS2/syntax | 280 | 252 | 2 |
| CSS2/tables | 1140 | 250 | 716 |
| CSS2/text | 564 | 377 | 109 |
| CSS2/ui | 239 | 52 | 135 |
| CSS2/values | 26 | 25 | 1 |
| CSS2/visudet | 41 | 38 | 1 |
| CSS2/visufx | 104 | 50 | 45 |
| CSS2/visuren | 57 | 26 | 23 |
| CSS2/zindex | 52 | 29 | 20 |
| CSS2/zorder | 1 | 1 | 0 |
| css-break #abspos-breaking | 96 | 0 | 0 |
| css-break #box-splitting | 30 | 0 | 0 |
| css-break #break-between | 5 | 0 | 0 |
| css-break #break-decoration | 64 | 3 | 0 |
| css-break #break-margins | 7 | 1 | 0 |
| css-break #break-propagation | 9 | 0 | 0 |
| css-break #break-within | 5 | 3 | 0 |
| css-break #breaking-controls | 2 | 0 | 0 |
| css-break #breaking-rules | 11 | 0 | 0 |
| css-break #end-block | 1 | 0 | 0 |
| css-break #flex-containers | 1 | 0 | 0 |
| css-break #forced-breaks | 6 | 0 | 0 |
| css-break #fragmentation | 34 | 0 | 0 |
| css-break #fragmentation-model | 20 | 0 | 0 |
| css-break #grid-axis-pagination | 1 | 0 | 0 |
| css-break #issuecomment-951767882 | 12 | 0 | 0 |
| css-break #legacy-shorthand | 1 | 0 | 0 |
| css-break #monolithic | 6 | 0 | 0 |
| css-break #overflow-properties | 2 | 0 | 0 |
| css-break #page-break-values | 2 | 2 | 0 |
| css-break #pagination | 531 | 27 | 0 |
| css-break #parallel-flows | 26 | 2 | 0 |
| css-break #possible-breaks | 20 | 3 | 0 |
| css-break #propdef-box-decoration-break | 3 | 0 | 0 |
| css-break #propdef-break-after | 3 | 0 | 0 |
| css-break #propdef-break-before | 3 | 0 | 0 |
| css-break #propdef-break-inside | 3 | 0 | 0 |
| css-break #propdef-orphans | 3 | 0 | 0 |
| css-break #propdef-widows | 3 | 0 | 0 |
| css-break #property-index | 1 | 0 | 0 |
| css-break #repeated-headers | 18 | 0 | 0 |
| css-break #transforms | 25 | 0 | 0 |
| css-break #unforced-breaks | 24 | 0 | 0 |
| css-break #valdef-box-decoration-break-slice | 5 | 0 | 0 |
| css-break #varying-size-boxes | 5 | 0 | 0 |
| css-break #widows-orphans | 28 | 0 | 0 |
| css-break (no section) | 370 | 24 | 0 |
| css-gcpm #dotted-leader | 1 | 0 | 1 |
| css-gcpm #setting-named-strings-the-string-set-pro | 12 | 0 | 12 |
| css-gcpm #solid-leader | 1 | 0 | 1 |
| css-gcpm #string-first | 1 | 0 | 1 |
| css-gcpm #string-first-except | 1 | 0 | 1 |
| css-gcpm #string-last | 2 | 0 | 2 |
| css-gcpm #string-leader | 1 | 0 | 1 |
| css-gcpm #string-start | 1 | 0 | 1 |
| css-page #at-page-rule | 16 | 11 | 0 |
| css-page #at-page-rules | 1 | 0 | 0 |
| css-page #background-image | 1 | 0 | 0 |
| css-page #cascading-and-page-context | 3 | 3 | 0 |
| css-page #descdef-page-size | 1 | 0 | 0 |
| css-page #first-pseudo | 4 | 4 | 0 |
| css-page #layering | 4 | 0 | 0 |
| css-page #margin-at-rules | 2 | 0 | 0 |
| css-page #margin-dimension | 18 | 14 | 0 |
| css-page #margin-property-list | 1 | 0 | 0 |
| css-page #margin-text-alignment | 1 | 1 | 0 |
| css-page #media1 | 1 | 1 | 0 |
| css-page #page-based-counters | 10 | 10 | 0 |
| css-page #page-box-page-rule | 1 | 0 | 1 |
| css-page #page-break-props | 1 | 0 | 1 |
| css-page #page-breaks | 4 | 4 | 0 |
| css-page #page-margin-safety | 1 | 1 | 0 |
| css-page #page-model | 2 | 2 | 0 |
| css-page #page-orientation-prop | 8 | 5 | 0 |
| css-page #page-properties | 29 | 23 | 3 |
| css-page #page-selectors | 2 | 0 | 0 |
| css-page #page-size | 3 | 0 | 3 |
| css-page #page-size-prop | 14 | 5 | 8 |
| css-page #painting | 6 | 4 | 0 |
| css-page #populating-margin-boxes | 4 | 2 | 1 |
| css-page #possible-breaks | 3 | 3 | 0 |
| css-page #spread-pseudos | 2 | 2 | 0 |
| css-page #syntax-page-selector | 2 | 0 | 1 |
| css-page #the-csspagerule-interface | 6 | 0 | 0 |
| css-page #typedef-page-size-page-size | 2 | 0 | 2 |
| css-page #using-named-pages | 52 | 44 | 0 |
| css-page #valdef-position-fixed | 2 | 1 | 0 |
| css-page (no section) | 76 | 63 | 0 |
<!-- /report -->
