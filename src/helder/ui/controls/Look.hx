package helder.ui.controls;

import helder.gfx.Color;
import helder.ui.Style;
import helder.ui.Theme;
import helder.ui.controls.Tokens;
import helder.ui.controls.Variant;
import helder.ui.controls.Props;
import helder.ui.view.UiView;
import helder.view.graph.Context;
import helder.view.graph.Graph;

// What the controls look like: tokens, a recipe per control (a function
// of the tokens giving each part's style, by state and by variant), the
// renderings an app replaced, its own parts. Its palette is a Theme (theme:
// each colour a token, light and dark), its recipes compiled into Styles
// (style: a control's part in a variant and size; part: the framework's
// own pieces, an app's), made once each: a control's states change which
// of a style's variants hold, nothing is made a frame. Look.base is
// helder's (Base); an app's is Look.base.with({...}) (LookOf.with: a
// patch's keys over the look's, by part and state, property by property;
// its variants added to the look's, which the controls' variant and size
// are checked against). <Themed look={look}> installs one for a subtree; a
// control outside any takes base's theme for itself.
//
// Each state of a recipe eases over the look's time for it (hoverTime,
// toggleTime): what blends (colours, opacity, transforms) blends through
// the parts' transitions, which Compile gives them (unless a part gives its
// own); Eased has the amounts for what draws itself. Under reduced motion,
// travel jumps and colours fade.
class Look<V> {
	public static var base(get, never):LookOf<BaseVariants>;
	// the tokens, as inline markup takes them (color={Look.ref.fg3}): the nearest look's theme's colours
	// (every one there: TypeScript's Refs, a patch's, has them optional)
	@:typescript.type("Required<Refs>") public static var ref(get, never):Refs;
	// the look of the subtree (Themed's)
	public static final context:Context<Null<Look<Dynamic>>> = Graph.context((null : Look<Dynamic>));

	static var baseLook:Null<Look<BaseVariants>> = null;

	// (every one there, as a patch's are not)
	@:typescript.type("Required<Tokens>") public final tokens:Tokens;
	// its palette as tokens (a subtree's: Node.theme)
	public final theme:Theme;
	// what its recipes read: the colours as the theme's tokens, the rest as they are
	public final refs:Refs;
	final density:Density;
	final accent:Accent;
	final tokenPatch:Dynamic;
	final recipes:Map<String, Array<Refs->Dynamic>>;
	final renders:Map<String, Dynamic>;
	final parts:Map<String, Array<Refs->Dynamic>>;
	// (each control's recipes run, each part's style by its key)
	final results = new Map<String, Array<Dynamic>>();
	final styles = new Map<String, Style>();

	function new(density:Density, accent:Accent, tokenPatch:Dynamic, recipes, renders, parts) {
		this.density = density;
		this.accent = accent;
		this.tokenPatch = tokenPatch;
		this.recipes = recipes;
		this.renders = renders;
		this.parts = parts;
		tokens = TokenSet.accented(TokenSet.merged(TokenSet.make(density, accent), tokenPatch), tokenPatch);
		theme = TokenSet.theme(tokens);
		refs = TokenSet.refs(tokens);
	}

	static function get_base():LookOf<BaseVariants> {
		if (baseLook == null) {
			Base.font();
			baseLook = Base.look();
		}
		return cast baseLook;
	}

	static function get_ref():Refs
		return base.refs;

	// a tone (a token's light and dark colours), as CSS writes them (one for both)
	public static function tone(light:String, ?dark:String):Tone {
		var l = Color.parse(light);
		return {light: l, dark: dark == null ? l : Color.parse(dark)};
	}

	// (the look a control mounted here takes: the subtree's, else base)
	@:noCompletion public static function current():Look<Dynamic>
		return (helder.view.graph.Owner.current == null ? null : Graph.use(context)) ?? cast base;

	// (whether no Themed is above: a control then takes its look's theme itself)
	@:noCompletion public static function outside():Bool
		return helder.view.graph.Owner.current == null || Graph.use(context) == null;

	// (the default look: Base's recipes)
	@:noCompletion public static function make(recipes:Map<String, Array<Refs->Dynamic>>, ?parts:Map<String, Array<Refs->Dynamic>>):Look<BaseVariants>
		return new Look(Comfortable, Graphite, {}, recipes, new Map(), parts ?? new Map());

	// this look with a patch over it (TypeScript's; Haxe's: LookOf.with, which checks the patch)
	@:typescript.type("<P extends import('./style').LookPatch>(patch: P) => Look<V & import('./style').PatchVariants<P>>")
	public function with(patch:Recipe.TsPatch):Look<Dynamic>
		return extend(patch);

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

	// a control's part ("root", "icon"...) in a variant and size
	public function style(control:String, ?variant:String, ?size:String, part = "root"):Style {
		var key = '$control $variant $size $part', s = styles.get(key);
		if (s == null) styles.set(key, s = Compile.style(resultsOf(control), control, variant, size, part, tokens));
		return s;
	}

	// a piece of the framework's own (nav-bar, sheet, touch-menu, h1, grid-marquee...) or an app's (Look.with's parts)
	public function part(name:String):Style {
		var key = ' $name', s = styles.get(key);
		if (s == null) styles.set(key, s = Compile.part([for (f in parts.get(name) ?? []) f(refs)]));
		return s;
	}

	// the Button, Checkbox and Switch whose variant and size are this look's
	// (the nearest look still draws them: Themed's); values, so that markup
	// of either language takes them as components (<look.Button>)
	public final Button:ButtonProps<V>->UiView = props -> Standard.Button(cast props);
	public final Checkbox:CheckboxProps<V>->UiView = props -> Standard.Checkbox(cast props);
	public final Switch:SwitchProps<V>->UiView = props -> Standard.Switch(cast props);

	// (a control's replaced rendering, its default variant and size, its states' times)
	@:noCompletion public function renderOf(control:String):Null<Dynamic>
		return renders.get(control);

	@:noCompletion public function defaultOf(control:String, axis:String):Null<String> {
		var v:Null<String> = null;
		for (r in resultsOf(control)) {
			var d:Dynamic = Reflect.field(r, "defaults");
			if (d != null && Reflect.field(d, axis) != null) v = Reflect.field(d, axis);
		}
		return v;
	}

	@:noCompletion public function times():Array<Float>
		return [tokens.hoverTime, tokens.hoverTime, tokens.toggleTime, tokens.hoverTime, tokens.openTime];

	function resultsOf(control:String):Array<Dynamic> {
		var r = results.get(control);
		if (r == null) results.set(control, r = [for (f in recipes.get(control) ?? []) if (f != null) f(refs)].filter(o -> o != null));
		return r;
	}
}
