# Start

The user watches the canvas. Put something real on it within your first
few tool calls: the app's first view, its screen the starter's `App/Start`
scenario. Don't explore the repository: this guide and its topics have
what you need (`studio.guide {topic}`: ui, game, 3d, design, assets).

## The project

A new project is the starter: a TypeScript helder program.

| File | What it is |
|---|---|
| `main.tsx` | the app in a window (`helder run .`) |
| `app.tsx` | its model and its view |
| `app.scenario.tsx` | its screens: each scenario the app at a moment, a frame on the canvas |
| `tsconfig.json` | helder's TypeScript options, extended (leave it) |
| `*.helder` | design files: frames and groups the studio draws itself |

`app.tsx` is a plain placeholder: replace it with the app (keep `App` as
its view's name, or change `main.tsx` with it). Until your first change
the canvas holds the places of your first frames, not this screen.

```tsx file=app.tsx
import { signal } from "helder/view";

// the app's model: exported top-level signals, which a scenario's boot sets
export const title = signal("App");

export function App() {
	return <view flexGrow={1} alignItems="center" justifyContent="center" background="#ffffff">
		<text fontSize={14} color="#71717a">{title()}</text>
	</view>;
}
```

```tsx file=main.tsx
import { UiWindow, Surface } from "helder/ui";
import { App } from "./app";

UiWindow.run(
	<Surface title="App" width={480} height={640}>
		<App/>
	</Surface>
);
```

## Screens are scenarios

Keep the app's model in exported top-level signals, one per value, not in
closures or module variables (`let`), which a scenario cannot reach. A
scenario is the real app (`main.tsx`, as it is) at a moment: `boot` runs
first in its screen, setting the signals or calling the app's own
functions. Name it `Flow/Screen` (the part before the last `/` is its row).

```tsx file=app.scenario.tsx
import { scenario } from "helder/scenario";
import { title } from "./app";

export const start = scenario({ name: "App/Start" });
export const welcome = scenario({ name: "App/Welcome", boot() { title("Welcome back"); } });
```

Each scenario is a literal `scenario({...})` at the module's top level,
read before anything is built. Add one to add a screen; rename or remove
one and the canvas follows. Also: `loop`, `size: [w, h]` (else main's
window's), `dark`, `play` (seconds of its clock run to the moment: its
timers fire, `setTimeout` and `setInterval` included). Each screen has
state of its own: screens never share a value.

A scenario sees nothing of the machine: set what the moment depends on.
`time: "2026-11-26T09:00"` (its clock's start, `new Date()` reads it),
`zone: "+01:00"` (`"UTC"` or a fixed offset; UTC unless given), `locale:
"nl-BE"` (dates and numbers formatted so; en-US unless given), `settings:
{textScale: 1.5, reducedMotion: true}`, `seed` (`Math.random`'s, the
screen's own). Write one scenario per place or language that matters.

A scenario makes no live request: give it `http`, the answers by url
(no scheme; `*` any run; a method first when it matters), each a status,
a JSON value or a file's path in the project. A request none answers
fails its screen, naming its method and url: add the fixture it asks for.
Play stays live.

```tsx
export const offline = scenario({ name: "Weather/Offline", http: { "api.open-meteo.com/*": 503 } });
export const ghent = scenario({ name: "Weather/Ghent", http: { "api.open-meteo.com/v1/forecast*": "fixtures/forecast.json" } });
```

The canvas is a storyboard of stills: a scenario shows its moment, it does
not run. Write one for each key moment, named for it ("Pong/Serve",
"Pong/Game over"), so the frame is exact and repeatable. `loop: 2` records
2 s from its moment, played while its frame is hovered: only where motion
is the point. Play runs the app itself, in a window of its own, live.

## Stories are for components

A story (`*.story.tsx`) shows a component alone, with controls the user
can change: write one only for that. Its name and a scenario's are one
list: name them apart.

```tsx file=badge.tsx
import { Read } from "helder/view";

export function Badge(props: { label: Read<string>; color: Read<number> }) {
	return <view padding="4 10" borderRadius={10} background={props.color()}>
		<text fontSize={12} color="#ffffff">{props.label()}</text>
	</view>;
}
```

```tsx file=badge.story.tsx
import { story } from "helder/story";
import { Badge } from "./badge";

export const badge = story({ name: "Badge/Default", width: 240, height: 120,
	render: c => <Badge label={c.text("label", "New")} color={c.color("color", 0xFF2563EB)}/> });
```

## The loop

1. `studio.focus`: what the user looks at. Then `studio.working {note}`.
2. Ask only when a choice matters: draw the options as frames in a
   `<Group>` titled with the question (`studio.guide {topic: "design"}`),
   then `studio.ask` with options pointing at them (`frame:
   "sketches.helder#Dusk"`), without wait; keep working meanwhile. A
   prompt with no clear subject: 2-3 directions, asked so, and start on
   the first.
3. Make it real, a step at a time so the canvas grows with the work:
   first something that draws on its scenario, then one concept per
   step (a small `project.patch`, `build.check`, the screen updating),
   new scenarios as their moments exist. Each step real, no scaffolding;
   one build per concept, not per line. `{path, text}` makes a new file
   (its folders too).
4. Look: `run.snap {screen: "App/Start"}`, `run.tree` for nodes and their
   `file:line`; `build.check` before you say it works.
5. `studio.done {note}`.

## What each edit costs

- A design file's edit: drawn at once, nothing built.
- A literal in a view (a colour, a number, a string): patched into the
  running screens at once, no build.
- Anything else in code: a build of the screens' program, a few seconds;
  the screens reload with their state. A failed build keeps the last good
  one running and says why (`project.patch` answers with the diagnostics).
