package ui.fast;

import helder.test.Test;
import helder.ui.fast.Style;
import helder.ui.fast.Style.TintValue;
import helder.ui.fast.StyleModule;
import helder.ui.fast.Theme;

// A CSS module compiled to fast styles when the test is built: what it
// says the same Style as the same written in Haxe.
function tests() {
	describe("StyleModule", () -> {
		test("a module's classes are Styles: states, nesting, composes, tokens", () -> {
			final s = StyleModule.load("ui/fast/card.module.css");
			var card = Style.of({
				padding: [4, 8],
				borderRadius: 6,
				display: Flex,
				flexDirection: Row,
				alignItems: Center,
				columnGap: 8,
				background: Theme.token("surface"),
				color: 0xFF18181B,
				borderWidth: 1,
				borderColor: 0xFFE4E4E7,
				cursor: Pointer,
				hover: {background: Theme.token("hover")},
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
	});
}
