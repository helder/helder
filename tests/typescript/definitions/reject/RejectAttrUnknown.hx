// an attribute none of ui's elements has, CSS's name for one of them, in a component (in TypeScript: attr-unknown.tsx).
// expect: helder.ui: no attribute flex-direction (not one of NodeRenderer's or Style's); did you mean direction?
import helder.ui.UiWindow;
import helder.ui.UiWindow.Surface;

class RejectAttrUnknown implements helder.view.Markup {
	static function main()
		UiWindow.run(<Surface title="x" width={100} height={100}><Row/></Surface>);

	static function Row(props:{})
		return <view flex-direction="row"><text>hi</text></view>;
}
