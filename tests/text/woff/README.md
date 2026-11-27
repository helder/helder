# WOFF and WOFF2 fixtures

What `src/helder/text/Woff.test.hx` reads, each against the font it was
made from (`make.py` writes them all again, with fontTools and brotli):

- `inter.woff`, `inter.woff2`, `inter-hmtx.woff2` (hmtx transformed too):
  `src/helder/text/fonts/Inter.ttf` (SIL Open Font License 1.1:
  `src/helder/text/fonts/Inter-OFL.txt`).
- `dejavu-cff.woff`, `dejavu-cff.woff2`: `tests/canvas/fonts/DejaVuSans-pdf.otf`
  (DejaVu's licence: `tests/canvas/fonts/README.md`).
- `ahem.woff2`: `tests/flow/fixtures/Ahem.ttf` (WPT's Ahem, public domain).
- `opensans-latin.woff2`: Google Fonts' Open Sans 400, its Latin subset
  as fonts.gstatic.com serves it (v44, Google's encoder), and
  `opensans-latin.ttf`, fontTools' sfnt of it: the reference (SIL Open
  Font License 1.1: `OpenSans-OFL.txt`).
- `pair.woff2`: a collection of `tests/text/coretext/Inter-Bold-subset.ttf`
  and `tests/canvas/fonts/DejaVuSans-pdf.ttf` (fontTools writes no WOFF2
  collection: make.py joins two of its files).
