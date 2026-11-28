package helder.ui.controls;

import helder.ui.Style;
import helder.ui.Style.GroupProps;
import helder.ui.Style.Props;
import helder.ui.Transition;

// A look's recipes as Styles (Look.style, Look.part): a part's style in
// each recipe's result (a patch's over the look's), then its variant's,
// then its size's, merged property by property, state by state. A part
// follows its control's states: its root is a group (Press), and its
// other parts' states are compiled into group variants, recursively
// (checked: {hover: ...} the group's checked, then its hover); the root's
// are its own, as a composite's (a path bar's) pieces', each pressed
// alone. Each control's parts ease what their states change over the
// look's times (a transition each, unless a part gives its own): a
// hover's for a button, a toggle's for the others, a toggle's travel
// (its knob's) springing.
@:noCompletion class Compile {
	static final COMPOSITE = ["pathbar"];
	// (a toggle's travel: a spring's overshoot, as a cubic Bézier)
	static final SPRING = [0.3, 1.35, 0.55, 1.0];

	// (results: each recipe's, in order)
	public static function style(results:Array<Dynamic>, control:String, variant:Null<String>, size:Null<String>, part:String, tokens:Tokens):Style {
		var p = new Props();
		inline function add(o:Dynamic)
			if (o != null) p = Style.merge(p, Props.from(o));
		for (r in results) add(Reflect.field(r, part));
		for (r in results) add(of(r, "variant", variant, part));
		for (r in results) add(of(r, "size", size, part));
		if (p.transition == null) p.transition = eases(control, tokens);
		if (part != "root" && COMPOSITE.indexOf(control) < 0) p = grouped(p);
		return Style.intern(p);
	}

	// (an app's own part: each recipe's merged)
	public static function part(results:Array<Dynamic>):Style {
		var p = new Props();
		for (r in results) if (r != null) p = Style.merge(p, Props.from(r));
		return Style.intern(p);
	}

	// (a variant's part: variants.variant.primary.root)
	static function of(r:Dynamic, axis:String, value:Null<String>, part:String):Dynamic {
		if (value == null) return null;
		var v:Dynamic = Reflect.field(r, "variants");
		if (v != null) v = Reflect.field(v, axis);
		if (v != null) v = Reflect.field(v, value);
		return v == null ? null : Reflect.field(v, part);
	}

	// (each look's transitions: made once, so that its styles intern alike)
	static final made = new Map<String, Transition>();

	static function eases(control:String, t:Tokens):Transition {
		var toggle = control == "checkbox" || control == "switch";
		var key = '$toggle ${t.hoverTime} ${t.toggleTime}', e = made.get(key);
		if (e == null) {
			var time = toggle ? t.toggleTime : t.hoverTime;
			made.set(key, e = new Transition(Transition.EASED, [for (_ in Transition.EASED) time], null,
				[for (p in Transition.EASED) p == "transform" && toggle ? SPRING : Transition.EASE_OUT]));
		}
		return e;
	}

	// (p's states its group's: a part following its control's; placeholder and dark its own)
	static function grouped(p:Null<Props>):Null<Props> {
		if (p == null) return null;
		var o = Style.merge(p, new Props()), g = new GroupProps(), was = p.group;
		g.hover = join(was?.hover, grouped(p.hover));
		g.pressed = join(was?.pressed, grouped(p.pressed));
		g.focus = join(was?.focus, grouped(p.focus));
		g.disabled = join(was?.disabled, grouped(p.disabled));
		g.selected = join(was?.selected, grouped(p.selected));
		g.checked = join(was?.checked, grouped(p.checked));
		g.mixed = join(was?.mixed, grouped(p.mixed));
		o.hover = o.pressed = o.focus = o.disabled = o.selected = o.checked = o.mixed = null;
		o.dark = grouped(p.dark);
		o.placeholder = grouped(p.placeholder);
		o.group = g;
		return o;
	}

	static function join(a:Null<Props>, b:Null<Props>):Null<Props>
		return a == null ? b : b == null ? a : Style.merge(a, b);
}
