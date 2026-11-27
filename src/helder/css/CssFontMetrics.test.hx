package helder.css;

import helder.css.CssFontMetrics;
import helder.dom.Dom;
import helder.test.Test;

// The font-relative units through CssStyles.metrics (an engine's hook): ex,
// ch, cap and ic the element's first available font's, the font properties'
// the parent's, rex and the others the root's, lh for line-height: normal
// that font's; without the hook they stay as written
function tests() {
	describe("CssFontMetrics", () -> {
		// (each size's metrics as fractions of it: what a font of the family "big" doubles)
		function metrics(q:CssFontQuery):CssFontMetrics {
			var k = q.family.length > 0 && q.family[0].match(Ident("big")) ? 2 : 1;
			return {ex: q.size * 0.5 * k, ch: q.size * 0.6 * k, cap: q.size * 0.7 * k, ic: q.size * k, lineHeight: q.size * 1.25};
		}
		function styled(css:String):CssStyles {
			var s = CssCascade.styles(Dom.parse('<!doctype html><style>html { font-size: 10px } $css</style><div id=a><p id=b>x</p></div>'));
			s.metrics = metrics;
			return s;
		}
		function text(s:CssStyles, id:String, p:String)
			return s.computed(s.document.getElementById(id)).text(p);

		test("ex, ch, cap and ic: the element's font's", () -> {
			var s = styled("#a { font-size: 20px; margin-left: 2ch; margin-right: 1ex; margin-top: 1cap; margin-bottom: 1ic }");
			equals([text(s, "a", "margin-left"), text(s, "a", "margin-right"), text(s, "a", "margin-top"), text(s, "a", "margin-bottom")],
				["24px", "10px", "14px", "20px"]);
		});
		test("font-size in ex: the parent's font's; another family's metrics its own", () -> {
			var s = styled("#a { font-size: 20px } #b { font-size: 2ex; font-family: big; margin-left: 1ch }");
			equals(text(s, "b", "font-size"), "20px");
			equals(text(s, "b", "margin-left"), "24px");
		});
		test("rch and rex: the root's", () -> {
			equals(text(styled("#b { font-size: 30px; margin-left: 2rch; margin-right: 1rex }"), "b", "margin-left"), "12px");
		});
		test("lh for line-height: normal: the font's", () -> {
			equals(text(styled("#a { font-size: 20px; margin-left: 1lh }"), "a", "margin-left"), "25px");
		});
		test("without the hook: as written", () -> {
			var s = CssCascade.styles(Dom.parse('<!doctype html><style>#a { margin-left: 2ch }</style><div id=a></div>'));
			equals(s.computed(s.document.getElementById("a")).text("margin-left"), "2ch");
		});
	});
}
