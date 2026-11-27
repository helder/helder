# Scenarios: snapshots of the real program

Design of 2026-11-26, kept current as it is built (PR #278: phases 0 and 1).

## 1. A scenario

```tsx
import {scenario} from 'helder/scenario'
import {score, over} from './game'
import {addHabit, check} from './app'

export const won = scenario({name: 'Pong/You win', boot() { score([7, 5]); over(true) }})
export const moving = scenario({name: 'Pong/In motion', loop: 3})
export const added = scenario({name: 'Habits/Added', time: '2026-11-26T09:00', boot() { addHabit('Read'); check('Read', day) }})
```

A scenario is the real program at a moment. main runs once, as always; in the studio's preview
host `UiWindow.run` keeps its root (`helder.ui.Hosting`, `-D helder.scenarios`) and each scenario
renders that root in a screen of its own: a ScreenContext and a store of values (section 6).
`boot` runs there first: it writes the app's signals or calls the app's own functions, checked by
the ordinary type checker (no key scheme). Fields: `boot`, `time` (its clock's start, an ISO date
or ms; the clock stands at the moment), `zone` ("UTC" or a fixed offset), `locale`, `settings`,
`seed`, `size: [w, h]` (else the root's `<Surface>`'s), `dark`, `play` (seconds of its clock run to
the moment), `loop` (seconds run live from the moment while hovered), `http` (its requests'
answers, strict), `steps` (what a user does after boot: `tap`, `type`, `press`, `scroll`,
`drag`, `waitFor`). Stories stay for
components (controls); a story's and a scenario's names are one list (two of one name: an error).

The model lives in exported top-level signals and memos. Component-local signals stay as they
are, each screen's own, not bootable (phase 2's steps reach them).

## 2. Inputs, semantic (point 2)

Borrow Playwright/Testing Library/Maestro: find by what the user sees, every step waits.
- Queries ranked: role+name, label, text, id (`tap('Add')` = the one button/element named Add;
  ambiguous = error). helder already has this: the headless script's locator (tag, role, label,
  id, index, wait: `src/helder/os/headless/Script.hx:25`, `Headless.find` `Headless.hx:539`)
  over the access tree (`ui/access/AccessTree.hx`, roles, names, `identifier` = markup id);
  actions exist as `Ui.accessAction` (Click, Focus, SetValue, ScrollIntoView) and raw
  pointer/wheel/key/text (`Ui.hx`), and HostAgent already injects them per screen.
- Steps: `tap, longPress, type, scroll(target, to: query|'end'|px), swipe(dir, on), drag(from,
  to), pinch(scale, on), waitFor(query)`. Maestro's `scrollUntilVisible` and Detox's
  `whileElement(...).scroll` are the model for "scroll until".
- Wait = run the virtual clock until the query resolves and nothing is pending (frames, timers,
  transitions): exact, not a sleep (Espresso idling / Flutter pumpAndSettle).
- A step that stops resolving after an edit is shown on the frame and told to the agent:
  `step 2: no button "Add" (near: button "Add habit")`, with near misses and a compact tree
  (Playwright's locator log). The agent repairs it like a type error.
- The agent sees the access tree as text (Playwright MCP snapshots), writes queries, not refs.

## 3. Non-determinism (point 3)

Policy (FoundationDB/VOPR lesson: control where it enters, don't patch after). Phase 1 has
`time` (TS `Date.now`/`new Date()` read the screen's clock, `helder.os.Now`), `seed`, `size`, `dark`;
the rest below is phase 2's.
- Injected, never recorded: time (start instant, zone, locale), randomness (seed), size, dark,
  settings, fonts (bundled; already deterministic).
- Network: per scenario, strict. Fixtures written by the agent (MSW-style: url pattern ->
  status / JSON / file); later, record-once-then-replay from Play (VCR/HAR). A request no
  fixture matches fails the screen with its URL, and the agent adds one. No live calls in stills.
- Files: per-scenario virtual folder (the Store is already scoped per context).

Work in helder (from the map):
- HTTP has no hook: `async/http/Client.hx:21` needs a per-context interceptor.
- `Date.now`/zone (`typescript/js/Dates.hx:91-105`), `Locale` (`os/Locale.hx:13`), `Settings`
  (`os/Settings.hx`), TS `setTimeout` (`typescript/js/Promises.hx:174`, global real-time loop)
  and `Seed` are process globals: move them onto ScreenContext (UI Clock/timers already are,
  `ui/Clock.hx:20`).

## 4. Many in one process (point 4)

Fork is out: macOS frameworks (ObjC, Metal, IOSurface) are not fork-safe, and our pool threads,
sockets and GPU contexts wouldn't survive (Apple/objc notes; no fork use in helder today).

Two layers, cheapest first:
1. **Values per store (built).** Every signal's and memo's value is per store (section 6),
   so one program serves every scenario: each is a ScreenContext with a store of its own
   (own clock, timers, keymap, size, dark, settings; `ui/ScreenContext.hx`). Module-level
   mutable variables (`let`) and raw timers at a top level are the only leak; the guide forbids
   them (flagging them in studio builds is left for phase 2: a reassigned top-level `let` is an
   IR global `ts_<name>_<n>`, `typescript/lower/Frontend.hx`).
2. **Worlds, if 1 isn't enough.** hxmc already keeps reference statics in one block behind
   `rt_globals` (`hxmc/std/hxmc/rt/Gc.hx:102`). Make it a per-program World: scalars (`G_*`)
   moved into it, helder's shared layer (GPU, renderer, text engine, GC, threads) marked shared,
   each scenario a World with its own block, its statics' inits run into it (not a heap clone:
   init is cheap, cloning a heap isn't), swapped when its context runs. Costs: the `rt_globals`
   load is `MConst` and can be hoisted, so swaps happen only between turns; the GC scans every
   block; no per-module init exists yet (`DataGen.hx:427`). Handmade Hero's game-memory block +
   replayed input after each recompile is the same idea. Only if layer 1 fails in practice.

Hot recompile: the dev host already loads each build as a library beside the old one
(`dev/DevHost.hx:13`); every scenario is rebuilt from its data on the new build (no state
migration: a scenario is its inputs).

## 5. What main looks like (point 5)

Today every main is `UiWindow.run(<Surface title width height><App/></Surface>)`, which opens a
window and never returns. Kept exactly so. The studio's host program imports main first (TS:
`import "../main"` in the generated screens.tsx; Haxe: `Main.main()` before
`Screens.run(stories, scenarios)`), built `-D helder.scenarios`: `UiWindow.run` keeps the root and
returns, and `<Surface>` rendered in a scenario's screen gives that screen its children (and its
size, probed once with nothing rendered). `helder run` and Play are unchanged. What main does
before `run` runs once, at the program's start, in the default store.

## 6. Values per store (atoms)

Decided after a first try with string-named signals (dropped): Jotai's atom/store split in the
graph itself (`helder.view.graph.Atoms`), atly's views as the model (github.com/benmerckx/atly).

- Every signal and memo is an atom: its value is per store. Each keeps the node of the store it
  was made in inline (its home: the default store during a program's start, a screen's store
  when made in a screen). Read or written in another store, it resolves that store's node, kept
  in that store's map (atom -> node, by identity) and owned by the store's root, made then from
  its initial value (a memo's: its function, computed from that store's nodes; lazy as its atom
  if the atom is unowned). The default store sees through to a node's home. Fast path: the
  current store is the node's home, or none: one comparison.
- The current store is the current screen's (ScreenContext.run); a computation runs in its home,
  so a flush outside every screen still reads the right nodes; an effect's apply and error handler
  too. TS timers and promise continuations run in the store that set them.
- An effect made with no owner in the default store (a top level's) is made again in each store
  as the store is made (recorded only in `-D helder.scenarios` builds), owned by its root.
- Lifetimes are explicit: a store let go (`dispose`: the screen gone) disposes its root and drops
  its map; using it after is an error. `clear` (a screen built again from its start) the same,
  then its top-level effects made again. An atom keeps nothing of other stores; no weak maps.
- Solid 2 has no instances of the graph, only temporary layers (transactions, optimistic lanes,
  hydration's snapshot scopes), so the graph is not made again per store: two stores' nodes are
  disjoint parts of the one graph and the one Scheduler serves all. But a flush staged every
  pending write in one transaction: an async read pending in screen A would hold screen B's
  commit. So a flush stages each store's writes in a transaction of its own (the default
  store's first, then by first write), a transaction made outside a flush (an ask, a landing)
  takes its node's store, and `Tx.merge` refuses two stores' transactions.
- A signal's initial value is the same object in every store: right for immutable data, which a
  value should be.
- Hot reload keeps each store's values by the same key as the default's, in the store's scope.
- Cost (tests/bench/AtomsBench.hx, natively, least of 5, ns an op): a read in the default store
  3.5 (main: 3.4), a memo read 5.5 (5.5), a write and flush 67 (66): within noise; a screen's own
  signal read 3.8; a top-level signal read in a screen (its map) 7.3; its write and flush 69.

Tests: `src/helder/view/graph/Atoms.test.hx` (isolation, per-store memos, held vs committed
across stores, landings out of order, isPending/latest, boundaries, options carried, derived and
owned writes, clear, disposal, the merge guard, no growth over 200 stores);
`AtomsModel.test.hx` (a property: random graphs of signals, sum/conditional/async memos and
effects, random ops over stores against fresh copies of the graph; 150 cases a run, 50 seeds
passed locally); the graph's 288 tests through stores (`view-stores` lane: home 266/266,
foreign 262/262 and 4 left out that count a top-level memo's runs); `tests/typescript/helder/
stores.ts` (a TS timer and promise continuation run in their store); RefreshCheck (two stores
kept across a reload).

## 7. Stories stay

Components with controls (knobs, play) as today; scenarios are the app's moments on the canvas.
Same frame cache: a scenario's key = its file and what it imports, main and what it imports,
helder's files, its name.

## Phase 0: the field-test apps rewritten

`tests/scenario/fixtures/{pong,habits,weather}`: copies of field-3's s1, s3, s2 (markup moved to
audit F's names), their model in exported top-level signals, a `*.scenario.tsx` each.

- **pong** (`game.tsx`): `ball`, `left`, `right`, `score`, `over`, `paused`, `velocity`, `keys`
  (were a closure's `vx, vy, up, down` and one `state` signal). The clock's last tick stays a
  component closure (frame time, not the model). Scenarios: Serve, Rally, Point scored, You win,
  You lose, In motion (`loop: 3`). Its stories now pose `Court` as "Court/...".
- **habits** (`app.tsx`): `model`, `draft`, and the app's own `addHabit`, `check`; `nextId` gone
  (the next id comes from the habits). Today is `time`. Scenarios: Today, All done, Empty, Added.
- **weather** (`app.tsx`, `weather.ts`): `forecast`, `error`; a day's `date` a `YYYY-MM-DD`
  string (a `Date` is not data). Scenarios: Ghent, Offline.

Moments `boot` + `time` cannot express (phase 2's input):

- weather, any moment: App starts a live request as it mounts; its answer (or failure) can land
  after the still and overwrite what boot gave. Needs strict `http` fixtures; "Loading" needs a
  fixture that never answers.
- weather: the time zone comes from the URL (Europe/Brussels) and the machine: `zone`/`locale`.
- habits, typing: the field's text is `draft`, but focus, the caret and a selection are not
  signals: `steps` (`type('New habit', 'Stretch')`).
- habits, a long list scrolled to the end: `steps` (`scroll('Habits', 'end')`).
- pong, a paddle moving: `keys` says a key is held, but the motion needs the clock run (`play`)
  or `steps`.
- any: hover and pressed looks, a focus ring moved by Tab, a gesture in flight: `steps`.

## Status of phase 1 (PR #278)

Works: `helder/scenario` (TS, Haxe `*.scenario.hx`), the host (`Hosting`, `Act`, `Host`), the
studio (discovery, canvas frames, names, loops, frame cache, run.snap/run.tree, Play of a
scenario plays the app), the guide. Pong's five posed scenarios are pixel-identical to its
stories' stills (`scenarios` lane, over MCP). Numbers (pong, this Mac, `bin/scenario/results.md`):

| | screens | stills after the screens' program started | reopened from frames.hframes | program RSS |
|---|---|---|---|---|
| stories | 7 | 392 ms | 31 ms | 88.6 MB |
| scenarios | 6 | 296 ms | 32 ms | 93.2 MB |

A scenario screen costs about 2.7 MB (1 scenario against 6). Cold builds took 9-14 s on both.

A store cleared or let go (every edit resets screens) drops the TS timers, intervals and promise
continuations set in it before (`Atoms.generation`; `tests/typescript/helder/store-timers.ts`):
nothing runs on the old store, what is set after runs.

What turned out different from the first design:

- Named signals (string keys from bindings, a `set` map) were built and dropped for atoms +
  `boot`: no key scheme, the type checker checks boot, the app's own functions can be called.
- main runs once, not once per scenario: top levels make definitions; the root is rendered per
  screen.
- "Same bring rules" would run an endless game step for 2 s of the clock and move the ball off
  its moment; a scenario's clock stands at its moment (`play` runs it there).

The papercraft field test's fixes (harbour, a TypeScript 3D app; 2026-11-26):

- **Loops of a 3D scenario played from the file.** A loop whose scene is kept as its picture (not
  markup alone) is recorded as pictures: 24 fps, 480 px at most, each a JPEG when opaque, encoded
  as it is read (holding the readbacks made it GC-bound). Hovered, a fresh still's loop plays
  from frames.hframes even while the program runs; the host is asked to loop live only when no
  loop is kept. Harbour: its two 7 s scenario loops and a 4 s story loop kept, 168/168/96 frames,
  4.7 MB a 7 s loop, 4-20 s to record (load 18-580); hovered, decoded in 339 ms, its first frame
  339 ms after the hover. Its frames file is 41 MB, 27 MB of it the stills' 2x PNGs.
- **Rows apart.** A row's gap grows with the widest row, so titles and captions fit at the
  zoom that fits wide frames (harbour's scenario row sat on its story row).
- **Cache misses.** A live literal's patch made the program's sources the patched files (the
  stills taken after it were keyed by the old ones: all stale on reopen; the `scenarios` lane:
  13 stale before, 0 now), the unchanged ones re-keyed. A crashed screen's old still stays in
  the file under its old key: reopened, dimmed (the field test's 1 of 8).
- **Worlds.** At most 8 stills built at once (`Host.MOUNTED`): the settled one drawn longest ago
  let go, its still written first, built again at a focus, its loop, a request or a literal's
  patch. 24 screens of a `<Scene>` failed from the 17th ("more than 16 worlds alive").
- **The guide.** Instructions, the start, game, 3d and ui topics and the starter default to
  scenarios (the starter's `app.scenario.tsx`, its model a top-level signal); stories for
  components with controls.

Found while building: `signal(undefined)()` reads back `null` in TypeScript (weather's
`forecast() === undefined` never held; the fixture reads `== null`). An interop gap, not the
stores'.

## Open: known gaps

- **`latest` through a memo, beside a hold.** A change held on an answer
  (`s0 = 1`, a render effect waiting on a memo that asks with it), then a
  write beside it (`s1 = 0`): a user effect showing `latest(() -> s0 + s1)`
  (the sum a memo) shows 0 here, its memo reading `s0`'s committed value;
  Solid 2.0.4 shows 1, looking ahead to the held `s0`. Not the stores': the
  plain graph does the same. `tests/view/graph/solid-oracle.mjs` case 3
  (Solid's output: `made [] · answer 7 [e3: 7, e0: 1, ...] · s0 = 1
  [e0: 2] · s1 = 0 [e0: 1]`), the skipped test in `Holds.test.hx` ("latest
  looks ahead to a held value through a memo..."). The stores fuzzer leaves
  `latest` over memos out until it is fixed (`latest` over signals stays).

## The viewer (apps/viewer, stacked on #278)

The first Haxe app on scenarios: `src/viewer/Viewer.scenario.hx`, 16 moments.

- **Model per screen.** `Shell.main` keeps what is the process's (the command line, `--store`,
  `--register`, `--version`, the error log, the single instance, the keymap's user file); the
  explorer is made in `Window`, the root main gives `UiWindow.run`, once a screen and owned by it.
  `Cell`'s plain `value` stays: each screen's explorer has its own cells. `Shell.explorer` (a
  top-level signal) is the current screen's.
- **Effects from the environment.** In a preview host (`Hosting.on`) a screen's files are the
  `Sandbox`'s: the tests' folders and the samples in memory (read once a process, at their paths
  under the project, where the host runs), an empty folder and one whose listing is refused
  (`MemoryFiles.denied`); decodes, previews, PDF sizes and thumbnails made at once from those
  bytes, so a still is whole when it is drawn; no store, log, instance, menu bar or thumbnails'
  cache of the user's. The phone and tablet shells follow from `size` (the size class).
- **Per-window statics** into the screen's: the video playing (`Viewer.video`, was
  `MediaView.current`), the window's geometry (`Geometry`, was `Shell.asked`/`offset`),
  `Kinds.utc` a signal; the keymap's defaults bound once a keymap (each screen has its own), the
  actions' names declared once a process. Kept by content, every screen's: Tiles, Thumbnails,
  PdfPages, Glyphs; a viewer's DecodeCache is its own.
- **Async in its store (helder).** `helder.async.Home`: a task started in a screen with a store
  (ScreenContext sets `Home.current`) takes the screen's dispatcher: its body, children,
  continuations, timers and jobs' results run in that store and context; a store cleared or let go
  drops what is pending (`src/helder/view/graph/AtomsAsync.test.hx`).
- **boot through the actions.** `act(Go(...))`, `act(OpenRecent(...))`, `with(x -> ...)` (the
  explorer's own functions: a selection, a search's text). Boot runs before the root renders, so
  they wait for the screen's explorer and run as it is made; a folder boot goes to stands in for
  the command line's path (no history to go back to).

Numbers (`bun run test viewer-scenarios`, this Mac, bin/scenario-viewer/results.md): every still
drawn; App/Photo full size, App/Markdown (dark, light) and App/Phone, photo the same pixels as
Viewer/fit, Viewer/Markdown and Phone/Full size (the first three stories went); the others differ
where the Sandbox is richer (thumbnails, the sidebar's places, no video or audio). All 16 stills
0.7-1.4 s after the screens' program started (cold; 0.7 s on a quiet Mac, the rest under other
sessions' builds), 56-62 ms reopened from frames.hframes. Memory, RSS over five runs: a scenario
screen 27-38 MB (36 in three), a story screen 5-25 MB; mostly a screen's frame (1100x700 at 2x is
12 MB) and its decodes, and too noisy here to say more (stories and scenarios together once came
in under stories alone).

Moments that wait for phase 2's steps (their stories stay): the PDF between two pages (a scroll),
the marquee (a drag held mid-way), the phone's long press, select mode and
info sheet (PhoneState is the phone shell's own, not bootable), the sidebar's volume card (the
volumes are the machine's: a Sandbox of volumes, or `settings`). The search field focused is
App/Search focused, dark and light: a tap (phase 2c).

Found while porting: the studio could not build the viewer's screens at all (its stories under
tests/, no class path of the project's: now each story file's root by its package; a main that is
private: `@:privateAccess`); dev builds' live literals broke two markup patterns the viewer uses (a
variant, `size="sm"`, checked as a literal; a ternary's string beside a number, `"auto"`): both
fixed in helder.

- **Held transactions depend on the order nodes were made.** With async
  answers in flight (several asks, holds, an answer failing), helder's
  graph shows a held change differently depending on whether its nodes
  were made in the order written or as first read: a store makes its
  nodes of the atoms as they are first read, a fresh graph as written, so
  the stores fuzzer sees them differ, in either direction (one shrunk case
  the store consistent and the fresh graph not). The minimal cases do it
  without stores. Solid 2.0.4 differs from both at times
  (`solid-oracle.mjs` case 4: it shows `e3: 4` after `s1 = 1`, helder
  neither). Until the graph's hold rules are ported closer to Solid's
  (a differential fuzz of the graph against the package is the tool), the
  stores soak's per-op comparison makes no async memos. A second property
  keeps them and compares settled states only (every ask answered by its
  input, the flush done: each store's values and its effects' last views
  against a fresh copy's), which do not depend on the order nodes were made
  in (`AtomsModel.test.hx`, "stores with async memos ... settled", in the
  fuzz lane). It found six graph bugs, fixed, each with a regression test
  (three on main without stores): a computation stopped at an async memo
  that landed an equal answer never ran again; one whose answer was
  dropped while its source waited, the source settling unchanged, showed
  nothing; a chain marked pending through an unchanged answer stayed
  pending; a read joining a transaction staged ahead read the committed
  value when the merge kept the other root; a free memo let go of mid-run
  asked again for ever; a computation reading itself overflowed the stack.
  Two 550 s soaks then passed (125,270 cases the second). Left out of it:
  effects reading untracked (what they show is what they read first,
  timing's), and what the clock gap below makes.

- **Unobserved memos are fresh by the write clock** (Solid 2's, and the
  conformance suite's 8 cases helder fails as Solid 2.0.4 does): a memo
  nothing observes, read after any write, computes again, an async one
  asking again. Helder's unowned memos are lazy, so this shows where
  Solid's eager ones ask at the write (Jotai's tests port: 'lazy').

## Phase 2a: determinism per screen (done)

A scenario reads nothing of the machine it runs on. A screen with a store (a preview host's)
carries its environment on its `ScreenContext`, set into `helder.os` while it is current
(`ScreenContext.environ`, at each enter and leave) and the system's again outside:
- **Clock**: `helder.os.Now.get` (its `time`, #278); `Now.time()` for Haxe code (Haxe's
  `Date.now` is hxmc's runtime's and reads the system's: a gap until hxmc takes a hook).
- **Zone**: `Now.zone`, minutes east of UTC; TypeScript's `Date` local time (`Dates.offsetAt`) and
  `Format.date` (the OS formatter, given the instant whose system local time is the screen's)
  read it. Fixed offsets and UTC only: a named zone (Europe/Brussels) has rules helder does not
  carry, and the machine's tz data would differ. A `time` without a zone is in the scenario's.
- **Locale**: `Locale.screen` over the device's (`Locale.current`, `preferred()`; `Format`'s
  numbers and dates).
- **Settings**: `Settings.screen` (textScale, reducedMotion, reducedTransparency, contrast,
  orientation: its size's unless given); `context.reducedMotion` too.
- **Randomness**: each screen its own xoshiro state (`Seed.SeedState`), swapped in on enter and
  out on leave: screens drawn in turn draw as alone. `seed` starts it.
- **TypeScript timers**: set in a screen, on its clock (`Now.after`: its `ScreenContext`
  timers), not the host's loop: `play` runs them, a still's clock stands.
- **Defaults**: zone UTC, locale en-US, settings at rest, seed 1.
- The device's `Locale` and `Settings` signals are `shared` (#322's: their watchers write from
  outside every screen).

Tests: `Scenario.test.hx` (environment per screen, none outside; random side by side as alone;
a timer on the screen's clock); the `scenarios` lane's clock fixture (its zone's date, its
locale's formats, `Math.random`, an interval): each place the same pixels built twice, Delhi the
same beside other neighbours, Brussels and Delhi apart.

## Phase 2b: strict HTTP fixtures (done)

A scenario's requests are answered by its `http`, none going out (MSW's way):
`helder.async.http.Fixtures` on its screen's store (`Atoms.http`, which helder.ui never names:
#293's lesson), asked first by `Client.request` (Haxe's and TypeScript's alike: TypeScript has
no fetch, `Client.request` from helder/async; `Fetch` reads files and the page's assets, not
hosts). A rule's pattern is a url without its scheme, `*` any run, a method first when it
matters (`"POST api.example.com/todos"`); its answer a status (an empty body), a `.json` or
`.txt` file's path read from the project, or any other value's JSON (200). A request none
matches throws in the program (`no http fixture for GET <url> (... {"host/path*": ...})`) and
fails its screen at the host's next turn (`HostScreen.missed`: the studio's crash on the frame,
`project.patch`'s crashed for the agent). A scenario without `http` is strict too. Play runs the
app outside the host: live.

Found on the way: the screens' host never turned helder.async's loop (hosting, `UiWindow.run`
returns before it would), so a screen's tasks, a TypeScript `await Client.request` among them,
never ran: NativeHost turns it each turn now. And the weather fixture's app showed an error that
came after its first render nowhere (its `<Show>` built once): fixed in the fixture.

Tests: `Scenario.test.hx` (a JSON answer, a POST's status, a 503, a file; a request none
matches the screen's failure, named); the `scenarios` lane's weather fixture: its request
answered by a file and by a 503, each the same pixels as the story posing that answer; a request
none matches crashes its screen, named in the studio's log.

## Phase 2c: semantic steps (done)

`steps: [tap("Add"), type("New habit", "Stretch"), press("Enter"), scroll("Rows", "end"),
drag(from, to), waitFor("Saved")]` (`helder.scenario.Steps`; TypeScript's from
`helder/scenario`): run after boot, before the still and before a loop, in the screen's context
and store (its clock, its zone, its seed). A query is a string, tried in this order: a node with
a role and that name, that label, that text, that id; or `{role, name, label, text, id}`, each
given matched. Only what is shown counts (a size, some opacity, its centre inside the screen
and inside each scroll view round it); the first tier that matches must match one node, more is
an error (`"Twin" is 2 nodes: button "Twin", button "Twin" (a role, a label or an id tells them
apart)`). Queries read `UiInspector`'s nodes (the access tree's role and label, a text's text, a
markup id), not the headless script's locator: theirs is a tag-first match for scripts.

A step acts as a user does: `tap` presses and releases at the node's centre, `type` taps then
types, `press` a key, `scroll` wheels the node's scroll view (by points, to an end, or until a
query is shown), `drag` presses, moves in ten frames and releases. After each step the screen's
clock runs until nothing is pending (frames asked for, animations, timers due within a second,
helder.async's tasks), a minute of it at most: exact, not a sleep; `waitFor` runs it until its
query is shown. After the last step the pointer leaves the screen, so no hover shows in the
still. A step that finds nothing fails its screen as an http miss does (the crash on the frame,
`project.patch`'s crashed for the agent): `step 2: no "Ad" (near: button "Add")` and a compact
tree of what is shown (40 lines), the near misses closest first.

Found on the way: `UiInspector` kept a node's source and component only in dev and headless
builds, and failed to compile outside them; and a step file's module functions shadowed the
class's statics TypeScript keeps (the functions are the class's alone now). A scenario's
position is its Haxe file's (`scenario({...})`), none for TypeScript's.

Tests: `Scenario.test.hx` (a tap, typing and Enter; a scroll until a row is shown, then its tap;
a step that finds nothing and an ambiguous one, their messages); the `scenarios` lane's habits
fixture: "All done" and "Added" reached by hand (taps and typing after boot) the same pixels as
boot writing them, and a broken step failing its screen, its near miss named; the viewer's
search field focused (dark, light) reached by a tap (`viewer-scenarios`, beside its stories).
Left: `longPress`, `swipe`, `pinch`; a drag held mid-way (the marquee's story stays); the
phone's select mode and info sheet (PhoneState is the phone shell's own: steps reach them now,
not yet written).

## The UI monkey (property rollout item 5)

`helder.scenario.Monkey`: a stateful property over the real program, booted as its scenarios,
many cases in one process and none drawn (no GPU device: a Ui, a ScreenContext and a store a case,
the root mounted by `Act.mount` as a host's screen is, its frames painted onto nothing).

```haxe
Hosting.on = true;
App.main();
Hosting.on = false;
test("the app under a monkey", () -> Monkey.check({
  from: Monkey.from("app.App_scenario"),          // or Monkey.from(plain, crowded)
  atoms: [Monkey.atom(App.rows), Monkey.atom(App.query)]
}, {cases: 40, limit: 30}));
```

- **A case**: one of the scenarios (`from`), its environment drawn over its own (size, a phone's
  to 2000 x 1400, no smaller than `smallest`, 240 x 180; dark; locale; text scale; start time
  1970-2100; a fixed zone), the atoms written after its boot (values of their types, derived by
  `Monkey.atom`'s macro: Int, Float, Bool, String, arrays, Null, structures, enums, enum abstracts;
  or a Gen given; strings: short words, runs of any characters, right to left, emoji, marks, line
  breaks, huge one-word names, long texts), then up to `steps` (20) steps drawn from what the
  screen shows: taps on its nodes (interactive roles mostly), typing into its text fields, keys,
  scrolls of its overflowing scrollers (to an end, by points), drags, resizes, idle time
  (`wait`). Each is a `Steps` step, run and waited for exactly as a scenario file runs it.
- **Invariants**, after boot, each step and the end (the pointer gone): `throws` (nothing thrown,
  no request its fixtures miss), `sizes` (no NaN, infinite or negative box), `window` (what is
  shown, outside every clipping box, inside the window), `settles` (its clock rests within a
  minute), `steady` (a frame after settling nothing moved, no frame asked), `scrolls` (a scroller
  wheeled to its end is there, its last row shown; to its start at 0), `kept` (idle time moves
  no scroll position and makes no node again; typing keeps its field's focus and moves no
  scroller but its own, or one clamped to a shorter end), `popups` (an anchored popup closed with
  its anchor gone, else at it). `except` leaves some out.
- **A failure** is shrunk (helder.test's choices: steps taken out, values lowered, the
  environment back to the scenario's) and written as a scenario file
  (`bin/test/monkey/<test>.<line>.scenario.hx`; the fuzz lane's `bin/fuzz/monkey`, CI's
  artifact): the scenario it started from (its boot by its path), the environment that differs,
  the atoms' values, its steps. Moved beside the scenarios, it opens in the studio.
  `Monkey.find` returns the smallest case instead of failing the test (its scenario too, built
  again).
- **Seeds**: the test lane's fixed (seed 0, 30 cases), the fuzz lane's random (its 20 s soak).

**Sealed off the machine** (`helder.os.Seal`). A scenario's screen in a preview host and each monkey
case carry a seal on their ScreenContext, current while they run. What would change or open the
machine's own files calls `Seal.check` where it happens: `helder.os.Trash.move`, `Places.user` and
`volumes`, `Store.open` past a screen's in-memory stores (a `dir`, the page's localStorage), the
viewer's `NativeFiles` and its thumbnail cache. Under a seal it throws and is kept, so the screen
fails, named, even when the program catches the throw. Outside every sealed screen it does nothing.
A monkey case also holds `Hosting.on` (a program gives a host its in-memory files, as the
viewer's Sandbox) and makes its Ui in its own screen. Found the hard way: before this, the viewer
under the monkey made its real-disk explorer, the user's places and the system's trash in reach of
its Delete key.

Steps gained `resize(w, h)`, `wait(seconds)` and taps and scrolls at `{x, y}` for it (a node no
query tells apart, a scroller with no name). A resize step changes the screen's Ui, not the studio
frame's size (its still is drawn at the scenario's).

Found on the way: each step's wait ran a minute of the screen's clock (only a paint answers
`Ui.needsFrame`; a frame asked for is now painted onto nothing); a one-line field took a line break
typed (iOS's Return, an input method's) or given as its value and grew a line each; a soak's
rejections were bounded by the cases asked, not run.

Tests: `src/helder/scenario/Monkey.test.hx` (a small program that holds: 30 cases, a 20 s soak of
15,121 cases passed; one with two bugs, each found, shrunk, written and replayed: a huge name past
the window, to the atom's value alone; a popup left open as a search takes its anchor away, to a
few steps), in the fuzz lane.

**The viewer** (`apps/viewer/tests/viewer/Monkey.test.hx`, in the fuzz lane from apps/viewer):
its 16 scenarios (`Monkey.from("viewer.Viewer_scenario")`: `helder test` links a project's
`*.scenario.hx` as `Foo_scenario`, as the studio does) and a made folder, desktop and phone:
`Sandbox.made`, an atom of names and kinds (huge, right to left, emoji and combining names, many
entries; photos, PNG, GIF, WebP, text, Markdown, PDF, an MP4 video and audio, a broken JPEG, one
cut short, empty files, folders), files in the Sandbox's memory, under a HELDER_HOME of its own.
Its failures land in apps/viewer/bin/fuzz. `checks`: each case's files the Sandbox's (a probe of 60 cases first, no steps), and media's (one
player at most playing, the viewer's, its file shown in it; a test plays the clip and closes it).

Found by it: a decode's key cut a file name at a line break (Null Access opening it); a touch
menu taller than the window ran off it (its last choices out of reach: the viewer's View options
on a phone held sideways); a code view's caret blinked on the wall's clock, not its screen's (a
still's phase the wall's; a scenario never settled). Open: `Buffer.adopt: no buffer`
(helder.image.ImageMemory's buffers and views out of step) once in about six 60-case runs, never
alone (GC timing: an hxmc runtime issue, reported, not fixed). Press-on-pointer-down is not
checked: no control says it acts on pointer-down.

Follow-ups: TypeScript programs (a `helder/scenario` monkey), and the invariants left:
a press on pointer-down where the control says so, unrelated input recreating stable parts beyond
idle time and typing, at most one media playing, frames compared (a still built twice the same
pixels), perf bounds; a resize step as the studio frame's size; `play` scenarios (their clock run
first).

## Phase 2 notes

- Per-context, left: Haxe's `Date.now` (hxmc's runtime), Haxe's tasks' clock
  (helder.async.Home's on the real loop).
- Flag reassigned top-level `let` and top-level `setTimeout`/`setInterval` in studio builds.
