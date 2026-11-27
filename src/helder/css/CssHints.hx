package helder.css;

import helder.css.CssProperty;
import helder.css.CssSheet;
import helder.css.CssTerm;
import helder.dom.Element;
import helder.dom.Node;

using StringTools;

// HTML's presentational hints its Rendering section says in prose (the
// ones it writes as CSS are CssUserAgent.hints()): attributes mapped to
// properties, as WeasyPrint's -p does. Colours by the legacy colour value
// rules (a name, or hex with or without #), lengths by the rules for
// dimension values (px, or a percentage).
class CssHints {
	static inline var HTML = "http://www.w3.org/1999/xhtml";

	// (HTML's list numbering, applied whether or not hints are: li's value
	// as counter-set, ol's start and reversed as counter-reset, Rendering
	// §15.3.7; a list numbers wrongly without them)
	public static function lists(el:Element):Null<Array<CssDeclared>> {
		if (el.namespaceURI != HTML) return null;
		switch el.localName {
			case "li":
				var v = integer(el.getAttribute("value"));
				return v == null ? null : counter(CounterSet, false, v);
			case "ol":
				var start = integer(el.getAttribute("start"));
				if (el.hasAttribute("reversed")) return counter(CounterReset, true, start == null ? null : start + 1);
				return start == null ? null : counter(CounterReset, false, start - 1);
			case _: return null;
		}
	}

	// (`counter-set: list-item 3`, `counter-reset: reversed(list-item) 4`, as
	// a sheet compiles them: no parser for every cascade)
	static function counter(p:CssProperty, reversed:Bool, value:Null<Int>):Array<CssDeclared> {
		var name = CssTerm.Ident("list-item");
		var terms = [reversed ? CssTerm.Func("reversed", [name]) : name];
		if (value != null) terms.push(CssTerm.Number(value, true));
		return [{property: CssProperties.name(p), id: p, value: Terms(terms), important: false}];
	}

	// (HTML's rules for parsing integers: spaces, a sign, digits, the rest ignored)
	static function integer(text:Null<String>):Null<Int> {
		if (text == null) return null;
		var k = 0, n = text.length;
		while (k < n && " \t\n\r\x0C".indexOf(text.charAt(k)) >= 0) k++;
		var negative = false;
		if (k < n && (text.charAt(k) == "-" || text.charAt(k) == "+")) negative = text.charAt(k++) == "-";
		var start = k;
		var v = 0.0;
		while (k < n && text.charCodeAt(k) >= "0".code && text.charCodeAt(k) <= "9".code) v = v * 10 + (text.charCodeAt(k++) - "0".code);
		if (k == start) return null;
		if (v > 2147483647) v = 2147483647;
		return Std.int(negative ? -v : v);
	}

	// SVG's presentation attributes (SVG 2 §6.6) of the properties helder has:
	// declarations as the hints are, an author's rule of specificity zero
	// (an SVG element's style attribute and the sheets' rules over them).
	// Whether HTML's hints are taken or not.
	public static function presentation(el:Element):Array<CssDeclared> {
		if (el.namespaceURI != SVG) return [];
		var css = new StringBuf();
		for (name in PRESENTATION) {
			var v = el.getAttribute(name);
			if (v != null && v.indexOf(";") < 0) css.add('$name: $v;');
		}
		// (an svg element's width and height: its box's, SVG 2 §8.2's geometry properties, a number as px)
		if (el.localName == "svg") for (name in ["width", "height"]) {
			var v = el.getAttribute(name);
			if (v == null || v.indexOf(";") >= 0) continue;
			v = v.trim();
			css.add('$name: ${~/^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$/.match(v) ? v + "px" : v};');
		}
		var text = css.toString();
		return text == "" ? [] : CssSheet.attribute(text);
	}

	static inline var SVG = "http://www.w3.org/2000/svg";
	static final PRESENTATION = [
		"fill", "fill-opacity", "fill-rule", "stroke", "stroke-width", "stroke-opacity", "stroke-linecap", "stroke-linejoin", "stroke-miterlimit",
		"stroke-dasharray", "stroke-dashoffset", "stop-color", "stop-opacity", "color", "opacity", "visibility", "display"
	];

	public static function declarations(el:Element):Array<CssDeclared> {
		if (el.namespaceURI != HTML) return [];
		var css = new StringBuf();
		inline function add(property:String, value:Null<String>)
			if (value != null) css.add('$property: $value;');
		var name = el.localName;
		switch name {
			case "body":
				add("color", color(el.getAttribute("text")));
				add("background-color", color(el.getAttribute("bgcolor")));
				add("background-image", image(el.getAttribute("background")));
				// (HTML §15.3.2: the first of each margin's attributes that parses, else 8px)
				inline function margin(property:String, a:String, b:String)
					add(property, length(el.getAttribute(a)) ?? length(el.getAttribute(b)) ?? "8px");
				margin("margin-top", "marginheight", "topmargin");
				margin("margin-bottom", "marginheight", "bottommargin");
				margin("margin-left", "marginwidth", "leftmargin");
				margin("margin-right", "marginwidth", "rightmargin");
			case "table":
				add("background-color", color(el.getAttribute("bgcolor")));
				add("background-image", image(el.getAttribute("background")));
				add("width", length(el.getAttribute("width")));
				add("height", length(el.getAttribute("height")));
				add("border-spacing", length(el.getAttribute("cellspacing")));
				var border = el.getAttribute("border");
				if (border != null) {
					var w = pixels(border) ?? 1;
					css.add('border-width: ${w}px; border-style: ${w > 0 ? "outset" : "none"};');
				}
			case "td" | "th":
				add("background-color", color(el.getAttribute("bgcolor")));
				add("background-image", image(el.getAttribute("background")));
				add("width", length(el.getAttribute("width")));
				add("height", length(el.getAttribute("height")));
				if (el.hasAttribute("nowrap") && !(el.getAttribute("width") ?? "").endsWith("px")) css.add("white-space: nowrap;");
				// (the table's cellpadding, and its border's 1px inset cells)
				var table = ancestor(el, "table");
				if (table != null) {
					var pad = length(table.getAttribute("cellpadding"));
					if (pad != null) css.add('padding: $pad;');
					var border = table.getAttribute("border");
					if (border != null && (pixels(border) ?? 1) > 0) css.add("border-width: 1px; border-style: inset;");
				}
			case "tr" | "thead" | "tbody" | "tfoot":
				add("background-color", color(el.getAttribute("bgcolor")));
				add("background-image", image(el.getAttribute("background")));
				if (name == "tr") add("height", length(el.getAttribute("height")));
			case "col" | "colgroup":
				add("width", length(el.getAttribute("width")));
			case "img" | "object" | "embed" | "iframe" | "video" | "canvas":
				add("width", length(el.getAttribute("width")));
				add("height", length(el.getAttribute("height")));
				var h = length(el.getAttribute("hspace")), v = length(el.getAttribute("vspace"));
				if (h != null) css.add('margin-left: $h; margin-right: $h;');
				if (v != null) css.add('margin-top: $v; margin-bottom: $v;');
				if (name == "img" || name == "object") {
					var b = pixels(el.getAttribute("border") ?? "");
					if (b != null) css.add('border-width: ${b}px; border-style: solid;');
				}
			case "hr":
				add("width", length(el.getAttribute("width")));
				var c = color(el.getAttribute("color"));
				if (c != null) css.add('color: $c; background-color: $c;');
				var size = pixels(el.getAttribute("size") ?? "");
				if (size != null) css.add(size > 1 ? 'height: ${size - 2}px;' : "border-bottom-width: 0;");
			case "font":
				add("color", color(el.getAttribute("color")));
				var face = el.getAttribute("face");
				if (face != null && face.trim() != "") css.add('font-family: ${face};');
				add("font-size", fontSize(el.getAttribute("size")));
			case _:
		}
		var text = css.toString();
		return text == "" ? [] : CssSheet.attribute(text);
	}

	static function ancestor(el:Element, name:String):Null<Element> {
		var n = el.parentNode;
		while (n != null) {
			if (n.nodeType == Node.ELEMENT_NODE && (cast n : Element).localName == name) return cast n;
			n = n.parentNode;
		}
		return null;
	}

	// (the rules for parsing dimension values: digits, maybe a fraction, then % or not)
	static function length(v:Null<String>):Null<String> {
		if (v == null) return null;
		var r = ~/^[ \t\n\r\x0C]*([0-9]+(\.[0-9]+)?)(%?)/;
		if (!r.match(v)) return null;
		return r.matched(3) == "%" ? r.matched(1) + "%" : r.matched(1) + "px";
	}

	static function pixels(v:String):Null<Int> {
		var r = ~/^[ \t\n\r\x0C]*([0-9]+)/;
		return r.match(v) ? Std.parseInt(r.matched(1)) : null;
	}

	// (a legacy colour: a name, else hex digits with or without #)
	static function color(v:Null<String>):Null<String> {
		if (v == null) return null;
		var s = v.trim();
		if (s == "" || Css.lower(s) == "transparent") return null;
		if (CssColors.keyword(s) != null) return s;
		var hex = s.startsWith("#") ? s.substr(1) : s;
		return ~/^[0-9A-Fa-f]{3}$|^[0-9A-Fa-f]{6}$/.match(hex) ? '#$hex' : null;
	}

	static function image(v:Null<String>):Null<String>
		return v == null || v.trim() == "" ? null : 'url(${CssText.string(v.trim())})';

	// (font's size: 1 to 7, or relative to 3)
	static function fontSize(v:Null<String>):Null<String> {
		if (v == null) return null;
		var r = ~/^[ \t\n\r\x0C]*([+-]?)([0-9]+)/;
		if (!r.match(v)) return null;
		var n = Std.parseInt(r.matched(2));
		if (r.matched(1) == "+") n = 3 + n else if (r.matched(1) == "-") n = 3 - n;
		if (n < 1) n = 1;
		if (n > 7) n = 7;
		return ["x-small", "small", "medium", "large", "x-large", "xx-large", "xxx-large"][n - 1];
	}
}
