// An element takes its own attributes: a text area's rows on a view names whose (in Haxe: RejectAttributeElement.hx).
// expect: markup: <view> has no attribute rows (<textarea>'s)
import {render} from "helder/view";
import {Node} from "helder/ui";

// @ts-expect-error: what markup rejects with its own message
render(<view rows={3}/>, new Node());
