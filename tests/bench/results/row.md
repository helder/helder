# helder.css: restyling a viewer's rows

`bun run test bench row` (tests/bench/RowBench.hx), 2026-11-26, natively
on a MacBook (darwin-arm64) shared with other builds (load average about
8). A list of 12 rows of 18 elements each (an icon, a name and its line
under, four facts, three buttons): 220 elements with the document's.

The sheet is the viewer's kind: rows and their hover, focus-within and
selected states, the row's parts, siblings' borders (`.row + .row`,
`:nth-child(odd)`), buttons' `:hover`, `:active` and `:focus-visible`,
and one `.list:has(.selected) .row`.

Each operation is the DOM's change and then the restyle: the elements
CssRestyle marks, matched again through the rule index and Bloom filter.
Beside it is the same change with every element matched again (no
invalidation). The least of 200 runs, in microseconds.

| operation | restyle (marked) | every element matched again (220) |
| --- | ---: | ---: |
| the rows made (createElement, appendChild) | 183 µs (220) | 159 µs |
| a row hovered | **17 µs (18)** | 146 µs |
| a row unhovered | **17 µs (18)** | 144 µs |
| a button focused (focus, focus-visible; focus-within up to the root) | **18 µs (18)** | 145 µs |
| a row selected (its class) | 127 µs (220) | 129 µs |

- **Hovered, unhovered, focused**: the row's subtree alone. Focus sets
  `:focus-within` on the button's ancestors up to `<html>`, and the
  guards (a feature's compound's other ids, classes and tag) skip the
  list, body and html: none is a `.row`. Before the guards, focusing
  marked all 220 (158 µs).
- **Selected**: `.list:has(.selected) .row` puts the class inside
  `:has()`, and anything inside `:has()` restyles the document, as
  documented. Without that rule the change marks the row alone.
- **Made**: every new element needs a style, so the marks cost a little
  over matching everything (the tracker's marks and their read-out).
