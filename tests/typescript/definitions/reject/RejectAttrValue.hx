// a value an enum attribute does not take in a component (in TypeScript: attr-value.tsx).
// expect: helder.ui: textAlign="end": not a TextAlign (left, center, right, justify)
import helder.ui.UiWindow;
import helder.ui.UiWindow.Surface;

class RejectAttrValue implements helder.view.Markup {
	static function main()
		UiWindow.run(<Surface title="x" width={100} height={100}><Row/></Surface>);

	static function Row(props:{})
		return <view><text textAlign="end">hi</text></view>;
}
