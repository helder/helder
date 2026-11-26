// React's names are warnings naming HTML's (set as those); rejected for the view's grow (in Haxe: RejectReactNames.hx).
// expect: markup: htmlFor is for in helder's markup (as HTML writes it)
// expect: markup: className is class in helder's markup (as HTML writes it)
// expect: markup: grow is flexGrow (CSS's name, in camel)
import {render} from "helder/view";
import {Node} from "helder/ui";

// @ts-expect-error: what markup rejects with its own message
render(<view className="row"><label htmlFor="name">Name</label><view grow={1}/></view>, new Node());
