// HTML's names are elements of their own, no view: or text: before them (in Haxe: RejectTagPrefix.hx).
// expect: markup: <view:button> is <button> (HTML's names, no prefix)
import {render} from "helder/view";
import {Node} from "helder/ui";

render(<view:button/>, new Node());
