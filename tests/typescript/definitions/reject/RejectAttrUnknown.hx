// an attribute in CSS's kebab-case, its camel name said, in a component (in TypeScript: attr-unknown.tsx).
// expect: markup: flex-direction is written flexDirection (camel, as CSS's and HTML's are in JavaScript)
import helder.ui.UiWindow;
import helder.ui.UiWindow.Surface;

class RejectAttrUnknown implements helder.view.Markup {
	static function main()
		UiWindow.run(<Surface title="x" width={100} height={100}><Row/></Surface>);

	static function Row(props:{})
		return <view flex-direction="row"><text>hi</text></view>;
}
