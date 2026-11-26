# helder studio

A project's screens on a canvas, its code, an inspector and an agent's
tools, all editing the source files: the first vertical slice of the
studio (helder.build's PLAN.md, step 5). It is a helder app, drawn by
helder.ui, and it opens itself.

```sh
bun run helder studio examples/ts-todo     # this checkout; npx helder studio in a project
bun run helder studio tests/studio/design      # design files alone: nothing built
bun run helder studio                      # the project in this directory, else a new one
```

## The shell

The studio is a blank sheet with a prompt; the user's agent works and the
user watches it on a canvas that is theirs (`Watch`):

- **A header**: the window's buttons, the project's tab (its dot the
  working agent's colour, pulsing while it works, ringed while a question
  waits), Play.
- **A blank sheet**: a project with nothing on its canvas yet (an empty
  folder; `helder studio` outside a project makes `~/Helder/Untitled n`)
  is the dot grid and one prompt in the middle, the agent's chip in it
  (its menu: the agents found). The first prompt moves into the chat.
- **The chat** (`Chat`, left; Cmd+B puts it away): the user's prompts as
  bubbles; the agent's reply as Markdown (helder.markdown, updated as it
  streams), its links to places (`studio:screen/<name>`,
  `studio:frame/<file>#<name>`, `studio:group/<file>#<title>`) and to the
  project's files (`app.tsx:12`, `app.tsx#L12`, a code span naming one) as
  chips: a place's flies the camera there, a file's opens it read only
  over the canvas at its line (`CodePanel`; Escape closes it); its plan
  one dim line, "Thinking…" while it thinks, its last tools as lines
  (the ones before folded: "Made N changes"), a failed build's row, its
  question as a card (answered there, and only there: studio.ask's and an
  ACP agent's permission asks alike, the asker named and in its colour in
  the card, the input's glow and the tab's dot; several picks toggled,
  then Send). Below: the questions waiting (a quiet strip), the input:
  the agent's chip (its menu a popup above it: the agents found, the
  studio's own tools only when none is) and send, which while the agent
  works is its mark, pulsing in its colour (a press stops it). What the user types
  while it works is a note for it (`Inbox`: "sent while working", then
  "seen"), not a new prompt: carried by its next tool call to the
  studio, or, over ACP, sent as the next prompt when its turn ends.
- **The canvas** (`Board`, watched): every frame as before, panned (a
  drag, any button; an open hand while Space is held over it, a closed
  one while it pans) and zoomed; a click makes a frame the prompt's focus (a quiet ring), a
  double click plays it. Nothing on it is selected, dragged or edited:
  every input is the chat's.

`--classic` mounts the earlier shell (the sidebar, the inspector, the
layers, the command field, the prompt bar, below), which tests/studio's
scripted lanes drive; the browser's studio is still that one.

- **The project's files** in the sidebar (below, "The sidebar"), each
  opening in its view.
- **A free canvas.** Every frame (a design's, a story's, the app's) is
  where it was put, in the world's points: a design's frame at its
  `canvas:at`, a story or the app at its `<Frame story="file#name"
  canvas:at="x y"/>` or `<Frame app canvas:at="x y"/>` in a design file.
  A frame without one sits right of the one before it in its page, else in
  a row a page below the design frames; moving a story or the app the
  first time writes its `<Frame story>` into the design file that already
  places frames, else into `canvas.helder` at the project's root, made then
  (a file of the canvas' own rather than an edit of the user's pages: the
  places are the canvas', and a project without design files gets one
  only when something is moved). Pan with a drag on the empty canvas or
  the wheel, zoom with secondary (Ctrl, Cmd) and the wheel, a trackpad's
  pinch or two fingers, at any time; shift-1 fits every frame, shift-2 the
  selected one (the command field has both).
- **Select, enter.** A click selects a frame at any zoom (the camera stays
  where it is), its caption or itself dragged moves it; a double click
  enters it and selects the node there, a click in it then selects
  another; Escape leaves the frame (it stays selected), again selects
  nothing. The sidebar's frame rows select a frame and fly to it.
- **A screen, live.** Each story's screen is a story of the project's
  program, a dev build, running in one process for the whole project
  (each story a root of its own), offscreen at the screen's size; the
  canvas shows its frames as it draws them.
- **A design's frame, at once.** A design file's frames (`*.helder`,
  below) are drawn by the studio itself, interpreted from their markup:
  nothing built or run, an edit drawn again in the next frame.
- **A node.** Double-click a frame's part (then click others): the node is
  selected (the program's tree: its box, and where its markup is), drawn
  as an outlined box. The inspector shows its layout (width, height,
  padding, gap), style (fill, colour, radius), text and source line.
- **Edit.** A field changes the element's attribute in the source,
  formatting kept (helder.syntax), only its span. A live literal's value
  (a colour, a number, a text written in the markup) is patched in the
  running screens at once, no build, then saved; anything else is saved
  and built, and the screens reloaded with their state. A number's label
  scrubs it: drag left or right.
- **Code.** "Code" shows the selected node's file beside the screen
  (helder.ui.code's CodeEditor), its element revealed and marked. Typing
  is saved after a pause: patched when only live literals changed, else
  built, the build's diagnostics in the editor.
- **Undo and redo** (secondary-Z, secondary-shift-Z, the header's
  buttons) go through every edit in order, whoever made it: the canvas,
  the inspector, the code, an agent. Each edit is a helder.syntax
  transaction on one file; a gesture (a field typed into, a number
  scrubbed, a word typed) is one entry.
- **The prompt bar** asks about what is in focus ("Ask about the whole
  app…", "Ask about Three items…"): the user's own coding agent answers
  (below, "Agents in the studio"), its turn shown above the bar; `/tree`,
  `/snap`, `/check` and `/read <file>` call the studio's tools.

## Screens

A screen's content has a source (Project.Source): a story of the
program, the program's own window (the App), or a design file's frame.

A project's screens are its **stories**: `story({...})` in its
`*.story.hx` (Haxe) and `*.story.tsx` / `*.story.ts` (TypeScript) files,
anywhere under the project's directory but `bin/` and `node_modules/`
(helder.story).

- A story's **name** is `Flow/Screen`: its flow the part before the last
  `/` (no `/`: the flow "Screens"), its label the rest. The canvas has a
  row per flow, in the order the files (by path) and their stories (as
  written) give.
- Its **size** is the story's `width` and `height` (points); without them
  a phone's, 390 by 844.
- TypeScript's stories are **exported** (`export const items = story({...})`):
  the studio imports them by name.
- A project with an entry and no stories has one screen of its program,
  its own window (the page "App"), design files or not. (With stories
  the program is theirs: the App is not drawn beside them.)
- Its **cover** (DESIGN.md §2) is the screen whose `<Frame>` is flagged
  `cover` in a design file (a story's: `<Frame story="Todo.story.hx#items"
  cover/>`), else the first. `studio <project> --cover <png>` writes it at
  2x and closes; headless, `bun run helder run --headless apps/studio
  --stats <json> -- <project> --cover <png>` (apps/studio/web/build.mjs
  --covers: each example's examples/<name>/cover.png).

```tsx
// examples/ts-todo/app.story.tsx
export const empty = story({name: 'Todo/Empty', width: 480, height: 560, render: () => <App/>})
export const phone = story({name: 'Phone/Three items', render: () => {todos(three); return <App/>}})
```

The stories are read from their text (helder.syntax) when the project
opens, not built, so the canvas is laid out before anything compiled. A
story file is read again whenever it changes, whoever changed it (the
code view, an agent's `project.patch`, another editor or an agent on disk:
the studio watches the story and design files), and when one is added or
removed: when its stories changed (added, removed, renamed, resized, bound
to another export) the screens follow (those whose names stay keep their
place and their last frame), the host's main is written again
(`screens.tsx`, `StudioScreens.hx`) and every source built. A project
whose stories are all gone shows its App screen again.

## Design files

A design file (`*.helder`, DESIGN.md) is helder's markup alone: a root
(`<Design>`, or a fragment) of frames, each a place on the canvas with a
size. Every one under the project's directory (but `bin/`,
`node_modules/` and dot directories) is a page of the canvas, named by its
path, its frames its screens, before the stories' flows. A frame's id is
its file's path and its name (`app.helder#Home`), so that no story's
`Flow/Screen` is one.

A `<Group title="Which start screen?" canvas:at="x y">` of frames is a
titled region: its frames side by side, 28 apart, from its place (else
after what is before it), its title above them (15 points, medium).
Groups don't nest. The agent composes the canvas with frames and groups
(a sketch, a comparison, a question's options) and links to them from the
chat (`studio:frame/<file>#<name>`, `studio:group/<file>#<title>`: a
click flies there).

```
<Design>
	<Frame name="Home" width={390} height={844} canvas:at="0 0" background="#f8fafc" padding={24}>
		<note>For the editor only.</note>
		<text fontSize={28} fontWeight={700} color="#3b82f6">todos</text>
	</Frame>
</Design>
```

- **A frame** is drawn as a view of its size (a phone's, 390 by 844,
  without), its attributes its style but its name and the editor's; at
  `canvas:at` in its flow's row (else after the one before). `canvas:*`
  attributes and `<note>` are the editor's: dropped before it is drawn.
- **Interpreted, in the studio's process** (helder.ui.view.Interpreter: a
  Target of helder.view.Plan, the compiler's planner, its steps run at
  once against NodeRenderer's run-time functions), into nodes in the
  canvas' world beside the stories' images, under ui's defaults rather
  than the studio's theme. The same literal compiled makes the same tree
  (the test lane's Interpreter.test.hx).
- **What it cannot run is marked in place**, the rest drawn: a hole that
  is not a literal number or string (`{items.length}`), an unknown
  element, a component (code: not drawn in a design yet), a value its
  attribute rejects, each outlined in red; a file that does not read
  shows why in its frames.
- **Select and edit as a story's screens**: a click selects the node
  there directly (the interpreted nodes' boxes and their markup's
  offsets, no program to ask); the inspector's fields, the code view and
  undo go through the same helder.syntax transactions (`.helder` is
  helder.syntax's Markup language), the file saved and its frames drawn
  again at once.
- **Followed as it changes**: the file's frames are read again after
  every edit of it (the inspector, the code view, an agent, undo), and the
  design files on disk are watched (a second apart, natively): a file
  changed there comes in as an edit (its one differing range, in the
  history), a file added or deleted shows or drops its page. A frame
  added, removed or renamed shows at once; a renamed frame keeps its focus
  and selection.
- **Pages**: each design file is a page; its row in the sidebar's tree
  shows its frames, a click on it fits them (none selected).
- **Images by path** (`<image src="logo.png"/>`, an SVG too): read from
  the design file's folder, decoded by helder.image (again when the file
  changes); natively (in the browser: marked, not yet).
- **A project of design files alone** has no program: it opens with no
  build and no App screen (tests/studio/design). A project with stories and
  design files builds its stories' program as before, its frames drawn
  from the start; one with an entry and no stories, its App.
- Opening a `.helder` file opens its folder as the project.
- **MCP's `run.tree` and `run.snap`** on a design frame: its nodes
  interpreted offscreen at its size (the tree: tags, boxes, texts,
  colours, each node's `file:line`, and what could not be interpreted),
  drawn by a headless device of the studio's own as store screenshots
  are (a PNG at 2x).

### Editing on the canvas

On a design's frame the canvas edits the markup directly
(helder.build's PLAN step 6, design frames first; Drag, Snap, Layers):

- **Move a frame** by its caption (or by itself, selected: a click on
  its background): `canvas:at` written.
- **Resize** by the selection's handles: a frame's `width` and `height`
  (and `canvas:at` from its left or top); a node's `width` and `height`,
  a node placed absolutely (`position="absolute"`) its `left` and `top`
  too from its left or top.
- **Move nodes** placed absolutely by dragging them (`left`, `top`); a
  node in auto layout is resized only (its place is its parent's: reorder
  it in the layers).
- **Snapping**: the moving edges (and centre, for a move) to the frame's
  and the siblings' edges and centres (a frame's to the other frames'),
  within 6 points of the stage, the guides drawn; values rounded to a
  point.
- **Layers**: the zoomed frame's elements as written (`<note>`s left
  out), a row each beside the frame; a click selects (shift: adds), a row
  dragged up or down moves its element among its siblings
  (helder.syntax's Edits.move), the markup's order the drawing's.
- **Multiple selection**: shift-click adds a node or takes it out; the
  selected nodes placed absolutely move together; the inspector shows
  the one clicked last.
- Each gesture is one entry of the history (its moves one transaction
  each, merged), the file's formatting kept, the frame interpreted again
  at once; undo and redo as for any edit.

## Play

**The watched shell's canvas is a storyboard of stills.** Each story's
frame shows its moment (helder.story.Host's stills: brought there as a
store screenshot is, its `Controls.play` frame by frame, else its
transitions for 2 s of its clock, then not run; a live literal, a rebuild
still draw it again). A story with `loop: <seconds>` (`story({..., loop:
2})`, at most 30) plays that long from its moment while its frame is
hovered, then from its moment again, watch-only (no input reaches it), and
is its still again when the pointer leaves; such frames have a small loop
mark by their caption. Play opens a window of its own: the header's Play
the app (the frame aimed at, when one is), a double click on a frame that
screen, live, its input its own, at its size. It is `helder dev` on it (a
TypeScript story: a main of it the studio writes, `.helder-play.tsx` at
the project's root, `play(story)` from helder/story; the app: the
project), so it rebuilds in place as the project changes, its state kept,
while the agent works; closing the window ends it, another Play replaces
it. A headless run says what it would open (`play-window`).

In the old shell (`--classic`) the toolbar's Play (`Play.hx`) runs what is
selected, else the app from its start; the target beside it says where;
Stop or Escape ends it.

- **In the studio** (the default; the browser's only target): a story
  full size (fitted when it does not fit) and live: the pointer's, the
  wheel's and the keys' events in the player go to its screen in the
  preview host (the devtools protocol's `Input.pointer`, `Input.wheel`,
  `Input.key`, `Input.text`), its controls in a panel beside it
  (`Story.controls`, `Story.set`: a number, a flag, a choice, a colour, a
  text). The app the same, when the project's program is its own (a project
  with stories runs them, one program a project: its app plays in a window).
  An App frame placed with a route plays from its start: routing is not
  made yet. A design's frame plays as a prototype: its page's frames one
  after the other with the arrow keys (flows and interactions are not made
  yet).
  On a phone (compact), Play takes the page below the top bar: the screen
  alone, fitted to it (larger too, drawn at the display's scale for the
  size shown), centred; the story's controls a sheet from the top bar's
  button (the screen fitted above it), a prototype's frames the top bar's
  arrows; Stop stays where Play was.
- **In a window**: `helder dev` on the project (hot reload kept, its own
  window), with the helder that started the studio (`HELDER_CLI`, set by
  `helder studio`); its output's last line in the player.
- **On a phone**: `helder dev --target android`, to a connected one (no QR
  code of the web build's page yet).
- **In a browser's tab**: `helder dev --target web`, the page it serves
  opened in the system's browser.

## The sidebar: the project's files

The sidebar's tree is the project's folder (`FileTree`: bin/,
node_modules/ and dot directories left out; read again every second
natively, after the studio's own writes in the browser). Folders holding
design or story files start open, the others closed; a row's chevron
opens and closes it.

- **A design file** (`.helder`) goes on to its frames, **a story file** to
  its stories: a click on the file shows its page on the canvas, on a frame
  focuses it.
- **Code** (`.hx`, `.ts`, `.tsx`, `.json`, `.md`...) opens in the code view.
- **An image** (PNG, JPEG, GIF, WebP, SVG) opens in its viewer
  (`FileView`): fitted (never past 1:1) or at 1:1, its size, format and
  bytes, and where it is used: each line of the project's code and design
  files naming it, a click opening that file. Natively (images by path are
  not read in the browser yet).
- **A font** (TTF, OTF) opens in a specimen: its family, the alphabet, a
  line at 12, 16, 24 and 36 points.
- **glTF models and sounds** show their kind and size: their viewport and
  waveform are not made yet.
- **Layers** of the frame in focus are a section below the tree, its
  header closing it.
- **Drag an image from the tree onto a design's frame**: an `<image src>`
  of its path from the design file, its size the image's (fitted into the
  frame's width), the frame's last child, one history entry.
- **Drop files from the system** on a folder's row (a file's: its folder;
  elsewhere, the project's): copied there, natively.

## How it runs

- **The project never runs in the studio's process, and runs once.** The
  studio builds one program of the project's stories (a dev build, `-D
  hxmc.dev`, `-D helder.headless`; its main `helder.story.Screens` over
  them, generated in `<root>/bin/studio/<name>`) and starts it once: the
  preview host (helder.story.NativeHost), every story mounted as a root of
  its own with a context of its own (helder.story.Host,
  helder.ui.ScreenContext: its clock and timers, keymap, settings, safe
  area, dark or light). A crash or an endless loop takes the host down,
  not the studio: the canvas keeps the last frames, each screen says what
  stopped it (the uncaught error and its frames: a dev build reports
  them, natively with files and lines, in the browser the functions) and
  the host is started again (three times a build, in the browser too).
- **The studio's own errors are shown, not fatal.** An error of the
  studio's out of an event, a frame or a view's making (helder.os's
  App.onError, an Errored boundary) is shown over it (studio.Crash: the
  message, where it was thrown, the stack) with Reload, which makes the
  studio's view again, the project and its previews kept. In the browser
  a WebAssembly catch has no stack, so the module is left to end there and
  the page shows the same panel from its JavaScript stack (the module
  built with `hxmc.symbols`, its frames named), Reload reloading the page
  (every edit is in OPFS).
- **Frames are GPU textures the studio composites.** The host draws each
  screen into a texture of its own the studio's process opens without a
  copy (helder.gfx's shared textures: an IOSurface through Metal on macOS,
  a DXGI texture with a keyed mutex through Direct3D 11 on Windows, a
  dma-buf through EGL on Linux), and the studio draws it as an image with
  its own renderer (Image.ofShared: the zoom, the selection's outline and
  the transitions stay the studio's). A frame's texture goes back to the
  host once the canvas drew a newer one (up to three a screen). Where the
  GPU shares none (Mesa's llvmpipe: CI, this lane) the frames come through
  shared memory instead (a file in /dev/shm both map: helder.story.FrameFile),
  copied into the studio's texture. Only the screens in the canvas' view
  draw: the selected one every frame it changes, at the canvas' scale
  (its pixels a point in halves, up to 3), the others at 1x when something
  in them changes; a screen out of view is suspended and its last frame
  kept.
- **The devtools protocol on the dev connection** (src/helder/dev,
  helder.story.HostAgent): `Host.show` (the screens in view, the one
  selected, its scale), `Host.frame` and `Host.release` (the frames'
  textures), `Ui.getTree` and `Ui.nodesAt` naming a screen, live literals
  (`Hot.literals`: one program, every screen's next frame shows a patch),
  reloads (`Runtime.reload`: the host's state in Hot's snapshot, each
  screen's keys in a scope of its name, the new build started from it with
  the screens the last one had built), `Host.snap` (a frame's pixels read back for
  `run.snap`). The host ends with the studio (`HXMC_DEV_EXIT_WITH_SERVER`).
- The compiler stays warm (helder.compiler.service). One build runs at a
  time; files edited during a build are written after it.
- **A failed build is shown, not only logged.** The last good build keeps
  running, and each frame of the program says so: its last frame dimmed,
  a chip by its caption ("Build failed · app.tsx:88 · TS2322: …", the
  first error), until a build is good again. After a failed build every
  save builds again (not a live literal's patch). The failure is the
  studio's state (`Studio.failure`: its first error, where, every
  diagnostic) for a prompt's turn to say; `project.patch` answers with
  the diagnostics.
- A project's stories share its modules' state, one program: a story keeps
  what it changes to itself (examples/ts-todo's stories each make a store
  of their own, `store(three, "done")`, rather than setting the module's
  signals).

## In the browser

The same studio built for the web (helder's web target, WebGPU or WebGL2:
`?gfx=webgl2`), its page `apps/studio/web`:

```sh
node apps/studio/web/build.mjs bin/studio-web/site examples/todo=Todo   # then serve the directory
```

- **Projects live in OPFS** (the origin's private file system), each under
  `projects/<name>/`. The welcome (no `?project=`) makes a new project
  (`web/new/app.helder`, one design file: nothing built, named `project`,
  `project-2`...), opens a folder (the File System Access API: its sources
  copied into OPFS, and written back to the folder while the page may), an
  example bundled with the page, or a project already in OPFS; `?new` and
  `?example=<name>` do the first and the third from a link (helder.build's
  pages). The page reads the project into memory before the studio's
  module starts and writes each save back (`studio.mjs`, `Files`). The
  page's URLs are relative: it is served under any path (helder.build's
  `/studio/`).
- **One preview host per project.** The project's program runs once, in a
  Web Worker, every story mounted in it as a root of its own with a
  context of its own (helder.story.Host, helder.ui.ScreenContext: its
  clock and timers, keymap, settings, safe area, dark or light; its Ui's
  focus and theme). Only the screens in the canvas' view draw: the selected
  one every frame, the others when something in them changes; a
  screen out of view is suspended and its last frame kept. Each frame is
  drawn on the worker's OffscreenCanvas and posted as an ImageBitmap; the
  studio's renderer uploads it (copyExternalImageToTexture) and composites
  it like any image, so the studio owns its pixels
  (helder.story.web.Preview, `studio.web.WebPreviews`). The screen zoomed
  into draws at the canvas' scale (its pixels a point in halves, up to 3),
  the others at 1x.
- **The devtools protocol as the worker's messages**: Ui.getTree and
  Ui.nodesAt name the screen, Hot.literals patches the one program (every
  screen's next frame shows it). An inspector's colour reaches the
  preview's frame in 10 to 25 ms, one or two studio frames.
- **The preview's module** of an example is built where the page is built
  (`helder studio <project> -- --export-web <dir>`: the screens' program
  for the web, a dev build, with its live literals' tables and the links
  from its build's paths to the project's). A structural edit goes to the
  compiler's worker (helder.compiler.web, its protocol's `build`, when the
  site is built with it: `build.mjs --compiler bin/compiler-web`): the
  project written to the compiler under `/work/<name>`, the screens'
  program beside it (`.studio/gen`), built, and the preview host started
  again from the running one's state (Hot's snapshot); the build's live
  literals' tables come back with it, so the next colour is a patch again.
- **Touch: sheets.** Narrower than 900 points (a phone, a tablet
  upright) the canvas is always underneath (a finger pans, two pinch, a
  tap selects, a double tap enters) and the desktop's panels are sheets
  over it, one at a time (`Sheets`): the files and layers (the sidebar's
  parts), the inspector (its card), the code, the prompt; a bar at the
  bottom switches them (the current one's tab closes it). A sheet rests
  at a detent: peek (its handle and first row), half, full; dragged by its
  handle it follows the finger and settles at the nearest (a fling one
  further; flung down from peek, or dragged below it, away), a tap on the
  handle goes up one. The canvas fits what is in focus above the sheet (at
  most at half), so the code at half leaves the frame in view: an edit is
  seen landing. A frame picked in the files' sheet lowers it to peek. A top
  bar has where you are, undo, redo and Play. A phone's studio is this
  page in the system's web view.

The studio-web lane (`bun run test studio-web`, tests/studio-web) drives
it in headless Chromium: the welcome's Todo opened, all screens shown,
one selected, its title selected, its colour changed (patched, the
next frames showing it, the file in OPFS), at a desktop's width and a
phone's (the sheets from the bar, a frame picked, a double tap, a
pinch), the overview and zoomed states
against goldens; and 50 screens opened and measured. The story-host lane
measures the host natively and the desktop studio with it (50 screens of
examples/todo, Linux, llvmpipe, 4 cores):

| | open to every first frame | resident | Pss |
|---|---|---|---|
| one host, headless (helder.story.Host, frames read back) | 280–310 ms | 202 MB | 168–201 MB |
| the desktop studio's preview process (NativeHost; llvmpipe: frames through shared memory) | 304 ms from its start (2.8 s from the project's open, its cold build included) | 209 MB | 150 MB |
| the desktop studio itself, the 50 frames its images | | 312 MB | 252 MB |
| a process a screen (the desktop studio before) | 0.8–3.3 s | 6.1 GB (sum) | 2.8 GB (sum) |

An inspector's colour change on a zoomed screen reaches the host's new
frame on the canvas in 17 ms, one studio frame. Each screen's first frame
in the host was its own process's byte for byte (the studio lane's
goldens, unchanged). In
Chromium (SwiftShader's WebGPU, the same machine), 50 screens: every
screen shown 0.7 to 2.4 s after the project opened, the preview's module
78 MB, the studio's 27 MB, the page's JavaScript 12 MB. With the
compiler's worker: started in 0.5 to 0.8 s, a padding added built (its
first build) and swapped in in 8.8 s, undone (warm) in 0.8 s; when a warm
build's program ends right after it starts (hxmc's server, as above), the
page builds it again from cold with a new compiler.

## Agents in the studio

The prompt bar drives the coding agent the user already has, over the
Agent Client Protocol (ACP: JSON-RPC on the agent's stdin and stdout,
`AcpAgent`), with the user's own login:

| `--agent` | Started as | Taken by default when |
|---|---|---|
| `claude` | `npx -y @agentclientprotocol/claude-agent-acp` (Claude Code's adapter, the Claude Agent SDK's) | `claude` is on the PATH |
| `codex` | `codex-acp`, else `npx -y @agentclientprotocol/codex-acp` | `codex-acp` or `codex` is |
| `gemini` | `gemini --experimental-acp` (newer Gemini CLIs also take `--acp`) | `gemini` is |
| `local` | none: the studio's tools alone | none of them is |
| a command line | any other ACP agent: `--agent "node my-agent.mjs"` | never |

`--agent`, else `HELDER_STUDIO_AGENT`, else the first found in that order
(a headless run: `local` unless one is named); the studio says which at
start. The agent starts as the project opens, in the background (its
process, `initialize`, its session: npx resolves its package for
seconds), so the first prompt goes straight to it; a prompt sent before
it is up waits for it ("Starting Claude…" in the turn), and a start that
fails is a row of the chat's (the next prompt tries again). The turn shows
at once: the prompt's bubble and the agent's pulsing mark. It runs in the
project's directory, with the studio's MCP server (below) when it takes one over HTTP, so it
has `run.snap`, `run.tree`, `build.check` beside its own tools. A prompt
carries the screen in focus and the selection's `file:line`, and the
screen's last frame as an image when the agent takes images.

Above the bar its turn streams in: its reply as Markdown (helder.markdown's
MarkdownView, updated as each chunk comes: the blocks before the last
kept), its thinking dim, the tools it calls (each with its status), its
plan, and what it asks permission for, as buttons; Stop cancels the turn.
A link in the reply opens in the browser, a file of the project's (`app.tsx`,
`app.tsx:12`, `app.tsx#L12`) in the code view at its line. What it reads is the files as the studio has them,
unsaved edits too; what it writes goes through the studio's history, one
entry a file written: shown on the canvas at once (a live literal
patched, else built) and undone like any other edit. Paths outside the
project are refused. A turn ends once the studio's build of its edits
has: a failed build shows with it (its first error), and every prompt
carries the last build's errors while it is failing, so the agent does
not take its work for done. When the agent's process ends, the turn fails with
its last log lines and the next prompt starts it again.

## Agents over MCP

The studio serves its tools over MCP (Streamable HTTP, JSON responses)
on 127.0.0.1: the port `--mcp-port`, else `HELDER_STUDIO_MCP_PORT`, else
7340; when it is taken the next ones up to 7359, then a free one (a
headless run's a free one). It prints the URL at start and writes it to
`<root>/bin/studio/<name>/mcp.json`.

`/mcp` follows the project in front (one today; with tabs, the tab in
front); `/mcp/<name>` is the project named `<name>` (its
`bin/studio/<name>`), an unknown name a 404 JSON-RPC error. Each agent is
a session: `initialize` answers with an `Mcp-Session-Id`, and the client
it names (`clientInfo.name`) is the agent's name: `claude-code` Claude,
`codex…` Codex, `gemini…` Gemini, `cursor…` Cursor, `opencode` OpenCode,
anything else its name title-cased; a second Claude is "Claude 2". Later
requests carry the header; a request without it (an older client) is the
one anonymous agent, "Agent"; an unknown one is a 404 (the client
initializes again), and `DELETE /mcp` with it ends the session.

| Tool | Does |
|---|---|
| `project.read {path?}` | a file's text as the studio has it (its unsaved state too); without a path, the files and the screens by flow |
| `project.patch {path, edits: [{old, new}]}` or `{path, text}` | an edit through the studio's history (undoable like any other, the agent's name on it): live literals patched in the screens, anything else built; answers what happened and the diagnostics. `{path, text}` on a path not there makes the file (its folders too; its undo deletes it) |
| `build.check {}` | the program typed (tsgo's check too), nothing written: diagnostics at file and line |
| `run.snap {screen?, path?}` | a screen's last frame as a PNG (the selected one, else the first); a design's frame drawn offscreen |
| `run.tree {screen?}` | a screen's node tree: tags, boxes, texts, colours and each node's `file:line` (a design's frame: its interpreted nodes) |
| `studio.focus {}` | what the user looks at: the project (name, dir), the screen in focus, the node selected (its tag, `file:line`, box) and the screens in view |
| `studio.working {note, screen?, path?}` | what the agent is about to do: the note its status |
| `studio.done {note?}` | the agent finished: its marks fade, the note its status |
| `studio.ask {question, options: [{id?, label, note?, frame?, screen?, image?}], multiple?, wait?}` | a question in the chat: options pointing at the canvas (`frame`: `<file>#<name>`, `screen`, `image`) or text alone; `{id}` at once (the answer comes with a later result), `wait: true` blocks (10 minutes, then `{pending: true}`), `{id}` alone waits for an earlier one |
| `studio.inbox {}` | what the user said since (answers, direction typed while the agent works) |
| `studio.guide {topic?}` | how to build here, fast (`apps/studio/guide/*.md`): `start` (the default: the project's files, screens as stories, sketching, the loop, what builds take), `ui`, `game`, `design`, `assets`; each topic's TypeScript is built by its test (`Guides.test.hx`) |

**A project starts working.** An empty folder opened in the studio (the
Untitled one, or any) becomes the starter (`Starter`): the smallest
TypeScript program that builds and shows on the canvas (`main.tsx`,
`app.tsx`, `app.story.tsx` with one plain screen; a `tsconfig.json`
mapping helder's modules to the helder the studio was built with when no
package resolves them, and TypeScript's checker found beside it). Until
the agent changes the project the canvas waits: the blank sheet is the
dots and the prompt alone; after the first prompt, three frame-sized
blocks (radius 12, no caption) hold the places where the first frames
will land, a shimmer sweeping them (1.6 s, the queued frames' own). The
agent's first change fades them and the frames rise onto the canvas,
built (the arrive motion).
What a project is (TypeScript or Haxe, its main, whether it has a program)
is read again whenever a story or a main is made or changes (`revive`), so
a folder that starts empty or changes kind comes alive: its screens shown,
its program built and checked.

**Questions and the inbox.** A question (`Questions`) is a card in the
chat (`Asks`): its options as thumbnails of the frames they point at (or
an image; text options as buttons), "See them on the canvas" when they
share a group, "Something else…" (the input's next message is the answer).
The user picks in the card alone; the picked frame is ringed in the card
and on the canvas. Answers and what the user types while the agent works
are notes of the inbox (`Studio.inbox`): every tool result an agent gets
carries the notes not delivered yet as a last text block ("The user
answered "Which start screen?": Dusk. (picked: dusk)", "The user says:
make the fisher a fox."), then they are delivered (the chat's "seen").

**Presence** (`Presence`): the studio knows each agent here, its colour
(one of six, in order of arrival, freed when it leaves), the screen it is
on, the file it works on, the lines its last patch made, its status and
whether it works. Its tool calls move it without a call of its own: a
file read, a screen's tree or frame, a patch ("Editing app.tsx"), a check
("Checking"); `studio.focus` puts it where the user looks. A minute
without a call it no longer works, ten and it leaves. An ACP agent's
writes make it present too (by its name, the history entry's).

**Its work on the canvas** (`Marks`, the model; `Feedback`, the layer: the
boards' Motion.dc.html), all in the agent's colour and only for an
agent's edits (the user's own move nothing; the camera is never moved
for an agent):

- the frame it is on breathes a halo (a 1.5-point ring and a soft spread,
  6 to 12 points, 2 s), a chip by its caption says its status; done, the
  halo fades (300 ms) and the chip says the done note a few seconds;
- its cursor (an arrow and its name) sits where it last touched and
  glides there in 600 ms (an analytic track in world points: a pan moves
  it with the canvas);
- what an edit made flashes (a 2-point ring and a 10-point spread), keeps
  a 1.5-point outline for 1.5 s, then fades; the chat's turn says it, a
  line a file ("Claude changed pond.helder (3 edits) · Undo": Undo while
  its last edit is still the one undo takes; the canvas takes no input);
- a frame's new image after a build it caused is revealed top to bottom
  behind a 2-point scan line, ~1 s; a frame not drawn yet (a story added,
  its build running) holds its place as a shimmer (1.6 s); a new frame
  rises 8 points into place (500 ms, 120 ms apart);
- an agent whose frame is out of the view is a tab on the edge nearest it
  ("Codex · Settings ›": a click flies the camera there); so is a frame
  new since the project opened, until it has been in the view ("New:
  Settings ›");
- a failed build dims each program's frame, a chip by its caption; one
  chip a frame: an agent's status while it works there, else the failure.

Times are the canvas' clock's (helder.ui.Clock: a headless run's virtual
one), stepped only while something moves. The ground is #0f0f11 with a
dot grid (a point every 24, `Dots`); `--classic` keeps the old shell's
ground for the scripted lanes. The header has a chip each, its status
after its name. The history keeps who made each edit (null: you), and
the undo button says it: "Undo Claude: app.tsx".

`initialize`'s instructions (`Instructions`) tell an agent how to work
here: start with `studio.focus`, look before changing (`run.tree`,
`project.read`), say what it is about to do (`studio.working`), patch in
small steps, look at the result (`run.snap`, `build.check`) and finish
with `studio.done`.

Claude Code, with the studio open on a project:

```sh
bun run helder studio examples/ts-todo
claude mcp add --transport http helder-studio http://127.0.0.1:7340/mcp
```

Then ask Claude Code to change the app: it reads what you look at
(`studio.focus`), the files and the screens' trees (`project.read`,
`run.tree`), edits with `project.patch` (you see each edit on the canvas,
in its colour, and can undo it), checks with `build.check` and looks at
the result with `run.snap` before it reports with `studio.done`. The
prompt bar's agent (`Agent`: its turn as events) is the interface the
hosted prompt box plugs into later, through the same tools.

**In the browser** the same tools are the page's (`studio.web.WebTools`:
the page calls them through the module, `studio.mjs`, and makes each
`run.snap`'s PNG from the GPU's pixels: a design's frame drawn into a
render target, read back asynchronously; a story's frame from its
bitmap). Where the browser has WebMCP (`document.modelContext`, earlier
`navigator.modelContext`: Chrome's `chrome://flags/#enable-webmcp-testing`)
they are registered with it, beside `project.create {name?, files?}`,
`project.list` and `project.open {name}` (the page's projects in OPFS);
without it nothing changes. Two links open files an agent made:

- `#import=<data>`: `{name?, files: {path: text}}` as JSON (as is,
  percent-encoded), base64url, or `z.` and base64url of its deflate-raw
  bytes; opened as a new project of OPFS (at most 1 MB and 200 files).
- `#draft=<id>`: a draft of helder.build's MCP relay
  (`https://helder.build/mcp`), opened into OPFS and kept linked
  (`.studio/draft.json`): the agent's patches come over a WebSocket and go
  through the studio's history (shown at once, undoable), the files the
  studio writes go back, and after each change the tab reports its check,
  each screen's tree and a small PNG (at most 12 screens), which the
  agent reads with `project.status`.

## Look

Every value of the look is in `src/studio/Theme.hx`: the colours as
tokens (the code view's too), the type, the radii, the layout's sizes, the
canvas' spring and the one shadow, and a helder.ui StyleSheet of the
studio's parts by slot. Its direction is paper.design's interface (calm,
dense, precise), made the studio's own:

- **Near neutral darks**, a hint of cool at most: the canvas darkest
  (`canvas`), the panels a step up (`bg`), fields and hovers above
  (`well`, `hover`, `active`); text in three greys, near white at the top
  (`fg`, `fg2`, `fg3`); hairlines faint (`line`, `edge`: white at 7% and
  14%).
- **Panels flush with the window**, a hairline between them and the
  canvas, no cards, no shadows: the sidebar left, the inspector (or the
  code) right, the toolbar between them above the canvas, its hairline
  and the sidebar's top row's one line across. The canvas runs under them
  (the camera fits what is in focus between them: `Studio.insets`). The
  sidebar's top row holds the window's buttons (`<WindowControls/>`, an
  inset title bar: helder.os's `TitleBar`; none in the browser) and the
  project. The toolbar: a breadcrumb (page, frame; the project is the
  sidebar's), the command field (secondary-K, written ⌘K on macOS and in a
  browser on a Mac, Ctrl K elsewhere: `Command`, a frame, a file or a tool
  by name), undo, redo, Design and Code (a segmented control), Play. Its
  empty parts and the sidebar's top drag the window.
- **Dense**: 12-point type in the panels (11 for values and notes), rows
  24 points (layers 22), the inspector's values short fields with their
  label inside (`W 342`, `H 52`, `Padding 10 12`), two numbers to a row, a
  colour a row with its swatch; a layout's direction a segmented control.
  Sections are a word in medium weight over their rows, a hairline above:
  hierarchy by weight and grey, not boxes. Radii 4 (controls, rows) and 6
  (what floats: the command field, menus, the prompt bar); a phone's sheet
  10. On a phone (narrower than helder.ui's `md`) rows and fields are a
  finger's: 32 and 30.
- **One accent**, a blue (`accent`), for what is selected or acts: the
  selection's outline and handles (white squares edged in it), the snaps'
  guides, the frame in focus (its outline, its name in it), focus (a ring,
  `focus`), Play, the switch's current side. The current page, file,
  frame, layer and sheet's tab are a tint of it (`on`), their icons in it
  (`accent-ink`). Files' icons a quiet hue by kind (`kind-*`: a design's
  violet, a story's orange, code blue, an image green); everything else
  grey.
- **Icons** where they name a thing: Lucide's (ISC, `icons/`, only those
  used, embedded by `Icons.hx`, strokes 1.75): a page's kind, a frame, a
  layer's element, the toolbar's buttons.
- **The code's hues** (violet keywords, blue tags, rose attributes, green
  strings, orange numbers) retuned to the darks, at 12 points on 18; its
  cursor and selection the accent's.
- **Motion only where something moves**: a hover, a selection, a focus,
  a tab or a row's tint change at once (no springs on colours, the
  selection's box where its node is, nothing fading in). What moves: the
  camera (pan, zoom, pinch; zoom to fit and to a frame on a short spring,
  `ZOOM`), a phone's sheet (slid up, dragged and flung; its content at
  once), Play opening (a quick fade and scale).

Dark first: every colour is a token, so a light theme is a sheet of the
same names. The fonts are Hanken Grotesk for the interface and Geist Mono
for values (`fonts/`, SIL Open Font License).

## Checks and numbers

The studio lane (`bun run test studio`, tests/studio) runs the studio
headless on copies of examples/todo and examples/ts-todo: all screens,
a frame selected, its title selected, its colour changed in the
inspector, a padding added and undone, an attribute typed in the code
view, the prompt bar's `/tree`; the files and every edit's span checked,
the overview, zoomed and selected frames against goldens. Then on
tests/studio/design (design files alone): both frames drawn with nothing
built, the first moved by its caption (snapped to the other's top), the
title selected, its colour changed (drawn again within 3 frames: in 1 on
a Mac), undone and redone, resized by its handle (snapped to the frame's
centre), a second node shift-clicked into the selection and out, the
title's layer dragged below the input row, both undone (the resize one
entry), every edit's span and the file checked. Then the file browser
(tests/studio/files.json: tests/studio/design with an image, a font and code
in folders): the folders opened, the image, the font and the code each in
its view, the image dragged onto the Home frame (the file's `<image>`), a
file dropped from the system on a folder (headless scripts' `drop`). Then
a story file changed under the studio (a copy of examples/ts-todo driven
over MCP, as an agent drives it): its exports renamed, a story renamed and
one added (the screens follow, built, the new ones shown), a story file
written on disk (read by the watcher, its screen shown), a type error in
app.tsx (the failure, at app.tsx:88) and its fix (cleared). The
test lane runs the studio's own tests (Snap.test.hx, FileTree.test.hx,
Turn.test.hx; Acp.test.hx: ACP's lines and messages; AcpAgent.test.hx:
a turn against a scripted agent, tests/studio/acp-agent.mjs on node, its
events, its permission answered, its write one entry of the history, a
cancel, its process ending).

On a 4-core Linux container (Mesa's llvmpipe, headless, otherwise idle):

| | todo (Haxe) | ts-todo (TypeScript) |
|---|---|---|
| Cold start to the first frame | 116 ms | 134 ms |
| Project open to all 4 screens shown (a cold build, one host process) | 2.6 s | 3.1 s |
| An inspector's colour change to the program's frame (a live literal) | 17 ms, 1 studio frame | 20 ms, 1 studio frame |
| A structural edit (an attribute added): built, the screens reloaded | 0.6–0.8 s (built in 0.57 s) | 0.6–1.2 s (built in 0.47–0.54 s) |

The gfx-shared lane proves each platform's way of sharing a frame between
two processes (tests/gfx/SharedTextureCheck.hx: a frame drawn in one, opened,
drawn and read back in the other, then a second frame through the same
texture): IOSurface on CI's macOS runner (opened and drawn in 95 ms, the
next frame 1.7 ms), DXGI on its Windows runner (7.7 ms, 0.7 ms), dma-bufs
where the GPU exports them (none on CI: llvmpipe, which the studio lane
runs through shared memory).

## Not yet

- The canvas: a frame's screen is not tiled (the selected one at the
  canvas' scale up to 3, at most 4096 pixels a side; deeper zooms scale
  it); the edges of a pinch or a pan have no momentum on the desktop.
- The files' viewers: glTF models (a viewport with orbit controls) and
  sounds (a waveform, play) show their size only; images and fonts are
  read natively, not in the browser yet.
- Play: prototypes along flows and interactions (not made yet: the arrow
  keys go through a page's frames); an App frame's route (routing is not
  made: from its start); a phone reached by a QR code of the web build's
  page; Play in the browser sends the player's input to the worker's
  screens as natively, not checked there yet.
- The window: the inset title bar is verified on macOS; Windows' and
  Linux's (Wayland, X11) are built and their hit-testing unit-tested, not
  yet tried on those systems; on Wayland and X11 the edges show no resize
  cursors of their own.

- Design files (DESIGN.md), beyond frames of static markup: components
  in a design's frame (islands drawn by the preview host), parts used
  from code, tokens and themes, `<For>` over sample data, interactions.
- Canvas editing, beyond the above: a node is not dragged into another
  parent (the layers reorder among siblings), a multiple selection is
  not resized, no arrow keys' nudges, no new frame or node drawn on the
  canvas; a story's screen (code) is not edited on the canvas yet.
- The App beside stories: one program a project, so a project with
  stories shows them and not its App.
- Designs in the browser's studio are drawn and edited as on the
  desktop (tests/studio/design bundled, a new project's); images by path
  and `run.snap` of a design are native only, and its files are not
  watched (the page's own copy).
- In the browser a project's screens are its stories and design frames:
  an App screen (a project without stories) does not run in the preview
  host's worker, so the examples bundled are those with stories
  (examples/todo, signup, mail) and tests/studio/design.

- The selected frame's screen is drawn at the canvas' scale in halves up
  to 3, at most 4096 pixels a side, not tiled: deeper zooms scale its
  frame; the others at 1x.
- A story's shortcuts bound at a module's start (Keymap.global there) are
  the program's main context's, not the screens'.
- On a story's screen selection is click only: no move, resize,
  snapping, layers or multiple selection (a design's frame has them).
- The inspector writes attributes as text; its fields do not come from
  the generated declarations yet (types, units, enums).
- The warm compiler sometimes builds a wrong program after an attribute
  is added to an element of a module a story file uses (hxmc's server:
  the story's view gets its attributes crossed; fixed by hxmc#161, not yet
  in the nightly package.json pins); the studio sees the host end at its
  start and builds again from cold (2 s more).
- The prompt bar's agent: no picker yet (`--agent`); a file the agent
  makes is written, not in the history; the agent's own terminal edits
  files behind the studio's back (the design files are read again from
  disk, the others are not); no agent in the browser.
- In the browser: a TypeScript project's structural edits are not built
  there yet (its screens' program for the web is Haxe's alone); its screens share its modules'
  state in one program (a story that sets a module's signal sets it for
  every screen: ts-todo's stories), so only Haxe examples are bundled; the
  screens' input (a click on a screen selects, it is not the app's yet);
  no MCP server of its own (WebMCP, a draft's link); `run.snap` of a
  design's frame needs WebGPU and a tab in the foreground (its frames).
- Opening apps/studio in itself works crudely: its stories show the shell
  without a project and with examples/todo not started, at the window's
  size, without the camera fitted.
