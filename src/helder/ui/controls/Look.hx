package helder.ui.controls;

import helder.ui.Color;
import helder.ui.Rule;
import helder.ui.StyleSheet;
import helder.ui.Transition;
import helder.ui.controls.Tokens;
import helder.ui.controls.Variant;
import helder.ui.controls.Props;
import helder.ui.view.UiView;
import helder.view.graph.Context;
import helder.view.graph.Graph;

// What the controls look like: tokens, a recipe per control (a function
// of the tokens giving each part's style, by state and by variant), the
// renderings an app replaced, its own parts. Compiled once into a
// StyleSheet (sheet: a rule per part and state, its colours the tokens'
// light and dark values), which Rules runs: a control's states change
// what holds, nothing is made a frame. Look.base is helder's (Base); an
// app's is Look.base.with({...}) (LookOf.with: a patch's keys over the
// look's, by part and state, property by property; its variants added to
// the look's, which the controls' variant and size are checked against).
// <Themed look={look}> installs one for a subtree; a control outside any
// installs base for itself.
//
// Each state of a recipe is an amount that eases from 0 to 1 over the
// look's time for it (hoverTime, toggleTime, openTime): what blends
// (colours, opacity, transforms, shadows, rings) blends through the parts'
// transitions, which compile gives them (unless a part gives its own), on
// the quad every part already draws as; Eased has the amounts for what
// draws itself. Under reduced motion, travel jumps and colours fade.
class Look<V> {
	public static var base(get, never):LookOf<BaseVariants>;
	// the token references, as inline markup takes them (color={Look.ref.fg3}): resolved with the nearest sheet's colours
	public static var ref(get, never):Refs;
	// the look of the subtree (Themed's)
	public static final context:Context<Null<Look<Dynamic>>> = Graph.context((null : Look<Dynamic>));
	// (a TypeScript program's styles parsed: Styles.of, set by with)
	@:noCompletion public static var parse:Null<Dynamic->helder.ui.StyleProps> = null;

	static var baseLook:Null<Look<BaseVariants>> = null;
	static var refs0:Null<Refs> = null;

	public final tokens:Tokens;
	final density:Density;
	final accent:Accent;
	final tokenPatch:Dynamic;
	final recipes:Map<String, Array<Refs->Dynamic>>;
	final renders:Map<String, Dynamic>;
	final parts:Map<String, Array<Refs->Dynamic>>;
	var compiled:Null<Compiled> = null;

	function new(density:Density, accent:Accent, tokenPatch:Dynamic, recipes, renders, parts) {
		this.density = density;
		this.accent = accent;
		this.tokenPatch = tokenPatch;
		this.recipes = recipes;
		this.renders = renders;
		this.parts = parts;
		tokens = TokenSet.accented(TokenSet.merged(TokenSet.make(density, accent), tokenPatch), tokenPatch);
	}

	static function get_base():LookOf<BaseVariants> {
		if (baseLook == null) {
			Base.font();
			baseLook = Base.look();
		}
		return cast baseLook;
	}

	static function get_ref():Refs {
		if (refs0 == null) refs0 = TokenSet.refs(base.tokens);
		return refs0;
	}

	// a tone (a token's light and dark colours), as CSS writes them (one for both)
	public static function tone(light:String, ?dark:String):Tone {
		var l = Color.parse(light);
		return {light: l, dark: dark == null ? l : Color.parse(dark)};
	}

	// (the look a control mounted here takes: the subtree's, else base)
	@:noCompletion public static function current():Look<Dynamic>
		return (helder.view.graph.Owner.current == null ? null : Graph.use(context)) ?? cast base;

	// (the default look: Base's recipes)
	@:noCompletion public static function make(recipes:Map<String, Array<Refs->Dynamic>>):Look<BaseVariants>
		return new Look(Comfortable, Graphite, {}, recipes, new Map(), new Map());

	// this look with a patch over it (TypeScript's; Haxe's: LookOf.with, which checks the patch)
	@:typescript.type("<P extends import('./style').LookPatch>(patch: P) => Look<V & import('./style').PatchVariants<P>>")
	public function with(patch:Recipe.TsPatch):Look<Dynamic> {
		parse = helder.ui.Styles.of;
		helder.ui.Rules.parse = helder.ui.Styles.of;
		return extend(patch);
	}

	@:noCompletion public function extend(patch:Dynamic):Look<Dynamic> {
		var p:Dynamic = patch ?? {};
		var d:Density = Reflect.field(p, "density") ?? density, a:Accent = Reflect.field(p, "accent") ?? accent;
		var t = TokenSet.merged(tokenPatch, Reflect.field(p, "tokens") ?? {});
		// (each control by its name: a field read by a name not known where
		// it is written is a TypeScript build's whole dynamic lookup)
		var rs = [for (k => v in recipes) k => v.copy()];
		function recipe(c:String, f:Null<Refs->Dynamic>)
			if (f != null) {
				if (!rs.exists(c)) rs.set(c, []);
				rs.get(c).push(f);
			}
		recipe("button", Reflect.field(p, "button"));
		recipe("checkbox", Reflect.field(p, "checkbox"));
		recipe("switch", Reflect.field(p, "switch") ?? Reflect.field(p, "switch_"));
		recipe("pathbar", Reflect.field(p, "pathbar"));
		var rn = [for (k => v in renders) k => v];
		var given:Dynamic = Reflect.field(p, "render");
		function render(c:String, f:Dynamic)
			if (f != null) rn.set(c, f);
		if (given != null) {
			render("button", Reflect.field(given, "button"));
			render("checkbox", Reflect.field(given, "checkbox"));
			render("switch", Reflect.field(given, "switch") ?? Reflect.field(given, "switch_"));
		}
		var ps = [for (k => v in parts) k => v.copy()];
		var own:Dynamic = Reflect.field(p, "parts");
		if (own != null)
			for (k in Reflect.fields(own)) {
				if (!ps.exists(k)) ps.set(k, []);
				var f:Refs->Dynamic = Reflect.field(own, k);
				ps.get(k).push(f);
			}
		return new Look(d, a, t, rs, rn, ps);
	}

	// the look's StyleSheet: its rules and colours, made once
	public function sheet():StyleSheet
		return result().sheet;

	// what its recipes read: the colours as references, the rest as they are
	public function refs():Refs
		return TokenSet.refs(tokens);

	// the Button, Checkbox and Switch whose variant and size are this look's
	// (the nearest look still draws them: Themed's); values, so that markup
	// of either language takes them as components (<look.Button>)
	public final Button:ButtonProps<V>->UiView = props -> Standard.Button(cast props);
	public final Checkbox:CheckboxProps<V>->UiView = props -> Standard.Checkbox(cast props);
	public final Switch:SwitchProps<V>->UiView = props -> Standard.Switch(cast props);

	// (a control's replaced rendering, its default variant and size, its parts' draws, its states' times)
	@:noCompletion public function renderOf(control:String):Null<Dynamic>
		return renders.get(control);

	@:noCompletion public function defaultOf(control:String, axis:String):Null<String> {
		var d = result().defaults.get(control);
		return d == null ? null : Reflect.field(d, axis);
	}

	@:noCompletion public function drawOf(slot:String):Null<Recipe.PartDraw>
		return result().draws.get(slot);

	@:noCompletion public function times():Array<Float>
		return [tokens.hoverTime, tokens.hoverTime, tokens.toggleTime, tokens.hoverTime, tokens.openTime];

	function result():Compiled {
		if (compiled == null) compiled = Compile.look(tokens, refs(), recipes, parts);
		return compiled;
	}
}

// (a compiled look: Look.result)
@:noCompletion class Compiled {
	public final sheet:StyleSheet;
	public final defaults:Map<String, Dynamic>;
	public final draws:Map<String, Recipe.PartDraw>;

	public function new(sheet, defaults, draws) {
		this.sheet = sheet;
		this.defaults = defaults;
		this.draws = draws;
	}
}
