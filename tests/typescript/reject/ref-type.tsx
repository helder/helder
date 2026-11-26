// A ref is given its element's node: a function of a TextNode is no
// image's ref (in Haxe: tests/view/reject/RefType.hx).
// expect: TS2322
import {render} from "helder/view";
import {Node, TextNode} from "helder/ui";

render(<image ref={(t: TextNode) => console.log(t.text)}/>, new Node());
