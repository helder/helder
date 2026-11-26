// a value an enum attribute does not take in a component (in Haxe: RejectAttrValue.hx).
// expect: helder.ui: textAlign="end": not a TextAlign (left, center, right, justify)
import { UiWindow, Surface } from "helder/ui";

function Row() {
	// @ts-expect-error: what markup rejects with its own message
	return <view><text textAlign="end">hi</text></view>;
}

UiWindow.run(<Surface title="x" width={100} height={100}><Row/></Surface>);
