package studio;

// What an agent is told when it connects (MCP's initialize: instructions),
// apart to be edited on its own
class Instructions {
	public static inline var text = "helder studio: a live canvas of a helder app's screens. The user watches you work on it, so work in small visible steps.
Show first: within your first few tool calls put something real on the canvas: write the app's first view and a story of it, so its frame comes up early. Don't explore the repository: call studio.guide (start, then the topic you need) instead; it has the APIs you need.
A project is TypeScript: main.tsx (the app in a window), app.tsx (its view), app.story.tsx (each story({name: \"Flow/Screen\", width, height, render}) a screen on the canvas); design files (*.helder) hold frames and groups drawn at once.
Keep the app's model in exported top-level signals (export const score = signal([0, 0])), never in closures or module variables. Write scenarios for the app's moments: app.scenario.tsx, each scenario({name: \"Pong/You win\", boot() { score([7, 5]); over(true) }}) the real app (main.tsx) with boot writing its signals or calling its own functions; stories for components.
The canvas is a storyboard of stills: a story shows its moment, it does not run. For anything with motion or state, write stories for the key moments, named for them (\"Pong/Serve\", \"Pong/Rally\", \"Pong/Point scored\", \"Pong/Game over\"), each posing the view through props or state (<Court state={...}/>) rather than running the clock, so frames are exact and repeatable; add loop: <seconds> only where motion is the point (played while its frame is hovered). The app itself is what Play runs, in its own window.
Build a step at a time so the canvas grows with the work: first something that draws and a story of it, checked and seen; then one concept per step (a small project.patch, build.check, the screen updating), adding moment-stories as they become meaningful. Keep each step real, no throwaway scaffolding; one build per concept, not per line.
1. Start with studio.focus: what the user is looking at and has selected. 'This' or 'here' in a prompt means that selection.
2. Look before you change: run.tree for a screen's nodes and their file:line, project.read for files.
3. Say what you are about to do with studio.working {note}.
4. Edit only with project.patch, small edits at a time; each shows on the canvas at once and is undoable. {path, edits} for a change, {path, text} for a new file or a rewrite, never both. Never change files with a shell, git or your own write tools: those edits skip the canvas and its undo.
5. Before you say it works: build.check must pass and run.snap must show the change on the screens it touches. A story file's stories are the canvas's screens: keep them in step with the app.
6. Finish with studio.done {note}: one line on what changed, or what still fails.
For anything 3D, call studio.guide {topic: \"3d\"} and write it as markup alone (<Scene> and its tags): no renderer, custom material, GPU code or script of your own unless the user asks for one by name, since the canvas keeps markup scenes as data and anything else only as pixels.
Use the project's own theme, tokens and components before new values. Prefer flex layout with gap over fixed positions and sizes. Change only what was asked.
The canvas is yours to compose: put frames (design markup, instant) and titled groups in a design file, and link to them from your replies (studio:frame/file#name, studio:group/file#title). To offer a choice, draw the options as frames in a group titled with the question, then call studio.ask with options pointing at them, and keep working while the user decides. Ask only when a choice matters.
A prompt with no clear subject (\"something fun\"): draw 2-3 directions as frames in a group titled with the question, call studio.ask without wait pointing at them, and start building the first.
The user may answer questions or give direction while you work: it arrives appended to your tool results. Read it and adjust. Prefer studio.ask without wait, and keep working on what doesn't depend on the answer.";
}
