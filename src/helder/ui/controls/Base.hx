package helder.ui.controls;

import helder.gfx.Color;
import helder.ui.Shadow;
import helder.ui.Transform;
import helder.ui.controls.Recipe;
import helder.ui.controls.Tokens;
import helder.ui.controls.Variant;

// helder's default look (Look.base), after CUI's (MIT,
// github.com/yappologistic/CUI): pure grays in
// light and dark, a neutral accent (others to choose), soft rectangles on
// a radius ladder (controls, panels, surfaces), two densities; solid
// controls on a hairline of shadow; an opaque blue ring for the keyboard
// alone, fading in; a press that darkens and barely gives, a toggle's
// travel that springs; disabled controls faded, not recoloured. Its
// values are helder's own.
@:typescript.hide
class Base {
	public static function look():Look<BaseVariants>
		return Look.make(["button" => [t -> button(t)], "checkbox" => [t -> checkbox(t)], "switch" => [t -> toggle(t)], "pathbar" => [t -> pathBar(t)]],
			touch());

	// (the touch pieces' parts, a slot each: helder.ui.nav's bars and sheets,
	// helder.ui.menu's touch menu; 44-point targets, the system's type sizes
	// of iOS: 17 for a bar's title and a row, 32 for a large title; and the
	// grid's marquee, GridScroll's, which has no look of its own; a
	// composite field's box and its text field)
	static function touch():Map<String, Array<Refs->Dynamic>> {
		var parts = new Map<String, Array<Refs->Dynamic>>();
		function part(slot:String, f:Refs->PartStyle)
			parts.set(slot, [t -> f(t)]);
		var item = (t:Refs) -> ({
			flexDirection: Row, alignItems: Center, justifyContent: Center, minWidth: 44, height: 44, padding: [0, 10], borderRadius: 22, color: t.fg,
			fontSize: 17, cursor: Pointer, pressed: {opacity: 0.5}, disabled: {opacity: t.disabledOpacity}, focus: ring(t)
		} : PartStyle);
		part("nav-screen", t -> {background: t.canvas, color: t.fg, fontSize: 17});
		part("nav-bar-fill", t -> {background: t.surface, opacity: 0.92});
		part("nav-title", t -> {fontSize: 17, fontWeight: 600, textAlign: Center, textWrap: NoWrap, textOverflow: Ellipsis});
		part("nav-large", t -> {padding: [0, 0, 4, 0]});
		part("nav-large-title", t -> {fontSize: 32, fontWeight: 700, letterSpacing: -0.6, padding: [2, 16, 8, 16], textWrap: NoWrap, textOverflow: Ellipsis});
		part("nav-subtitle", t -> {fontSize: 13, color: t.fg3, padding: [0, 16, 10, 16], margin: [-6, 0, 0, 0]});
		part("nav-back", t -> {
			flexDirection: Row, alignItems: Center, height: 44, minWidth: 44, maxWidth: 140, padding: [0, 8, 0, 0], columnGap: 2, color: t.fg, fontSize: 17,
			cursor: Pointer, pressed: {opacity: 0.5}, focus: ring(t)
		});
		part("nav-back-title", t -> {textWrap: NoWrap, textOverflow: Ellipsis, minWidth: 0, flexShrink: 1});
		part("nav-item", item);
		part("nav-bottom", t -> {background: t.surface});
		part("sheet-scrim", t -> {background: t.scrim});
		part("sheet", t -> {background: t.raised, color: t.fg, borderRadius: 14, boxShadow: lifted(0.25), padding: [6, 0, 0, 0]});
		part("sheet-grabber", t -> {width: 36, height: 5, borderRadius: 3, background: t.edge, alignSelf: Center, margin: [0, 0, 8, 0], focus: ring(t)});
		part("sheet-popover", t -> {background: t.raised, color: t.fg, borderRadius: t.radiusPanel, boxShadow: lifted(0.2), padding: [8, 0], overflow: Hidden});
		part("touch-menu-preview", t -> {borderRadius: 12, boxShadow: lifted(0.3)});
		part("touch-menu", t -> {background: t.raised, color: t.fg, borderRadius: 13, boxShadow: lifted(0.3)});
		var row = (t:Refs, danger:Bool) -> ({
			flexDirection: Row, alignItems: Center, height: 44, padding: [0, 16], columnGap: 12, fontSize: 16, color: danger ? t.danger : t.fg,
			cursor: Pointer, borderColor: t.line, pressed: {background: t.press}, disabled: {opacity: t.disabledOpacity}, focus: {background: t.hover}
		} : PartStyle);
		part("touch-menu-item", t -> row(t, false));
		part("touch-menu-item-danger", t -> row(t, true));
		part("touch-menu-separator", t -> {background: t.line});
		part("grid-marquee", t -> {background: t.accentSoft, borderWidth: 1, borderColor: t.accent, borderRadius: 3});
		// (a composite field, an icon and a text field in a box (a search
		// field): one ring round the box at its radius while what is in it
		// has the focus, as macOS rings one, none on the text field)
		part("field-box", t -> {flexDirection: Row, alignItems: Center, columnGap: 7, padding: [0, 8], borderRadius: t.radius, background: t.fill, color: t.fg,
			ringColor: CLEAR, focusWithin: {ringWidth: 3, ringColor: t.focusSoft, ringOffsetWidth: 0}});
		// (HTML's text elements, NodeRenderer's slots for them: headings by
		// level, strong, em and code; a page's renderer has the browser's)
		part("h1", t -> {fontSize: t.size * 2, fontWeight: 700, lineHeight: 1.2});
		part("h2", t -> {fontSize: t.size * 1.5, fontWeight: 700, lineHeight: 1.2});
		part("h3", t -> {fontSize: t.size * 1.25, fontWeight: 600, lineHeight: 1.25});
		part("h4", t -> {fontSize: t.size * 1.1, fontWeight: 600});
		part("h5", t -> {fontSize: t.size, fontWeight: 600});
		part("h6", t -> {fontSize: t.small, fontWeight: 600, color: t.fg3});
		part("strong", t -> {fontWeight: 700});
		part("em", t -> {fontStyle: Italic});
		part("code", t -> {fontFamily: "monospace", fontSize: t.size * 0.92});
		part("field-box-input", t -> {flexGrow: 1, minWidth: 0, outlineStyle: None});
		return parts;
	}

	static final CLEAR = Color.TRANSPARENT;

	// (the look's Inter where the system has none, so the controls look the
	// same everywhere; a web page ships it already: Page)
	public static function font() {
		#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
		var fonts = helder.text.SystemFonts.get();
		if (!fonts.families().contains("Inter")) fonts.add(helder.asset.Asset.embed("helder/text/fonts/Inter.ttf"));
		#end
	}

	// (the keyboard's ring: 2 px at a 2 px offset, the canvas between)
	static function ring(t:Refs):PartStyle
		return {ringWidth: 2, ringColor: t.focus, ringOffsetWidth: 2, ringOffsetColor: t.canvas};

	// (what rests on the page casts a hairline of shadow; what floats more)
	static function resting(alpha:Float):Shadow
		return {y: 1, blur: 2, color: Color.rgba(0, alpha)};

	static function lifted(alpha:Float):Shadow
		return {y: 1, blur: 2, color: Color.rgba(0, alpha), next: ({y: 2, blur: 6, color: Color.rgba(0, alpha / 2)} : Shadow)};

	static function button(t:Refs):ButtonRecipe {
		var rest = resting(0.035), dark:PartStyle = {boxShadow: resting(0.18)};
		return {
			root: {
				flexDirection: Row,
				alignItems: Center,
				justifyContent: Center,
				columnGap: t.gap,
				height: t.control,
				padding: [0, t.pad],
				borderRadius: t.radius,
				fontFamily: t.font,
				fontSize: t.size,
				fontWeight: t.medium,
				color: t.fg,
				background: CLEAR,
				borderWidth: 1,
				borderColor: CLEAR,
				ringColor: CLEAR,
				userSelect: None,
				cursor: Pointer,
				pressed: {transform: Transform.scale(t.pressScale)},
				focus: ring(t),
				disabled: {opacity: t.disabledOpacity, cursor: Default, transform: Transform.scale(1)}
			},
			icon: {width: t.icon, height: t.icon, flexShrink: 0},
			label: {lineClamp: 1},
			variants: {
				variant: {
					// (a solid one lightens under the pointer and settles back when pressed)
					primary: {root: {boxShadow: rest, dark: dark, background: t.accent, borderColor: t.accent, color: t.accentFg, hover: {background: t.accentStrong, borderColor: t.accentStrong},
						pressed: {background: t.accent, borderColor: t.accent}}},
					secondary: {root: {background: t.fill, borderColor: t.fill, hover: {background: t.fillHover, borderColor: t.fillHover},
						pressed: {background: t.fillPress, borderColor: t.fillPress},
						selected: {background: t.accentSoft, hover: {background: t.fillHover}, pressed: {background: t.fillPress}}}},
					outline: {root: {boxShadow: rest, dark: dark, background: t.surface, borderColor: t.edge, hover: {background: t.hover, borderColor: t.edgeStrong},
						pressed: {background: t.press}, selected: {background: t.accentSoft, hover: {background: t.hover}, pressed: {background: t.press}}}},
					ghost: {root: {hover: {background: t.hover}, pressed: {background: t.press},
						selected: {background: t.accentSoft, color: t.fg, hover: {background: t.hover}, pressed: {background: t.press}}}},
					danger: {root: {boxShadow: rest, dark: dark, background: t.danger, borderColor: t.danger, color: t.dangerFg, hover: {background: t.dangerStrong, borderColor: t.dangerStrong},
						pressed: {background: t.danger, borderColor: t.danger}}}
				},
				size: {
					sm: {
						root: {height: t.controlSm, padding: [0, t.padSm], columnGap: t.gap - 2, fontSize: t.small + 1, borderRadius: t.radius - 2},
						icon: {width: t.icon - 2, height: t.icon - 2}
					},
					md: {},
					lg: {
						root: {height: t.controlLg, padding: [0, t.padLg], columnGap: t.gap + 2, fontSize: t.size + 1, borderRadius: t.radius + 2},
						icon: {width: t.icon + 2, height: t.icon + 2}
					}
				}
			},
			defaults: {variant: "secondary", size: "md"}
		};
	}

	static function pathBar(t:Refs):PathBarRecipe {
		var segment:PartStyle = {
			flexDirection: Row, alignItems: Center, height: 24, flexShrink: 0, padding: [0, 6], columnGap: 4, borderRadius: 6,
			color: t.fg2, cursor: Pointer, ringColor: CLEAR, hover: {background: t.hover, color: t.fg}, focus: ring(t)
		};
		return {
			root: {height: 32, minWidth: 0, flexShrink: 0, flexDirection: Row, alignItems: Center, padding: [0, 6],
				background: CLEAR, fontFamily: t.font, fontSize: t.small, userSelect: None, overflow: Hidden},
			segment: segment,
			segmentIcon: {width: 14, height: 14, flexShrink: 0},
			separator: {width: 11, height: 24, alignItems: Center, justifyContent: Center, flexShrink: 0, borderRadius: 6,
				color: t.fg3, ringColor: CLEAR, focus: ring(t)},
			overflow: segment,
			current: {flexDirection: Row, alignItems: Center, height: 24, minWidth: 0, padding: [0, 6], columnGap: 4, borderRadius: 6,
				color: t.fg, fontWeight: t.medium, overflow: Hidden},
			field: {flexGrow: 1, minWidth: 0, height: 26, padding: [0, 6], borderRadius: 6, color: t.fg, background: t.well,
				borderWidth: 1, borderColor: t.focus, userSelect: Text},
			variants: {size: {md: {root: {height: 36}, segment: {height: 28}, separator: {height: 28},
				overflow: {height: 28}, current: {height: 28}, field: {height: 30}}}}
		};
	}

	static function checkbox(t:Refs):CheckboxRecipe
		return {
			root: {
				flexDirection: Row,
				alignItems: Center,
				columnGap: t.gap + 2,
				minHeight: t.controlSm,
				fontFamily: t.font,
				fontSize: t.size,
				color: t.fg,
				userSelect: None,
				cursor: Pointer,
				disabled: {opacity: t.disabledOpacity, cursor: Default}
			},
			box: {
				width: t.box,
				height: t.box,
				flexShrink: 0,
				alignItems: Center,
				justifyContent: Center,
				borderRadius: Math.round(t.box * 0.28),
				borderWidth: 1.5,
				borderColor: t.edgeStrong,
				background: t.surface,
				color: t.accentFg,
				ringColor: CLEAR,
				hover: {borderColor: t.fg3},
				pressed: {transform: Transform.scale(0.94)},
				checked: {background: t.accent, borderColor: t.accent, hover: {background: t.accentStrong, borderColor: t.accentStrong}},
				mixed: {background: t.accent, borderColor: t.accent, hover: {background: t.accentStrong, borderColor: t.accentStrong}},
				focus: ring(t)
			},
			mark: {
				width: t.box - 4,
				height: t.box - 4,
				opacity: 0,
				transform: Transform.scale(0.5),
				checked: {opacity: 1, transform: Transform.scale(1)},
				mixed: {opacity: 1, transform: Transform.scale(1)}
			}
		};

	static function toggle(t:Refs):SwitchRecipe {
		var inset = (t.trackHeight - t.thumb) / 2;
		var travel = t.track - t.thumb - inset * 2;
		return {
			root: {
				flexDirection: Row,
				alignItems: Center,
				columnGap: t.gap + 4,
				minHeight: t.controlSm,
				fontFamily: t.font,
				fontSize: t.size,
				color: t.fg,
				userSelect: None,
				cursor: Pointer,
				disabled: {opacity: t.disabledOpacity, cursor: Default}
			},
			track: {
				width: t.track,
				height: t.trackHeight,
				flexShrink: 0,
				flexDirection: Row,
				alignItems: Center,
				padding: inset,
				borderRadius: t.trackHeight / 2,
				background: t.rail,
				ringColor: CLEAR,
				hover: {background: t.railHover},
				checked: {background: t.accent, hover: {background: t.accentStrong}},
				focus: ring(t)
			},
			knob: {
				width: t.thumb,
				height: t.thumb,
				borderRadius: t.thumb / 2,
				background: t.knob,
				boxShadow: lifted(0.14),
				dark: {boxShadow: lifted(0.35)},
				transform: Transform.translate(0, 0),
				pressed: {transform: Transform.scale(0.94)},
				checked: {background: t.accentFg, transform: Transform.translate(travel, 0), pressed: {transform: Transform.translate(travel, 0)}}
			}
		};
	}
}
