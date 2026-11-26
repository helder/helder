package helder.css;

import helder.css.CssProperty;
import helder.dom.Dom;
import helder.test.Test;

// Which properties start transitions when a style changes (Transitions
// 1 §3, 2 §3), with their timing, and their values over time.
function tests() {
	describe("CssTransition", () -> {
		test("a changed property with a duration starts", () -> {
			var t = starts("width: 10px", "width: 20px; transition: width 2s 1s linear");
			equals(t.length, 1);
			equals(CssProperties.name(t[0].property), "width");
			equals(t[0].duration, 2);
			equals(t[0].delay, 1);
			equals(written(t[0], 2), "15px");
			equals(written(t[0], 0.5), "10px");
			equals(written(t[0], 4), "20px");
		});
		test("no duration, no change, none: nothing starts", () -> {
			equals(starts("width: 10px", "width: 20px; transition: width 0s").length, 0);
			equals(starts("width: 10px", "width: 10px; transition: width 1s").length, 0);
			equals(starts("width: 10px", "width: 20px; transition: none").length, 0);
			equals(starts("width: 10px", "width: 20px; transition: height 1s").length, 0);
		});
		test("a negative delay starts part way", () -> {
			var t = starts("opacity: 0", "opacity: 1; transition: opacity 2s -1s linear");
			equals(t.length, 1);
			equals(written(t[0], 0), "0.5");
		});
		test("all, shorthands, the last name winning, lists repeated", () -> {
			var t = starts("width: 1px; height: 1px; opacity: 0", "width: 2px; height: 2px; opacity: 1; transition: all 1s, height 3s");
			var timed = [for (x in t) '${CssProperties.name(x.property)} ${x.duration}'];
			timed.sort(Reflect.compare);
			equals(timed.join(", "), "height 3, opacity 1, width 1");
			var m = starts("margin: 0", "margin: 4px; transition-property: margin; transition-duration: 1s, 2s");
			equals(names(m), "margin-top margin-right margin-bottom margin-left");
			var r = starts("width: 1px; height: 1px", "width: 2px; height: 2px; transition-property: width, height; transition-duration: 1s, 2s, 3s");
			equals([for (x in r) x.duration].join(" "), "1 2");
		});
		test("discrete ones start with allow-discrete only, and flip", () -> {
			equals(starts("float: left", "float: right; transition: float 1s").length, 0);
			var t = starts("float: left", "float: right; transition: float 1s allow-discrete");
			equals(t.length, 1);
			equals(t[0].discrete, true);
			equals(written(t[0], 0.25), "left");
			equals(written(t[0], 0.75), "right");
			var d = starts("display: none", "display: block; transition: display 1s allow-discrete");
			equals(written(d[0], 0.1), "block");
		});
		test("currentcolor transitions as the colour", () -> {
			var t = starts("color: rgb(0, 0, 0); border-top-color: currentcolor", "color: rgb(0, 0, 0); border-top-color: rgb(0, 200, 0); transition: border-top-color 1s linear");
			equals(written(t[0], 0.5), "rgb(0, 100, 0)");
		});
		test("the easing shapes the progress", () -> {
			var t = starts("opacity: 0", "opacity: 1; transition: opacity 1s steps(2)");
			equals(written(t[0], 0.4), "0");
			equals(written(t[0], 0.6), "0.5");
		});
	});
}

private function starts(before:String, after:String):Array<CssTransition.CssTransitionStart>
	return CssTransition.starts(style(before), style(after));

private function written(t:CssTransition.CssTransitionStart, time:Float):String {
	var name = CssProperties.name(t.property);
	return CssValues.written(name, CssTransition.value(t, time), @:privateAccess style("").context());
}

private function names(t:Array<CssTransition.CssTransitionStart>):String
	return [for (x in t) CssProperties.name(x.property)].join(" ");

private function style(declarations:String):CssStyle {
	var doc = Dom.parse('<!doctype html><p id=x style="$declarations"></p>');
	return CssCascade.styles(doc).computed(doc.getElementById("x"));
}
