import helder.gfx.Color;
import helder.ui.Shadow;
import helder.ui.controls.Look;
import helder.ui.controls.Tokens;
import helder.ui.controls.Tone;

// Foundry's look: helder's controls (Look.base) dense, in Hanken Grotesk
// with Geist Mono for values, near neutral darks with a hint of cool, one
// blue accent for what is current or acts; the window's parts (panels,
// sections, fields, a glyph's cell, a first letter's chip, a starting
// font's card) in its tokens. A state by its attribute: data-selected
// (current), data-state="checked" (a first letter drawn).
class AppLook {
	// the window's metrics the tokens have none for
	public static inline var PAD = 12;
	public static inline var HEADER = 40;
	public static inline var ROW = 24;
	public static inline var FIELD = 24;

	public static final look = Look.base.with({
		density: Compact,
		tokens: {
			font: "Hanken Grotesk",
			mono: "Geist Mono",
			size: 12,
			small: 11,
			medium: 500,
			radius: 4,
			radiusPanel: 6,
			icon: 14,
			// (a button 26 high, 7 in from its sides, 5 between its icon and its label)
			control: 26,
			pad: 7,
			gap: 5,
			canvas: Look.tone("#f3f3f5", "#0b0b0d"),
			surface: Look.tone("#ffffff", "#141416"),
			well: Look.tone("#f3f3f5", "#1c1c1f"),
			hover: Look.tone("#ececef", "#232326"),
			press: Look.tone("#e3e3e7", "#2c2c30"),
			line: Look.tone("rgba(0, 0, 0, 0.08)", "rgba(255, 255, 255, 0.07)"),
			edge: Look.tone("rgba(0, 0, 0, 0.14)", "rgba(255, 255, 255, 0.14)"),
			fg: Look.tone("#18181b", "#f0f0f2"),
			fg2: Look.tone("#55555e", "#a3a3aa"),
			fg3: Look.tone("#8e8e97", "#66666d"),
			accent: Look.tone("#2563eb", "#3b82f6"),
			accentStrong: Look.tone("#1d58d8", "#4b8ef7"),
			accentSoft: Look.tone("rgba(37, 99, 235, 0.10)", "rgba(59, 130, 246, 0.16)"),
			accentFg: Look.tone("#ffffff", "#ffffff"),
			accentInk: Look.tone("#1d4ed8", "#7eaaf8"),
			focus: Look.tone("rgba(37, 99, 235, 0.6)", "rgba(59, 130, 246, 0.7)"),
			focusSoft: Look.tone("rgba(37, 99, 235, 0.20)", "rgba(59, 130, 246, 0.28)"),
			danger: Look.tone("#c2393a", "#ec8383"),
			success: Look.tone("#2f7d3b", "#a8c9a0"),
			warning: Look.tone("#9a7310", "#dcc994"),
			info: Look.tone("#2f5ea8", "#93b0dc")
		},
		// (a ghost button: grey text that darkens under the pointer, the accent's tint and ink while on; a primary one 10 in)
		button: t -> {
			variants: {
				variant: {
					ghost: {root: {color: t.fg2, fontWeight: 400, hover: {background: t.hover, color: t.fg},
						selected: {background: t.accentSoft, color: t.accentInk, hover: {background: t.accentSoft, color: t.accentInk}}}},
					primary: {root: {padding: [0, 10]}}
				}
			}
		},
		parts: {
			body: t -> {background: t.canvas, color: t.fg, fontFamily: t.font, fontSize: t.size},
			panel: t -> {background: t.surface, borderColor: t.line, overflow: Hidden},
			section: t -> {padding: [8, PAD, PAD], rowGap: 6, borders: [1, 0, 0, 0], borderColor: t.line},
			"section-head": t -> {flexDirection: Row, alignItems: Center, columnGap: 6, height: ROW, color: t.fg3, fontWeight: t.medium, cursor: Default},
			field: t -> {flexDirection: Row, alignItems: Center, columnGap: 6, minWidth: 0, height: FIELD, padding: [0, 0, 0, 8], borderRadius: t.radius,
				background: t.well, borderWidth: 1, borderColor: Color.TRANSPARENT, cursor: Text, hover: {background: t.hover},
				focusWithin: {background: t.well, borderColor: t.accent}},
			"field-label": t -> {flexShrink: 0, color: t.fg3, fontFamily: t.font, fontSize: t.small},
			"field-input": t -> {flexGrow: 1, minWidth: 0, height: FIELD - 2, padding: [0, 8, 0, 0], color: t.fg, fontFamily: t.mono, fontSize: t.small,
				outlineStyle: None, placeholder: {color: t.fg3}, selection: {background: t.focusSoft}},
			input: t -> {flexGrow: 1, minWidth: 0, color: t.fg, outlineStyle: None, placeholder: {color: t.fg3}, selection: {background: t.focusSoft}},
			// (a small button of the window's own size: a missing letter's, the zoom's)
			tool: t -> {flexDirection: Row, alignItems: Center, justifyContent: Center, columnGap: 5, height: t.control, minWidth: t.control, padding: [0, 7],
				borderRadius: t.radius, color: t.fg2, cursor: Pointer, hover: {color: t.fg, background: t.hover},
				selected: {color: t.accentInk, background: t.accentSoft}, focus: outline(t, 0)},
			// (a glyph's cell; a first letter's chip, checked once drawn; a starting font's card)
			cell: t -> {height: 56, borderRadius: t.radiusPanel, background: t.well, borderWidth: 1, borderColor: Color.TRANSPARENT, cursor: Pointer,
				alignItems: Center, padding: [4, 2, 3, 2], hover: {background: t.hover}, selected: {background: t.accentSoft, borderColor: t.accent},
				focus: outline(t, 1)},
			chip: t -> {width: 28, height: 34, borderRadius: t.radius, background: t.surface, borderWidth: 1, borderColor: Color.TRANSPARENT, cursor: Pointer,
				alignItems: Center, justifyContent: Center, hover: {background: t.hover}, checked: {background: t.accentSoft},
				selected: {borderColor: t.accent}},
			starter: t -> {padding: 8, borderRadius: t.radiusPanel + 2, background: t.surface, borderWidth: 1, borderColor: t.line, cursor: Pointer,
				hover: {background: t.hover, borderColor: t.edge}, focus: outline(t, 1)},
			// (the starting dialog: what floats, its shadow deeper in dark)
			dialog: t -> {background: t.surface, borderRadius: t.radiusPanel + 4, borderWidth: 1, borderColor: t.edge,
				boxShadow: ({y: 10, blur: 28, color: Color.rgba(0, 0.14)} : Shadow), dark: {boxShadow: ({y: 12, blur: 32, color: Color.rgba(0, 0.45)} : Shadow)}},
			// (Standard's Slider, Segmented and Tooltip at the window's size: a field's height, its label small and grey)
			slider: t -> {columnGap: 6, height: FIELD, padding: [0, 8], background: t.well, hover: {background: t.hover}},
			"slider-label": t -> {color: t.fg3, fontFamily: t.font, fontSize: t.small},
			segmented: t -> {borderRadius: t.radiusPanel, background: t.well},
			"segmented-item": t -> {columnGap: 5, height: FIELD - 2, padding: [0, 9], color: t.fg3, hover: {color: t.fg2},
				selected: {background: t.accentSoft, color: t.accentInk, boxShadow: Shadow.NONE}},
			tooltip: t -> {height: 22, padding: [0, 8], background: t.press},
			"tooltip-keys": t -> {fontFamily: t.font}
		}
	});

	// the look's tokens (its metrics: tokens.small, tokens.medium...)
	public static var tokens(get, never):Tokens;

	static inline function get_tokens():Tokens
		return look.tokens;

	// a token's colour on this screen, light or dark (what paints itself
	// takes colours, not the sheet's references): paint(tokens.fg)
	public static function paint(tone:Tone):Color
		return helder.ui.ScreenContext.current.dark() ? tone.dark : tone.light;

	// Foundry's own colours, of no token: rose (measures, kerning), violet (agents)
	static final ROSE = Look.tone("#a84469", "#dba7b6");
	static final VIOLET = Look.tone("#6c4fb3", "#b9aee0");

	public static function rose():Color
		return paint(ROSE);

	public static function violet():Color
		return paint(VIOLET);

	// (the keyboard's focus: a hairline of the focus colour, offset out by `offset`)
	static function outline(t:Refs, offset:Float):helder.ui.controls.Recipe.PartStyle
		return {outlineWidth: 1, outlineOffset: offset, outlineColor: t.focus};
}
