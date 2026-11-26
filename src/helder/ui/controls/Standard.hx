package helder.ui.controls;

import helder.ui.Node;
import helder.ui.Rules;
import helder.ui.controls.Variant;
import helder.ui.controls.Props;
import helder.ui.widgets.Icons;
import helder.ui.view.UiView;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph;

// helder's standard controls, drawn by the nearest look (Themed's, else
// Look.base), their behaviour Press's and Toggle's: a Button, a Checkbox
// (indeterminate too) and a Switch. A look that replaces one's rendering
// (render: {switch: Lamp}) is drawn instead, there and inside other
// widgets. A look's own variants: look.Button's (Look). A control under
// no look takes Look.base's sheet as its own.
//
//   <Button variant="primary" onPress={save}>Save</Button>
//   <Checkbox label="Remember me" checked={remember} onChange={v -> remember(v)}/>
//   <Switch label="Dark mode" checked={dark} onChange={v -> dark(v)}/>
// (pinned to ui's renderer, UiView: drawn controls, of no other renderer)
class Standard implements Markup {
	public static function Button(props:ButtonProps<BaseVariants>):UiView {
		var look = Look.current(), own = Graph.use(Look.context) == null;
		var render:Null<ButtonProps<Dynamic>->UiView> = look.renderOf("button");
		if (render != null) return render(cast props);
		var p = Press.of(props, "button");
		p.variant = props.variant ?? look.defaultOf("button", "variant");
		p.size = props.size ?? look.defaultOf("button", "size");
		var text = Std.isOfType(props.children, String), alone = props.children == null && props.icon != null;
		return <button tag={props.tag} ref={(n:Node) -> {
			p.root(n);
			if (own) n.theme = look.sheet();
			// (an icon alone: square, no padding)
			if (alone) {
				n.style.aspectRatio = 1;
				n.style.padding = 0;
				Rules.keep(n, ["padding"]);
			}
		}}>
			<Show when={props.icon != null}><image ref={p.part("icon")} src={props.icon}/></Show>
			<Show when={text}><text ref={p.part("label")}>{props.children}</text></Show>
			<Show when={!text && props.children != null}>{props.children}</Show>
		</button>;
	}

	public static function PathBar(props:PathBarProps):UiView
		return <>{new PathBarMount(props)}</>;

	public static function Checkbox(props:CheckboxProps<BaseVariants>):UiView {
		var look = Look.current(), own = Graph.use(Look.context) == null;
		var render:Null<CheckboxProps<Dynamic>->UiView> = look.renderOf("checkbox");
		if (render != null) return render(cast props);
		var t = new Toggle("checkbox", helder.ui.access.Role.CheckBox, props.checked, props.indeterminate, props.onChange, props.disabled);
		t.label = props.label;
		t.variant = props.variant ?? look.defaultOf("checkbox", "variant");
		t.size = props.size ?? look.defaultOf("checkbox", "size");
		return <view tag={props.tag} ref={(n:Node) -> {
			t.root(n);
			if (own) n.theme = look.sheet();
		}}>
			<view ref={t.part("box")}>
				<image ref={t.part("mark")} src={() -> mark(t.mixed())}/>
			</view>
			<text aria-hidden ref={t.part("label")}>{props.label}</text>
		</view>;
	}

	public static function Switch(props:SwitchProps<BaseVariants>):UiView {
		var look = Look.current(), own = Graph.use(Look.context) == null;
		var render:Null<SwitchProps<Dynamic>->UiView> = look.renderOf("switch");
		if (render != null) return render(cast props);
		var t = new Toggle("switch", helder.ui.access.Role.Switch, props.checked, null, props.onChange, props.disabled);
		t.label = props.label;
		t.variant = props.variant ?? look.defaultOf("switch", "variant");
		t.size = props.size ?? look.defaultOf("switch", "size");
		return <view tag={props.tag} ref={(n:Node) -> {
			t.root(n);
			if (own) n.theme = look.sheet();
		}}>
			<view ref={t.part("track")}><view ref={t.part("knob")}/></view>
			<text aria-hidden ref={t.part("label")}>{props.label}</text>
		</view>;
	}

	static var marks:Null<Array<helder.ui.Svg>> = null;

	// (a checkbox's mark: bolder than an icon's stroke, about 2 px at its size)
	static function mark(mixed:Bool):helder.ui.Svg {
		if (marks == null) marks = [for (d in ["M20 6 9 17l-5-5", "M5 12h14"]) Icons.parse(Icons.OPEN.split('stroke-width="2"').join('stroke-width="3.5"') + '<path d="$d"/></svg>')];
		return marks[mixed ? 1 : 0];
	}

		// a look for what it holds: its sheet, and the look its controls draw with
	public static function Themed(props:{look:Look<Dynamic>, ?children:Any}):UiView {
		Graph.setContext(Look.context, props.look);
		// (no taller nor wider than where it is put: a scroller inside it scrolls)
		return <view flexGrow={1} minWidth={0} minHeight={0} ref={(n:Node) -> n.theme = props.look.sheet()}>{props.children}</view>;
	}
}
