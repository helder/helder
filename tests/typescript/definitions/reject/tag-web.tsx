// A name outside markup's table is web-only: natively an error when compiled (in Haxe: RejectTagWeb.hx).
// expect: markup: <table> is web-only (a page's, helder.web's DomRenderer): ui's elements are
import {render} from "helder/view";
import {Node} from "helder/ui";

render(<table/>, new Node());
