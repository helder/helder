# helder.css: the cascade on the HTML Standard

`bun run test bench cascade` (tests/bench/CascadeBench.hx), 2026-11-26,
natively on a MacBook (darwin-arm64) shared with other builds (load
average 3 to 6). The HTML Standard as one page: 341,289 elements, its
four sheets and the user agent's.

| | styles (every element's) | shared before matching | after matching | worked out | per element |
| --- | ---: | ---: | ---: | ---: | ---: |
| before the sharing cache (#339; one run, parse 116 ms) | 554 ms | 0 | 339,320 | 1,969 | 1.62 µs |
| with it (least of 5, parse 98 ms) | **238 ms** | 235,786 | 103,534 | 1,969 | 0.70 µs |

- **Shared before matching** (the style-sharing cache, CssStyles): an
  element takes one of the 32 elements styled last's style without being
  matched. The candidate must be a sibling, or a cousin whose parent is
  that one's twin. The tag, classes, the attributes selectors read, the
  state and the hints must be the same, and it must have no id a
  selector names. Its non-local selectors (positional, siblings',
  `:has()`) are matched again (Stylo's revalidation).
- **After matching**: the cascade's existing share, an element whose
  matched rules and parent style are an earlier one's.
- **Worked out**: the cascade resolved and the groups interned.

Parity in the same run: every element's display, margin-top, color and
font-size, and every 37th's every longhand (3,191,706 values). They
match against #321's cascade, frozen in tests/css/reference, with 0
differences, and against the same cascade without the cache
(`share: false`), with 0 differences.

How the cache got there, measured on this page:

| step | shared | styles |
| --- | ---: | ---: |
| an id bars sharing; no candidate that tried a non-local selector | 49,420 | 442 ms |
| an id no selector names may share; `[attr]` and `:link` read presence, not values | 105,232 | 429 ms |
| non-local selectors revalidated instead of barring the candidate | 222,756 | 299 ms |
| 32 candidates, not 16 | 235,786 | 244 ms |

The non-local selectors barring most of the page were its own sheet's,
in the universal bucket: `.example > :first-child`, `.domintro >
:last-child`, `.mdn-anno … span:first-of-type`, each tried on every
element inside those blocks. A 64-entry cache gave 233 ms, within noise
of 32.
