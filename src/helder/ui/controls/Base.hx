package helder.ui.controls;

import helder.ui.Color;
import helder.ui.Transform;
import helder.ui.controls.Recipe;
import helder.ui.controls.Tokens;
import helder.ui.controls.Variant;

// helder's default look (Look.base), after CUI's principles (MIT,
// github.com/yappologistic/CUI: docs/design/controls.md): semantic OKLCH
// colours in light and dark, one accent, a radius ladder on a 4-point grid
// (controls, panels, surfaces), two densities; edges on what rests, shadows
// only on what floats; a focus ring for the keyboard alone, fading in;
// a press that gives a little, a toggle's travel that springs; disabled
// controls faded, not recoloured. Its values are helder's own.
@:typescript.hide
class Base {
	public static function look():Look<BaseVariants>
		return Look.make(["button" => [t -> button(t)], "checkbox" => [t -> checkbox(t)], "switch" => [t -> toggle(t)]]);

	static final CLEAR = Color.TRANSPARENT;

	// (the keyboard's ring: outside the edge, the canvas between; a small
	// part's closer, clear of its label)
	static function ring(t:Refs, offset = 2.0):PartStyle
		return {ringWidth: 2, ringColor: t.focus, ringOffsetWidth: offset, ringOffsetColor: t.canvas};

	static function button(t:Refs):ButtonRecipe
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
					primary: {root: {background: t.accent, color: t.accentFg, hover: {background: t.accentStrong}}},
					secondary: {root: {background: t.surface, borderColor: t.edge, hover: {background: t.well, borderColor: t.edgeStrong}}},
					ghost: {root: {color: t.fg2, hover: {background: t.hover, color: t.fg}, pressed: {background: t.press}}},
					danger: {root: {background: t.danger, color: t.dangerFg, hover: {background: t.dangerStrong}}}
				},
				size: {
					sm: {
						root: {height: t.controlSm, padding: [0, t.padSm], columnGap: t.gap - 2, fontSize: t.small, radius: t.radius - 2},
						icon: {width: t.icon - 2, height: t.icon - 2}
					},
					md: {},
					lg: {
						root: {height: t.controlLg, padding: [0, t.padLg], columnGap: t.gap + 2, fontSize: t.large, radius: t.radius + 2},
						icon: {width: t.icon + 2, height: t.icon + 2}
					}
				}
			},
			defaults: {variant: "secondary", size: "md"}
		};

	static function checkbox(t:Refs):CheckboxRecipe
		return {
			root: {
				direction: Row,
				alignItems: Center,
				columnGap: t.gap,
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
				radius: Math.round(t.radius * 0.6),
				borderWidth: 1.5,
				borderColor: t.edgeStrong,
				background: t.surface,
				color: t.accentFg,
				ringColor: CLEAR,
				hover: {borderColor: t.fg3},
				pressed: {transform: Transform.scale(0.92)},
				checked: {background: t.accent, borderColor: t.accent, hover: {background: t.accentStrong, borderColor: t.accentStrong}},
				mixed: {background: t.accent, borderColor: t.accent},
				focus: ring(t, 1)
			},
			mark: {
				width: t.box - 6,
				height: t.box - 6,
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
				columnGap: t.gap + 2,
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
				background: t.edgeStrong,
				ringColor: CLEAR,
				hover: {background: t.fg3},
				checked: {background: t.accent, hover: {background: t.accentStrong}},
				focus: ring(t, 1)
			},
			knob: {
				width: t.thumb,
				height: t.thumb,
				radius: t.thumb / 2,
				background: t.knob,
				transform: Transform.translate(0, 0),
				pressed: {transform: Transform.scale(0.92)},
				checked: {transform: Transform.translate(travel, 0), pressed: {transform: Transform.translate(travel, 0)}}
			}
		};
	}
}
