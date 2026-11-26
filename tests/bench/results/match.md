# helder.css: selector matching, before and after the index

`bun run test bench match` (tests/bench/MatchBench.hx, tests/bench/match.mjs),
2026-11-26, natively on a MacBook (darwin-arm64) shared with other
builds (load average 6 to 10). Every element of each page against every
selector of its own sheets, Chromium's UA sheet (html.css at 130.0.6723.58)
and Bootstrap 5.3.3. The pages and their sheets are fetched live (not
pinned): the HTML Standard as one page with its four sheets, and the
Wikipedia article on World War II with its two `load.php` sheets.

| page | elements | selectors | each selector | index | index and Bloom filter |
| --- | ---: | ---: | ---: | ---: | ---: |
| HTML Standard | 341,289 | 3,959 | 49,900 ms | 3,868 ms | **718 ms** |
| Wikipedia | 16,803 | 5,176 | 2,538 ms | 477 ms | **41 ms** |

What each way tries (selectors matched in full, of all element and selector pairs):

| page | each selector | index | index and Bloom filter | rejected by the filter |
| --- | ---: | ---: | ---: | ---: |
| HTML Standard | 1,351,163,151 (100%) | 50,489,401 (3.7%) | 13,751,096 (1.0%) | 36,738,305 (72.8% of the index's candidates) |
| Wikipedia | 86,972,328 (100%) | 2,081,804 (2.4%) | 425,147 (0.5%) | 1,656,657 (79.6% of the index's candidates) |

- **each selector**: every selector tried on every element; CssMatcher
  fails fast on the rightmost compound, but there are 1.35 billion pairs
  on the HTML Standard. Run once.
- **index**: `CssRuleIndex.matching`, each element only visiting its
  buckets (its id's, classes', tag's, attributes', the universal one).
  The least of 5.
- **index and Bloom filter**: `CssRuleIndex.walk`, the ancestors' counting
  filter pushed and popped during the walk, rejecting a selector whose
  ancestor ids, classes and types are not all there before matching it.
  The least of 5.

The matches (3,133,696 and 187,673) are the same every way, or the bench
fails. Its first run did fail: the filter's ancestor hashes then included
compounds a sibling combinator follows (the `p` of `p + * > li`, a sibling
of the li's parent), so it rejected 26,361 matches on the HTML Standard.
The hashes now come only from compounds a child or descendant combinator
follows, as WebKit collects them, and a unit test covers that case.

The cascade (CssStyles) now uses the same index and filter. It meets
elements lazily, in any order, so `CssBloom.moveTo(el)` keeps the
ancestors shared with the last element and pops and pushes the rest.
