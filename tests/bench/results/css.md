# helder.css: tokenizing and parsing speed

`bun run test bench css` (tests/bench/CssBench.hx, tests/bench/css.mjs),
2026-11-26, a MacBook (darwin-arm64) shared with other builds at the
time (load average 7 to 16). MB/s of each sheet's bytes, the least of 10
to 15 runs after a warm-up. Of five runs this is the quietest; how the
others went is below the table.

| sheet | KB | native: tokens | native: sheet | wasm32-wasi: tokens | wasm32-wasi: sheet | lightningcss 1.33.0 (napi): parse + print |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| bootstrap.css | 274 | 175 MB/s | 105 MB/s | 137 MB/s | 86 MB/s | 39 MB/s |
| tailwind.css | 3557 | 95 MB/s | 58 MB/s | 88 MB/s | 48 MB/s | 43 MB/s |
| bulma.css | 745 | 196 MB/s | 97 MB/s | 163 MB/s | 110 MB/s | 53 MB/s |
| primer.css | 728 | 193 MB/s | 131 MB/s | 158 MB/s | 106 MB/s | 47 MB/s |
| foundation.css | 164 | 149 MB/s | 100 MB/s | 121 MB/s | 77 MB/s | 50 MB/s |
| fontawesome.css | 130 | 157 MB/s | 105 MB/s | 111 MB/s | 71 MB/s | 43 MB/s |
| animate.css | 93 | 142 MB/s | 99 MB/s | 97 MB/s | 66 MB/s | 65 MB/s |

Across the five runs each side moved by up to a factor of two with the
load:

- In four of them, helder.css's native sheet was ahead of lightningcss's
  parse + print on every sheet.
- In one, lightningcss ran faster than in the others (63 MB/s on
  bootstrap, 54 on tailwind). It came out ahead of the native sheet on
  tailwind (46) and of the wasm sheet on bootstrap (59).
- The wasm sheet was behind lightningcss on tailwind in two runs (22 and
  27 MB/s against 33 and 32).

What each side does:

- **helder.css tokens**: Syntax 3's tokenizer alone (`Css.tokens`).
- **helder.css sheet**: tokenized and parsed into rules, declarations
  and component values (`Css.sheet`). No property grammar is applied:
  a declaration's value stays component values.
- **lightningcss parse + print**: its JavaScript API has no parse-only
  call, so this is `transform` with minify off, no targets and error
  recovery on. It parses every known property into typed values and
  prints the sheet back, both in the time. Its parse alone (the Rust
  crate's `StyleSheet::parse`) needs a Rust toolchain, which this Mac
  has not.

So the comparison is not like for like. lightningcss does more per byte
(typed values, then printing); helder.css's sheet is the syntax layer
the values layer will build on.

## Where the time goes, and why no kernel or SIMD scan

On tailwind.css (3.6 MB, 945,852 tokens), natively:

- A bare scan of the String (`fastCodeAt` over every unit) takes 3.4 ms.
- Making 945,852 `CssToken`s with no value takes 21 ms; with a 4-unit
  substring each, 49 ms.
- `Css.tokens` takes 45 to 60 ms (across runs).

Tokenizing is allocation-bound: the tokens, their kinds' values and
their strings, not the scan. An `@:hxmc.kernel` or `hxmc.simd` scan of
ident, whitespace, string or comment runs could save at most the 3.4 ms
scan (about 6%). It would also need the text as a byte span, which a
String is not (hxmc stores a String's units one or two bytes wide). I
tried interning plain idents (one String per name per sheet, matched
while scanning): no gain within the noise. So none of these went in.

The parse phase is allocation too (a `Token` value per token, arrays per
block). Fewer allocations would be the lever: a flat token tape (kinds
and offsets in arrays, strings on demand) would change the API.
