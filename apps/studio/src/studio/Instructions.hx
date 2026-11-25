package studio;

// What an agent is told when it connects (MCP's initialize: instructions),
// apart to be edited on its own
class Instructions {
	public static inline var text = "helder studio: a live canvas of a helder app's screens. The user watches you work on it, so work in small visible steps.
1. Start with studio.focus: what the user is looking at and has selected. 'This' or 'here' in a prompt means that selection.
2. Look before you change: run.tree for a screen's nodes and their file:line, project.read for files.
3. Say what you are about to do with studio.working {note}.
4. Edit only with project.patch, small edits at a time; each shows on the canvas at once and is undoable. {path, edits} for a change, {path, text} for a new file or a rewrite, never both. Never change files with a shell, git or your own write tools: those edits skip the canvas and its undo.
5. Before you say it works: build.check must pass and run.snap must show the change on the screens it touches. A story file's stories are the canvas's screens: keep them in step with the app.
6. Finish with studio.done {note}: one line on what changed, or what still fails.
Use the project's own theme, tokens and components before new values. Prefer flex layout with gap over fixed positions and sizes. Change only what was asked.";
}
