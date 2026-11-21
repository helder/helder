package helder.ui.controls;

import helder.ui.Color;
import helder.ui.Shadow;
import helder.ui.Transform;
import helder.ui.controls.Recipe;
import helder.ui.controls.Tokens;
import helder.ui.controls.Variant;

// helder's default look (Look.base), after CUI's (MIT,
// github.com/yappologistic/CUI: docs/design/controls.md): pure grays in
// light and dark, a neutral accent (others to choose), soft rectangles on
// a radius ladder (controls, panels, surfaces), two densities; solid
// controls on a hairline of shadow; an opaque blue ring for the keyboard
// alone, fading in; a press that darkens and barely gives, a toggle's
// travel that springs; disabled controls faded, not recoloured. Its
// values are helder's own.
@:typescript.hide
class Base {
	public static function look():Look<BaseVariants>
		return Look.make(["button" => [t -> button(t)], "checkbox" => [t -> checkbox(t)], "switch" => [t -> toggle(t)]]);

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
		var rest = resting(0.035), dark:PartStyle = {shadow: resting(0.18)};
		return {
			root: {
				direction: Row,
				alignItems: Center,
				justify: Center,
				columnGap: t.gap,
				height: t.control,
				padding: [0, t.pad],
				radius: t.radius,
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
			icon: {width: t.icon, height: t.icon, shrink: 0},
			label: {maxLines: 1},
			variants: {
				variant: {
					// (a solid one lightens under the pointer and settles back when pressed)
					primary: {root: {shadow: rest, dark: dark, background: t.accent, borderColor: t.accent, color: t.accentFg, hover: {background: t.accentStrong, borderColor: t.accentStrong},
						pressed: {background: t.accent, borderColor: t.accent}}},
					secondary: {root: {background: t.fill, borderColor: t.fill, hover: {background: t.fillHover, borderColor: t.fillHover},
						pressed: {background: t.fillPress, borderColor: t.fillPress}}},
					outline: {root: {shadow: rest, dark: dark, background: t.surface, borderColor: t.edge, hover: {background: t.hover, borderColor: t.edgeStrong},
						pressed: {background: t.press}}},
					ghost: {root: {hover: {background: t.hover}, pressed: {background: t.press}}},
					danger: {root: {shadow: rest, dark: dark, background: t.danger, borderColor: t.danger, color: t.dangerFg, hover: {background: t.dangerStrong, borderColor: t.dangerStrong},
						pressed: {background: t.danger, borderColor: t.danger}}}
				},
				size: {
					sm: {
						root: {height: t.controlSm, padding: [0, t.padSm], columnGap: t.gap - 2, fontSize: t.small + 1, radius: t.radius - 2},
						icon: {width: t.icon - 2, height: t.icon - 2}
					},
					md: {},
					lg: {
						root: {height: t.controlLg, padding: [0, t.padLg], columnGap: t.gap + 2, fontSize: t.size + 1, radius: t.radius + 2},
						icon: {width: t.icon + 2, height: t.icon + 2}
					}
				}
			},
			defaults: {variant: "secondary", size: "md"}
		};
	}

	static function checkbox(t:Refs):CheckboxRecipe
		return {
			root: {
				direction: Row,
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
				shrink: 0,
				alignItems: Center,
				justify: Center,
				radius: Math.round(t.box * 0.28),
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
				direction: Row,
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
				shrink: 0,
				direction: Row,
				alignItems: Center,
				padding: inset,
				radius: t.trackHeight / 2,
				background: t.rail,
				ringColor: CLEAR,
				hover: {background: t.railHover},
				checked: {background: t.accent, hover: {background: t.accentStrong}},
				focus: ring(t)
			},
			knob: {
				width: t.thumb,
				height: t.thumb,
				radius: t.thumb / 2,
				background: t.knob,
				shadow: lifted(0.14),
				dark: {shadow: lifted(0.35)},
				transform: Transform.translate(0, 0),
				pressed: {transform: Transform.scale(0.94)},
				checked: {background: t.accentFg, transform: Transform.translate(travel, 0), pressed: {transform: Transform.translate(travel, 0)}}
			}
		};
	}
}
