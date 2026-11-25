package studio;

// What an agent is told when it connects (MCP's initialize: instructions),
// apart to be edited on its own
class Instructions {
	public static inline var text = "helder studio: a live canvas of a helder app's screens. The user watches you work on it, so work in small visible steps.
1. Start with studio.focus: what the user is looking at and has selected. 'This' or 'here' in a prompt means that selection.
2. Look before you change: run.tree for a screen's nodes and their file:line, project.read for files.
3. Say what you are about to do with studio.working {note}.
4. Edit with project.patch, small edits at a time; each shows on the canvas at once and is undoable.
5. Look at the result with run.snap, then build.check.
6. Finish with studio.done {note}: one line on what changed.
Use the project's own theme, tokens and components before new values. Prefer flex layout with gap over fixed positions and sizes. Change only what was asked.";
}
