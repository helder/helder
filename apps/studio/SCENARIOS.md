# Scenarios: snapshots of the real program

Design of 2026-11-26, kept current as it is built. Status and what was
learned building it: the end of this file.

**Decided since:** there is no `state()` API. The store is the program's own
signals: a signal holding plain data, bound to a variable, has a readable
and stable name (`Game.score` for `const score = signal(...)` in `Game`), and
a scenario sets it by that name (`set`, not `store`). Sections 1 and 6 read
with that change.

User's model: one program running; a snapshot = the real app given {env, store, virtual clock}
(+ inputs where state can't express it); an edit recompiles hot and every snapshot redraws.
Stories stay for components (they have controls).

Sources: codebase map (agent a9d011262a0aa792f) and outside research (agent ada29e9664fe436c0),
both summarized below with paths/links.

## 1. A scenario

```tsx
import {scenario, tap, type, scroll} from 'helder/scenario'

export const rally = scenario({name: 'Pong/Rally', size: [480, 320],
  set: {'Game.score': [3, 2], 'Game.ball': {x: 300, y: 118}, 'Game.velocity': {x: 240, y: -180}}})
export const won = scenario({name: 'Pong/You win', set: {'Game.score': [7, 5], 'Game.over': true}})
export const moving = scenario({name: 'Pong/In motion', loop: 3})

export const offline = scenario({name: 'Weather/Offline', http: {'api.open-meteo.com/*': 503}})
export const ghent = scenario({name: 'Weather/Ghent', time: '2026-11-26T09:00+01:00',
  http: {'api.open-meteo.com/*': 'fixtures/ghent.json'}})

export const adding = scenario({name: 'Habits/Adding', set: {'App.habits': sample},
  steps: [type('New habit', 'Stretch 5 min'), tap('Add'), scroll('Habits', 'end')]})
```

Fields: `set` (the app's named data signals' values), `time` (the start instant; the clock is virtual and
paused at the moment), `seed`, env (`size`, `dark`, `locale`, `zone`, `settings`), `http`
fixtures, `steps` (only for what state can't say: a scroll, a gesture, typing), `loop` (seconds
run live on hover, as today). The program is `main` itself, unchanged.

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

Policy (FoundationDB/VOPR lesson: control where it enters, don't patch after):
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
1. **State not in globals.** If the app's state is in the context's store (section 6), one
   program serves every scenario: each scenario is a ScreenContext (already: own clock, timers,
   keymap, size, dark, Store scope; `ui/ScreenContext.hx:28-123`). Module-level mutable state
   is the only leak; the guide forbids it and the compiler can flag a top-level `let` that is
   reassigned (TS globals are IR globals `ts_<name>_<n>`, `typescript/lower/Frontend.hx:195`).
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
window and never returns (`ui/UiWindow.hx:920-1000`). Keep it exactly so. In the preview host
`UiWindow.run` doesn't open or block: it hands the root to the scenario being mounted, and
`Surface` gives its size/title to the screen. So `helder run`/Play are unchanged, the agent
writes no extra export, and the scenario runs the real entry: main's top level runs once per
scenario mount, in that scenario's context. Things main does before `run` (load data, start a
fetch) run under the scenario's env, which is the point.

## 6. Getting the store to a good-enough state (point 6)

Field-test apps kept state in local closures and module variables (habits
`app.tsx:38`'s `let nextId`, pong `game.tsx:8`'s `let vx, vy, up, down`), so
no scenario could set it. Push agents to one pattern: the model in signals of
plain data, one per variable, made in the component (or module) that owns it:

```tsx
export function Game() {
  const ball = signal({x: 235, y: 155})
  const score = signal([0, 0])
  const over = signal(false)
  ...
}
```

- A signal made by `signal(value)` and bound to a variable is named by it:
  `Function.variable` (`Game.score`); a module-level one `module.variable`
  (`game.score`); Haxe `Class.function.variable` (`Pong.Game.score`), a
  field's or a constructor's `Class.variable`. A second of one name in a
  screen is `Game.score#1` (a second instance). Derived signals and unbound
  ones have no name.
- Named in the screen it is made in (each scenario's ScreenContext holds its
  own names), so two scenarios of one program never share a value.
- A scenario's `set` gives a signal its value as it is made, before anything
  reads it (main runs as written; its first frame already shows the moment).
- Checked: a name no signal took fails the screen (`no signal named
  "Game.scor" (did you mean "Game.score"?)`), a value of another shape than
  the signal's initial one too (`Game.ball: no field "dx"`). Phase 1 checks
  at run time, shown on the frame; a compile-time check needs the names'
  types before the scenario file is checked (a generated `.d.ts`
  augmenting helder/scenario's `Names`), left for later.
- "Good enough": the whole game/app model in named signals, derived and
  visual state (animations, hover, scroll, a frame's last time) not. What
  remains goes to `steps`.
- Later: capture a state from Play ("save this moment" -> the names' values
  as a new scenario): Redux DevTools export / Elm's debugger import.

## 7. Stories stay

Components with controls (knobs, play) as today; scenarios are the app's moments on the canvas.
Same frame cache: a scenario's key = program sources + its data (+ its fixtures).

## Plan

- P0 (paper): rewrite pong, weather, habits as named signals + scenarios by hand; list what needs
  steps or fixtures. Settles the API before code.
- P1: preview host mounts main per scenario (UiWindow.run in host mode); named data signals;
  set/time/seed/size per context; scenario files in the studio and the cache. One program, no
  compiler work. Guide: the model in named signals, no closures or module variables.
- P2: steps over the existing locators with auto-wait and repair messages; HTTP fixtures (strict);
  Date/zone/locale/TS timers per context.
- P3 only if needed: hxmc Worlds.

## Phase 0: the field-test apps rewritten

`tests/scenario/fixtures/{pong,habits,weather}`: copies of field-3's s1, s3,
s2 with their model in named signals and a `*.scenario.tsx` each.

- **pong** (`game.tsx`): `Game.ball`, `left`, `right`, `score`, `over`,
  `paused`, `velocity`, `keys` (was a closure's `vx, vy, up, down`). The
  clock's last tick stays a closure (frame time, not the model). Scenarios:
  Serve, Rally, Point scored, You win, You lose, In motion (`loop: 3`).
  Everything the stories posed is a `set`.
- **habits** (`app.tsx`): `App.habits`, `App.draft`; `nextId` is gone (the
  next id comes from the habits). Today is `time`. Scenarios: Today, All
  done, Empty.
- **weather** (`app.tsx`, `weather.ts`): `App.forecast`, `App.error`; a day's
  `date` is now a `YYYY-MM-DD` string (a `Date` is not data). Scenarios:
  Ghent, Offline.

Moments `set` + `time` cannot express (phase 2's input):

- weather, any moment: main starts a live request; its answer (or failure)
  lands after the still and overwrites what `set` gave. Needs strict `http`
  fixtures; "Loading" needs a fixture that never answers (or a delay).
- weather: the forecast's "today" comes from the data, the time zone from
  the URL (Europe/Brussels) and the machine: a scenario's `zone`/`locale`.
- habits, typing: the field's text is `App.draft`, but focus, the caret and
  a selection are not signals: `steps` (`type('New habit', 'Stretch')`).
- habits, a long list scrolled to the end: `steps` (`scroll('Habits', 'end')`).
- pong, a key held: `Game.keys` says it, but a paddle *moving* needs the
  clock run (`play` seconds) or `steps` of key presses.
- any: hover and pressed looks, a focus ring moved by Tab, a gesture in
  flight: `steps`.
