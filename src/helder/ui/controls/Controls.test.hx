package helder.ui.controls;

import helder.test.Test;
import helder.ui.Clock;
import helder.ui.Color;
import helder.ui.Key;
import helder.ui.Node;
import helder.ui.Ui;
import helder.ui.controls.Props;
import helder.ui.controls.Variant;
import helder.view.Render;
import helder.view.View;
import helder.view.graph.Graph;
import helder.view.graph.Signal;

// The controls: Press's and Toggle's keys and states, the access tree's;
// Look.base's recipes as rules, look.with's token, variant, part and
// render; the eased states, a background blending between its rule's
// values; inline token references; a hover's restyle allocating nothing
function tests() {
	function mount(v:View, w = 320, h = 200):{ui:Ui, dispose:Void->Void} {
		var ui = new Ui(new helder.story.StoryText(), w, h);
		var dispose = Render.render(v, ui.root);
		ui.update();
		return {ui: ui, dispose: dispose};
	}
	// (laid out, and drawn as a paint marks what it drew: what changes from now on eases)
	function drawn(n:Node) {
		@:privateAccess n.style.drawn = true;
		for (c in n.children)
			drawn(c);
	}
	function settle(ui:Ui) {
		Graph.flush();
		ui.update();
		Clock.finish();
		ui.update();
		drawn(ui.root);
	}
	function light(name:String):Color
		return Look.base.sheet().light.get(name);
	function dark(name:String):Color
		return Look.base.sheet().dark.get(name);

	describe("Press", () -> {
		test("a click, Enter and Space press it; disabled, nothing and not focusable", () -> {
			var count = 0, off = Graph.signal(false);
			var m = mount(Fixture.button(() -> count++, off));
			var b = m.ui.root.find("save");
			equals(b.semantics.role, helder.ui.access.Role.Button);
			m.ui.pointerDown(b.absX + 4, b.absY + 4, 1);
			m.ui.pointerUp(b.absX + 4, b.absY + 4, 1);
			m.ui.setFocus(b);
			m.ui.keyDown(Key.ENTER, 0);
			m.ui.keyDown(Key.SPACE, 0);
			equals(count, 3);
			off(true);
			Graph.flush();
			m.ui.keyDown(Key.SPACE, 0);
			equals(count, 3);
			equals(b.focusable, false);
			equals(b.attr("data-disabled"), "");
			equals(b.semantics.disabled, true);
			m.dispose();
		});
		test("pressed while the pointer is down and over it, not once it leaves", () -> {
			var m = mount(Fixture.pressed());
			var b = m.ui.root.find("own");
			var p:Press = Fixture.lastPress;
			m.ui.pointerMove(b.absX + 4, b.absY + 4);
			m.ui.pointerDown(b.absX + 4, b.absY + 4, 1);
			Graph.flush();
			equals(p.hovered.peek(), true);
			equals(p.pressed.peek(), true);
			m.ui.pointerMove(b.absX + 300, b.absY + 150);
			Graph.flush();
			equals(p.pressed.peek(), false);
			m.dispose();
		});
	});

	describe("Toggle", () -> {
		test("a checkbox: Space and a click toggle it, Enter does not; mixed turns on", () -> {
			var on = Graph.signal(false), mixed = Graph.signal(true);
			var m = mount(Fixture.checkbox(on, mixed));
			var c = m.ui.root.find("terms");
			equals(c.semantics.role, helder.ui.access.Role.CheckBox);
			equals(c.attr("data-state"), "mixed");
			equals(c.semantics.mixed, true);
			m.ui.setFocus(c);
			m.ui.keyDown(Key.ENTER, 0);
			Graph.flush();
			equals(on.peek(), false);
			m.ui.keyDown(Key.SPACE, 0);
			Graph.flush();
			equals(on.peek(), true);
			mixed(false);
			Graph.flush();
			equals(c.attr("data-state"), "checked");
			m.ui.pointerDown(c.absX + 4, c.absY + 4, 1);
			m.ui.pointerUp(c.absX + 4, c.absY + 4, 1);
			Graph.flush();
			equals(on.peek(), false);
			equals(c.semantics.checked, false);
			m.dispose();
		});
		test("a switch: Enter toggles it too; its own state without checked", () -> {
			var m = mount(Fixture.plainSwitch());
			var s = m.ui.root.find("wifi");
			equals(s.semantics.role, helder.ui.access.Role.Switch);
			m.ui.setFocus(s);
			m.ui.keyDown(Key.ENTER, 0);
			Graph.flush();
			equals(s.attr("data-state"), "checked");
			equals(s.semantics.checked, true);
			m.dispose();
		});
	});

	describe("Look", () -> {
		test("base's recipes: a rule per part and state, its parts' states their root's", () -> {
			var rules = Look.base.sheet().rules;
			assert(Lambda.exists(rules, r -> r.slot == "button" && r.variant == "primary"), "a primary button");
			assert(Lambda.exists(rules, r -> r.slot == "switch-knob" && r.when != null && r.when.indexOf("group/switch:data-state=checked") >= 0),
				"a knob's checked, its switch's");
			equals(Look.base.sheet().markers.get("switch"), "group/switch");
		});
		test("a button's variant, its hover, light and dark", () -> {
			var m = mount(Fixture.primary());
			var b = m.ui.root.find("go");
			settle(m.ui);
			equals(b.style.background, light("accent"));
			equals(b.style.height, (36 : helder.ui.Dim));
			m.ui.pointerMove(b.absX + 4, b.absY + 4);
			settle(m.ui);
			equals(b.style.background, light("accentStrong"));
			m.ui.dark = true;
			settle(m.ui);
			equals(b.style.background, dark("accentStrong"));
			m.dispose();
		});
		test("the default variant and size, the defaults' own", () -> {
			var m = mount(Fixture.button(() -> {}, Graph.signal(false)));
			var b = m.ui.root.find("save");
			equals(b.variant, "secondary");
			equals(b.size, "md");
			settle(m.ui);
			equals(b.style.background, light("fill"));
			equals(b.style.borderColor, light("fill"));
			m.dispose();
		});
		test("with: a token, a variant, a part", () -> {
			var look = Look.base.with({
				tokens: {accent: Look.tone("#e11d48")},
				button: t -> {variants: {variant: {soft: {root: {background: t.accentSoft, color: t.accentInk}}}}},
				"switch": t -> {knob: {radius: 3}},
				density: Compact
			});
			var m = mount(<Standard.Themed look={look}>
				<view padding={10} row-gap={8}>
					<look.Button tag="go" variant="primary">Go</look.Button>
					<look.Button tag="soft" variant="soft">Soft</look.Button>
					<look.Switch tag="knob" label="Knob"/>
				</view>
			</Standard.Themed>);
			var go = m.ui.root.find("go"), soft = m.ui.root.find("soft"), knob = m.ui.root.find("knob").children[0].children[0];
			settle(m.ui);
			equals(go.style.background, Color.parse("#e11d48"));
			equals(soft.style.background, look.sheet().light.get("accentSoft"));
			equals(knob.slot, "switch-knob");
			equals(knob.style.radius, 3.0);
			equals(go.style.height, (30 : helder.ui.Dim));
			m.dispose();
		});
		test("with: a rendering replaced, its behaviour and access kept", () -> {
			var look = Look.base.with({render: {"switch": Fixture.lamp}});
			var on = Graph.signal(false);
			var m = mount(Fixture.lamped(look, on));
			var lamp = m.ui.root.find("lamp");
			equals(lamp.semantics.role, helder.ui.access.Role.Switch);
			equals(lamp.slot, "switch");
			m.ui.setFocus(lamp);
			m.ui.keyDown(Key.SPACE, 0);
			Graph.flush();
			equals(on.peek(), true);
			equals(lamp.children[0].slot, "switch-icon");
			m.dispose();
		});
	});

	describe("Eased", () -> {
		test("a state eases from 0 to 1 over its time; reduced motion jumps", () -> {
			var e = new Eased([0.1, 0.1, 0.2, 0.1, 0.2]), t0 = Clock.now;
			e.set(Eased.CHECKED, true);
			Clock.tick(t0 + 0.1);
			assert(e.checked > 0.5 && e.checked < 1, 'halfway: ${e.checked}');
			Clock.tick(t0 + 0.25);
			equals(e.checked, 1.0);
			Clock.reducedMotion = true;
			e.set(Eased.CHECKED, false);
			equals(e.checked, 0.0);
			Clock.reducedMotion = false;
		});
		test("a hover's background blends between its rule's values", () -> {
			var m = mount(Fixture.primary());
			var b = m.ui.root.find("go");
			settle(m.ui);
			var t0 = Clock.now;
			m.ui.pointerMove(b.absX + 4, b.absY + 4);
			Graph.flush();
			m.ui.update();
			Clock.tick(t0 + 0.01);
			Clock.tick(t0 + 0.05);
			m.ui.update();
			var mid:Color = b.style.background, from = light("accent"), to = light("accentStrong");
			assert(mid != from && mid != to, "between");
			settle(m.ui);
			equals(b.style.background, to);
			m.dispose();
		});
	});

	describe("Tokens", () -> {
		test("an inline token: the nearest sheet's colour, light and dark", () -> {
			var m = mount(Fixture.inlined());
			var n = m.ui.root.find("muted");
			settle(m.ui);
			equals(n.style.color, light("fg3"));
			m.ui.dark = true;
			settle(m.ui);
			equals(n.style.color, dark("fg3"));
			n.style.color = Color.rgb(0xFF0000);
			m.ui.dark = false;
			settle(m.ui);
			equals(n.style.color, Color.rgb(0xFF0000));
			m.dispose();
		});
	});

	#if (target.name == "hxmc")
	describe("Rules", () -> {
		test("a hover restyled, once its merges are made: nothing allocated", () -> {
			var m = mount(Fixture.primary());
			var b = m.ui.root.find("go");
			function hover(on:Bool) {
				m.ui.pointerMove(on ? b.absX + 4 : b.absX + 300, b.absY + 150 * (on ? 0 : 1) + 4);
				Clock.finish();
				m.ui.update();
			}
			for (_ in 0...3) {
				hover(true);
				hover(false);
			}
			var restyle = b;
			var before = hxmc.GcStats.threadBytesAllocated();
			for (_ in 0...50)
				@:privateAccess helder.ui.Rules.restyle(restyle);
			equals(hxmc.GcStats.threadBytesAllocated() - before, 0.0);
			m.dispose();
		});
	});
	#end
}

private class Fixture implements helder.view.Markup {
	public static var lastPress:Null<Press> = null;

	public static function button(onPress:Void->Void, off:Signal<Bool>):View
		return <view padding={10}><Standard.Button tag="save" onPress={onPress} disabled={off}>Save</Standard.Button></view>;

	public static function primary():View
		return <view padding={10}><Standard.Button tag="go" variant="primary">Go</Standard.Button></view>;

	public static function checkbox(on:Signal<Bool>, mixed:Signal<Bool>):View
		return <view padding={10}>
			<Standard.Checkbox tag="terms" label="Terms" checked={on} indeterminate={mixed} onChange={v -> {
				on(v);
				mixed(false);
			}}/>
		</view>;

	public static function plainSwitch():View
		return <view padding={10}><Standard.Switch tag="wifi" label="Wi-Fi"/></view>;

	public static function pressed():View {
		var p = lastPress = new Press("button");
		return <view padding={10}><view tag="own" ref={p.root} width={60} height={30}/></view>;
	}

	public static function lamp(props:SwitchProps<Dynamic>):View {
		var t = new Toggle("switch", Switch, props.checked, null, props.onChange);
		t.label = props.label;
		return <view tag="lamp" ref={t.root} direction="row">
			<view ref={t.part("icon")} width={24} height={24}/>
		</view>;
	}

	public static function lamped(look:LookOf<Dynamic>, on:Signal<Bool>):View
		return <Standard.Themed look={look}><Standard.Switch label="Porch" checked={on} onChange={v -> on(v)}/></Standard.Themed>;

	public static function inlined():View
		return <Standard.Themed look={Look.base}><text tag="muted" color={Look.ref.fg3}>muted</text></Standard.Themed>;
}
