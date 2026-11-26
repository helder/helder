// an attribute in CSS's kebab-case, its camel name said, in a component (in Haxe: RejectAttrUnknown.hx).
// expect: markup: flex-direction is written flexDirection (camel, as CSS's and HTML's are in JavaScript)
import { UiWindow, Surface } from "helder/ui";

function Row() {
	return <view flex-direction="row"><text>hi</text></view>;
}

UiWindow.run(<Surface title="x" width={100} height={100}><Row/></Surface>);
