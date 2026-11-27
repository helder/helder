package helder.css;

import helder.css.CssProperty;
import helder.dom.Dom;
import helder.test.Test;

// Computed values interpolated by each property's animation type (the
// WPT cases are the css lane's, CssInterpolationCheck): lengths and their
// mixes with percentages, colours, transforms, shadows, filters,
// visibility, ratios, discrete values.
function tests() {
	describe("CssInterpolate", () -> {
		test("lengths, percentages and their mix", () -> {
			equals(at("width", "10px", "30px", 0.25), "15px");
			equals(at("width", "10%", "30%", 0.5), "20%");
			equals(at("width", "10px", "50%", 0.5), "calc(25% + 5px)");
			equals(at("width", "2em", "40px", 0.5), "35px");
		});
		test("ranges clamp, integers round", () -> {
			equals(at("width", "10px", "20px", -2), "0px");
			equals(at("opacity", "0.5", "1", 2), "1");
			equals(at("z-index", "1", "4", 0.5), "3");
			equals(at("order", "1", "4", 0.4), "2");
		});
		test("colours: legacy in sRGB, others in Oklab, premultiplied", () -> {
			equals(at("color", "rgb(0, 0, 0)", "rgb(255, 255, 255)", 0.5), "rgb(128, 128, 128)");
			equals(at("color", "rgba(255, 0, 0, 0)", "rgb(0, 0, 255)", 0.5), "rgba(0, 0, 255, 0.5)");
			equals(at("color", "black", "green", 1.5), "rgb(0, 192, 0)");
			equals(at("color", "oklab(0 0 0)", "oklab(1 0.2 0)", 0.5), "oklab(0.5 0.1 0)");
		});
		test("currentcolor and system colours", () -> {
			equals(at("background-color", "currentcolor", "rgb(0, 0, 255)", 0.5, "color: rgb(255, 0, 0)"), "rgb(128, 0, 128)");
			equals(at("border-top-color", "canvastext", "rgb(0, 200, 0)", 0.5), "rgb(0, 100, 0)");
		});
		test("transforms: function by function, else matrices", () -> {
			equals(at("transform", "none", "translate(200px) rotate(720deg)", 0.25), "translate(50px) rotate(180deg)");
			equals(at("transform", "translateX(100px)", "translateY(200px)", 0.25), "translate(75px, 50px)");
			equals(at("transform", "scale(2)", "scale(4)", 0.5), "scale(3)");
			equals(near(at("transform", "matrix(1, 0, 0, 7, 0, 0)", "matrix(7, 0, 1, 1, 0, 0)", 0.5)), "matrix(4, 0, 2, 4, 0, 0)");
			equals(near(at("transform", "rotate(90deg)", "translate(10px) scale(2)", 0.5)), "matrix(1.06066, 1.06066, -1.06066, 1.06066, 5, 0)");
			equals(at("transform", "perspective(10px)", "none", 0.5), null);
		});
		test("translate, scale, rotate: none as the identity", () -> {
			equals(at("translate", "none", "10px 20px", 0.5), "5px 10px");
			equals(at("scale", "none", "3", 0.5), "2");
			equals(at("rotate", "none", "90deg", 0.5), "45deg");
		});
		test("shadows: the shorter list padded", () -> {
			equals(at("box-shadow", "none", "10px 10px 10px 0px rgb(0, 0, 0)", 0.5), "rgba(0, 0, 0, 0.5) 5px 5px 5px 0px");
			equals(at("box-shadow", "inset 1px 1px black", "1px 1px black", 0.5), null);
			equals(at("text-shadow", "2px 2px 2px red", "4px 4px 4px red", 0.5), "rgb(255, 0, 0) 3px 3px 3px");
		});
		test("filters: none as each function's identity, blurs at least 0", () -> {
			equals(at("filter", "none", "blur(10px) opacity(0)", 0.5), "blur(5px) opacity(0.5)");
			equals(at("filter", "none", "blur(10px)", -1), "blur(0px)");
			equals(at("filter", "blur(1px)", "opacity(0)", 0.5), null);
		});
		test("spacing: normal as 0", () -> {
			equals(at("letter-spacing", "normal", "10px", 0.3), "3px");
			equals(at("letter-spacing", "normal", "10px", 0), "normal");
		});
		test("visibility, ratios, font-style", () -> {
			equals(at("visibility", "hidden", "visible", 0.1), "visible");
			equals(at("visibility", "hidden", "visible", 0), "hidden");
			equals(at("visibility", "hidden", "collapse", 0.5), null);
			equals(at("aspect-ratio", "1 / 1", "4 / 1", 0.5), "2 / 1");
			equals(at("font-style", "normal", "oblique 20deg", 0.5), "oblique 10deg");
		});
		test("lists by layer, repeatable ones to a common length", () -> {
			equals(at("background-position-x", "0px", "10px, 20px", 0.5), "5px, 10px");
			equals(at("border-top-left-radius", "20px", "10px 30px", 0.5), "15px 25px");
			equals(at("border-top-left-radius", "20px", "10px 30px", 0), "20px");
		});
		test("discrete values don't interpolate, display keeps what isn't none", () -> {
			equals(at("display", "block", "flex", 0.5), null);
			equals(at("counter-reset", "a 1", "a 3", 0.5), null);
			equals(at("width", "auto", "10px", 0.5), null);
			equals(discrete("display", "none", "block", 0.1), "block");
			equals(discrete("display", "block", "none", 0.9), "block");
			equals(discrete("display", "block", "none", 1), "none");
			equals(discrete("content-visibility", "hidden", "auto", 0.1), "auto");
			equals(discrete("content-visibility", "visible", "hidden", 0.9), "visible");
			equals(discrete("float", "left", "right", 0.4), "left");
			equals(discrete("float", "left", "right", 0.5), "right");
		});
	});
}

// (a property from one value to another, written; null when they don't interpolate)
private function at(property:String, from:String, to:String, t:Float, ?extra:String):Null<String> {
	var p = CssProperties.of(property);
	var a = style('$property: $from; ${extra ?? ""}'), b = style('$property: $to; ${extra ?? ""}');
	var v = CssInterpolate.values(p, CssTransition.resolved(a, p), CssTransition.resolved(b, p), t);
	return v == null ? null : CssValues.written(property, v, @:privateAccess a.context());
}

private function discrete(property:String, from:String, to:String, t:Float):String {
	var p = CssProperties.of(property);
	var a = style('$property: $from'), b = style('$property: $to');
	return CssValues.written(property, CssInterpolate.discrete(p, a.terms(p), b.terms(p), t), @:privateAccess a.context());
}

private function style(declarations:String):CssStyle {
	var doc = Dom.parse('<!doctype html><div style="font-size: 15px"><p id=x style="$declarations"></p></div>');
	return CssCascade.styles(doc).computed(doc.getElementById("x"));
}

// (numbers to five places, as a matrix prints near 0)
private function near(v:Null<String>):Null<String>
	return v == null ? null : ~/-?\d+\.?\d*(e-?\d+)?/g.map(v, m -> {
		var n = Math.round(Std.parseFloat(m.matched(0)) * 100000) / 100000;
		n == 0 ? "0" : Std.string(n);
	});
