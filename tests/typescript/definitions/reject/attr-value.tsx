// a value an enum attribute does not take, CSS's, in a component (in Haxe: RejectAttrValue.hx).
// expect: helder.ui: text-align="end": not a TextAlign (left, center, right, justify)
import { UiWindow, Surface } from "helder/ui";

function Row() {
	return <view><text text-align="end">hi</text></view>;
}

UiWindow.run(<Surface title="x" width={100} height={100}><Row/></Surface>);
