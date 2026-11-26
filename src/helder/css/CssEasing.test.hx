package helder.css;

import helder.css.CssProperty;
import helder.css.CssTerm;
import helder.dom.Dom;
import helder.test.Test;

// Easing functions (Easing 1, 2): the keywords, cubic-bezier(), steps(),
// linear().
function tests() {
	describe("CssEasing", () -> {
		test("keywords", () -> {
			equals(at("linear", 0.3), 0.3);
			equals(at("ease", 0.5), 0.8024);
			equals(at("ease-in", 0.5), 0.3154);
			equals(at("ease-out", 0.5), 0.6846);
			equals(at("ease-in-out", 0.5), 0.5);
			equals(at("step-start", 0), 1);
			equals(at("step-end", 0.99), 0);
		});
		test("cubic-bezier, past 0 and 1 along its tangents", () -> {
			equals(at("cubic-bezier(0, 0, 1, 1)", 0.4), 0.4);
			equals(at("cubic-bezier(0.5, 1.5, 0.5, -0.5)", 0.5), 0.5);
			equals(at("cubic-bezier(0.25, 0.5, 0.75, 0.5)", -1), -2);
			equals(at("cubic-bezier(0.25, 0.5, 0.75, 0.5)", 2), 3);
		});
		test("steps", () -> {
			equals(at("steps(4)", 0.3), 0.25);
			equals(at("steps(4, start)", 0.3), 0.5);
			equals(at("steps(4, jump-none)", 0.5), 0.6667);
			equals(at("steps(4, jump-both)", 0.3), 0.4);
			equals(at("steps(4, end)", 1), 1);
			equals(CssEasing.of(terms("steps(1, start)")).at(0, true), 0);
		});
		test("linear(), its missing inputs spread", () -> {
			equals(at("linear(0, 1)", 0.25), 0.25);
			equals(at("linear(0, 0.25, 1)", 0.25), 0.125);
			equals(at("linear(0, 0.5 25%, 1)", 0.25), 0.5);
			equals(at("linear(0, 0.5 25% 75%, 1)", 0.5), 0.5);
			equals(at("linear(0, 1)", 2), 2);
		});
	});
}

private function at(easing:String, x:Float):Float
	return Math.round(CssEasing.of(terms(easing)).at(x) * 10000) / 10000;

private function terms(easing:String):Array<CssTerm> {
	var doc = Dom.parse('<!doctype html><p id=x style="transition-timing-function: $easing"></p>');
	return CssCascade.styles(doc).computed(doc.getElementById("x")).terms(TransitionTimingFunction);
}
