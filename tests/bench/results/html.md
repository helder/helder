# HTML parsing (helder.dom)

`bun run test bench html`, 2026-11-26, an Apple M4 laptop shared with
other sessions' builds (load averages of 30 to 200: the times vary by up
to 2x run to run; each number the least of 10 runs). The inputs: the HTML
Standard as one page (16 MB, much of it tables and references), a long
Wikipedia article (World War II, 2.1 MB, attribute-heavy) and a generated
document (6.5 MB: 5,000 nested divs, then 50,000 paragraphs with
attributes, references and inline markup).

| parser | html-spec (16.0 MB) | wikipedia (2.1 MB) | generated (6.5 MB) |
|---|---|---|---|
| helder (native) | 636 ms, 25.2 MB/s | 36 ms, 58.2 MB/s | 364 ms, 17.9 MB/s |
| helder (wasm32-wasi, node) | 848 ms, 18.9 MB/s | 37 ms, 56.2 MB/s | 603 ms, 10.8 MB/s |
| @lukeed/html (node) | 147 ms, 108.9 MB/s | 9 ms, 233.2 MB/s | 72 ms, 90.7 MB/s |
| lexbor (C, -O2) | 145 ms, 110.2 MB/s | 8 ms, 262.5 MB/s | 153 ms, 42.3 MB/s |

@lukeed/html is the fastest JavaScript parser but not a conformant one:
it recovers from bad markup its own way (as htmlparser2 does: no implied
elements, no adoption agency, no foster parenting), so its trees differ
from a browser's. lexbor follows the standard's algorithm, in C with its
own arenas.

How helder got there (natively, the least of each change's runs at the time):

| change | html-spec | wikipedia | generated |
|---|---|---|---|
| first conformant version | 1,538 ms | 210 ms | 2,272 ms |
| a count of open elements a tag (a scope check of a tag none is open of: no walk), the token's tag id kept, tag tokens reused | 808 ms | 42 ms | 637 ms |
| tag and attribute names the parser knows read straight from the input (no copy, no hash), character references without a buffer | 474 ms | 28 ms | 376 ms |
| text runs, attribute values and comments found by a SIMD kernel (Scan.hx), against the same code scanning a unit at a time | 813 / 827 ms | 31 / 45 ms | 569 / 609 ms |

(The last row's pairs were measured at a busier moment than the rows
above it: what matters is each pair, the kernel against the scalar loop,
interleaved on the same load.)

Where the time goes now (macOS' sample on a -debug build, the Wikipedia
article): the collector about 40% (every node a parse makes survives it:
copied once out of the nursery), the tokenizer's state machine about 25%,
substrings for text and attribute values 5%, the rest the tree builder.
No hxmc.unsafe is used: the kernel reads the string through
hxmc.rt.StrView's checked spans. Next, if it is wanted: fewer objects a
node (an element's attributes made Attr nodes only when asked for:
@lukeed/html reads attributes and text, and decodes their references,
only when they are read).
