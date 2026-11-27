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

## Selectors

`CssSelectorsCheck.hx` reads `fixtures/selectors.json` (WPT's
dom/nodes/selectors.js, BSD-3-Clause: `WPT-LICENSE.md`; extracted by
`import-wpt.mjs`). Its invalid selectors must not parse and its valid and
scoped ones must (querySelector's: no @namespace declared). Then the
valid ones run as ParentNode-querySelector-All.html runs them, on
`selectors.html` parsed by helder.dom:

- setupSpecialElements' elements are added;
- the contexts are the document, the in-document `#root`, a detached
  clone and a fragment with a clone, each with the div verifyStaticList
  appends;
- the `data-clone` copy is appended to the body before the in-document
  element's run;
- querySelectorAll's ids in tree order must be the expected ones.

Its `PENDING` cases (the name and context, and why) must fail, and fail
the run once they pass: `:target`, which never matches. The scoped
selectors are Selectors API 2's `find()` and refNodes, gone from the DOM,
so they are only parsed.

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
19641 of 19941 required (98.5%): checkpoint 1's progress; 300 pending, our gaps; 9737 skipped, not checkpoint 1's.

| Pending, by the stage that clears them | Cases |
| --- | --- |
| layout | 255 |
| values | 45 |

| Pending because | Cases |
| --- | --- |
| layout: grid tracks' sizes | 183 |
| layout: getComputedStyle's resolved value (the used one) | 39 |
| layout: percentages of the containing block | 27 |
| values: WPT's logical inset files want 0 as written and calc() unresolved, unlike its top, right, bottom and left files (followed: Values 4's computed value) | 12 |
| values: box-shadow's longhands (Borders 4): WPT has a draft's expectations, no browser the longhands | 9 |
| layout: the font's own metrics | 6 |
| values: WPT's inset-block and inset-inline files want the value as written (0, auto auto), unlike its other logical shorthands' and inset's (followed: the shortest) | 6 |
| values: Align 3's `[ first | last ]? && baseline` takes `baseline last` | 5 |
| values: Images 3's grammar still has `<angle> || flip`, which browsers dropped and WPT rejects | 5 |
| values: WPT's computed gradients in cursor: its expected texts drop a parenthesis, and cursor's grammar has image-set() of URLs, not <image> | 3 |
| values: rgb() with none as color(srgb): WPT wants 8 digits here, 6 everywhere else (followed) | 3 |
| values: WPT disagrees with itself: translateX() as written in one file, scalex() lowercase in the others (followed) | 1 |
| values: its initial value: WPT has Text Decoration 4's auto, checkpoint 1's table 3's over right | 1 |

| Skipped because | Cases |
| --- | --- |
| out of scope: Color 5 and 6 (color-mix(), relative colours, light-dark(), contrast-color()); checkpoint 1 is Color 4 | 5035 |
| outdated fixture: css-parsing-tests leaves lab() and lch() unclamped (WPT and Color 4: L in its range, C at least 0) | 2760 |
| out of scope: drafts past checkpoint 1 (Values 5's functions, custom functions, -webkit-image-set()) | 614 |
| outdated fixture: css-parsing-tests resolves none in hsl() and hwb() (WPT: kept) | 488 |
| outdated fixture: css-parsing-tests keeps rgb()'s fractions (WPT: rounded) | 468 |
| out of scope: container query units (@container is deferred) | 85 |
| out of scope: url()'s request modifiers and param() (Values 5) | 78 |
| out of scope: Text 4's white-space-trim | 51 |
| out of scope: Flexbox 2's balance | 38 |
| out of scope: Transforms 2 (3D functions, percentages in scale()) | 28 |
| out of scope: a draft's value past checkpoint 1's modules | 28 |
| out of scope: Fonts 5's oblique-only | 20 |
| out of scope: Backgrounds 4's border-area | 13 |
| out of scope: Grid 3's grid-lanes (masonry) | 12 |
| out of scope: Images 5's object-fit pairs | 9 |
| out of scope: writing modes (deferred): the test's page is vertical | 9 |
| out of scope: Color 5 (color-mix(), relative colours, light-dark(), contrast-color()); checkpoint 1 is Color 4 | 1 |

| Module | Required | Pending | Skipped |
| --- | --- | --- | --- |
| colors | 4326 | 0 | 3735 |
| compositing-2 | 43 | 0 | 0 |
| css-align-3 | 738 | 5 | 18 |
| css-backgrounds-3 | 1500 | 9 | 269 |
| css-box-3 | 202 | 6 | 6 |
| css-break-3 | 96 | 0 | 0 |
| css-cascade-4 | 10 | 0 | 0 |
| css-color-4 | 5831 | 3 | 5016 |
| css-content-3 | 235 | 0 | 12 |
| css-display-3 | 281 | 0 | 12 |
| css-flexbox-1 | 251 | 0 | 51 |
| css-fonts-4 | 803 | 6 | 86 |
| css-forms-1 | 11 | 0 | 0 |
| css-grid-1 | 1021 | 183 | 3 |
| css-images-3 | 123 | 5 | 9 |
| css-inline-3 | 149 | 3 | 3 |
| css-lists-3 | 224 | 0 | 9 |
| css-logical-1 | 582 | 39 | 6 |
| css-masking-1 | 12 | 0 | 0 |
| css-overflow-3 | 55 | 0 | 0 |
| css-overflow-4 | 89 | 0 | 0 |
| css-page-3 | 21 | 0 | 0 |
| css-page-floats-3 | 31 | 0 | 0 |
| css-position-3 | 125 | 0 | 131 |
| css-scrollbars-1 | 30 | 0 | 0 |
| css-sizing-3 | 369 | 13 | 218 |
| css-sizing-4 | 40 | 0 | 0 |
| css-tables-3 | 45 | 0 | 0 |
| css-text-3 | 427 | 0 | 55 |
| css-text-4 | 84 | 0 | 0 |
| css-text-decor-3 | 281 | 1 | 11 |
| css-text-decor-4 | 35 | 0 | 0 |
| css-transforms-1 | 237 | 24 | 28 |
| css-transforms-2 | 193 | 0 | 12 |
| css-transitions-1 | 289 | 0 | 5 |
| css-ui-3 | 114 | 0 | 0 |
| css-ui-4 | 125 | 3 | 8 |
| css-writing-modes-3 | 22 | 0 | 0 |
| filter-effects-1 | 591 | 0 | 34 |
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
`import-wpt.mjs`). Its invalid selectors must not parse and its valid and
scoped ones must (querySelector's: no @namespace declared). Then the
valid ones run as ParentNode-querySelector-All.html runs them, on
`selectors.html` parsed by helder.dom:

- setupSpecialElements' elements are added;
- the contexts are the document, the in-document `#root`, a detached
  clone and a fragment with a clone, each with the div verifyStaticList
  appends;
- the `data-clone` copy is appended to the body before the in-document
  element's run;
- querySelectorAll's ids in tree order must be the expected ones.

Its `PENDING` cases (the name and context, and why) must fail, and fail
the run once they pass: `:target`, which never matches. The scoped
selectors are Selectors API 2's `find()` and refNodes, gone from the DOM,
so they are only parsed.

## Cascade

helder.css's cascade against WPT's css-cascade and css-variables tests,
natively (`bun run test css`: CssCascadeCheck; BLESS=1:
cascade-manifest.json and the counts below; SHOW=1: each case that
doesn't pass):

This check and CssValuesCheck also run every value they read through #321's cascade as it
was merged (`reference/`, frozen: its CssStyle, CssStyles, CssSheet and
the rest renamed Ref*, the user agent's sheets with logical properties as
physical ones, as #321 had them) and require the same text: the row's
property on every row, every longhand on a page's first. Pages with
logical properties are left out (#321 had none).

- `fixtures/cascade.json`: every test of those directories with what
  became of it: read (its cases), a reftest (layout's), or out with why
  (a script that changes the page or the CSSOM: no JavaScript here;
  @scope, animation, shadow trees: past checkpoint 1). The pages read,
  their markup without scripts, and their cases: `getComputedStyle(el)`'s
  value of a property against a literal or another's (`assert_equals`
  and `assert_not_equals` read statically: elements by id, the root,
  `querySelectorAll`'s), variable-cycles' `test_cycles` (an element of
  its declarations), crash tests (the page styled whole).
- `CssCascadeCheck.hx`: each page parsed by helder.dom and cascaded as
  WPT's harness shows it (a screen of 800 by 600); each case required
  unless cascade-manifest.json's `pending` says why; a case that fails on
  a page past checkpoint 1 (revert-rule, @scope, @container, @property,
  animation, shadow trees, ident(), vertical writing modes) is skipped with
  that reason, one that passes is required.

<!-- cascade -->
71 of 71 cases pass; skipped (their page is past checkpoint 1):

| Skipped because | Cases |
| --- | --- |
| out of scope: Cascade 6's revert-rule | 23 |
| out of scope: @scope (deferred) | 10 |
| out of scope: Values 5's ident() | 2 |
| out of scope: animation (a page is still) | 1 |
| out of scope: registered custom properties (@property) | 1 |

The tests, by what became of them:

| Status | Tests |
| --- | --- |
| layout: a reftest | 235 |
| out: its script changes the page (no JavaScript here) | 40 |
| read | 36 |
| out of scope: @scope (deferred) | 28 |
| out: the CSSOM (no JavaScript here) | 25 |
| out: no assertion read statically | 21 |
| out of scope: animation (a page is still) | 14 |
| read: values.json has its cases | 4 |
| out of scope: shadow trees | 3 |
| out: manual | 1 |
<!-- /cascade -->

## Reftests

helder.ui.box drawing WPT's reftests, natively (`CssReftestCheck.hx`, the
css-reftests lane):

```sh
node tests/css/import-wpt.mjs --checkout     # bin/wpt at REVISION: css/, fonts/ (Ahem), images/
bun run test css-reftests                    # BLESS=1: reftest-manifest.json from the results
bun run test css-reftests normal-flow block-in-inline   # those alone (a directory or a name's part)
VERBOSE=1 bin/css/CssReftestCheck margin-padding-clear  # each name before it is drawn
bun run test css-render bin/wpt/css/CSS2/box/x.xht out.png --tree --ref bin/wpt/css/CSS2/box/x-ref.xht
```

- Each in-scope test of `fixtures/reftests.json` and each of its
  references are parsed (`.xht` as XML, `Dom.parseXml`), at their WPT
  URL (`http://web-platform.test/...`, so `/fonts/ahem.css` is found),
  their sheets, images and fonts read from bin/wpt (`WptPage.hx`), Ahem
  registered as WPT's runners have it; drawn by `DocumentView` at 800 by
  600 on the CPU canvas, white under them. Pixels compare as WPT's runner
  compares them: a `match` reference alike, a `mismatch` one not, within
  the test's `<meta name=fuzzy>` (maxDifference and totalPixels, for every
  reference or a named one). A crash test passes when it draws. A
  reference's own references are not followed.
- `reftest-manifest.json` is the gate, like tests/layout-conformance's:
  every test is required to pass unless `pending` says why (its stage,
  then how it differs) or `skip` does (`paged`: css-break's tests in
  columns and the paged directories' noref tests, no goldens of printed
  pages yet; `script`). A
  pending test that passes fails the run too, until BLESS=1 requires it.
  The stage is the directory's (floats, positioning, tables, fonts, inline,
  generated, ui), else what the test's and its references' sources use
  (a table, a float or clear, absolute or fixed positioning, generated
  content and lists, first-line and first-letter, inline blocks,
  vertical-align, line-height, white-space and the other line properties,
  ex and ch, which helder.css computes without the font's metrics yet,
  images); a rough guess, kept while it holds.
- Every page is drawn with the same fonts on every machine
  (`WptPage.shared`): none of the system's (`HELDER_FONT_DIRS`), DejaVu
  2.37's Serif, Sans and Sans Mono for the generic families (fetched by
  `import-wpt.mjs --checkout` into bin/fonts/dejavu-2.37, not committed),
  and the fonts WPT's runners install: Ahem, fonts/CSSTest's and
  fonts/ahem-extra's (Ahem as "White Space", "serif", "inherit"...).
- Print reftests (`-print`, WPT's; and the paged directories' crash
  tests) are drawn on pages by PagedView, at WPT's default page (5in by
  3in, 0.5in margins: a user sheet under the test's @page), and compared
  page by page as WPT's runner does: as many pages, each alike within
  the fuzzy, `<meta name=reftest-pages>` choosing which. Their stages:
  margin boxes, named pages, else as the others'.
- The `noref` tests (WPT's visual tests, no
  reference: 2,350) are drawn against goldens Chromium draws
  (`goldens.mjs`, which the lane runs first): headless Chromium through
  Playwright (the version CI's setup pins, `bun add --no-save
  playwright@1.56.1`, `bunx playwright install chromium`), one browser,
  two pages at a time, each test at 800 by 600 at its WPT URL, with
  helder's fonts alone: each face (`CssReftestCheck --fonts`) a web font
  added before the page loads, then every font-family of its sheets and
  style attributes rewritten (a generic family as the face helder takes,
  since Chromium's settings can't name a web font; a family neither has
  renamed to one no machine has, so a Mac's Arial is skipped as on
  Linux; the UA's monospace elements in a layer below the page's; DejaVu
  Sans after every list, helder's fallback for characters a face lacks,
  so Hebrew and Arabic aren't the machine's); text
  antialiased in grayscale as helder draws it. A golden is a PNG in
  `bin/css/goldens/<WPT revision>-chromium-<version>-<hash>/`, the hash
  of goldens.mjs and the fonts: the same on every machine, not
  committed, drawn where missing and kept (CI caches the directory by
  that key). A noref test passes within its `<meta name=fuzzy>`, or when
  it differs from its golden only as two engines' antialiasing does: no
  pixel off by more than 8 where the golden is flat, and at most 10 at
  edges (text, curves) unlike every pixel within a pixel of them by more
  than 96. The manifest gates them as the drawn ones, by stage. Skipped:
  those that ask for a paged view, the default font set by hand,
  scrollbars (the goldens hide them) or an alternate style sheet chosen
  by hand, and those Chromium draws against their own words (`CHROMIUM`
  in CssReftestCheck.hx: row-visibility-003, a cell spanning into a
  collapsed row not clipped).

At WPT bc5ea7a9006b with goldens from Chromium 141.0.7390.37, the same
on every machine: 8,268 drawn, 6,487 pass, 145 skipped.

| | Pass | Pending | Skipped |
| --- | ---: | ---: | ---: |
| reftests and crash tests | 5,055 | 697 | 3 |
| noref against goldens | 1,286 | 922 | 142 |
| print reftests on pages | 146 | 162 | 0 |

The noref tests pending by stage: tables 497, generated 256, inline 39,
ui 39, fonts 37, positioning 21, paged 20, floats 13.

The print reftests pending by stage: named pages 47, generated 34,
margin boxes 32, positioning 26, tables 16, floats 7.

At WPT bc5ea7a9006b, the reftests and crash tests by chapter (the box
tree, block flow, tables and the inline engine), as the css-reftests lane
draws them (5,752 drawn in about 30 s, 3 skipped: css-break's, in columns):

| Chapter | Pass | Drawn |
| --- | --- | --- |
| CSS2 | 0 | 5 |
| CSS2/abspos | 14 | 25 |
| CSS2/backgrounds | 312 | 333 |
| CSS2/bidi-text | 30 | 34 |
| CSS2/borders | 488 | 504 |
| CSS2/box | 4 | 9 |
| CSS2/box-display | 81 | 86 |
| CSS2/cascade | 24 | 31 |
| CSS2/cascade-import | 0 | 1 |
| CSS2/colors | 19 | 19 |
| CSS2/css1 | 141 | 164 |
| CSS2/css21-errata | 4 | 9 |
| CSS2/csswg-issues/submitted/css2.1 | 0 | 3 |
| CSS2/floats | 81 | 112 |
| CSS2/floats-clear | 178 | 203 |
| CSS2/floats/crashtests | 1 | 1 |
| CSS2/fonts | 137 | 159 |
| CSS2/generated-content | 185 | 205 |
| CSS2/linebox | 172 | 192 |
| CSS2/lists | 155 | 155 |
| CSS2/margin-padding-clear | 646 | 683 |
| CSS2/media | 17 | 17 |
| CSS2/normal-flow | 622 | 696 |
| CSS2/positioning | 431 | 513 |
| CSS2/sec5 | 22 | 23 |
| CSS2/selectors | 447 | 467 |
| CSS2/stacking-context | 1 | 3 |
| CSS2/syntax | 213 | 252 |
| CSS2/tables | 204 | 250 |
| CSS2/text | 301 | 376 |
| CSS2/text/crashtests | 1 | 1 |
| CSS2/ui | 40 | 52 |
| CSS2/values | 11 | 25 |
| CSS2/visudet | 19 | 37 |
| CSS2/visudet/crashtests | 1 | 1 |
| CSS2/visufx | 4 | 49 |
| CSS2/visufx/crashtests | 1 | 1 |
| CSS2/visuren | 23 | 26 |
| CSS2/zindex | 25 | 29 |
| CSS2/zorder | 0 | 1 |
| all | 5055 | 5752 |

Pending by stage: positioning 202, generated content 186, inline 122, tables 78, floats 75, fonts 22, ui 12.

## GCPM

WPT's css-gcpm tests (visual, paged, without references: what passes is
in their own words) read through helder.css's GCPM API, natively (`bun run
test css`: CssGcpmCheck; BLESS=1: gcpm-manifest.json; SHOW=1: each test's
pages and what its words want):

- `fixtures/gcpm.json` (made by `import-wpt.mjs`): each test's page,
  scripts out, and its "Test passes if ..." words.
- `CssGcpmCheck.hx`: each page walked as the box tree walks it
  (CssCounters), its pages where its forced breaks are (the tests are
  short), string-set's assignments page by page (CssRunning: an element
  at a page's start when nothing shown comes before it there), each
  page's margin boxes' content resolved, and the words checked: each
  page's running heads, a leader's fill. All 20 pass. Their reftests are
  pending in reftest-manifest.json, stage paged: the paged host draws them
  (Chromium has no GCPM, so no golden).

## Interpolation

Interpolation and transitions against WPT's interpolation tests,
natively (`bun run test css`: CssInterpolationCheck; BLESS=1:
interpolation-manifest.json and the counts below; SHOW=1: each case that
doesn't pass):

- `fixtures/interpolation.json` (made by `import-wpt.mjs`): every
  `test_interpolation`, `test_no_interpolation` and `test_not_animatable`
  call of css/ with a property in scope, as CSS Transitions runs it (its
  own expectations when the call gives them), with its page, scripts out.
- `CssInterpolationCheck.hx`: each case's targets built as
  interpolation-testcommon.js builds them, the from and to values
  computed, every longhand interpolated by CssInterpolate (currentcolor
  resolved as CssTransition resolves it; with allow-discrete, a discrete
  one flipped as CssTransition flips it), written (a shorthand from its
  longhands) and required to be the expected value computed on its own
  target, both normalized as the harness does; a discrete or not
  animatable case required not to interpolate. A case is required unless
  interpolation-manifest.json's `pending` says why.

<!-- interpolation -->
3417 of 4373 cases pass.

| Pending because | Cases |
| --- | --- |
| sizes: calc-size() and interpolate-size not yet (Values 5) | 380 |
| transforms: 3D functions, axes and perspective not yet (2D only) | 262 |
| grid: track lists not interpolated yet (Grid 1 §7.2.5) | 192 |
| images: list-style-image is discrete (Lists 3); the test wants it to transition, flipping halfway as Chrome's cross-fade does | 48 |
| resolved values: getComputedStyle's px are layout's, and this check has none | 37 |
| math functions: sign(), progress() and random() not resolved in computed values yet | 18 |
| clip: rect() without commas, CSS 2's form the expected values use, not parsed | 11 |
| display: expects an animation's flip (none until p > 0); without allow-discrete no transition starts | 6 |
| colours: one channel off by one, a browser's 8-bit premultiplied rounding | 1 |
| page: its script sets height: auto before this case, so neutral isn't the page's 10px | 1 |
<!-- /interpolation -->

## Report

<!-- report -->
At WPT bc5ea7a9006b, made by import-wpt.mjs.

### Values

44341 calls of the helpers read in 97 directories of css/ (a loop's items and a helper's calls each one); 21617 rows for 297 in-scope properties from 877 files (432 duplicates dropped), 10472 calls on 340 properties out of scope (most: position-area 2925, clip-path 341, shape-outside 271, offset-path 208, font-palette 180, will-change 171, mask 159, animation-timing-function 125), and 307 not read statically:

| Why not read | Calls |
| --- | --- |
| a name not bound to a literal | 273 |
| in a helper | 19 |
| a loop over what it can't read | 14 |
| undefined in a template | 1 |

| Module | Properties | Valid | Invalid | Computed | Shorthand | Inherits |
| --- | --- | --- | --- | --- | --- | --- |
| compositing-2 | 2 | 18 | 5 | 18 | 0 | 2 |
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
| css-forms-1 | 1 | 2 | 7 | 2 | 0 | 0 |
| css-grid-1 | 15 | 375 | 338 | 424 | 60 | 10 |
| css-images-3 | 3 | 60 | 38 | 36 | 0 | 3 |
| css-inline-3 | 5 | 59 | 34 | 58 | 0 | 4 |
| css-lists-3 | 7 | 93 | 59 | 75 | 1 | 5 |
| css-logical-1 | 52 | 226 | 192 | 168 | 12 | 29 |
| css-masking-1 | 1 | 3 | 4 | 4 | 0 | 1 |
| css-overflow-3 | 3 | 15 | 9 | 29 | 0 | 2 |
| css-overflow-4 | 5 | 42 | 38 | 5 | 0 | 4 |
| css-page-3 | 1 | 5 | 9 | 6 | 0 | 1 |
| css-page-floats-3 | 2 | 11 | 5 | 11 | 0 | 4 |
| css-position-3 | 7 | 97 | 103 | 46 | 4 | 6 |
| css-scrollbars-1 | 2 | 11 | 17 | 0 | 0 | 2 |
| css-sizing-3 | 7 | 222 | 282 | 89 | 0 | 7 |
| css-sizing-4 | 1 | 14 | 11 | 14 | 0 | 1 |
| css-tables-3 | 5 | 12 | 14 | 14 | 0 | 5 |
| css-text-3 | 17 | 167 | 151 | 147 | 0 | 17 |
| css-text-4 | 2 | 36 | 20 | 26 | 0 | 2 |
| css-text-decor-3 | 11 | 128 | 61 | 95 | 1 | 8 |
| css-text-decor-4 | 1 | 12 | 8 | 15 | 0 | 0 |
| css-transforms-1 | 3 | 63 | 192 | 31 | 0 | 3 |
| css-transforms-2 | 3 | 85 | 37 | 80 | 0 | 3 |
| css-transitions-1 | 6 | 66 | 162 | 59 | 3 | 4 |
| css-ui-3 | 5 | 44 | 44 | 23 | 1 | 2 |
| css-ui-4 | 4 | 62 | 20 | 51 | 0 | 3 |
| css-writing-modes-3 | 2 | 8 | 4 | 8 | 0 | 2 |
| filter-effects-1 | 2 | 238 | 183 | 202 | 0 | 2 |

### Selectors

selectors.json: 34 invalid, 207 valid, 198 scoped selectors.

### Reftests

12021 tests (references and support files left out), 8926 in scope: 6539 reftests, 33 crash tests and 2354 noref (no reference yet: checked later against goldens Chromium draws, a tier the reftest runner adds):

| Suite | Tests | In scope | Reftests | Noref | Crash | Of them Ahem | Of them print |
| --- | --- | --- | --- | --- | --- | --- | --- |
| css/CSS2 | 9208 | 8105 | 5790 | 2310 | 5 | 1459 | 43 |
| css/css-page | 283 | 223 | 199 | 20 | 4 | 9 | 202 |
| css/css-break | 1386 | 65 | 64 | 0 | 1 | 4 | 61 |
| css/css-gcpm | 20 | 20 | 0 | 20 | 0 | 0 | 0 |
| css/css-fonts | 583 | 347 | 336 | 3 | 8 | 46 | 2 |
| css/css-values | 541 | 166 | 150 | 1 | 15 | 7 | 2 |

| Out of scope because | Tests |
| --- | --- |
| deferred: multicol | 1178 |
| testharness.js: needs JavaScript | 627 |
| script: needs JavaScript | 574 |
| interact: needs a person | 363 |
| deferred: writing-mode | 91 |
| deferred: writing-mode (its help) | 90 |
| http: needs an HTTP server's headers | 57 |
| animated: a page is still | 53 |
| userstyle: needs a user style sheet set by hand | 23 |
| deferred: forms | 11 |
| scroll: a page doesn't scroll | 6 |
| deferred: @layer | 5 |
| deferred: Sizing 4 (its help) | 5 |
| history: :visited | 3 |
| deferred: 3D transforms | 3 |
| deferred: ruby (its help) | 3 |
| deferred: past checkpoint 1's modules (its help) | 2 |
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
| css-fonts #char-handling-issues | 3 | 2 | 0 |
| css-fonts #cluster-matching | 4 | 3 | 0 |
| css-fonts #cssfontfeaturevaluesmap | 1 | 0 | 0 |
| css-fonts #default-features | 4 | 3 | 0 |
| css-fonts #descdef-font-face-font-style | 1 | 0 | 0 |
| css-fonts #descdef-font-face-font-variation-settings | 2 | 2 | 0 |
| css-fonts #descdef-font-face-size-adjust | 2 | 2 | 0 |
| css-fonts #descdef-font-face-unicode-range | 1 | 0 | 0 |
| css-fonts #family-name-syntax | 2 | 0 | 0 |
| css-fonts #feature-precedence | 2 | 2 | 0 |
| css-fonts #feature-tag-value | 1 | 0 | 0 |
| css-fonts #first-available-font | 7 | 7 | 0 |
| css-fonts #font-display-desc | 3 | 0 | 0 |
| css-fonts #font-display-timeline | 2 | 0 | 0 |
| css-fonts #font-face-rule | 5 | 2 | 0 |
| css-fonts #font-face-src-formats | 1 | 0 | 0 |
| css-fonts #font-face-src-parsing | 3 | 0 | 0 |
| css-fonts #font-family-2-desc | 2 | 2 | 0 |
| css-fonts #font-family-prop | 6 | 1 | 0 |
| css-fonts #font-feature-settings-prop | 6 | 3 | 0 |
| css-fonts #font-feature-values | 1 | 0 | 0 |
| css-fonts #font-kerning-prop | 9 | 3 | 0 |
| css-fonts #font-language-override-prop | 3 | 3 | 0 |
| css-fonts #font-matching-algorithm | 6 | 0 | 0 |
| css-fonts #font-metrics-override-desc | 5 | 4 | 0 |
| css-fonts #font-optical-sizing-def | 2 | 0 | 0 |
| css-fonts #font-palette-prop | 46 | 37 | 0 |
| css-fonts #font-palette-values | 6 | 0 | 0 |
| css-fonts #font-prop | 9 | 0 | 0 |
| css-fonts #font-prop-desc | 19 | 12 | 0 |
| css-fonts #font-rend-desc | 6 | 4 | 0 |
| css-fonts #font-size-adjust-prop | 27 | 18 | 1 |
| css-fonts #font-size-prop | 19 | 10 | 0 |
| css-fonts #font-stretch-prop | 20 | 18 | 0 |
| css-fonts #font-style-matching | 5 | 4 | 0 |
| css-fonts #font-style-prop | 8 | 1 | 0 |
| css-fonts #font-synthesis | 6 | 3 | 0 |
| css-fonts #font-synthesis-intro | 1 | 1 | 0 |
| css-fonts #font-synthesis-prop | 5 | 5 | 0 |
| css-fonts #font-synthesis-small-caps | 6 | 4 | 0 |
| css-fonts #font-synthesis-style | 7 | 5 | 0 |
| css-fonts #font-synthesis-weight | 11 | 7 | 0 |
| css-fonts #font-variant-alternates-prop | 22 | 20 | 0 |
| css-fonts #font-variant-caps-prop | 14 | 7 | 0 |
| css-fonts #font-variant-east-asian-prop | 14 | 10 | 0 |
| css-fonts #font-variant-emoji-prop | 8 | 5 | 0 |
| css-fonts #font-variant-ligatures-prop | 18 | 14 | 0 |
| css-fonts #font-variant-numeric-prop | 13 | 9 | 0 |
| css-fonts #font-variant-position-prop | 9 | 5 | 0 |
| css-fonts #font-variant-prop | 4 | 4 | 0 |
| css-fonts #font-variation-settings-def | 1 | 1 | 0 |
| css-fonts #font-weight-prop | 9 | 2 | 0 |
| css-fonts #font-width-prop | 3 | 0 | 0 |
| css-fonts #funcdef-calc | 1 | 0 | 0 |
| css-fonts #funcdef-palette-mix | 1 | 1 | 0 |
| css-fonts #generic-font-families | 2 | 1 | 0 |
| css-fonts #ink | 1 | 0 | 0 |
| css-fonts #issuecomment-402034497 | 2 | 0 | 0 |
| css-fonts #language-specific-support | 1 | 0 | 1 |
| css-fonts #local-font-fallback | 2 | 1 | 0 |
| css-fonts #missing-weights | 1 | 1 | 0 |
| css-fonts #om-fontfeaturevalues | 3 | 0 | 0 |
| css-fonts #override-color | 1 | 1 | 0 |
| css-fonts #propdef-font | 3 | 0 | 0 |
| css-fonts #propdef-font-family | 26 | 26 | 0 |
| css-fonts #propdef-font-language-override | 3 | 0 | 0 |
| css-fonts #propdef-font-optical-sizing | 3 | 0 | 0 |
| css-fonts #propdef-font-palette | 6 | 0 | 0 |
| css-fonts #propdef-font-size | 5 | 0 | 0 |
| css-fonts #propdef-font-size-adjust | 1 | 0 | 0 |
| css-fonts #propdef-font-style | 2 | 1 | 0 |
| css-fonts #propdef-font-variant | 3 | 0 | 0 |
| css-fonts #propdef-font-variant-alternates | 2 | 0 | 0 |
| css-fonts #propdef-font-variation-settings | 8 | 0 | 0 |
| css-fonts #propdef-font-weight | 5 | 4 | 0 |
| css-fonts #property-index | 1 | 0 | 0 |
| css-fonts #serializing-at-rules | 1 | 0 | 0 |
| css-fonts #size-adjust-desc | 1 | 0 | 0 |
| css-fonts #src-desc | 2 | 0 | 0 |
| css-fonts #standard-font-families | 20 | 20 | 0 |
| css-fonts #system-ui-def | 8 | 8 | 0 |
| css-fonts #the-color-property | 1 | 1 | 0 |
| css-fonts #unicode-range-desc | 3 | 2 | 1 |
| css-fonts #valdef-font-caption | 2 | 0 | 0 |
| css-fonts #valdef-font-size-adjust-ic-height | 1 | 0 | 0 |
| css-fonts #valdef-font-style-oblique-angle | 5 | 5 | 0 |
| css-fonts (no section) | 56 | 27 | 0 |
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
| css-values #:~:text=and%20always%20in%20the%20case%20of%20media%20queries | 1 | 0 | 0 |
| css-values #:~:text=reserved%20for%20them)%20unconditionally | 1 | 1 | 0 |
| css-values #absolute-lengths | 4 | 2 | 0 |
| css-values #angles | 5 | 5 | 0 |
| css-values #attr-notation | 31 | 17 | 0 |
| css-values #attr-notations | 5 | 0 | 0 |
| css-values #attr-security | 9 | 0 | 0 |
| css-values #calc-computed-value | 11 | 0 | 0 |
| css-values #calc-context | 2 | 1 | 0 |
| css-values #calc-func | 1 | 0 | 0 |
| css-values #calc-mix | 3 | 0 | 0 |
| css-values #calc-notation | 38 | 35 | 0 |
| css-values #calc-range | 6 | 3 | 0 |
| css-values #calc-serialize | 7 | 0 | 0 |
| css-values #calc-simplification | 2 | 0 | 0 |
| css-values #calc-size | 39 | 17 | 0 |
| css-values #calc-syntax | 3 | 2 | 0 |
| css-values #calc-type-checking | 13 | 1 | 0 |
| css-values #ch | 3 | 2 | 0 |
| css-values #combine-integers | 5 | 1 | 0 |
| css-values #comp-func | 30 | 3 | 0 |
| css-values #component-function-commas | 1 | 0 | 0 |
| css-values #container-queries | 1 | 0 | 0 |
| css-values #counters | 1 | 1 | 0 |
| css-values #exponent-funcs | 6 | 0 | 0 |
| css-values #font-face-load | 3 | 0 | 0 |
| css-values #font-relative-lengths | 44 | 14 | 0 |
| css-values #funcdef-attr | 1 | 0 | 0 |
| css-values #funcdef-calc | 6 | 4 | 0 |
| css-values #funcdef-clamp | 5 | 0 | 0 |
| css-values #funcdef-random-item | 8 | 0 | 0 |
| css-values #ic | 4 | 4 | 0 |
| css-values #ident | 5 | 0 | 0 |
| css-values #if-notation | 7 | 0 | 0 |
| css-values #inherit-notation | 4 | 0 | 0 |
| css-values #interpolate-size | 3 | 0 | 0 |
| css-values #lengths | 1 | 0 | 0 |
| css-values #lh | 1 | 0 | 0 |
| css-values #local-urls | 1 | 0 | 0 |
| css-values #math | 1 | 0 | 0 |
| css-values #math-function-simplify-an-expression | 1 | 0 | 0 |
| css-values #position | 3 | 0 | 0 |
| css-values #progress | 3 | 0 | 0 |
| css-values #propdef-height | 2 | 0 | 0 |
| css-values #propdef-max-height | 3 | 0 | 0 |
| css-values #propdef-max-width | 2 | 0 | 0 |
| css-values #propdef-min-height | 2 | 0 | 0 |
| css-values #propdef-min-width | 2 | 0 | 0 |
| css-values #propdef-width | 2 | 0 | 0 |
| css-values #random | 12 | 0 | 0 |
| css-values #relative-urls | 4 | 0 | 0 |
| css-values #rem | 5 | 2 | 0 |
| css-values #request-url-modifiers | 5 | 0 | 0 |
| css-values #revert-rule-keyword | 2 | 0 | 0 |
| css-values #rgba-color | 1 | 0 | 0 |
| css-values #rlh | 1 | 0 | 0 |
| css-values #round-func | 5 | 1 | 0 |
| css-values #sign-funcs | 2 | 0 | 0 |
| css-values #transparency | 1 | 0 | 0 |
| css-values #tree-counting | 24 | 0 | 0 |
| css-values #trig-funcs | 4 | 0 | 0 |
| css-values #typedef-attr-name | 3 | 2 | 0 |
| css-values #typedef-request-url-modifier-cross-origin-modifier | 23 | 6 | 0 |
| css-values #typedef-request-url-modifier-integrity-modifier | 13 | 5 | 0 |
| css-values #typedef-request-url-modifier-referrer-policy-modifier | 23 | 1 | 0 |
| css-values #url-empty | 1 | 0 | 0 |
| css-values #viewport-relative-lengths | 44 | 19 | 0 |
| css-values (no section) | 26 | 16 | 1 |
<!-- /report -->
