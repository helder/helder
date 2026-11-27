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

### Now: after speed PRs 1–3 (layout cache, flex reuse, inline content)

Load 4.1; frame ms median (least); "ratio" the engine's median over
helder.ui's (first frame: the least of each, the medians being noisy).

| todo | helder.ui | engine | engine: update / draw | ratio |
| --- | ---: | ---: | ---: | ---: |
| first frame (20 rows) | (2.8) | 6.4 (4.3) | 3.9 / 2.5 | 1.5 |
| scroll the list (1,020 rows) | 1.3 | 2.6 | 0.4 / 2.2 | 2.0 |
| hover over rows | 1.3 | 1.9 | 0.4 / 1.5 | 1.45 |
| type into a field | 1.3 | 4.4 | 1.8 / 2.6 | 3.3 |
| resize, two widths in turn | 4.9 | 4.3 | 1.8 / 2.5 | 0.9 |
| drag-resize, a new width each frame | 4.4 | 10.1 | 7.5 / 2.6 | 2.3 |
| add 1,000 rows | 17.6 | 39.2 | 36.4 / 2.8 | 2.2 |

| mail | helder.ui | engine | engine: update / draw | ratio |
| --- | ---: | ---: | ---: | ---: |
| first frame (20 rows) | (3.0) | 6.0 (5.9) | 3.2 / 2.9 | 2.0 |
| scroll the list | 2.1 | 3.4 | 0.4 / 3.1 | 1.6 |
| hover over rows | 2.1 | 3.1 | 0.3 / 2.8 | 1.5 |
| type into a field | 1.9 | 3.5 | 1.2 / 2.3 | 1.8 |
| resize, two widths in turn | 1.8 | 3.9 | 1.1 / 2.8 | 2.2 |
| drag-resize | 1.8 | 4.0 | 1.2 / 2.8 | 2.2 |
| add 1,000 rows | 26.7 | 42.2 | 39.1 / 3.2 | 1.6 |

What is left over 1.5×: the draw of any change (the node records as one
display-list entry: any change records and draws the whole window again,
2.3–3.1 ms against helder.ui's 1.3–2.1), the paint order made again over
the whole document after a relayout, a scroll container in the document
repainted as it scrolls, new rows' styles (the cascade, 29 ms of todo's
36), first frame's sheets (to come from #456's compiled data).

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
