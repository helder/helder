# pdf-docs

Real-world documents through `helder pdf`, against their goldens and
against WeasyPrint, the print tier's parity target:

- `invoice.html`: a flex header, an items table, totals, "Page n of N".
- `report.html`: a title page, contents with leaders and
  `target-counter()`, running heads, bookmarks.
- `long-table.html`: 120 rows across pages, the header and footer
  repeated.
- `chapter.html`: A5, left and right page heads, justified text,
  endnotes.
- `floats.html`: figures floated left and right.
- `cv.html`: grid columns, flex-wrapped tags.

All of them use DejaVu 2.37 (`fonts.css`, from bin/fonts:
`node tests/css/import-wpt.mjs --checkout`), so both engines use the
same font files.

`bun run test pdf-docs` writes bin/pdf-docs/<name>.pdf and checks each
page, rasterised by helder.pdf at 96 dpi, against `goldens/`
(`BLESS=1` takes them). Where `bin/pdf-docs/<name>.weasyprint.pdf` is
there too, it compares the two page by page:

- a pixel differs when a channel is off by more than 48;
- the diff images (`bin/pdf-docs/diff`) show alike pixels in grey,
  helder's ink in red and WeasyPrint's in blue;
- the similarities go to `bin/pdf-docs/similarity.md`.

CI's advisory pdf-docs job makes WeasyPrint's PDFs and uploads all of it
as the `pdf-docs` artifact. To compare locally, copy its
`*.weasyprint.pdf` files into bin/pdf-docs.

## Differences kept

- `leader(dotted)` is the spec's `". "` (GCPM 3), a dot and a space.
  WeasyPrint's dots are denser.
- `font-size: smaller` (`<small>`) takes the spec's and Chromium's step
  down the keyword table, so it comes out a little smaller than
  WeasyPrint's ratio of 1/1.2.
