# CSS tests

helder.css's checks, against cases of
[web-platform-tests](https://github.com/web-platform-tests/wpt) read
statically, natively:

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
  reftest-wait, images, SVG, XML); out, each with why. Out: testharness.js
  tests and those with a script (no JavaScript), manual and `interact`
  ones, visual ones (no reference), flags past a page (`animated`,
  `history`, `userstyle`, `http`, `scroll`), and those of deferred features
  (multicol, writing modes, footnotes, `@layer`, `@container`, shapes,
  regions, forms, 3D transforms), by their help links or their CSS.
- `CssCheck.hx`: the lane. values.json's properties are the table's, every
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

## Report

<!-- report -->
At WPT bc5ea7a9006b, made by import-wpt.mjs.

### Values

44341 calls of the helpers read in 97 directories of css/ (a loop's items and a helper's calls each one); 19280 rows for 213 in-scope properties from 725 files (336 duplicates dropped), 17527 calls on 424 properties out of scope (most: position-area 2925, filter 365, clip-path 341, shape-outside 271, backdrop-filter 260, offset-path 208, font-palette 180, will-change 171), and 295 not read statically:

| Why not read | Calls |
| --- | --- |
| a name not bound to a literal | 262 |
| in a helper | 19 |
| a loop over what it can't read | 14 |

| Module | Properties | Valid | Invalid | Computed | Shorthand | Inherits |
| --- | --- | --- | --- | --- | --- | --- |
| css-align-3 | 15 | 245 | 242 | 240 | 22 | 12 |
| css-backgrounds-3 | 48 | 489 | 729 | 485 | 43 | 32 |
| css-box-3 | 10 | 97 | 75 | 26 | 8 | 8 |
| css-break-3 | 6 | 35 | 18 | 37 | 0 | 6 |
| css-cascade-4 | 1 | 3 | 7 | 0 | 0 | 0 |
| css-color-4 | 2 | 2028 | 1113 | 7707 | 0 | 2 |
| css-content-3 | 4 | 88 | 113 | 62 | 0 | 3 |
| css-display-3 | 2 | 117 | 57 | 117 | 0 | 2 |
| css-flexbox-1 | 8 | 103 | 77 | 88 | 28 | 6 |
| css-fonts-4 | 26 | 322 | 321 | 233 | 0 | 19 |
| css-grid-1 | 15 | 375 | 338 | 424 | 60 | 10 |
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

10897 tests (references and support files left out), 6063 in scope:

| Suite | Tests | In scope | Of them Ahem | Of them print |
| --- | --- | --- | --- | --- |
| css/CSS2 | 9208 | 5795 | 1181 | 43 |
| css/css-page | 283 | 203 | 9 | 202 |
| css/css-break | 1386 | 65 | 4 | 61 |
| css/css-gcpm | 20 | 0 | 0 | 0 |

| Out of scope because | Tests |
| --- | --- |
| visual: no reference (a golden blessed by eye could gate it) | 2907 |
| deferred: multicol | 1175 |
| script: needs JavaScript | 401 |
| testharness.js: needs JavaScript | 156 |
| deferred: writing-mode (its help) | 81 |
| deferred: writing-mode | 71 |
| http: needs an HTTP server's headers | 26 |
| deferred: @layer | 4 |
| interact: needs a person | 3 |
| deferred: 3D transforms | 3 |
| deferred: ruby (its help) | 3 |
| deferred: forms | 2 |
| userstyle: needs a user style sheet set by hand | 1 |
| deferred: multicol (its help) | 1 |

By directory (CSS2: its chapters; the others: their sections, from the first `<link rel=help>`):

| Directory or section | Tests | In scope |
| --- | --- | --- |
| CSS2 (top level) | 16 | 5 |
| CSS2/abspos | 33 | 25 |
| CSS2/backgrounds | 625 | 333 |
| CSS2/bidi-text | 108 | 34 |
| CSS2/borders | 762 | 504 |
| CSS2/box | 9 | 9 |
| CSS2/box-display | 139 | 86 |
| CSS2/cascade | 101 | 31 |
| CSS2/cascade-import | 19 | 1 |
| CSS2/colors | 22 | 19 |
| CSS2/css1 | 262 | 164 |
| CSS2/css21-errata | 9 | 9 |
| CSS2/csswg-issues | 3 | 3 |
| CSS2/floats | 163 | 113 |
| CSS2/floats-clear | 249 | 203 |
| CSS2/fonts | 324 | 159 |
| CSS2/generate | 17 | 0 |
| CSS2/generated-content | 316 | 205 |
| CSS2/i18n | 57 | 0 |
| CSS2/linebox | 250 | 192 |
| CSS2/lists | 286 | 155 |
| CSS2/margin-padding-clear | 740 | 683 |
| CSS2/media | 17 | 17 |
| CSS2/normal-flow | 868 | 696 |
| CSS2/other-formats | 4 | 0 |
| CSS2/page-box | 36 | 0 |
| CSS2/pagination | 103 | 43 |
| CSS2/positioning | 579 | 513 |
| CSS2/sec5 | 28 | 23 |
| CSS2/selectors | 552 | 467 |
| CSS2/stacking-context | 7 | 3 |
| CSS2/syntax | 280 | 252 |
| CSS2/tables | 1140 | 250 |
| CSS2/text | 564 | 377 |
| CSS2/ui | 239 | 52 |
| CSS2/values | 26 | 25 |
| CSS2/visudet | 41 | 38 |
| CSS2/visufx | 104 | 50 |
| CSS2/visuren | 57 | 26 |
| CSS2/zindex | 52 | 29 |
| CSS2/zorder | 1 | 1 |
| css-break #abspos-breaking | 96 | 0 |
| css-break #box-splitting | 30 | 0 |
| css-break #break-between | 5 | 0 |
| css-break #break-decoration | 64 | 3 |
| css-break #break-margins | 7 | 1 |
| css-break #break-propagation | 9 | 0 |
| css-break #break-within | 5 | 3 |
| css-break #breaking-controls | 2 | 0 |
| css-break #breaking-rules | 11 | 0 |
| css-break #end-block | 1 | 0 |
| css-break #flex-containers | 1 | 0 |
| css-break #forced-breaks | 6 | 0 |
| css-break #fragmentation | 34 | 0 |
| css-break #fragmentation-model | 20 | 0 |
| css-break #grid-axis-pagination | 1 | 0 |
| css-break #issuecomment-951767882 | 12 | 0 |
| css-break #legacy-shorthand | 1 | 0 |
| css-break #monolithic | 6 | 0 |
| css-break #overflow-properties | 2 | 0 |
| css-break #page-break-values | 2 | 2 |
| css-break #pagination | 531 | 27 |
| css-break #parallel-flows | 26 | 2 |
| css-break #possible-breaks | 20 | 3 |
| css-break #propdef-box-decoration-break | 3 | 0 |
| css-break #propdef-break-after | 3 | 0 |
| css-break #propdef-break-before | 3 | 0 |
| css-break #propdef-break-inside | 3 | 0 |
| css-break #propdef-orphans | 3 | 0 |
| css-break #propdef-widows | 3 | 0 |
| css-break #property-index | 1 | 0 |
| css-break #repeated-headers | 18 | 0 |
| css-break #transforms | 25 | 0 |
| css-break #unforced-breaks | 24 | 0 |
| css-break #valdef-box-decoration-break-slice | 5 | 0 |
| css-break #varying-size-boxes | 5 | 0 |
| css-break #widows-orphans | 28 | 0 |
| css-break (no section) | 370 | 24 |
| css-gcpm #dotted-leader | 1 | 0 |
| css-gcpm #setting-named-strings-the-string-set-pro | 12 | 0 |
| css-gcpm #solid-leader | 1 | 0 |
| css-gcpm #string-first | 1 | 0 |
| css-gcpm #string-first-except | 1 | 0 |
| css-gcpm #string-last | 2 | 0 |
| css-gcpm #string-leader | 1 | 0 |
| css-gcpm #string-start | 1 | 0 |
| css-page #at-page-rule | 16 | 11 |
| css-page #at-page-rules | 1 | 0 |
| css-page #background-image | 1 | 0 |
| css-page #cascading-and-page-context | 3 | 3 |
| css-page #descdef-page-size | 1 | 0 |
| css-page #first-pseudo | 4 | 4 |
| css-page #layering | 4 | 0 |
| css-page #margin-at-rules | 2 | 0 |
| css-page #margin-dimension | 18 | 14 |
| css-page #margin-property-list | 1 | 0 |
| css-page #margin-text-alignment | 1 | 1 |
| css-page #media1 | 1 | 1 |
| css-page #page-based-counters | 10 | 10 |
| css-page #page-box-page-rule | 1 | 0 |
| css-page #page-break-props | 1 | 0 |
| css-page #page-breaks | 4 | 4 |
| css-page #page-margin-safety | 1 | 1 |
| css-page #page-model | 2 | 2 |
| css-page #page-orientation-prop | 8 | 5 |
| css-page #page-properties | 29 | 23 |
| css-page #page-selectors | 2 | 0 |
| css-page #page-size | 3 | 0 |
| css-page #page-size-prop | 14 | 5 |
| css-page #painting | 6 | 4 |
| css-page #populating-margin-boxes | 4 | 2 |
| css-page #possible-breaks | 3 | 3 |
| css-page #spread-pseudos | 2 | 2 |
| css-page #syntax-page-selector | 2 | 0 |
| css-page #the-csspagerule-interface | 6 | 0 |
| css-page #typedef-page-size-page-size | 2 | 0 |
| css-page #using-named-pages | 52 | 44 |
| css-page #valdef-position-fixed | 2 | 1 |
| css-page (no section) | 76 | 63 |
<!-- /report -->
