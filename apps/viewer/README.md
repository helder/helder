# Viewer

A fast image viewer and file browser for Windows, macOS, Linux and the
web. Browse your folders, see what is in them, and open any image, PDF, Markdown document or
video full size; step through the folder from there and come back to where
you were. It is a single small program built on helder alone, with no
browser engine and no runtime to install.

- **A browser of folders.** A sidebar of your places (Home, Desktop,
  Documents, Downloads, Pictures, Movies, Music) and drives, one level at a
  time: a folder's subfolders, the one you are in highlighted, › to go
  deeper, the drive's free space at the foot. The sidebar is the
  system's material, as Finder's is: macOS's sidebar, Windows 11's Mica,
  KDE's blur (opaque with Reduce Transparency, and elsewhere). A toolbar with back and
  forward, the folder's name (its menu lists the folders enclosing it),
  search, the View menu (the order, folders first, hidden files: a menu
  button, opened as the mouse goes down, an item picked by dragging onto
  it and letting go) and the inspector; the path along the bottom, each folder a button and each
  separator a menu of that folder's subfolders.
- **A grid of thumbnails, or a list** (name, date, size, kind; sorted by
  its header). Thumbnails come from the viewer's own cache, the nearest
  first. Select several with Shift and Ctrl (Cmd), Ctrl+A, or a marquee
  drawn from empty space, and drag them out to other apps: a file
  manager, mail, chat, a browser's upload.
- **Files moved and named in place.** Drag the selection onto a folder's
  tile or row, or a folder in the sidebar, to move it there (hold Option,
  Alt, to copy); the folder lights up while the files are over it.
  Files dropped from another app onto a folder, or onto the folder shown,
  are copied in. A right click on empty space has New Folder (an
  "untitled folder", selected and named in place), the View menu, Show in
  Finder and Get Info; on a sidebar folder, Open, Rename, Move to Trash,
  Show in Finder and Copy Path. A name is edited in place (Enter keeps
  it, Escape gives it up). Undo puts back a trash, a rename or a move;
  what could not be done says why in the path bar a few seconds.
- **No empty list between folders**: the last folder's entries and the
  sidebar's level stay until the new folder's first are read (or 0.15 s,
  then the reading state).
- **Scrollbars that keep out of the way**: overlay ones on every system
  (macOS's even when a connected mouse makes the system show them
  always; thin ones on Windows, Linux and the web), shown while you
  scroll or bring the pointer to the edge, draggable, faded after.
- **Large folders.** A folder is read off the window's thread, 2,000
  entries at a time; the first show at once, the rest are merged in sorted
  without moving what you look at or losing the selection. A folder
  entered shows its top; back and forward show a folder where you left it
  (its scroll and selection kept with the history, put back once enough of
  it is read), and closing a file shown full size leaves the folder where
  it was with the last file viewed in view. Sorted the way
  people count (`img2` before `img10`), or by kind, date or size. Watched:
  files added, removed or changed show up.
- **The inspector**: the selected file's preview (several: a stack of
  them, their kinds and total size), its kind and size,
  Open, Show in Finder (Explorer, the file manager), Move to Trash (put
  back with Undo) and its details: dimensions, pages, duration, dates.
  Kept while the selected file is the same one (its path, size and
  modified time): a search's keystrokes, a sort or a batch read in change
  the list, not the inspector, whose preview is decoded once.
- **Opens** PNG and APNG, JPEG, GIF, WebP and PDF on every system, and
  TIFF, HEIC/HEIF, AVIF and camera RAW files where the system has their
  codecs (Windows' WIC, macOS's ImageIO, Linux's libtiff, libheif,
  libavif and libraw), full size in the same window, with a pill back to
  the folder. A file grows out of its thumbnail into place, as Quick Look
  does, and shrinks back into it when you go back (a short fade instead
  with reduced motion). The neighbours of the file shown are decoded
  ahead, so the next is already there.
- **Sharp at any size.** Images are filtered in linear light when they
  are scaled down. JPEGs are decoded at the size they are shown, and very
  large images (9000 pixels or more) are drawn in tiles. EXIF orientation
  is applied.
- **Animations play**: GIF, WebP and APNG.
- **PDFs as a browser shows them**: the pages in one column you scroll
  through, fitted to the window's width, each drawn at the size it is
  shown (sharp again after a zoom) as it comes into view, a tag with the
  page you are on, and straight to a page by its number.
- **Markdown documents** (`.md`, `.markdown`, `.mdown`) as a readable
  column: headings, lists and task lists, tables, quotes, code
  highlighted, pictures from the same folder. A link to a heading scrolls
  there, a link to another file of yours opens it in the viewer, a web
  address opens in your browser; Source shows the text itself. The grid
  shows a document's first heading, the inspector its first screen, its
  words and headings.
- **Video and audio** on macOS: MP4, MOV, M4V, WebM, MKV, M4A, MP3 and
  FLAC (H.264, HEVC, VP9 and AV1 where the Mac's hardware decodes them;
  AAC, MP3, FLAC, ALAC, Opus, Vorbis) play in the folder beside the
  images, with a scrub bar showing the keyframe under the pointer, frame
  stepping, and the volume.
- **Desktop integration**: "Open with", the system's open dialog, drag
  and drop, one window that later launches hand their file to, the light
  or dark appearance the system has, and the window's size and place, the
  folder, the order and the inspector remembered between runs.

## On the web

[viewer.helder.run](https://viewer.helder.run) is the same viewer in the
browser. It opens on a sample folder (photos of several shapes, a PDF, a
Markdown page, a video, a sound, a folder inside). In Chromium-based browsers (Chrome, Edge,
Opera, Brave) Open folder shows a folder of your own, read in the browser
and sent nowhere; in any browser you can drop a folder or files on the page.
What only a desktop does is not there: the trash, Show in Finder, Open with,
dragging files out, the settings kept between visits.

## On phones and tablets

The same viewer fits the screen it is on, by its width:

- **On a phone** it is a stack of screens, the way iOS Files and the
  Android file managers are. Browse lists your places (on a phone, the
  app's own Documents folder for now); a folder fills the screen with its
  large title, a search field under it and a grid of three columns (four
  on its side), or a list; its … menu has the view, the order, folders
  first and hidden files. Tap to open, swipe from the left edge or tap the
  back button to go back, and press and hold the back button for any
  folder above. Select picks several with taps, or a drag sideways across
  a row; its toolbar has Open in… (the system's share sheet), Copy, Info
  and Trash. Press and hold a file for its menu: Open, Get Info, Open in…,
  Copy, Select, Move to Trash. Full size, tap to hide the bars, swipe to
  the next or previous file, pinch or double tap to zoom and swipe down to
  go back; Info is a sheet you pull up. Recents lists the files you opened
  last.
- **On a tablet** held upright (and in a narrow window) it is the desktop's
  browser with more room for the folder: the sidebar slides over it from
  the toolbar's button or a swipe from the left edge, the inspector is a
  popover from Get Info, and the path bar is gone.
- **On a wide screen** (a tablet on its side, a desktop, the web) it is the
  browser described above.

Every target is at least 44 points, the bars stay inside the screen's
safe areas, and light and dark follow the system. In a browser at a
phone's width the phone's screens are the ones shown.

## Where it keeps things

The viewer keeps its settings (the window's size and place, the folder,
the layout, the order, recent files), its error log, your keymap file and
its thumbnails' cache where your system keeps an app's data. Point it
somewhere else with helder's `HELDER_HOME` environment variable (its data
under `<dir>/data`, its cache under `<dir>/cache`: helder.os's README), or
with `--store <dir>`, which sets it where no environment reaches the program
(macOS's `open -a`). The test lanes (`viewer-window`, `viewer-app`) do, and
check afterwards that your own store is as it was; a second launch hands
its file to the viewer started with the same home. When you try a build by
hand, do the same:

```sh
HELDER_HOME=$(mktemp -d) apps/viewer/bin/macos-arm64/viewer --new some/folder
```

## Install

Download the package for your system from the
[releases](https://github.com/helder/helder/releases) page.

**macOS 11 or later** (Apple silicon and Intel): unzip
`viewer-<version>-macos-universal.zip` and move `Viewer.app` to
Applications. Viewer then shows up in Finder's "Open With" menu for images
and PDFs. If the release is not notarised, macOS blocks it the first time
you open it: Control-click the app and choose Open, or go to System
Settings > Privacy & Security and click Open Anyway.

**Windows 10 or later** (x86-64): unzip
`viewer-<version>-windows-x86_64.zip` and run `Viewer\viewer.exe`. To add
it to "Open with" for your account, run `viewer.exe --register` once. If
the release is unsigned, SmartScreen may warn you: click More info, then
Run anyway.

**Linux** (x86-64, glibc; X11 or Wayland with OpenGL ES or OpenGL, which
Mesa provides):

```sh
tar xzf viewer-<version>-linux-x86_64.tar.gz
cd viewer-<version> && sh install.sh      # into ~/.local; PREFIX=/usr/local sudo sh install.sh for everyone
viewer ~/Pictures
```

`install.sh` puts the program in `~/.local/bin` and its menu entry, file
types and icons in `~/.local/share`. To use Viewer as a Flatpak instead,
put `org.helder.viewer.flatpak.json` next to the tarball and run
`flatpak-builder --user --install --install-deps-from=flathub build
org.helder.viewer.flatpak.json`, then `flatpak run org.helder.viewer`.

From the command line on any system, `viewer` opens the folder you were
last in (else Pictures, else your home folder), `viewer folder/` browses a
folder, `viewer photo.jpg` opens a file full size in its folder, `viewer
--new` opens a second window, and `viewer --version` prints the version.

## Shortcuts

Ctrl is Cmd on macOS.

| In the browser | |
| --- | --- |
| Move, select | the arrows (in the grid across and down), Home, End, Page Up and Down; type a name's first letters |
| Select several | Shift with a click or the arrows; Ctrl with a click (Cmd on macOS); Ctrl+A; a drag from empty space |
| Drag out to another app | drag the selected files |
| Move into a folder, copy | drag onto it; hold Alt (Option) to copy |
| New folder, rename | Ctrl+Shift+N; File > Rename… or a right click |
| Open (a folder: go in; a file: full size) | Enter, a double click; Cmd+Down on macOS |
| Back, forward | Ctrl+[ and Ctrl+], Alt+Left and Alt+Right |
| The enclosing folder | Ctrl+Up |
| Grid, list | Ctrl+1, Ctrl+2 |
| Search the folder by name | Ctrl+F; Escape clears it |
| The inspector | Ctrl+I |
| Type a path | Ctrl+L, then Enter |
| Show hidden files | Ctrl+Shift+. |
| Move to Trash (Recycle Bin), put back | Delete or Ctrl+Backspace; Ctrl+Z (a rename or a move too) |
| Copy the file's path | Ctrl+Shift+C; a right click has Show in Folder and Open with Default App too |

| Full size | |
| --- | --- |
| Back to the folder | Escape (after leaving full screen), Ctrl+Up, the pill at the top left |
| Next, previous file | Right or Down, Left or Up; Space, Page Down; Backspace, Page Up; the mouse wheel while the image fits |
| First, last file | Home, End |
| Zoom in, out | `+`, `-`; Ctrl and the wheel; a trackpad's pinch; the wheel once zoomed in |
| Fit, 100% | `0`, `1`; a double click toggles between them |
| Pan | drag the image |
| PDF: scroll | the wheel or a trackpad; Page Down or Space, Page Up or Backspace a screen; Down, Up a line |
| PDF: next, previous page | `]`, `[` |
| PDF: first, last page | Home, End |
| PDF: go to page | G or Ctrl+G, type the number, Enter |
| PDF: zoom | `+`, `-`; Ctrl and the wheel, a pinch, about the pointer; `0` fitted as it opened, `1` 100% (96 dpi) |
| Markdown: scroll | the wheel or a trackpad; Page Down or Space, Page Up or Backspace a screen; Down, Up a line; Home, End the top and the end |
| Markdown: the source | Ctrl+U, or Source in the bar; again for the document |
| Full screen | F11 or Enter (Ctrl+Cmd+F on macOS); Escape leaves it |
| Status line | I: the zoom, the size, the format, the page, the place in the folder |
| Video: play, pause | Space or K; next, previous file: Down, Up, Page Down, Page Up |
| Video: a frame on, back | `.` or Right, `,` or Left |
| Video: mute | M |

| Anywhere | |
| --- | --- |
| Open a file | Ctrl+O, or drop a file or a folder on the window |
| Menus | the menu bar (on Linux in the window: F10) |
| Quit | Ctrl+Q (Cmd+Q) |

Every shortcut can be changed in `helder-viewer-keymap.json` in the
viewer's settings folder (`~/.local/share/helder-viewer` on Linux,
`%APPDATA%\helder-viewer` on Windows, `~/Library/Application
Support/helder-viewer` on macOS). For example, to make N go to the next
image and turn off Space (the context `Viewer && full` is a file shown full
size, `Viewer && browser` the browser):

```json
[{"context": "Viewer && full", "bindings": {"n": "viewer::Next", "space": null}}]
```

The file is read again when it changes. The actions are listed in
`src/viewer/ViewerActions.hx`.

## Formats

| Format | Where | Notes |
| --- | --- | --- |
| PNG, APNG | everywhere | animations played |
| JPEG | everywhere | EXIF orientation applied; decoded at the size shown |
| GIF | everywhere | animations played |
| WebP | everywhere | lossy, lossless, animated; EXIF orientation applied |
| PDF | everywhere | every page; JPEG 2000 and CCITT images; password-protected files are not opened |
| Markdown (.md, .markdown, .mdown) | everywhere | CommonMark and GitHub's tables, task lists, strikethrough and autolinks (helder.markdown); raw HTML shown as text; pictures of the computer's files, not the web's |
| TIFF, HEIC/HEIF, AVIF | Windows, macOS; Linux with libtiff, libheif, libavif | the first frame |
| RAW (DNG, CR2, CR3, NEF, ARW, RAF, ORF, RW2) | where the system has the camera's codec; Linux with libraw | |

A file that is damaged, cut short, not an image or larger than the
viewer's limits (268 megapixels, 65,536 pixels a side) shows why in place
of the image, and the keys go on to the next one.

## Releasing

A tag `viewer-v<version>` builds the three packages and attaches them to
a draft GitHub Release (`.github/workflows/release.yml`); the owner
publishes the draft. The version must be `helder.json`'s `"version"`, and
`"build"` should rise with each release. The web build is published by
`.github/workflows/run.yml` on every push to main (helder.json's `run`).
`viewer-v<version>-dry` runs everything and publishes nothing (the
packages are the run's artifacts).

```sh
git tag viewer-v0.2.0-dry && git push origin viewer-v0.2.0-dry   # a rehearsal
git tag viewer-v0.2.0 && git push origin viewer-v0.2.0           # the draft release
```

The packages are `helder build --package` (src/helder/cli/Desktop.hx,
helder.pack), which builds them on any host. The other desktops' runtime
objects come from `node tests/pack/runtime.mjs bin/pack/rt --desktop` and
are passed with `HXMC_RT_DIR=bin/pack/rt`:

```sh
bun run helder build --target linux-x86_64 --package apps/viewer     # bin/dist: .tar.gz, Flatpak manifest
bun run helder build --target windows-x86_64 --package apps/viewer   # bin/dist: .zip of the .exe
bun run helder build --target macos --package apps/viewer            # bin/dist: .zip of Viewer.app
bun run helder publish --notarize apps/viewer                        # on a Mac: notarised and stapled
```

Signing is optional. Each secret holds the file's text, is read from
the environment, and is never printed. When a secret is missing, the
workflow warns and the package ships unsigned (Windows) or signed ad hoc
(macOS):

| Secret | What |
| --- | --- |
| `HELDER_MACOS_CERTIFICATE`, `HELDER_MACOS_KEY` (or `HELDER_MACOS_IDENTITY`, both in one PEM) | a Developer ID Application certificate with Apple's Developer ID G2 intermediate, and its unencrypted key (PEM: `openssl pkcs12 -in id.p12 -nokeys -out id.pem`, `-nocerts -nodes -out id.key`). helder signs the app with the hardened runtime and Apple's timestamp |
| `HELDER_ASC_KEY_ID`, `HELDER_ASC_ISSUER_ID`, `HELDER_ASC_KEY` | the App Store Connect API key that `helder publish --testflight` uses; here notarytool uses it to notarise (together with the Developer ID secrets) |
| `HELDER_WINDOWS_CERTIFICATE`, `HELDER_WINDOWS_KEY` (or `HELDER_WINDOWS_IDENTITY`) | a code signing certificate with its chain, and its key (PEM). helder signs with Authenticode, timestamped by DigiCert's TSA (repository variable `HELDER_WINDOWS_TIMESTAMP_URL` for another, `none` for no timestamp) |

Code signing certificates issued for Windows today keep their key in a
hardware module or a cloud service, so the key cannot be exported as PEM.
For those, set the repository variable `HELDER_WINDOWS_SIGN_COMMAND` to a
command that signs the file whose path is appended (jsign,
AzureSignTool, signtool), and pass that command's own credentials in
secrets that it reads.

## For developers

The viewer is built on helder alone (helder.os's window, helder.gfx,
helder.ui, helder.image's decoders, helder.pdf, helder.jobs).

```sh
bun run helder build apps/viewer                 # bin/<target>/viewer (--target windows-x86_64, macos-arm64)
apps/viewer/bin/linux-x86_64/viewer photo.jpg    # a file: full size, in its folder
apps/viewer/bin/linux-x86_64/viewer ~/Pictures   # a folder: browsed
bun run test viewer viewer-window                # its tests; a real window on the GPU
bun run helder build --target web apps/viewer    # bin/web: viewer.html, served as it is (helder dev apps/viewer --target web)
bun run helder publish apps/viewer --run --dry-run   # what run.yml publishes to viewer.helder.run
```

The title is the folder's name, or a file's full size: its name, its place
among the folder's files and its size (`photo.jpg · 3 / 128 · 4032×3024`). A file that cannot be read, is not
an image this viewer reads, is damaged or larger than helder.image's
limits (`ImageLimits`: 268 MP, 65536 a side, 2 GiB to decode) shows why
in place of the image, and the keys go on to the next. The window's
size and place, the folder and its selection, the layout, the order,
hidden files, the inspector and the status line are kept between runs
(helder.os's `Store`, `helder-viewer`).

### How it works

- **Files** (`src/viewer/Files.hx`): every file the browser reads or
  changes goes through one, a stand-in for hxmc's asynchronous file system
  to come: `list` (a folder's entries in batches of 2,000: name, kind,
  size, dates), `stat`, `open` (a `ByteSource`), `localPath`, `watch`,
  `trash`, `rename`, `makeFolder` and `copy` (each null where it cannot
  be done). **NativeFiles** reads a folder on helder.jobs'
  pool (its names, then a stat of each, sent back over a channel), its
  watch lists it again every 2 s; **MemoryFiles** is the tests';
  **WebFiles** the web's (below).
- **Browser** (`Browser.hx`): the folder shown and its history (back,
  forward, the enclosing folder with the one left selected), its entries
  as batches arrive, each sorted on its own and merged in (`Listing.hx`:
  natural order, kind, date or size, folders first, hidden files, the
  search's filter), the selection kept by name through new batches, a
  sort and the watch (a folder of fewer than 5,000 entries every 2 s, a
  larger one when the pointer comes back to the window: helder.os has no
  focus event), type-ahead, the trash and its undo (a rename back from
  where the trash put it, where the system says), a new folder, a rename
  and files moved or copied into a folder (`transfer`), their undo, and a
  short `notice` of what could not be done. Its state is `Cell`s:
  read back at once by the model, signals for the window.
- **Sidebar** (`Sidebar.hx`): the overview (helder.os's `Places.user()`
  and `Places.volumes()`) or a folder's level: its subfolders, each with
  › when it has its own (its listing stopped at the first). The level
  follows the folder shown: its parent, so the folder is among its
  siblings (a drive's top: itself); a place chosen shows its own.
- The selection is helder.ui's `Selection` (by name), the grid its
  `VirtualGrid` and the list its `VirtualList`, both with that selection's
  keys, presses, marquee and type-ahead; a drag of an entry (4 points)
  is helder.ui's drag of the selected files, their picture following the
  pointer (`DragOut.hx`), onto a folder of the window (`Drops.hx`: the
  folder's tile, row, sidebar row or the list itself, marked while the
  drag is over it); out of the window it becomes the system's
  (`Ui.dragFiles`, the entry's thumbnail its picture). The system's drop
  of another app's files is hit-tested to the same folders. A name is
  edited by `NameField.hx`.
- **Explorer** (`Explorer.hx`) is the browser and the viewer without a
  window: a file opened full size from the browser (the viewer's list
  the browser's viewable files in its order, again when it changes), back
  to the folder with the file viewed last selected, the command line's
  path, the actions of the keymap and the menus and their states.
- **FolderModel** (`FolderModel.hx`): the files the viewer steps
  through (the browser's list), the one shown, next and previous
  wrapping, the neighbours nearest first, natural order's comparison
  (`img2` before `img10`, without case); the list given again keeps the
  one shown by name (gone: the one now at its place).
- **DecodeCache** (`DecodeCache.hx`): decodes kept by path within a
  budget (768 MB), the wanted ones (the image shown, then two neighbours
  each side) decoded nearest first, two at a time; over the budget the
  farthest go, those no longer wanted first, never the one shown; one
  evicted while still wanted is not decoded again until the order
  changes. The decodes are `Decode.job` (`Decode.hx`) on helder.jobs'
  pool, so flipping to a neighbour shows it at once: a still PNG a GC-free
  job (ImageJobs), the rest GC jobs whose planes and pixels are off the GC
  heap (helder.image's `ImageMemory`) and whose row loops let collections
  in (`GcPoint`), the pixels moved back, not copied, and uploaded from
  there, freed when the cache lets them go (`bun run test viewer` builds
  nothing of it; `tests/bench/PrefetchBench.hx file...` measures the main
  thread's frames meanwhile: p99 88 ms, max 203 ms before; 1 to 5 ms,
  2 to 11 ms now, for a 24 MP JPEG, a 24 MP WebP and a 12 MP PNG);
  helder.image's decoders, every frame of a GIF, WebP or APNG, a WebP's
  EXIF orientation applied (JpegDecoder applies a JPEG's). A JPEG is
  decoded at the size it is shown (the view's larger side: 1/2, 1/4 or
  1/8 while still covering it; the status line says "decoded at 1/4"),
  and again larger when a zoom needs its pixels (`refine`: the smaller
  one shown meanwhile); a still image past 128 MP on the GPU is halved
  until within (its size stays the file's).
- **Thumbnails** (`Thumbnails.hx`): a folder's thumbnails, 256 pixels on
  the long side, decoded on helder.jobs (at most half the cores, at least
  two), the lowest priority first; a request can be cancelled or moved.
  A photo's or RAW's embedded preview where it is large enough (Exif.previews),
  else a JPEG decoded at a reduced scale, the system's decoders in their
  thumbnail mode (HEIC, AVIF, TIFF, RAW), helder's own (PNG, GIF, WebP),
  a PDF's first page, a video's keyframe near 10%. Every read of a file's
  bytes goes through one function (`read`). `ThumbCache` keeps them in the
  viewer's own cache (`thumbs/`, never the system's): 16 MB append-only
  segments of CRC-checked records (the JPEG at quality 80, or "none"), an
  index in memory saved every 5 s and rebuilt from the segments when it is
  missing, damaged or stale, the oldest segment deleted past 512 MB (a hit
  in the oldest quarter copied forward). One process owns it (`thumbs/lock`,
  held with flock or an exclusive handle); another reads only. A JPEG, PNG,
  GIF or WebP under 64 KB is decoded every time (as fast as a cache read);
  every other kind is cached at any size. The browser's grid and list ask it (`Tiles.thumbnail`).
- **PdfLayout**, **PdfDoc**, **PdfView** (`PdfLayout.hx`, `PdfDoc.hx`,
  `PdfView.hx`): a PDF as pdf.js shows one by default: its pages down one
  column, centred, 12 points apart, a white sheet each with a soft shadow
  on the canvas, their offsets a `HeightIndex`'s (the pages' sizes in points
  known first: `PdfPages.sizes`, on a job), at pdf.js's "auto" zoom until
  zoomed (fitted to the width, at most 125% of the actual size, so a wide
  window's column stays a page wide, an A4 page some 990 points; a
  landscape document fitted whole; Ctrl and the wheel, a pinch, about the
  pointer: the point under it stays; `+`, `-` about the middle; 100% its
  points at 96 dpi, as pdf.js's). Only the
  pages in view and one each side are made, and drawn: those in view
  first, two at a time, at the size shown in device pixels (again larger
  when a zoom needs it, the smaller drawing shown meanwhile; again smaller
  past 2.5 times), let go two pages out of view. The page at a third of
  the view's height is the one it is on (the title's, the tag's).
- **PdfPages** (`PdfPages.hx`): a PDF's pages, each a decode of its own
  (`Decode.key`: the path, the page after a newline), drawn at the side
  asked for (4096 a side at most; the inspector's first page at 512). The two documents opened
  last are kept open on the jobs' side with helder.pdf's own cache of
  decoded images and page contents (`PdfLimits.imageCache`, 48 MB each),
  so the next page decodes none of what the last one did; one page is
  drawn at a time under a lock; each page has its own decompression
  budget; a changed file is opened again. A file is read where its pages
  need it, not whole (helder.pdf's `Pdf.openSource`): one on disk through
  its handle, kept open while its document is; on the web through Files
  (`PdfPages.through`: its blocks fetched as a page needs them, on the
  page); a phone's document with no path is read whole (a job's thread
  cannot share the blocks fetched). A thumbnail and the inspector read the
  first page alone, its document not kept (a linearized file's from its
  start). The key context `pdf` (a PDF
  shown) gives Page Down, Space, Up, Down, `[`, `]`, Home and End to the
  column, Left and Right stay the folder's; `goto` is the go to page card's.
- **MarkdownDoc**, **MarkdownPage** (`MarkdownDoc.hx`, `MarkdownPage.hx`):
  a Markdown document read through Files (`Explorer.read`: on the loop,
  the web's from its Blobs and the samples), parsed by helder.markdown,
  its words and headings counted, and shown in a `MarkdownView` styled by
  the shell's look (its `markdown-*` parts: a column 760 points at most,
  centred, the system's font, code in JetBrains Mono, light or dark), or
  its source in a read-only `CodeView`. Its links: `#id` scrolls to the
  heading; a path is `Explorer.follow`'s (resolved against the
  document's folder: a file the viewer shows opened in its folder, its
  files stepped through, `other.md#usage` at that heading; a folder
  browsed; another file the system's app's); `http`, `https` and `mailto`
  are helder.os's `Links.open` (the browser; a new tab on the web). Its
  pictures are decoded as the viewer decodes a file (`Viewer.decode`, at
  most 1600 a side), at most the column's width, and laid out at the size
  their headers say (helder.image's `Image.size`, read through Files
  before the document is shown: `Viewer.measure`), so nothing below one
  moves when it lands; a web address's is not fetched, its alt text shown. The key context `markdown` (a document
  shown) gives Page Down, Space, Up, Down, Home and End to the column and
  Mod+U to the source. The grid's tile is a page with the document's
  first heading (`Tiles`: read once, its first 16 KB, no rendering), the
  inspector's preview its first twelve blocks laid out 600 points wide
  and shown at 0.38.
- **Version** (`Version.hx`): `helder.json`'s version, read at
  compile time, the about card's and `--version`'s.
- **ViewCamera** (`ViewCamera.hx`): the scale (device pixels per image
  pixel) and the image point at the view's centre; fitted by default
  (the whole image, never above 100%, centred), zooms about a point that
  stop at 100% and at the fit, the keys' steps, pans kept within the
  image, a glide.
- **ImageView** (`ImageView.hx`, `PhotoShader.hx`): the image in ui's
  layout, drawn into a texture of its box before ui's pass (as
  helder.sprite's SpriteBox): the image in `RGBA8Srgb` textures with every
  mip level (generated), tiles of at most 4096 a side past that (each
  with 64 pixels of its neighbours around it, drawn without them: no seam
  where filtering and the mips read across; off the view, not drawn), read trilinearly, so a photo fitted to the
  window is filtered and averaged in linear light, and nearest from 200%
  up; composed over the dark background in linear light and written as
  sRGB. An animation's frame written into the texture as it changes.
- **Viewer** (`Viewer.hx`) is a file full size without a window: the
  state and the texts the window shows as signals, the keys, the wheel
  and the pointer; **ViewerActions** (`ViewerActions.hx`) the actions,
  default keymap (the root's key context `Viewer`, with `browser` or
  `full`, and `fullscreen`, `pdf`, `media`, `goto`, `about` while they
  are), menus and context menus (helder.ui.actions, helder.ui.menu).
- **Preview** (`Preview.hx`): the inspector's picture of the selected
  file, an image or a PDF's first page decoded through Decode's path at
  512 pixels and halved to fit on the pool, a video's keyframe (Thumbs)
  and its duration; the thumbnail meanwhile. The list's and grid's
  pictures come from one place, `Tiles.thumbnail`: Thumbnails' queue, the
  newest asked for first, cancelled when its cell goes, the last 300 kept
  in memory; a file with none, or a kind none is made of, its glyph.
- **On the web** (`WebShell.hx`, `WebFiles.hx`, `Samples.hx`): the page
  is the window (no title bar of its own). `WebFiles` holds the sample
  folder (`samples/`, listed when compiling, each file fetched from beside
  the page when first read: helder.asset's `Asset.bytes`) and the folders
  the user opens or drops (helder.os's `WebFolders`: the File System Access
  API's `showDirectoryPicker`, read only, where the browser has it; a drop's
  folder handle, or its entry, or its files as a folder "Dropped"), each a
  top of its own by its name and a place in the sidebar; a folder is listed
  500 entries at a time, its files read through helder.media's `WebSource`
  (their Blobs). The decodes, the previews and the thumbnails (in memory
  only: `Tiles` keeps the last 300) read a file's bytes on the page and
  decode them on helder.jobs' Web Workers, a PDF on the page itself (a
  worker's instance runs only the static initializers before helder.jobs',
  and helder.pdf's come after). What needs a disk is left out of the build
  (`#if`): the trash, Show in Finder, Open with, the drag out, the second
  launch's hand-over, the thumbnails' cache, the system's decoders, the
  store; their buttons and menu items are not shown (`ViewerActions.LOCAL`).
- **Shell** (`Shell.hx`) the window (`UiWindow`, `<Surface>` with its
  title bar inset and `onDrop`), its look (helder's controls' `Look.base`
  in the system's font, the browser's parts in its tokens, light or dark
  as the system), the jobs, the settings; its parts `SidebarView`,
  `ContentView` (the toolbar, the list, `States`: empty, still reading,
  unreadable, no results; the path bar, helder's `PathBar`),
  `InspectorView` and `ViewerView` (a file full size, its back pill).

### Tests

`bun run test viewer` (`helder test` in this directory, natively, and on
Eval the camera's maths): `tests/viewer/Browser.test.hx` (on MemoryFiles: navigation
and history, the sidebar's level for a folder, the orders, folders first,
hidden files and the filter, batches merged with the selection kept, the
watch, a file opened full size and back, the trash and its undo,
several selected, a new folder, a rename refused and undone, files
moved and copied into a folder and undone), `FolderModel.test.hx` (natural order, wrapping, the
browser's list given again), `DecodeCache.test.hx` (the order, two at a time, eviction by
distance, a budget too small for every neighbour, a changed file),
`Markdown.test.hx` (on MemoryFiles, tests/fixtures/markdown: a document
opened among its folder's files, its column, its picture decoded and a
remote one's alt text, its links: an anchor, another document at a
heading of it, a web address, a missing file; the keys scrolling, the
source by Mod+U and back, the inspector's preview and the grid's tiles;
two pictures at their sizes before they decode), `Media.test.hx`
(tests/fixtures/media's silent Vorbis files, the desktop's and the
phone's shells: over open, next, previous, close, another folder,
another file and a PDF, at most one player plays, the shown file's),
`Scrub.test.hx` (the scrub bar: keyframe seeks as it is dragged, the
release exact), `ViewCamera.test.hx` (the fit, zooms about the cursor and their stops,
the steps, the double click, pans, the glide), `Samples.test.hx` (the web
build's sample folder as its browser has it: at Samples, its files and
subfolder, the PDF opened and its pages), `Viewer.test.hx` (a
scripted run of the shell's tree in a headless Ui: the fixture folder
browsed, a file opened with Enter, flipped through with the keys and the
wheel, an animation's frames, a damaged file's message, zoomed with `+`,
`1`, Ctrl and the wheel, `0`, the status line, EXIF's orientation, back
with Escape and Ctrl+Up, fullscreen's keys, the browser's keys: grid
and list, the inspector, search; a PDF's column: the keys scrolling
it, go to page, the zoom), `Pdf.test.hx` (the pages' places at a zoom,
the pages a scroll shows and draws, go to page's scroll, a zoom kept
about its point, a page that cannot be drawn, the auto zoom it opens at),
`Inspector.test.hx` (a search's keystrokes: the selected file's preview
asked for once, its picture and details kept), `Window.test.hx` (a
folder among 30, at desktop sizes: the panels and the path bar end at
the window's bottom, the sidebar's level scrolls; a folder entered from a
scrolled one at its top and back at the old offset, read a frame later,
in the list and the grid; a folder read in batches that each sort above
the last, still at its top; the full-size viewer closed with the folder
where it was and the last file in view; scrolled to the end by the
scroll and by End, the last row whole above the path bar with room, each
row's text inside its row; between folders the old entries and level
until the new are read; a right press on empty space and its menu, a new
folder named in place; a file dragged onto a folder's tile, marked,
moved and undone; another app's files dropped on a tile and on the
space; a sidebar folder's menu and its rename),
`Viewer.story.hx` (the grid and the list dark and light, several
selected, the inspector of a photo, of a PDF and of a Markdown document, a marquee
being dragged over the grid, an empty folder, a missing one, no results, a file full size, a
PDF's column scrolled between two pages, the Markdown sample dark and light,
an error in its place, the status line; their trees in
`Viewer.story.snap`). EXIF's reader is
helder.image's (`src/helder/image/Exif.test.hx`), the drops helder.os's
(`bun run test window`). `bun run test viewer-window`: the viewer in a
real window on the GPU (Linux under Xvfb; `GFX_TARGET=windows-x86_64`
under Wine), the fixtures' photo opened, decoded on helder.jobs and
shown full size, closed after 3 s (`--exit-after`: the title and state
printed, or the folder, its count and where the panels end against the
window's height while browsing), a PDF's first page, a
Markdown document (tests/fixtures/markdown), a folder among 40 (its
panels ending at the window's bottom), a 9000x2000 PNG in tiles
(`tests/bigpng.mjs`), then again with no system font
found (`HELDER_NO_SYSTEM_FONTS=1`: helder.text looks for none, and the
viewer adds its own, `fonts/DejaVuSans-viewer.ttf`, a 41 KB subset of
DejaVu Sans, only then). CI runs the tests in its
headless job, the window on Linux (gfx), macOS and Windows (the desktop
jobs).

`bun run test ui-web` builds the viewer for the web too and runs it in
headless Chromium (`tests/web.mjs`): the browser at Samples, the PDF
opened, the Markdown sample opened, files dropped on the page, Open folder on a tree of handles the
page makes; no error on the page.

`bun run test viewer-package`: the three releases built by `helder build
--package` (Linux's on Linux; Windows' signed by tests/pack/signing's
throwaway identity; macOS's ad hoc) and checked (tests/pack/DesktopCheck.hx,
then osslsigncode, desktop-file-validate and appstreamcli where installed,
codesign on a Mac).

### Packages

- **macOS**: the universal `Viewer.app` (arm64 and x86-64) in a zip. Its
  document types come from `helder.json`'s `fileHandlers`, so
  Finder's "Open With" lists it. Its icon is the manifest's on Apple's
  grid. The bundle is sealed (`_CodeSignature/CodeResources`) and each
  slice is signed by helder.pack's own codesign: ad hoc, or by a
  Developer ID with the hardened runtime and Apple's timestamp, which is
  what notarisation asks for. `helder publish --notarize` submits it with
  notarytool and staples the ticket. A DMG would need hdiutil on a Mac
  and gives nothing a zip does not, so the package is a zip.
- **Windows**: `viewer.exe` in a zip, made a GUI program (no console
  window), with its icon from 16 to 256 pixels and its version
  information as resources, and signed with Authenticode when a
  certificate is configured. "Open with" is the program's own
  `--register` (the user's registry). There is no MSIX: an MSIX must be
  signed to install at all, and it would sandbox the folder browsing the
  viewer is for.
- **Linux**: a `.tar.gz` (the program, `install.sh`, a `.desktop` file
  whose `MimeType` holds the file types, hicolor icons from 16 to 512, and
  AppStream metainfo) and a **Flatpak** manifest built from it. Flatpak
  rather than an AppImage: the program is one executable that loads the
  system's EGL, X11 or Wayland, fontconfig and codecs at run time, so an
  AppImage would bundle nothing but itself and still depend on the host.
  An AppImage also needs squashfs tools, a downloaded runtime and FUSE,
  and its file types only register with an extra daemon. The Flatpak
  manifest is text that is reproducible from the tarball (by its SHA-256);
  its freedesktop runtime has those libraries and the GPU drivers, its
  desktop file and icons are exported with the file types, and it is the
  form Flathub takes.

### Text in any script

File names, the title and the status line in any script: helder.text's
platform engine (HarfBuzz and FreeType on Linux, DirectWrite, Core Text)
shapes the scripts its own does not (Devanagari, Bengali, Tamil...) and
falls back to the system's fonts (fontconfig, IDWriteFontFallback, Core
Text's cascade), an emoji to a colour face; the list's names are laid
out left to right (`dir`: an extension stays at the end of a Hebrew or
Arabic name, the name itself right to left inside it, UAX #9).
`tests/fixtures/scripts`: Arabic, Hebrew, Devanagari, Bengali, Tamil,
Thai, CJK, emoji and mixed names (FolderModel.test.hx lists and decodes
them).

### Not yet

Renaming, dropping files into a folder (a drop opens it), tabs, a date
scrubber, EXIF's camera details, a thumbnail size. On Linux, libraw's and HEVC's paths (HEIC needs libheif's libde265 plugin)
have no fixture in the tests; colour management; a PDF's password
(no prompt), its text selection and search; a Markdown document's find (Mod+F)
and its pictures from the web; the window's maximised state
(helder.os has no call for it); an X11 window's class (WM_CLASS: helder.os
sets none, so an X11 desktop matches the window to its menu entry by its
title alone; Wayland's app_id is the program's name, `StartupWMClass` in
the desktop file).