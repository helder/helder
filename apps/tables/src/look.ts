// The app's look: helder's compact base with the studio's palette (near
// neutral darks with a hint of cool, one blue accent, three greys of text,
// hairlines between panels), Hanken Grotesk for the interface and Geist
// Mono for values; dense (12-point type, 24-point rows, 26-point buttons),
// radii 4 and 6, no shadow but what floats. Its parts by slot: "body",
// "panel", "section", "section-head", "list-item" (data-selected: current),
// "tool" (a plain button: data-selected, data-disabled), "primary", "field"
// and "field-tall" with "field-label", "field-input" and "field-input-tall"
// (data-invalid: its edge red), "floating", "menu-item" (data-disabled),
// "kbd"; Segmented's and the standard Button's recipe brought to the same
// sizes.
import { Look } from "helder/ui";

// (layout values of the app's own)
export const PAD = 12;
export const HEADER = 40;
export const ROW = 24;
export const FIELD = 24;
export const BUTTON = 26;

// (a current row's hover: its tint a step stronger)
const ON_HOVER = { light: "rgba(37, 99, 235, 0.15)", dark: "rgba(59, 130, 246, 0.22)" };

export const look = Look.base.with({
	density: "compact",
	tokens: {
		font: "Hanken Grotesk",
		mono: "Geist Mono",
		size: 12,
		small: 11,
		medium: 500,
		radius: 4,
		radiusPanel: 6,
		icon: 14,
		control: BUTTON,
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
	// (the standard Button at the studio's sizes: a ghost one grey until hovered, accent-coloured when selected)
	button: t => ({
		root: { columnGap: 5, padding: "0 7", fontWeight: 400, color: t.fg2, hover: { color: t.fg } },
		variants: {
			variant: {
				primary: { root: { padding: "0 10", fontWeight: t.medium, color: t.accentFg, hover: { color: t.accentFg } } },
				ghost: { root: { selected: { color: t.accentInk, background: t.accentSoft, hover: { background: t.accentSoft } } } }
			}
		}
	}),
	parts: {
		body: t => ({ background: t.canvas, color: t.fg, fontFamily: t.font, fontSize: t.size }),
		panel: t => ({ background: t.surface, borderColor: t.line, overflow: "hidden" }),
		section: t => ({ padding: `8 ${PAD} ${PAD}`, rowGap: 6, borders: "1 0 0 0", borderColor: t.line }),
		"section-head": t => ({ flexDirection: "row", alignItems: "center", columnGap: 6, height: ROW, color: t.fg3, fontWeight: t.medium, cursor: "default" }),
		"list-item": t => ({
			flexDirection: "row", alignItems: "center", columnGap: 6, height: ROW, padding: "0 8", borderRadius: t.radius, color: t.fg2, cursor: "pointer",
			hover: { background: t.hover, color: t.fg },
			selected: { background: t.accentSoft, color: t.fg, hover: { background: ON_HOVER.light, dark: { background: ON_HOVER.dark } } },
			focus: { outlineWidth: 1, outlineOffset: -1, outlineColor: t.focus }
		}),
		tool: t => ({
			flexDirection: "row", alignItems: "center", justifyContent: "center", columnGap: 5, height: BUTTON, minWidth: BUTTON, padding: "0 7",
			borderRadius: t.radius, color: t.fg2, cursor: "pointer",
			hover: { color: t.fg, background: t.hover },
			selected: { color: t.accentInk, background: t.accentSoft },
			focus: { outlineWidth: 1, outlineOffset: 0, outlineColor: t.focus },
			disabled: { color: t.fg3, background: "transparent", cursor: "default" }
		}),
		primary: t => ({
			flexDirection: "row", alignItems: "center", columnGap: 5, height: BUTTON, padding: "0 10", borderRadius: t.radius, background: t.accent,
			color: t.accentFg, fontWeight: t.medium, cursor: "pointer",
			hover: { background: t.accentStrong },
			focus: { outlineWidth: 1, outlineOffset: 1, outlineColor: t.focus }
		}),
		field: t => ({
			flexDirection: "row", alignItems: "center", columnGap: 6, minWidth: 0, height: FIELD, padding: "0 0 0 8", borderRadius: t.radius,
			background: t.well, borderWidth: 1, borderColor: "transparent", cursor: "text",
			hover: { background: t.hover },
			invalid: { borderColor: t.danger },
			focusWithin: { background: t.well, borderColor: t.accent, invalid: { borderColor: t.danger } }
		}),
		// (a field of several lines: as tall as its text, its label at the top)
		"field-tall": t => ({
			flexDirection: "row", alignItems: "start", columnGap: 6, minWidth: 0, height: "auto", minHeight: FIELD, padding: "3 0 3 8", borderRadius: t.radius,
			background: t.well, borderWidth: 1, borderColor: "transparent", cursor: "text",
			hover: { background: t.hover },
			focusWithin: { background: t.well, borderColor: t.accent }
		}),
		"field-label": t => ({ flexShrink: 0, color: t.fg3, fontFamily: t.font, fontSize: t.small }),
		"field-input": t => ({
			flexGrow: 1, minWidth: 0, height: FIELD - 2, padding: "0 8 0 0", color: t.fg, fontFamily: t.mono, fontSize: t.small, outlineStyle: "none",
			placeholder: { color: t.fg3 },
			selection: { background: t.focusSoft }
		}),
		"field-input-tall": t => ({
			flexGrow: 1, minWidth: 0, height: "auto", fieldSizing: "content", padding: "1 8 1 0", color: t.fg, fontFamily: t.mono, fontSize: t.small,
			outlineStyle: "none",
			placeholder: { color: t.fg3 },
			selection: { background: t.focusSoft }
		}),
		floating: t => ({
			background: t.surface, borderRadius: t.radiusPanel, borderWidth: 1, borderColor: t.edge, padding: 4,
			boxShadow: "0 10 28 rgba(0,0,0,0.14)", dark: { boxShadow: "0 12 32 rgba(0,0,0,0.45)" }
		}),
		"menu-item": t => ({
			flexDirection: "row", alignItems: "center", columnGap: 8, height: ROW + 2, padding: "0 8", borderRadius: t.radius, color: t.fg2, cursor: "pointer",
			hover: { background: t.hover, color: t.fg },
			focus: { background: t.hover, color: t.fg },
			disabled: { color: t.fg3, background: "transparent", cursor: "default" }
		}),
		kbd: t => ({ color: t.fg3, fontSize: t.small }),
		// (Segmented: the options on a well, the chosen one tinted)
		segmented: t => ({ padding: 2, columnGap: 2, borderRadius: t.radiusPanel, background: t.well }),
		"segmented-item": t => ({
			columnGap: 5, height: FIELD - 2, padding: "0 9", borderRadius: t.radius, color: t.fg3,
			hover: { color: t.fg2 },
			selected: { background: t.accentSoft, color: t.accentInk, boxShadow: "none" }
		})
	}
});
