// title: Controls
// summary: helder's standard controls in Look.base: the button's variants and sizes, a checkbox on, off and mixed, a switch, light and dark
// tags: ui, controls, docs
// demo: canvas 560x360
import helder.ui.controls.Look;
import helder.ui.controls.Standard;
import helder.ui.draw.UiWindow;
import helder.ui.draw.UiWindow.Surface;
import helder.ui.widgets.Icons;
import helder.view.*;
import helder.view.graph.Graph.*;

// The controls' variants side by side (the docs' Controls page): Button's
// variants in its three sizes and disabled, an icon alone, then a checkbox
// off, on and mixed and a switch, which turns dark mode on.
class Controls implements Markup {
	static function main() {
		var dark = signal(false);
		UiWindow.run(<Surface title="Controls" width={560} height={360} dark={dark}>
			<Standard.Themed look={Look.base}>
				<view grow={1} padding={20} row-gap={12} background={Look.ref.canvas} color={Look.ref.fg} font-family="Inter" font-size={14}>
					{[for (v in ["primary", "secondary", "outline", "ghost", "danger"]) <view direction="row" align-items="center" column-gap={10}>
						{button(v, "sm")}{button(v, "md")}{button(v, "lg")}{button(v, "md", true)}
					</view>]}
					<view direction="row" align-items="center" column-gap={20}>
						<Standard.Button icon={Icons.svg("search")} label="Search"/>
						<Standard.Checkbox label="Off"/>
						<Standard.Checkbox label="On" checked={true}/>
						<Standard.Checkbox label="Mixed" indeterminate={true}/>
						<Standard.Switch label="Dark" checked={dark} onChange={v -> dark(v)}/>
					</view>
				</view>
			</Standard.Themed>
		</Surface>);
	}

	static function button(variant:String, size:String, off = false):View
		return switch [variant, size] {
			case ["primary", "sm"]: <Standard.Button variant="primary" size="sm" disabled={off}>Small</Standard.Button>;
			case ["primary", "lg"]: <Standard.Button variant="primary" size="lg" disabled={off}>Large</Standard.Button>;
			case ["primary", _]: <Standard.Button variant="primary" disabled={off}>{off ? "Disabled" : "Primary"}</Standard.Button>;
			case ["secondary", "sm"]: <Standard.Button variant="secondary" size="sm" disabled={off}>Small</Standard.Button>;
			case ["secondary", "lg"]: <Standard.Button variant="secondary" size="lg" disabled={off}>Large</Standard.Button>;
			case ["secondary", _]: <Standard.Button variant="secondary" disabled={off}>{off ? "Disabled" : "Secondary"}</Standard.Button>;
			case ["outline", "sm"]: <Standard.Button variant="outline" size="sm" disabled={off}>Small</Standard.Button>;
			case ["outline", "lg"]: <Standard.Button variant="outline" size="lg" disabled={off}>Large</Standard.Button>;
			case ["outline", _]: <Standard.Button variant="outline" disabled={off}>{off ? "Disabled" : "Outline"}</Standard.Button>;
			case ["ghost", "sm"]: <Standard.Button variant="ghost" size="sm" disabled={off}>Small</Standard.Button>;
			case ["ghost", "lg"]: <Standard.Button variant="ghost" size="lg" disabled={off}>Large</Standard.Button>;
			case ["ghost", _]: <Standard.Button variant="ghost" disabled={off}>{off ? "Disabled" : "Ghost"}</Standard.Button>;
			case [_, "sm"]: <Standard.Button variant="danger" size="sm" disabled={off}>Small</Standard.Button>;
			case [_, "lg"]: <Standard.Button variant="danger" size="lg" disabled={off}>Large</Standard.Button>;
			case _: <Standard.Button variant="danger" disabled={off}>{off ? "Disabled" : "Danger"}</Standard.Button>;
		}
}
