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

## The HTML Standard in a live window: memory and resize

`HELDER_TEST_INPUT=1 bun run test document-window` on the Mac (2026-11-27):
a real window, a 20 s thumb drag at 250 Hz and a select drag posted to
its own queue. Memory is RSS before a full collection / live heap after
it / RSS after it. Chromium is the renderer process (headless,
Playwright, the same page and sheets, after load). For Ladybird, see
the measured references below; an earlier "just under 600 MB" from
Activity Monitor was wrong.

| | helder, main before (7a2b4d74) | #466 (fonts mapped, box side tables, inline content cut) | the resize PR (laid out where seen) | Chromium | Ladybird |
| --- | ---: | ---: | ---: | ---: | ---: |
| after load | 2,114 / 1,633 / 2,043 MB | 1,084 / 937 / 1,084 MB | 487 / 311 / 487 MB | 1,044 MB RSS, 795 MB footprint | 2,298 MB RSS, 1,861 MB footprint (below) |
| the most during the thumb drag | 2,265 MB | 1,280 MB | 617 MB | | |
| after the thumb drag | | 1,149 / 933 / 1,136 MB | 608 / 388 / 605 MB | | |
| after the select drag | | 1,249 / 987 / 1,223 MB | 613 / 396 / 613 MB | | |

The resize PR lays out a document of more than 50,000 boxes lazily,
as if its blocks had `content-visibility: auto`. A block far from the
scroll window whose layout isn't kept gets an estimated height: its
last layout's, scaled to the new width, else its text's. Its contents
are skipped until the window comes near, with scroll anchoring keeping
what was at the top in place. A window resize then restyles only what
its media queries and viewport units change: a sheet's query that flips
re-indexes the rules in place and restyles the elements its rules
match, those in skipped blocks when they're laid out. A display a
query changes rebuilds the nearest block that can be rebuilt alone,
not the whole tree.

| the HTML Standard, a relayout at another width | before | now |
| --- | ---: | ---: |
| in the live window (a frame each, 26 widths, 1024 → 688 → 1024) | 3,683 ms | median 40 ms, worst 186 ms |
| crossing the sheets' 768 px query | (the same) | 372–479 ms in a probe, within the frame budget in the window |
| the whole document laid out at another width (tests, print) | 2.2 s (3.7 s in the window) | 0.6 s in a probe (Chromium 0.54 s) |

The whole relayout's cuts: reuse of a block's layout beside floats that
don't reach it (the cache was off for every block after the first
float), no closures, maps or sorts for a line without inline boxes,
glyph ends found in one pass for left-to-right text, and the hot style
reads (`verticalAlign`, `stacking`, `line-height`, overflow) read once
a style.

## References: Ladybird and Chromium on the HTML Standard

Measured on the same Mac (2026-11-27). The page and its sheets were
served locally; each figure is the least of 3 runs.

| | Ladybird 2026.47.8 | Chromium 149 |
| --- | ---: | ---: |
| load to the first requestAnimationFrame after load | 4,153 ms | 1,794 ms |
| a forced relayout at 900 px (JS: the root's width set, then a layout read) | 294 ms | 139 ms |
| a real resize, 1280 → 900, to the next requestAnimationFrame | 635 ms | 271 ms |
| the content process, RSS / footprint | 2,298 / 1,861 MB | 1,176 / 1,052 MB |
| all its processes, footprint | 2,223 MB | 1,096 MB |

Chromium is the bar for speed and memory: a footprint under 1 GB after
load and while dragging, a forced full relayout at 900 px toward
139 ms (measured the same way), and the first full frame toward 1.8 s.
Ladybird's design is a reference where it is simpler and measures as
well.

## Exact layout (2026-11-27)

The whole document laid out, nothing estimated: what is seen first,
the rest in slices between the loop's turns (helder.os App.tasks, with
or without frames). The HTML Standard, the same Mac, least of 3 runs,
measured as the references above (a 1280 × 800 viewport; the relayout
the whole document at 900 px, from 1280):

| | helder | Chromium 149 | Ladybird 2026.47.8 |
| --- | ---: | ---: | ---: |
| load: parsed, styled and laid out whole | 1,681 ms (#482: 1,929) | 1,794 ms | 4,153 ms |
| a forced relayout at 900 px | 207 ms (#482: 287) | 139 ms | 294 ms |
| RSS after load | 787 MB (#482: 843) | 1,176 MB | 2,298 MB |
| live heap after load | 730 MB (#482: 785) | | |

A scroll's paint (the page laid out whole, drawn offscreen a frame at a
time): a wheel's frame (60 px) allocates nothing at the median; a
thumb's jump (20,000 px) 1.0 MB, where it was 4.1 MB.

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
