package helder.ui.controls;

import helder.ui.Rule;
import helder.ui.StyleProps;
import helder.ui.StyleSheet;
import helder.ui.Transition;
import helder.ui.controls.Tokens;

// A look's recipes as a StyleSheet (Look.sheet): each recipe run with the
// tokens' references, the results merged in order (by part, state and
// variant, property by property: a patch's keys over the look's), then a
// rule for each part and state. A part's slot is its control's ("button")
// and its name ("button-icon"); the root's states are its own, a part's its
// root's (group/button:hover: the root a group of its slot, the sheet's
// markers; a path bar's parts, each pressed alone: their own), as are a
// variant's and a size's. Each control's parts ease what
// their states change over the look's times (a transition each, unless a
// part gives its own): a hover's for a button, a toggle's for the others,
// a toggle's travel (its knob's) springing.
@:noCompletion class Compile {
	public static final CONTROLS = ["button", "checkbox", "switch", "pathbar"];
	static final STATES = ["hover", "pressed", "focus", "checked", "mixed", "selected", "open", "invalid", "readonly", "dark", "disabled", "focusWithin"];
	static final CONDS = [
		"hover", "active", "focus-visible", "data-state=checked", "data-state=mixed", "data-selected", "data-state=open", "data-invalid", "data-readonly", "dark",
		"data-disabled", "has:focus"
	];
	static final AXES = ["variant", "size"];
	// (a toggle's travel: a spring's overshoot, as a cubic Bézier)
	static final SPRING = [0.3, 1.35, 0.55, 1.0];

	static final COMPOSITE = ["pathbar"];

	// (a part's slot: segmentIcon's "pathbar-segment-icon")
	static function slotOf(control:String, part:String):String {
		if (part == "root") return control;
		var slot = control + "-";
		for (i in 0...part.length) {
			var ch = part.charAt(i), lower = ch.toLowerCase();
			slot += ch == lower ? ch : "-" + lower;
		}
		return slot;
	}

	public static function look(tokens:Tokens, refs:Refs, recipes:Map<String, Array<Refs->Dynamic>>, parts:Map<String, Array<Refs->Dynamic>>):Look.Compiled {
		var rules:Array<Rule> = [], markers = new Map<String, String>(), defaults = new Map<String, Dynamic>(), draws = new Map<String, Recipe.PartDraw>();
		for (c in CONTROLS) {
			var list = recipes.get(c);
			if (list == null) continue;
			var r = new Merged();
			for (f in list)
				r.add(call(f, refs));
			markers.set(c, "group/" + c);
			defaults.set(c, r.defaults);
			var toggle = c == "checkbox" || c == "switch", group = COMPOSITE.indexOf(c) < 0 ? c : null;
			var time = toggle ? tokens.toggleTime : tokens.hoverTime;
			var eases = new Transition(Transition.EASED, [for (p in Transition.EASED) p == "ringWidth" || p == "ringColor" ? tokens.hoverTime : time], null,
				[for (p in Transition.EASED) p == "transform" && toggle ? SPRING : Transition.EASE_OUT]);
			for (name => part in r.parts) {
				var slot = slotOf(c, name);
				if (part.draw != null) draws.set(slot, part.draw);
				emit(rules, slot, part, [], name == "root" ? null : group, null, null, eases);
			}
			for (axis in AXES)
				for (value => byPart in r.variants.get(axis))
					for (name => part in byPart) {
						var root = name == "root";
						var slot = slotOf(c, name);
						if (root) emit(rules, slot, part, [], null, axis == "variant" ? value : null, axis == "size" ? value : null, null)
						else emit(rules, slot, part, ['group/$c:$axis=$value'], group, null, null, null);
					}
		}
		for (name => list in parts) {
			var part = new Part();
			for (f in list)
				part.add(call(f, refs));
			emit(rules, name, part, [], null, null, null, null);
		}
		var light = new Map<String, helder.gfx.Color>(), dark = new Map<String, helder.gfx.Color>();
		var tones = TokenSet.tones(tokens);
		for (k in 0...tones.length) {
			var t = tones[k];
			if (t == null) continue;
			light.set(TokenSet.COLORS[k], t.light);
			dark.set(TokenSet.COLORS[k], t.dark);
		}
		return new Look.Compiled({rules: rules, light: light, dark: dark, markers: markers}, defaults, draws);
	}

	// (a recipe: a function of the references)
	static inline function call(f:Refs->Dynamic, refs:Refs):Dynamic
		return f(refs);

	// (a part's rules: its style, then each state's (its condition after
	// those it is under: the root's own, a part's its group's), a part's
	// transition with its style unless it gives one)
	static function emit(rules:Array<Rule>, slot:String, part:Part, when:Array<String>, group:Null<String>, variant:Null<String>, size:Null<String>,
			eases:Null<Transition>) {
		var props:Dynamic = Reflect.copy(part.props);
		if (eases != null && Reflect.field(props, "transition") == null) Reflect.setField(props, "transition", eases);
		if (Reflect.fields(props).length > 0) {
			var style:StyleProps = Look.parse == null ? props : Look.parse(props);
			rules.push({
				slot: slot,
				variant: variant,
				size: size,
				when: when.length == 0 ? null : when,
				style: style
			});
		}
		for (k in 0...STATES.length) {
			var s = part.states.get(STATES[k]);
			if (s == null) continue;
			var cond = group == null || STATES[k] == "dark" ? CONDS[k] : 'group/$group:${CONDS[k]}';
			emit(rules, slot, s, when.concat([cond]), group, variant, size, null);
		}
	}
}

// (a recipe's results merged: its parts, each variant's, its defaults)
private class Merged {
	public final parts = new Map<String, Part>();
	public final variants = ["variant" => new Map<String, Map<String, Part>>(), "size" => new Map<String, Map<String, Part>>()];
	public final defaults:Dynamic = {};

	public function new() {}

	public function add(r:Dynamic) {
		if (r == null) return;
		for (k in Reflect.fields(r)) {
			var v:Dynamic = Reflect.field(r, k);
			if (v == null) continue;
			switch k {
				case "variants":
					for (axis in Reflect.fields(v)) {
						var into = variants.get(axis);
						if (into == null) throw 'helder.ui.controls: no variant axis $axis (variant, size)';
						var values:Dynamic = Reflect.field(v, axis);
						for (value in Reflect.fields(values)) {
							var byPart = into.get(value);
							if (byPart == null) into.set(value, byPart = new Map());
							var ps:Dynamic = Reflect.field(values, value);
							for (name in Reflect.fields(ps))
								partOf(byPart, name).add(Reflect.field(ps, name));
						}
					}
				case "defaults":
					for (axis in Reflect.fields(v))
						Reflect.setField(defaults, axis, Reflect.field(v, axis));
				case _:
					partOf(parts, k).add(v);
			}
		}
	}

	static function partOf(m:Map<String, Part>, name:String):Part {
		var p = m.get(name);
		if (p == null) m.set(name, p = new Part());
		return p;
	}
}

// (a part's style merged: its properties, its states', its draw)
private class Part {
	static final STATES = ["hover", "pressed", "focus", "checked", "mixed", "selected", "open", "invalid", "readonly", "dark", "disabled", "focusWithin"];

	public final props:Dynamic = {};
	public final states = new Map<String, Part>();
	public var draw:Null<Recipe.PartDraw> = null;

	public function new() {}

	public function add(o:Dynamic) {
		if (o == null) return;
		for (k in Reflect.fields(o)) {
			var v:Dynamic = Reflect.field(o, k);
			if (v == null) continue;
			if (STATES.indexOf(k) >= 0) {
				var s = states.get(k);
				if (s == null) states.set(k, s = new Part());
				s.add(v);
			} else if (k == "draw") draw = v else Reflect.setField(props, k, v);
		}
	}
}
