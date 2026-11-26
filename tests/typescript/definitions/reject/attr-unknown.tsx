// an attribute none of ui's elements has, CSS's name for one of them, in a component (in Haxe: RejectAttrUnknown.hx).
// expect: helder.ui: no attribute flex-direction (not one of NodeRenderer's or Style's); did you mean direction?
import { UiWindow, Surface } from "helder/ui";

function Row() {
	return <view flex-direction="row"><text>hi</text></view>;
}

UiWindow.run(<Surface title="x" width={100} height={100}><Row/></Surface>);
