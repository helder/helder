package ui.fast;

import helder.test.Test;
import helder.ui.fast.Style;
import helder.ui.fast.Style.TintValue;
import helder.ui.fast.StyleModule;
import helder.ui.fast.Theme;

// A CSS module compiled to fast styles when the test is built: what it
// says the same Style as the same written in Haxe.
function tests() {
	final t = Theme.load("ui/fast/test.theme.css");
	describe("StyleModule", () -> {
		test("a module's classes are Styles: states, nesting, composes, tokens", () -> {
			final s = StyleModule.load("ui/fast/card.module.css", "ui/fast/test.theme.css");
			var card = Style.of({
				padding: [4, 8],
				borderRadius: 6,
				display: Flex,
				flexDirection: Row,
				alignItems: Center,
				columnGap: 8,
				background: t.surface,
				color: 0xFF18181B,
				borderWidth: 1,
				borderStyle: Solid,
				borderColor: 0xFFE4E4E7,
				cursor: Pointer,
				hover: {background: t.hover},
				selected: {background: 0xFFDBEAFE, fontWeight: 600}
			});
			equals(s.card == card, true);
			equals(s.cardTitle.props.fontSize, 20);
			equals(s.cardTitle.props.wrap, false);
			equals((s.cardTitle.props.padding : Array<Float>).join(","), "0,0,0,12");
			equals(s.cardTitle.props.dark.color, (Plain(0xFFFAFAFA) : TintValue));
			// (in a dark theme: its dark variant over it)
			equals(s.cardTitle.at(0, true).color, (Plain(0xFFFAFAFA) : TintValue));
			equals(s.cardTitle.at(0, false).color, null);
		});
		test("paint: border style, corners, shadows in CSS's order, an outline; pointer events, direction, figures, a ratio, a bar", () -> {
			final s = StyleModule.load("ui/fast/paint.module.css", "ui/fast/test.theme.css");
			var chip = Style.of({
				borderWidth: 1,
				borderStyle: Dashed,
				borderColor: 0xFFE4E4E7,
				borderRadius: [4, 4, 0, 0],
				shadows: [
					{x: 0, y: 1, blur: 2, spread: 0, color: 0x1A000000, inset: false},
					{x: 0, y: 0, blur: 0, spread: 1, color: t.line, inset: true}
				],
				outline: {width: 2, color: t.focus, style: Solid, offset: 2}
			});
			equals(s.chip == chip, true);
			equals(s.label == Style.of({pointerEvents: None, direction: Rtl, fontVariantNumeric: "tabular-nums", aspectRatio: 16 / 9, scrollbarWidth: Thin}), true);
		});
		test("a theme's file: typed tokens, light and dark, light-dark()", () -> {
			equals(t.surface.name, "surface");
			equals(t.accentSoft.name, "accent-soft");
			equals(t.color("surface"), 0xFFFFFFFF);
			equals(t.tone(true).color("surface"), 0xFF18181B);
			equals(t.tone(true).color("accent-soft"), 0xFF1E3A8A);
			equals(t.length("pad"), 8.0);
			equals(t.tone(true).length("pad"), 10.0);
			equals(t.length("scale"), 1.5);
			// (a module's length token, and a fallback where the theme has none)
			final m = StyleModule.load("ui/fast/tokens.module.css", "ui/fast/test.theme.css");
			equals(m.box == Style.of({padding: t.pad, background: 0xFFFF0000}), true);
		});
	});
}
