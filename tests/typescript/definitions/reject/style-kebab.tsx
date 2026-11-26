// A style property in CSS's kebab-case names the camel one markup writes (in Haxe: RejectStyleKebab.hx).
// expect: markup: flex-wrap is written flexWrap (camel, as CSS's and HTML's are in JavaScript)
import {render} from "helder/view";
import {Node} from "helder/ui";

render(<view flex-wrap="wrap"/>, new Node());
