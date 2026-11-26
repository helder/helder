# Start

The user watches the canvas. Put something real on it within your first
few tool calls: the app's first view and a story of it. Don't explore the repository: this guide and
its topics have what you need (`studio.guide {topic}`: ui, game, design,
assets).

## The project

A new project is the starter: a TypeScript helder program.

| File | What it is |
|---|---|
| `main.tsx` | the app in a window (`helder run .`) |
| `app.tsx` | its view |
| `app.story.tsx` | its screens: each story a frame on the canvas |
| `tsconfig.json` | helder's TypeScript options, extended (leave it) |
| `*.helder` | design files: frames and groups the studio draws itself |

`app.tsx` is a plain placeholder: replace it with the app (keep `App` as
its view's name, or change `main.tsx` and `app.story.tsx` with it). Until
your first change the canvas holds the places of your first frames, not
this screen.

```tsx file=app.tsx
export function App() {
	return <view flexGrow={1} alignItems="center" justifyContent="center" background="#ffffff">
		<text fontSize={14} color="#71717a">App</text>
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

## Screens are stories

Each `story` in a `*.story.tsx` file is a screen on the canvas, named
`Flow/Screen` (the part before the last `/` is its row). Its size is the
frame's (a phone's, 390 by 844, without one). Each story renders on its
own, with state of its own: make the state inside `render` (or a
component), not at a module's top level, so screens don't share it.

```tsx file=app.story.tsx
import { story } from "helder/story";
import { App } from "./app";

export const start = story({ name: "App/Start", width: 480, height: 640, render: () => <App/> });
export const phone = story({ name: "App/Phone", render: () => <App/> });
```

Each story is a literal `story({name, width, height, render})` at the
module's top level, read before anything is built: no helper making it,
no spread in it; put any shared code inside `render`.

Add a story to add a screen; rename or remove one and the canvas follows.

The canvas is a storyboard of stills: each story shows its moment, it does
not run. For anything with motion or state, write a story for each key
moment, named for it ("Pong/Serve", "Pong/Game over"), posing the view
through props or state (`<Court state={{...serve(), score: [3, 2]}}/>`)
rather than running its clock, so the frame is exact and repeatable. A
story with `loop: 2` plays 2 s from its moment while its frame is hovered:
only where motion is the point. The app itself (`main.tsx`) is what Play
runs, in a window of its own, live.

## The loop

1. `studio.focus`: what the user looks at. Then `studio.working {note}`.
2. Ask only when a choice matters: draw the options as frames in a
   `<Group>` titled with the question (`studio.guide {topic: "design"}`),
   then `studio.ask` with options pointing at them (`frame:
   "sketches.helder#Dusk"`), without wait; keep working meanwhile. A
   prompt with no clear subject: 2-3 directions, asked so, and start on
   the first.
3. Make it real, a step at a time so the canvas grows with the work:
   first something that draws and a story of it, then one concept per
   step (a small `project.patch`, `build.check`, the screen updating),
   new stories as their moments exist. Each step real, no scaffolding;
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
