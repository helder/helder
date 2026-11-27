# helder.compress

Decompression in pure Haxe, for untrusted input.

- `Brotli`: RFC 7932, in one go. `Brotli.exact(data, pos, len, size)`
  decodes a stream of exactly `size` bytes (WOFF2's tables);
  `Brotli.all(data, budget)` one of any size up to `budget`. Every
  count, length and distance is checked and a code that is not a complete
  prefix code is refused, so a damaged stream throws `Brotli: ...`: never
  a loop, a read past the input or memory past the bound. As the
  reference decoder does, it refuses a stream cut short, padding bits set
  and data after the stream. The static dictionary (`dictionary.bin`,
  122,784 bytes, RFC 7932's SHA-256) is built in with `Asset.embed`;
  `BrotliTables.hx` holds the context lookup table and the 121 word
  transforms. Both are written by `generate.mjs` from the brotli
  reference at a pinned revision (MIT, `LICENSE-brotli.txt`).
- Speed: natively, about 2.5 times the reference C decoder (a 92 KB
  WOFF2's stream in 2.8 ms, the C one's 1.1 ms on an M4).
- Tests: `Brotli.test.hx`, against the reference's test vectors
  (tests/compress/brotli) and as a fuzz property.

Deflate's inflate is `helder.image.Inflate` (PNG, zip, PDF and WOFF use
it).
