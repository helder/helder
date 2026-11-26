# helder.css: restyling a viewer's rows

`bun run test bench row` (tests/bench/RowBench.hx), 2026-11-26, natively
on a MacBook (darwin-arm64) shared with other builds (load average about
8). A list of 12 rows of 18 elements each (an icon, a name and its line
under, four facts, three buttons): 220 elements with the document's.

The sheet is the viewer's kind: rows and their hover, focus-within and
selected states, the row's parts, siblings' borders (`.row + .row`,
`:nth-child(odd)`), buttons' `:hover`, `:active` and `:focus-visible`,
and one `.list:has(.selected) .row`.

Each operation is the DOM's change, then the restyle: the elements
CssRestyle marks are let go (`CssStyles.forget`) and styled again. That
goes through the style-sharing cache, the rule index and Bloom filter,
and the cascade. Beside it is the same change with every element styled
again by a cascade without the sharing cache (no invalidation). The
least of 200 runs, in microseconds, 2026-11-26, load average about 5.

| operation | restyle (marked, shared) | every element again, no sharing cache |
| --- | ---: | ---: |
| 12 more rows made in the styled list | **149 µs** (436, 396 shared) | 225 µs (436) |
| a row hovered | **55 µs** (18, 6 shared) | 147 µs (220) |
| a row unhovered | **16 µs** (18, 6 shared) | 106 µs (220) |
| a button focused (focus, focus-visible; focus-within up to the root) | **68 µs** (18, 4 shared) | 156 µs (220) |
| a row selected (its class) | 174 µs (220, 156 shared) | 206 µs (220) |

- **Rows made**: the list's subtree is marked, all 436 elements, since
  the sheet counts siblings (`.row + .row`, `:nth-child(odd)`). 396 of
  them take a sibling's or cousin's style without matching. The rest
  costs both columns alike: the sheet's `.list:has(.selected) .row` is
  matched for each row, once per element through the `:has()` cache
  (CssHasCache) in both. Before that cache the column read 300 µs
  against 367 µs. A cascade made afresh costs more in both, because the
  first row's styles are worked out from nothing.
- **Hovered, unhovered, focused**: the row's subtree alone, through
  #337's guards. A hover's first styles are worked out (55 µs), and
  unhovering goes back to styles made before (16 µs).
- **Selected**: `.list:has(.selected) .row` puts the class inside
  `:has()`, and anything inside `:has()` restyles the document, as
  documented.

The first version of this bench (#337) timed matching alone, without the
cascade: a hover 17 µs against 146 µs.
