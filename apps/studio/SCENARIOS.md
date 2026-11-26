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
or ms; the clock stands at the moment), `seed`, `size: [w, h]` (else the root's `<Surface>`'s),
`dark`, `play` (seconds of its clock run to the moment), `loop` (seconds run live from the moment
while hovered). Phase 2: `steps`, `http`, `zone`, `locale`, `settings`. Stories stay for
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

## Phase 2 notes

- Steps over the headless locators (`os/headless/Script.hx`, `Headless.find`): run in the
  screen's context and store; a step's write is a store write like boot's.
- Per-context: Haxe's `Date.now`, zone, locale, settings, TS timers' clock (they run in their
  store now, but on the real clock).
- Strict `http` fixtures (`async/http/Client.hx` has no hook yet); an async memo's request is
  each store's already (no node shared), so fixtures can differ per scenario.
- Flag reassigned top-level `let` and top-level `setTimeout`/`setInterval` in studio builds.
