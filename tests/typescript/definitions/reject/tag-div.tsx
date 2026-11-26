// A page's div is no ui element: natively an error naming the one meant (in Haxe: RejectTagDiv.hx).
// expect: markup: <div> is no ui element; did you mean <view>?
import {render} from "helder/view";
import {Node} from "helder/ui";

render(<div/>, new Node());
