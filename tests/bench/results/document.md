# The CSS engine live in a window (bench document)

`bun run test bench document`: tests/bench/DocumentBench.hx natively,
each frame drawn by the GPU renderer offscreen and read back (DrawFrame,
Metal), median and least of runs; Chromium through Playwright on the same
pages (tests/bench/document.mjs). One run, 2026-11-27, a shared Mac
(M-series, other sessions busy): numbers move by up to 2×. The engine's
own work (DocumentNode.stats: restyle, layout, paint recording) is apart
from the frame. These are the numbers before the speed work (the PRs
after this one); the memory figures and a quiet-Mac run are owed.

## Engine against helder.ui today, same screens

examples/todo and examples/mail, mounted in helder.ui, mirrored as
helder.dom trees styled by src/helder/css/ua/app.css (AppUaCheck's
mirror, :hover looks as rules), 20 rows, then 1,020. Frame ms, median
(least) of the frames; the Mac's load 5–6 (not quiet: owed again).

### After the layout cache keeps a few layouts per box (speed PR 1)

| todo | helder.ui | engine | engine: update (restyle + relayout) / draw (paint + renderer + GPU) |
| --- | ---: | ---: | ---: |
| first frame (20 rows) | 4.0 (least) | 12.2 (9.8) | 8.5 / 5.3 |
| scroll the list (1,020 rows) | 2.6 | 3.9 | 0.6 / 3.3 |
| hover over rows | 2.5 | 3.3 | 0.6 / 2.7 |
| type into a field | 2.4 | 6.5 (5.8) | 3.0 / 3.6 |
| resize, two widths in turn | 7.4 | 5.9 | 2.6 / 3.3 |
| drag-resize, a new width each frame | 7.5 | 31.9 (27.4) | 28.3 / 3.5 |
| add 1,000 rows | 34.7 | 110 (94) | 106 / 3.8 |

| mail | helder.ui | engine | engine: update / draw |
| --- | ---: | ---: | ---: |
| first frame (20 rows) | 4.4 (least) | 10.7 (7.9) | 7.9 / 2.7 |
| scroll the list | 2.8 | 4.0 | 0.4 / 3.5 |
| hover over rows | 2.7 | 3.9 | 0.5 / 3.4 |
| type into a field | 2.4 | 5.3 | 1.8 / 3.5 |
| resize, two widths in turn | 2.0 | 5.2 | 1.7 / 3.5 |
| drag-resize | 2.0 | 5.7 | 2.0 / 3.7 |
| add 1,000 rows | 34.6 | 152 (135) | 147 / 5.1 |

### Before the speed work (#452's first run)

| todo | helder.ui frame ms | engine frame ms | engine's own: style + layout + paint |
| --- | ---: | ---: | ---: |
| first frame (20 rows) | 5.3 | 21.6 | 0 + 16.6 + 0.4 |
| scroll the list (1,020 rows) | 2.8 | 5.0 | 0 + 0 + 1.0 |
| hover over rows | 2.7 | 4.6 | 0 + 0 + 0 |
| type into a field | 2.7 | 382 | 378 (relayout) + 0 + 1.1 |
| resize the window | 9.1 | 413 | 0 + 408 + 1.2 |
| add 1,000 rows | 33 | 279 | 268 + 0 + 0.8 |

| mail | helder.ui frame ms | engine frame ms | engine's own |
| --- | ---: | ---: | ---: |
| first frame (20 rows) | 3.4 | 34.3 | 0 + 30.3 + 0.2 |
| scroll the list | 2.3 | 4.5 | 0 + 0 + 0.7 |
| hover over rows | 2.4 | 4.3 | 0 + 0 + 0.6 |
| type into a field | 2.2 | 1,404 | 1,400 (relayout) |
| resize the window | 2.0 | 1,573 | 0 + 1,568 + 0.8 |
| add 1,000 rows | 35 | 1,584 | 1,567 |

Binary size (macOS arm64 / wasm32-wasi): examples/todo 4.9 MB / 3.6 MB;
the same screen as DOM + CSS through the engine (tests/bench/document/
TodoDocument.hx) 8.0 MB / 6.3 MB.

## Engine against Chromium on documents (1024×768)

| page | operation | helder frame ms | helder's engine | Chromium main thread ms |
| --- | --- | ---: | ---: | ---: |
| sample (87 elements) | load to the first frame | 22 | 9 layout + 5.6 paint | 35 (to a frame after load) |
| | scroll 100 px | 2.6 | 0 | 0.26 |
| | hover links | 2.6 | 0.16 | 0.55 |
| | resize 1024 ↔ 900 | 5.7 | 0.45 + 2.1 | 2.6 |
| Wikipedia, World War II (16,803 elements) | load | 548 | 514 layout | 277 (FCP 188) |
| | hover links | 8.7 | 1.8 | 1.2 |
| | resize | 330 | 315 layout | 28 |
| the HTML Standard (341,289 elements, 2.49 M px) | load | 2,920 | 2,718 layout | 2,260 (FCP 352) |
| | scroll 100 px | 11.2 | 0 | 2.5 |
| | hover links | 24 | 12 paint | 7.8 |
| | resize | 3,683 | 3,605 layout | 538 |

Not comparable one to one: helder's frame is its whole frame, GPU and
readback included; Chromium's is its main thread's task time (raster
and compositing run on other threads). Wikipedia's scroll rows of this
run are left out: the page measured one window tall (`html, body {
height: 100% }`), fixed since (the node's height takes the overflow).

## Is it worth it

- Wins: scrolling costs the engine nothing (the compositor moves the
  recorded layer); a colour-only :hover is a restyle and a repaint of
  what is recorded, 0.16 ms on the sample; within ~1.7× of helder.ui for
  scroll and hover on the app screens.
- Loses: layout. App screens are nested flex boxes (app.css: every
  element a column flex box), and FlexFlow lays each item out again for
  each pass (measure, cross size, final), each pass rebuilding the
  item's inline content and line breaks: 0.25 ms a todo row, 70–700×
  helder.ui on a relayout of 1,020 rows. Caching the sized passes
  (this PR) took a todo relayout from seconds to 0.25–0.4 s; reusing a
  measured layout when the final size equals it (Taffy's, LayoutNG's)
  and keeping inline content across layouts are the next wins.
- Top costs (`sample`, symbolized build): FlexFlow.measureCross and
  contentMain re-laying items; InlineContent and LineBreaks rebuilt per
  layout; BoxStyle.keyword and idOf by name through string maps; GC
  (0.5–1 MB a frame where helder.ui allocates ~1 KB).
