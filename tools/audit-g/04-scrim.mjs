// Audit G 4: what a modal popover lays over the window behind it is its
// scrim: Popover's backdrop (a Color) is scrim, as is TouchMenu's slot
// (touch-menu-scrim). backdrop stays the window's material behind a
// transparent window (helder.os's WindowBackdrop: blur, mica, glass) and
// the glass' captured backdrop.
import { edit, done } from "./lib.mjs";

const POPOVER = ["src/helder/ui/view/UiFlow.hx", "src/helder/ui/index.d.ts"];
edit(() => true, (s, f) => {
	if (POPOVER.includes(f))
		s = s.replace(/\?modal:Bool, \?backdrop:Color/g, "?modal:Bool, ?scrim:Color").replace(/modal\?: boolean; backdrop\?: Color/g, "modal?: boolean; scrim?: Color")
			.replace("if (props.backdrop != null) p.style.background = props.backdrop;", "if (props.scrim != null) p.style.background = props.scrim;")
			.replace("a modal one's backdrop its colour", "a modal one's scrim its colour");
	s = s.replace(/touch-menu-backdrop/g, "touch-menu-scrim");
	// (Popover's uses: <Popover ... backdrop={...}>)
	s = s.replace(/(<Popover\b[^>]*?\s)backdrop=/g, "$1scrim=");
	if (f === "src/helder/ui/Popup.hx") s = s.replace("(its own style: a backdrop;", "(its own style: a scrim;");
	if (f === "src/helder/ui/Popups.hx") s = s.replace("on a modal one's backdrop, it.", "on a modal one's scrim, it.");
	if (f === "src/helder/ui/README.md") s = s.replace("or modal (a backdrop, the focus kept inside)", "or modal (a scrim, the focus kept inside)");
	return s;
});
done("04-scrim");
