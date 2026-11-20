package helder.ui.controls;

import helder.ui.Color;

// A look's tokens: its colours (each a Tone, light and dark) and its other
// values. A recipe reads them as Refs: the colours as token references
// (Color.token, resolved with the window's light or dark values), the rest
// as they are. A look's patch gives some of them (Look.with: tokens).
typedef Tokens = Palette<Tone> & Metrics;

typedef Refs = Palette<Color> & Metrics;

// the colours, by role: the window's base (canvas), what rests on it
// (surface), what floats over it (raised), an inset well (fields,
// tracks), the hover and press washes, hairlines (line), control edges
// (edge, edgeStrong), text in three steps (fg, fg2, fg3), the accent and
// its stronger shade, tint, text on it and accent-coloured text (accentInk),
// the focus ring, danger with its shade, tint and text on it, status
// colours, a switch's knob, a dialog's scrim, a floating layer's shadow
typedef Palette<T> = {
	?canvas:T,
	?surface:T,
	?raised:T,
	?well:T,
	?hover:T,
	?press:T,
	?line:T,
	?edge:T,
	?edgeStrong:T,
	?fg:T,
	?fg2:T,
	?fg3:T,
	?accent:T,
	?accentStrong:T,
	?accentSoft:T,
	?accentFg:T,
	?accentInk:T,
	?focus:T,
	?danger:T,
	?dangerStrong:T,
	?dangerSoft:T,
	?dangerFg:T,
	?success:T,
	?warning:T,
	?info:T,
	?knob:T,
	?scrim:T,
	?shadow:T
}

// the rest: density, fonts (the interface's, display, mono), text sizes,
// the medium weight, the radius ladder (controls, panels, surfaces), control
// heights and paddings (sm, md, lg), the gap between an icon and its label,
// icon size, a checkbox's box, a switch's track and thumb, and motion: the
// seconds of a hover, a toggle, a disclosure opening, a floating layer, a
// dialog and an exit, a press's scale, a disabled control's opacity
typedef Metrics = {
	?density:Density,
	?font:String,
	?display:String,
	?mono:String,
	?size:Float,
	?small:Float,
	?large:Float,
	?title:Float,
	?medium:Int,
	?radius:Float,
	?radiusPanel:Float,
	?radiusSurface:Float,
	?controlSm:Float,
	?control:Float,
	?controlLg:Float,
	?padSm:Float,
	?pad:Float,
	?padLg:Float,
	?gap:Float,
	?icon:Float,
	?box:Float,
	?track:Float,
	?trackHeight:Float,
	?thumb:Float,
	?hoverTime:Float,
	?toggleTime:Float,
	?openTime:Float,
	?floatTime:Float,
	?dialogTime:Float,
	?exitTime:Float,
	?pressScale:Float,
	?disabledOpacity:Float
}

enum abstract Density(String) to String {
	var Comfortable = "comfortable";
	var Compact = "compact";
}

// the accents a look can take (Look.with({accent: Violet})): one hue each,
// at the same lightness and chroma, graphite near neutral
enum abstract Accent(String) to String {
	var Blue = "blue";
	var Violet = "violet";
	var Teal = "teal";
	var Green = "green";
	var Amber = "amber";
	var Orange = "orange";
	var Red = "red";
	var Pink = "pink";
	var Graphite = "graphite";
}

@:typescript.hide
class TokenSet {
	// the palette's names, as the sheet's colours are named
	public static final COLORS = [
		"canvas", "surface", "raised", "well", "hover", "press", "line", "edge", "edgeStrong", "fg", "fg2", "fg3", "accent", "accentStrong", "accentSoft",
		"accentFg", "accentInk", "focus", "danger", "dangerStrong", "dangerSoft", "dangerFg", "success", "warning", "info", "knob", "scrim", "shadow"
	];

	// the palette's tones in COLORS' order (read as fields: no reflection
	// on a class's values, which a TypeScript build would convert)
	public static function tones(t:Tokens):Array<Null<Tone>>
		return [
			t.canvas, t.surface, t.raised, t.well, t.hover, t.press, t.line, t.edge, t.edgeStrong, t.fg, t.fg2, t.fg3, t.accent, t.accentStrong, t.accentSoft,
			t.accentFg, t.accentInk, t.focus, t.danger, t.dangerStrong, t.dangerSoft, t.dangerFg, t.success, t.warning, t.info, t.knob, t.scrim, t.shadow
		];

	// (each accent's hue and chroma, OKLCH's)
	static final HUES = [
		"blue" => [258, 0.19], "violet" => [292, 0.2], "teal" => [192, 0.12], "green" => [152, 0.15], "amber" => [70, 0.15], "orange" => [48, 0.17],
		"red" => [26, 0.2], "pink" => [352, 0.18], "graphite" => [265, 0.012]
	];

	// helder's tokens at a density, in an accent
	public static function make(density:Density, accent:Accent):Tokens {
		var t:Tokens = {
			// (neutrals with a hint of cool, the window a step below what rests on it)
			canvas: tone("0.975 0.003 265", "0.165 0.005 265"),
			surface: tone("1 0 0", "0.205 0.006 265"),
			raised: tone("1 0 0", "0.245 0.007 265"),
			well: tone("0.955 0.004 265", "0.235 0.006 265"),
			hover: tone("0.25 0.02 265 / 0.055", "1 0 0 / 0.065"),
			press: tone("0.25 0.02 265 / 0.1", "1 0 0 / 0.11"),
			line: tone("0.25 0.02 265 / 0.08", "1 0 0 / 0.07"),
			edge: tone("0.25 0.02 265 / 0.15", "1 0 0 / 0.13"),
			edgeStrong: tone("0.25 0.02 265 / 0.3", "1 0 0 / 0.26"),
			fg: tone("0.22 0.01 265", "0.96 0.003 265"),
			fg2: tone("0.44 0.012 265", "0.76 0.008 265"),
			fg3: tone("0.6 0.01 265", "0.58 0.008 265"),
			danger: tone("0.57 0.2 26", "0.65 0.19 26"),
			dangerStrong: tone("0.51 0.2 26", "0.71 0.17 26"),
			dangerSoft: tone("0.57 0.2 26 / 0.12", "0.65 0.19 26 / 0.2"),
			dangerFg: tone("0.985 0 0", "0.99 0 0"),
			success: tone("0.58 0.14 152", "0.72 0.15 152"),
			warning: tone("0.68 0.15 70", "0.8 0.14 78"),
			info: tone("0.58 0.13 232", "0.72 0.12 232"),
			knob: tone("1 0 0", "0.98 0 0"),
			scrim: tone("0.18 0.02 265 / 0.38", "0 0 0 / 0.58"),
			shadow: tone("0.2 0.03 265 / 0.14", "0 0 0 / 0.5")
		};
		var hc = HUES.get(accent) ?? HUES.get("blue"), h = hc[0], c = hc[1];
		if (accent == Graphite) {
			t.accent = tone("0.27 0.012 265", "0.93 0.006 265");
			t.accentStrong = tone("0.2 0.012 265", "0.99 0 0");
			t.accentSoft = tone("0.27 0.012 265 / 0.08", "1 0 0 / 0.1");
			t.accentFg = tone("0.985 0 0", "0.2 0.01 265");
			t.accentInk = tone("0.27 0.012 265", "0.93 0.006 265");
			t.focus = tone("0.45 0.02 265 / 0.55", "0.85 0.01 265 / 0.6");
		} else {
			t.accent = tone('0.55 $c $h', '0.62 $c $h');
			t.accentStrong = tone('0.49 $c $h', '0.68 $c $h');
			t.accentSoft = tone('0.55 $c $h / 0.12', '0.62 $c $h / 0.2');
			t.accentFg = tone("0.985 0 0", "0.99 0 0");
			t.accentInk = tone('0.48 ${c * 0.9} $h', '0.79 ${c * 0.6} $h');
			t.focus = tone('0.6 $c $h / 0.5', '0.7 $c $h / 0.55');
		}
		var compact = density == Compact;
		t.density = density;
		t.font = "Inter";
		t.display = "Inter Display";
		t.mono = "Geist Mono";
		t.size = compact ? 13 : 14;
		t.small = compact ? 11 : 12;
		t.large = compact ? 14 : 16;
		t.title = compact ? 17 : 20;
		t.medium = 500;
		t.radius = compact ? 6 : 8;
		t.radiusPanel = compact ? 10 : 12;
		t.radiusSurface = compact ? 14 : 16;
		t.controlSm = compact ? 24 : 28;
		t.control = compact ? 28 : 36;
		t.controlLg = compact ? 36 : 44;
		t.padSm = compact ? 8 : 10;
		t.pad = compact ? 10 : 14;
		t.padLg = compact ? 14 : 18;
		t.gap = compact ? 6 : 8;
		t.icon = compact ? 14 : 16;
		t.box = compact ? 16 : 18;
		t.track = compact ? 30 : 36;
		t.trackHeight = compact ? 16 : 20;
		t.thumb = compact ? 12 : 16;
		t.hoverTime = 0.12;
		t.toggleTime = 0.18;
		t.openTime = 0.26;
		t.floatTime = 0.22;
		t.dialogTime = 0.3;
		t.exitTime = 0.15;
		t.pressScale = 0.97;
		t.disabledOpacity = 0.42;
		return t;
	}

	static function tone(light:String, dark:String):Tone
		return Look.tone('oklch($light)', 'oklch($dark)');

	// tokens with a patch's over them
	public static function merged(t:Tokens, patch:Dynamic):Tokens {
		var out:Dynamic = Reflect.copy(t);
		for (k in Reflect.fields(patch)) {
			var v:Dynamic = Reflect.field(patch, k);
			if (v != null) Reflect.setField(out, k, v);
		}
		return out;
	}

	// tokens whose accent a patch gave alone: its shade, tint, text and ring
	// from it (those the patch gives kept), as the default accents' are
	public static function accented(t:Tokens, patch:Dynamic):Tokens {
		var a:Null<Tone> = Reflect.field(patch, "accent");
		if (a == null) return t;
		var out:Dynamic = Reflect.copy(t);
		var black = Color.rgb(0), white = Color.rgb(0xFFFFFF);
		inline function derive(name:String, light:Color, dark:Color)
			if (Reflect.field(patch, name) == null) Reflect.setField(out, name, ({light: light, dark: dark} : Tone));
		derive("accentStrong", Color.mix(a.light, black, 0.12), Color.mix(a.dark, white, 0.12));
		derive("accentSoft", a.light.fade(0.12), a.dark.fade(0.2));
		derive("accentInk", Color.mix(a.light, black, 0.08), Color.mix(a.dark, white, 0.35));
		derive("focus", a.light.fade(0.5), a.dark.fade(0.55));
		return out;
	}

	// what a recipe reads of tokens: references for the colours
	public static function refs(t:Tokens):Refs {
		var r:Dynamic = Reflect.copy(t);
		for (name in COLORS)
			Reflect.setField(r, name, Color.token(name));
		return r;
	}
}
