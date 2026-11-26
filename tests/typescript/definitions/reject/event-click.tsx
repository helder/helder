// A ui element's press is onPress: onClick, a page's, names it (in Haxe: RejectEventClick.hx).
// expect: markup: onClick is a page's; a ui element's press (a click, Enter or Space) is onPress
import {render} from "helder/view";
import {Node} from "helder/ui";

// @ts-expect-error: what markup rejects with its own message
render(<button onClick={() => console.log("x")}/>, new Node());
