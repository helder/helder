// Helder's old name of a style property CSS has names CSS's (in Haxe: RejectStyleOld.hx).
// expect: markup: grow is flexGrow (CSS's name, in camel)
import {render} from "helder/view";
import {Node} from "helder/ui";

// @ts-expect-error: what markup rejects with its own message
render(<view grow={1}/>, new Node());
