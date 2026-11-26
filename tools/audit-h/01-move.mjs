// Audit H 1: what helder.ui.widgets held that the controls build on, or
// that has no control of its own to become, moves into helder.ui.controls
// as it is: the editors (TextField, TextArea, EditableText: markup's input
// and textarea, the code editor's and the fields'), Icons, DataGrid with
// GridColumn and GridTheme, WindowButtons (WindowControls) and Pager
// (Pages). TypeScript has them as helder/ui's, by the same names.
import { edit, move, done } from "./lib.mjs";

const MOVED = ["TextField", "TextArea", "EditableText", "Icons", "DataGrid", "GridColumn", "GridTheme", "WindowButtons", "Pager"];
for (const t of MOVED) {
	move(`src/helder/ui/widgets/${t}.hx`, `src/helder/ui/controls/${t}.hx`);
	move(`src/helder/ui/widgets/${t}.test.hx`, `src/helder/ui/controls/${t}.test.hx`);
}

const NAME = `(${MOVED.join("|")})`;
edit(() => true, (s, f) => {
	if (f.startsWith("src/helder/ui/controls/") && MOVED.some((t) => f === `src/helder/ui/controls/${t}.hx` || f === `src/helder/ui/controls/${t}.test.hx`))
		s = s.replace(/^package helder\.ui\.widgets;/m, "package helder.ui.controls;");
	return s
		.replace(new RegExp(`\\bhelder\\.ui\\.widgets\\.${NAME}\\b`, "g"), "helder.ui.controls.$1")
		.replace(new RegExp(`\\bsrc/helder/ui/widgets/${NAME}\\.hx\\b`, "g"), "src/helder/ui/controls/$1.hx");
});
done("01-move");
