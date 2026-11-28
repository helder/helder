package helder.ui.controls;

import helder.ui.Key;
import helder.ui.Node;
import helder.ui.Svg;
import helder.ui.view.UiFlow.Popover;
import helder.view.graph.Read;
import helder.ui.controls.Variant;
import helder.ui.controls.Props;
import helder.ui.controls.Icons;
import helder.ui.view.UiView;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph;

// helder's standard controls, drawn by the nearest look (Themed's, else
// Look.base), their behaviour Press's and Toggle's: a Button, a Checkbox
// (indeterminate too), a Switch, a Slider, a Segmented choice and a
// Tooltip. A look that replaces one's rendering
// (render: {switch: Lamp}) is drawn instead, there and inside other
// widgets. A look's own variants: look.Button's (Look). A control under
// no look takes Look.base's theme as its own.
//
//   <Button variant="primary" onPress={save}>Save</Button>
//   <Checkbox label="Remember me" checked={remember} onChange={v -> remember(v)}/>
//   <Switch label="Dark mode" checked={dark} onChange={v -> dark(v)}/>
//   <Slider label="Weight" value={weight} min={20} max={200} step={1} onChange={weight}/>
//   <Segmented label="Tool" value={tool} options={[{value: "draw", label: "Draw"}, ...]} onChange={tool}/>
//   <Tooltip label="Tracing letter" keys="T"><Button icon={eye}/></Tooltip>
// (pinned to ui's renderer, UiView: drawn controls, of no other renderer)
class Standard implements Markup {
	public static function Button(props:ButtonProps<BaseVariants>):UiView {
		var look = Look.current();
		var render:Null<ButtonProps<Dynamic>->UiView> = look.renderOf("button");
		if (render != null) return render(cast props);
		var p = Press.of(props, "button");
		p.variant = props.variant ?? look.defaultOf("button", "variant");
		p.size = props.size ?? look.defaultOf("button", "size");
		var text = Std.isOfType(props.children, String), alone = props.children == null && props.icon != null;
		return <button tag={props.tag} ref={(n:Node) -> {
			p.root(n);
			// (an icon alone: square, no padding)
			if (alone) n.style = n.style.with({aspectRatio: 1, padding: 0});
		}}>
			<Show when={props.icon != null}><image ref={p.part("icon")} src={props.icon}/></Show>
			<Show when={text}><text ref={p.part("label")}>{props.children}</text></Show>
			<Show when={!text && props.children != null}>{props.children}</Show>
		</button>;
	}

	public static function PathBar(props:PathBarProps):UiView
		return <>{new PathBarMount(props)}</>;

	public static function Checkbox(props:CheckboxProps<BaseVariants>):UiView {
		var look = Look.current();
		var render:Null<CheckboxProps<Dynamic>->UiView> = look.renderOf("checkbox");
		if (render != null) return render(cast props);
		var t = new Toggle("checkbox", helder.ui.access.Role.CheckBox, props.checked, props.indeterminate, props.onChange, props.disabled);
		t.label = props.label;
		t.variant = props.variant ?? look.defaultOf("checkbox", "variant");
		t.size = props.size ?? look.defaultOf("checkbox", "size");
		return <view tag={props.tag} ref={(n:Node) -> t.root(n)}>
			<view ref={t.part("box")}>
				<image ref={t.part("mark")} src={() -> mark(t.mixed())}/>
			</view>
			<text aria-hidden ref={t.part("label")}>{props.label}</text>
		</view>;
	}

	public static function Switch(props:SwitchProps<BaseVariants>):UiView {
		var look = Look.current();
		var render:Null<SwitchProps<Dynamic>->UiView> = look.renderOf("switch");
		if (render != null) return render(cast props);
		var t = new Toggle("switch", helder.ui.access.Role.Switch, props.checked, null, props.onChange, props.disabled);
		t.label = props.label;
		t.variant = props.variant ?? look.defaultOf("switch", "variant");
		t.size = props.size ?? look.defaultOf("switch", "size");
		return <view tag={props.tag} ref={(n:Node) -> t.root(n)}>
			<view ref={t.part("track")}><view ref={t.part("knob")}/></view>
			<text aria-hidden ref={t.part("label")}>{props.label}</text>
		</view>;
	}

	// A number between min and max, shown as a field (its label inside on
	// the left, its value on the right, the part up to it filled): a press
	// or a drag anywhere sets it, the arrow keys step it (Shift: ten steps),
	// Home and End go to the ends. step 0: any value. Its look's parts:
	// "slider", "slider-fill", "slider-label", "slider-value".
	public static function Slider(props:{label:String, value:Read<Float>, min:Float, max:Float, ?step:Float, ?digits:Int, ?unit:String,
		onChange:Float->Void, ?tag:String}):UiView {
		var look = Look.current(), own = Look.outside();
		var step = props.step ?? 0.0, range = props.max - props.min;
		var digits = props.digits ?? (step >= 1 || step == 0 && range >= 20 ? 0 : step >= 0.1 ? 1 : 2);
		var root:Null<Node> = null, dragging = false;
		function fraction():Float {
			var f = range == 0 ? 0 : (props.value() - props.min) / range;
			return f < 0 ? 0 : f > 1 ? 1 : f;
		}
		function set(v:Float) {
			if (step > 0) v = props.min + Math.round((v - props.min) / step) * step;
			if (v < props.min) v = props.min;
			if (v > props.max) v = props.max;
			props.onChange(v);
		}
		function at(x:Float) {
			var r = root;
			if (r == null || r.width <= 0) return;
			set(props.min + (x - r.absX) / r.width * range);
		}
		function by(n:Float)
			set(props.value() + n * (step > 0 ? step : range / 100));
		return <view tag={props.tag} style={look.part("slider")} role="slider" aria-label={props.label} focusable aria-valuenow={props.value()}
			aria-valuemin={props.min} aria-valuemax={props.max} ref={(n:Node) -> {
				root = n;
				if (own) n.theme = look.theme;
			}} onPointerDown={e -> {
				root?.capture();
				dragging = true;
				at(e.x);
			}} onPointerMove={e -> if (dragging) at(e.x)} onPointerUp={_ -> dragging = false} onLostPointerCapture={_ -> dragging = false}
			onKeyDown={e -> {
				var shift = e.mods & helder.os.Mods.SHIFT != 0 ? 10 : 1;
				if (e.key == Key.RIGHT || e.key == Key.UP) by(shift) else if (e.key == Key.LEFT || e.key == Key.DOWN) by(-shift) else if (e.key == Key.HOME)
					set(props.min) else if (e.key == Key.END) set(props.max) else return;
				e.preventDefault();
			}}>
			<view style={look.part("slider-fill")} position="absolute" left={0} top={0} bottom={0} width={(fraction() * 100) + "%"} pointerEvents="none"/>
			<text style={look.part("slider-label")} flexGrow={1} pointerEvents="none">{props.label}</text>
			<text style={look.part("slider-value")} pointerEvents="none" fontVariantNumeric="tabular-nums">{format(props.value(), digits) + (props.unit ?? "")}</text>
		</view>;
	}

	// One of a few options side by side, the chosen one selected: a press
	// chooses, the arrow keys move between them (a radio group). compact:
	// an option with an icon shows the icon alone. Its look's parts:
	// "segmented", "segmented-item" (selected: the chosen; an icon follows its
	// colour).
	public static function Segmented(props:{label:String, value:Read<String>, options:Array<{value:String, label:String, ?icon:Svg, ?hint:String}>,
		onChange:String->Void, ?tag:String, ?compact:Bool}):UiView {
		var look = Look.current(), own = Look.outside();
		function move(by:Int) {
			var i = 0;
			for (k in 0...props.options.length)
				if (props.options[k].value == props.value()) i = k;
			var n = props.options.length;
			props.onChange(props.options[(i + by + n) % n].value);
		}
		return <view tag={props.tag} style={look.part("segmented")} role="radiogroup" aria-label={props.label} ref={(n:Node) -> if (own) n.theme = look.theme}
			onKeyDown={e -> {
			if (e.key == Key.RIGHT || e.key == Key.DOWN) move(1) else if (e.key == Key.LEFT || e.key == Key.UP) move(-1) else return;
			e.preventDefault();
		}}>
			<For each={props.options}>{(o:Read<{value:String, label:String, ?icon:Svg, ?hint:String}>) -> {
				var option = o();
				<button tag={props.tag == null ? null : props.tag + "-" + option.value} style={look.part("segmented-item")} role="radio"
					aria-label={option.hint ?? option.label} aria-checked={props.value() == option.value}
					data-state={props.value() == option.value ? "selected" : null}
					onPress={() -> props.onChange(option.value)}>
					<Show when={option.icon != null}><image src={option.icon} width={14} height={14} flexShrink={0}/></Show>
					<Show when={!(props.compact ?? false) || option.icon == null}><text>{option.label}</text></Show>
				</button>;
			}}</For>
		</view>;
	}

	// What a control does, said under it once the pointer rests on it (half
	// a second), with its shortcut beside it: for a button that shows only an
	// icon. A press or the pointer leaving hides it. Its look's parts: "tooltip",
	// "tooltip-keys".
	public static function Tooltip(props:{label:String, ?keys:String, ?placement:helder.ui.Placement, ?children:Any}):UiView {
		var look = Look.current(), own = Look.outside();
		// (on the animation clock: the same in a headless run as on a screen)
		var open = Graph.signal(false), hovered = -1.0;
		function hide() {
			hovered = -1;
			open(false);
		}
		Graph.onCleanup(hide);
		return <view flexDirection="row" onPointerEnter={_ -> {
			var since = hovered = helder.ui.Clock.now;
			helder.ui.Clock.add(now -> {
				if (hovered != since) return false;
				if (now - since < 0.5) return true;
				open(true);
				return false;
			});
		}} onPointerLeave={_ -> hide()} onPointerDown={_ -> hide()}>
			{props.children}
			<Popover open={open} placement={props.placement ?? Below} gap={6} dismissOnOutside={false}>
				<view style={look.part("tooltip")} role="tooltip" flexDirection="row" alignItems="center" columnGap={8} pointerEvents="none"
					ref={(n:Node) -> if (own) n.theme = look.theme}>
					<text>{props.label}</text>
					<Show when={props.keys != null}><text style={look.part("tooltip-keys")}>{props.keys ?? ""}</text></Show>
				</view>
			</Popover>
		</view>;
	}

	static function format(v:Float, digits:Int):String {
		if (digits <= 0) return Std.string(Math.round(v));
		var p = Math.pow(10, digits), s = Std.string(Math.round(Math.abs(v) * p));
		while (s.length <= digits)
			s = "0" + s;
		return (v < 0 && Math.round(Math.abs(v) * p) != 0 ? "-" : "") + s.substr(0, s.length - digits) + "." + s.substr(s.length - digits);
	}

	static var marks:Null<Array<helder.ui.Svg>> = null;

	// (a checkbox's mark: bolder than an icon's stroke, about 2 px at its size)
	static function mark(mixed:Bool):helder.ui.Svg {
		if (marks == null) marks = [for (d in ["M20 6 9 17l-5-5", "M5 12h14"]) Icons.parse(Icons.OPEN.split('stroke-width="2"').join('stroke-width="3.5"') + '<path d="$d"/></svg>')];
		return marks[mixed ? 1 : 0];
	}

	// a look for what it holds: its theme, and the look its controls draw with
	public static function Themed(props:{look:Look<Dynamic>, ?children:Any}):UiView {
		Graph.setContext(Look.context, props.look);
		// (no taller nor wider than where it is put: a scroller inside it scrolls)
		return <view flexGrow={1} minWidth={0} minHeight={0} ref={(n:Node) -> n.theme = props.look.theme}>{props.children}</view>;
	}
}
