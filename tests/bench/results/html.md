# HTML parsing (helder.dom)

`bun run test bench html`, 2026-11-26, an Apple M4 laptop shared with
other sessions' builds (load averages of 9 to 200 over the day: times vary
by up to 2x run to run, so a comparison is made interleaved, each number
the least of 10 runs). The inputs: the HTML Standard as one page (16 MB,
much of it tables and references), a long Wikipedia article (World War
II, 2.1 MB, attribute-heavy) and a generated document (6.5 MB: 5,000 nested
divs, then 50,000 paragraphs with attributes, references and inline
markup).

| parser | html-spec (16.0 MB) | wikipedia (2.1 MB) | generated (6.5 MB) |
|---|---|---|---|
| helder (native) | 163 ms, 98.2 MB/s | 7.3 ms, 288.2 MB/s | 103 ms, 63.2 MB/s |
| helder (wasm32-wasi, node) | 180 ms, 88.8 MB/s | 10.0 ms, 208.8 MB/s | 135 ms, 48.0 MB/s |
| @lukeed/html (node) | 105 ms, 153.0 MB/s | 5.7 ms, 366.7 MB/s | 45 ms, 143.5 MB/s |
| lexbor (C, -O2) | 98 ms, 164.1 MB/s | 8.0 ms, 262.5 MB/s | 70 ms, 92.7 MB/s |

@lukeed/html is the fastest JavaScript parser but not a conformant one:
it recovers from bad markup its own way (as htmlparser2 does: no implied
elements, no adoption agency, no foster parenting), so its trees differ
from a browser's. lexbor follows the standard's algorithm, in C with its
own arenas.

## Against lexbor, interleaved

The build before the speed work (helder.dom as first merged), the build
after it and lexbor, in turn, 4 rounds of 10 runs each, the least
(natively; one load for all three):

| | html-spec | wikipedia | generated |
|---|---|---|---|
| before | 420 ms | 27.5 ms | 279 ms |
| after | 216 ms | 9.1 ms | 151 ms |
| lexbor | 124 ms | 9.4 ms | 89 ms |
| after / lexbor | 1.74 | 0.97 | 1.69 |

What took it there, each change against the build before it (interleaved,
least of runs; each row's numbers measured together, at that row's load):

| change | html-spec | wikipedia | generated |
|---|---|---|---|
| nodes' views (childNodes, children, attributes, classList, a disconnected node's order) in one object made on demand; attributes kept as the parser's spans (five ints each, no Attr node or string until read) | 374 to 298 ms | 23 to 14 ms | 294 to 194 ms |
| text runs as spans (no substring for a run of the source), an ordinary tag read in one pass, a cheaper name hash, the formatting list's check from the top, a parser's insert without adopt's checks | 292 to 178 ms | 20 to 9.0 ms | 222 to 137 ms |
| one shared token for a formatting element without attributes, an attribute's name looked up when it is read | 249 to 147 ms | 17 to 8.1 ms | 192 to 132 ms |
| a text with references kept as its span too (decoded when read), the dispatcher's common case inline | 425 to 240 ms (lexbor 152) | 27 to 12 ms | 311 to 174 ms |

Before, from the first conformant version (each the least of the runs at
the time): open-element counts, interned tag names, buffer-free
references and reused tag tokens took 1,538 / 210 / 2,272 ms to 808 / 42 /
637; names read from the input without a copy to 474 / 28 / 376; the SIMD
kernel for text, attribute values and comments was then faster than the
scalar loop on all three.

## Where the time goes now

macOS' sample on a -debug build, grouped:

| | tokenizer | tree builder | collector | DOM | runtime |
|---|---|---|---|---|---|
| html-spec | 34% | 25% | 26% | 8% | 4% |
| wikipedia | 57% | 20% | 9% | 9% | 3% |

The collector was about 40% before the spans (an Attr node and a string an
attribute, a string a text run). What is left of it is the nodes
themselves: every Element and Text survives the parse, copied once out of
the nursery. The tokenizer's share is mostly the one-pass tag reader (14%
and 30%): each code unit read through StringTools.fastCodeAt, which tests
the string's representation (one byte a unit or two) each time.

## hxmc's API

`Scan.hx`, the kernel finding a run's end, reads the string through
hxmc.rt.StrView (`isOne`, `units1`, `units2`): the runtime's own view,
checked spans as long as the string, lent for the kernel's call, the same
its String.indexOf kernel uses. No hxmc.unsafe is used. What a public API
would need, so that code outside hxmc.rt can do the same:

- in a kernel, a string's units as a read-only span: whether it is stored
  a byte a unit, then a `ReadOnlySpan<UInt8>` or `ReadOnlySpan<UInt16>` of
  its units, bounds checked, valid for the call (the string lent: nothing
  collects or moves it meanwhile), never writable;
- or, without kernels, `indexOfAny(s, from, to, a, b, c, d)` on String:
  the first index of one of up to four units, SIMD in the runtime, which
  covers every use here (text, attribute values, comments);
- and, for the tag reader, a span over a string's units usable outside a
  kernel (each read checked, no representation test a unit), which would
  take its per-unit cost down.
