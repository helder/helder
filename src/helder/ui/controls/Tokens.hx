package helder.ui.controls;

import helder.ui.Color;

// A look's tokens: its colours (each a Tone, light and dark) and its other
// values. A recipe reads them as Refs: the colours as token references
// (Color.token, resolved with the window's light or dark values), the rest
// as they are. A look's patch gives some of them (Look.with: tokens).
typedef Tokens = Palette<Tone> & Metrics;

typedef Refs = Palette<Color> & Metrics;

// the colours, by role: the window's base (canvas), what rests on it
// (surface), what floats over it (raised), an inset well (fields), the
// hover and press washes, a filled control's gray and its hover and press
// steps (fill), a switch's track when off (rail), hairlines (line), control
// edges (edge, edgeStrong), text in three steps (fg, fg2, fg3), the accent
// and its hover shade, tint, text on it and accent-coloured text
// (accentInk), the focus ring, danger with its hover shade, tint and text
// on it, status colours, a switch's knob, a dialog's scrim, a floating
// layer's shadow
typedef Palette<T> = {
	?canvas:T,
	?surface:T,
	?raised:T,
	?well:T,
	?hover:T,
	?press:T,
	?fill:T,
	?fillHover:T,
	?fillPress:T,
	?rail:T,
	?railHover:T,
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
	?focusSoft:T,
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

// the accents a look can take (Look.with({accent: Violet})); graphite, the
// default, is neutral
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
		"canvas", "surface", "raised", "well", "hover", "press", "fill", "fillHover", "fillPress", "rail", "railHover", "line", "edge", "edgeStrong", "fg", "fg2", "fg3", "accent", "accentStrong", "accentSoft",
		"accentFg", "accentInk", "focus", "focusSoft", "danger", "dangerStrong", "dangerSoft", "dangerFg", "success", "warning", "info", "knob", "scrim", "shadow"
	];

	// the palette's tones in COLORS' order (read as fields: no reflection
	// on a class's values, which a TypeScript build would convert)
	public static function tones(t:Tokens):Array<Null<Tone>>
		return [
			t.canvas, t.surface, t.raised, t.well, t.hover, t.press, t.fill, t.fillHover, t.fillPress, t.rail, t.railHover, t.line, t.edge, t.edgeStrong, t.fg, t.fg2, t.fg3, t.accent, t.accentStrong, t.accentSoft,
			t.accentFg, t.accentInk, t.focus, t.focusSoft, t.danger, t.dangerStrong, t.dangerSoft, t.dangerFg, t.success, t.warning, t.info, t.knob, t.scrim, t.shadow
		];

	// (each accent's light and dark colour and text on them, after CUI's
	// table; teal its own)
	static final ACCENTS = [
		"blue" => ["#0562ef", "#ffffff", "#6ba3ff", "#0b1526"], "violet" => ["#7747ff", "#ffffff", "#a78bff", "#15102b"],
		"teal" => ["#00827a", "#ffffff", "#4fd1c5", "#0b1f1d"], "green" => ["#00864b", "#ffffff", "#53dca6", "#102016"],
		"amber" => ["#f3ad20", "#20190d", "#ffcb62", "#20190d"], "orange" => ["#c25300", "#ffffff", "#ffad5e", "#17130f"],
		"red" => ["#d1403a", "#ffffff", "#ff9386", "#21110f"], "pink" => ["#d23286", "#ffffff", "#ff8bc5", "#250f1b"]
	];

	// helder's tokens at a density, in an accent
	public static function make(density:Density, accent:Accent):Tokens {
		var t:Tokens = {
			// (pure grays; light: white with a muted well, dark: the window a step below what rests on it)
			canvas: gray(1, 0.18),
			surface: gray(1, 0.21),
			raised: gray(1, 0.24),
			well: gray(0.975, 0.26),
			hover: tone("0.15 0 0 / 0.05", "0.96 0 0 / 0.05"),
			press: tone("0.15 0 0 / 0.075", "0.96 0 0 / 0.075"),
			fill: gray(0.945, 0.26),
			fillHover: gray(0.92, 0.29),
			fillPress: gray(0.895, 0.32),
			rail: gray(0.895, 0.33),
			railHover: gray(0.86, 0.37),
			line: gray(0.915, 0.29),
			edge: gray(0.84, 0.29),
			edgeStrong: gray(0.665, 0.515),
			fg: gray(0.15, 0.96),
			fg2: gray(0.46, 0.77),
			fg3: gray(0.565, 0.64),
			// (one blue for every accent, opaque)
			focus: tone("0.58 0.15 250", "0.73 0.15 250"),
			// (a field's ring: the focus blue half seen, as macOS rings a text field)
			focusSoft: tone("0.58 0.15 250 / 0.5", "0.73 0.15 250 / 0.55"),
			danger: tone("0.55 0.19 27", "0.7 0.16 24"),
			dangerStrong: tone("0.6 0.17 27", "0.65 0.15 24"),
			dangerSoft: tone("0.55 0.19 27 / 0.12", "0.7 0.16 24 / 0.2"),
			dangerFg: Look.tone("#ffffff", "#1a0a0c"),
			success: tone("0.5 0.12 162", "0.79 0.14 162"),
			warning: tone("0.55 0.12 68", "0.83 0.12 78"),
			info: tone("0.51 0.11 240", "0.79 0.095 236"),
			knob: gray(1, 0.97),
			scrim: tone("0.13 0 0 / 0.32", "0 0 0 / 0.55"),
			shadow: tone("0 0 0 / 0.12", "0 0 0 / 0.4")
		};
		var a = ACCENTS.get(accent);
		if (a == null) {
			// (neutral: hovering lightens it in light, darkens it in dark)
			t.accent = gray(0.23, 0.93);
			t.accentStrong = gray(0.3, 0.85);
			t.accentSoft = tone("0.23 0 0 / 0.08", "0.93 0 0 / 0.12");
			t.accentFg = gray(1, 0.19);
			t.accentInk = gray(0.23, 0.93);
		} else {
			var light = Color.parse(a[0]), dark = Color.parse(a[2]);
			t.accent = Look.tone(a[0], a[2]);
			t.accentStrong = {light: Color.mix(light, Color.rgb(0xFFFFFF), 0.14), dark: Color.mix(dark, Color.parse("oklch(0.18 0 0)"), 0.14)};
			t.accentSoft = {light: light.fade(0.12), dark: dark.fade(0.2)};
			t.accentFg = Look.tone(a[1], a[3]);
			t.accentInk = {light: Color.mix(light, Color.rgb(0), 0.15), dark: dark};
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
		t.radius = compact ? 8 : 10;
		t.radiusPanel = compact ? 12 : 14;
		t.radiusSurface = compact ? 16 : 18;
		t.controlSm = compact ? 26 : 30;
		t.control = compact ? 30 : 36;
		t.controlLg = compact ? 36 : 44;
		t.padSm = compact ? 10 : 12;
		t.pad = compact ? 12 : 16;
		t.padLg = compact ? 16 : 20;
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
		t.pressScale = 0.98;
		t.disabledOpacity = 0.42;
		return t;
	}

	static function tone(light:String, dark:String):Tone
		return Look.tone('oklch($light)', 'oklch($dark)');

	static function gray(light:Float, dark:Float):Tone
		return tone('$light 0 0', '$dark 0 0');

	// tokens with a patch's over them
	public static function merged(t:Tokens, patch:Dynamic):Tokens {
		var out:Dynamic = Reflect.copy(t);
		for (k in Reflect.fields(patch)) {
			var v:Dynamic = Reflect.field(patch, k);
			if (v != null) Reflect.setField(out, k, v);
		}
		return out;
	}

	// tokens whose accent a patch gave alone: its shade, tint and text from
	// it (those the patch gives kept), as the default accents' are
	public static function accented(t:Tokens, patch:Dynamic):Tokens {
		var a:Null<Tone> = Reflect.field(patch, "accent");
		if (a == null) return t;
		var out:Dynamic = Reflect.copy(t);
		var black = Color.rgb(0), white = Color.rgb(0xFFFFFF);
		inline function derive(name:String, light:Color, dark:Color)
			if (Reflect.field(patch, name) == null) Reflect.setField(out, name, ({light: light, dark: dark} : Tone));
		derive("accentStrong", Color.mix(a.light, white, 0.14), Color.mix(a.dark, black, 0.14));
		derive("accentSoft", a.light.fade(0.12), a.dark.fade(0.2));
		derive("accentInk", Color.mix(a.light, black, 0.08), Color.mix(a.dark, white, 0.35));
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
