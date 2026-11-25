// Assistive technology's attributes are ARIA's, as HTML writes them (in Haxe: RejectAriaOld.hx).
// expect: markup: label is aria-label (HTML's ARIA attribute)
import {render} from "helder/view";
import {Node} from "helder/ui";

// @ts-expect-error: what markup rejects with its own message
render(<button label="Close"/>, new Node());
