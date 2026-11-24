# Samples

The folder the web build opens on (viewer.helder.run): a few files of each
kind the viewer shows, all of them made here, under the repository's MIT
license. The browser lists them under "Samples" (`src/viewer/Samples.hx`
reads this folder when compiling; this file is left out).

| File | What | Made with |
| --- | --- | --- |
| Murmuration.jpg (1200×1500), Starlings.jpg (1800×1000), Dusk panorama.jpg (2400×800) | starlings at dusk | `examples/murmuration`, `helder run --headless --snap` at 4, 9 and 14 s |
| Planet.jpg (1440×900) | a planet | `examples/planet`, `--snap` at 3 s, its buttons cropped off |
| Mandelbrot.jpg, More/Seahorse valley.jpg | the Mandelbrot set | ffmpeg's `mandelbrot` source |
| More/Rule 110.png | a cellular automaton | ffmpeg's `cellauto` source (rule 110) |
| More/Gradient.webp | a radial gradient | ffmpeg's `gradients` source, then cwebp |
| More/Spinner.gif | an animated GIF | `tests/fixtures/folder/anim.gif` |
| Starlings.mp4 | 6 s of H.264, 640×400 | `examples/murmuration`, `--video`, then ffmpeg (CRF 28) |
| Chimes.m4a | 8 s of AAC | ffmpeg's `aevalsrc`: four decaying sines (C, E, G, C) |
| About Viewer.pdf | three A4 pages: text, two of these photos | `node tests/samplepdf.mjs` |

Together about 4 MB, under helder.run's limits (25 MB a file, 100 MB in all).
