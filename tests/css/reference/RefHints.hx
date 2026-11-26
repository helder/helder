package reference;

// #321's cascade as it was merged (bee738a8), frozen: the oracle that
// computed styles through CssStyle's groups are checked against.

import helder.css.*;
import reference.RefSheet;
import reference.RefStyle;
import reference.RefStyles;
import reference.RefCascade;
import reference.RefUserAgent;
import helder.css.CssTerm;
import helder.css.CssCalc;
import helder.css.CssComputed;

import helder.dom.Element;
import helder.dom.Node;

using StringTools;

// HTML's presentational hints its Rendering section says in prose (the
// ones it writes as CSS are RefUserAgent.hints()): attributes mapped to
// properties, as WeasyPrint's -p does. Colours by the legacy colour value
// rules (a name, or hex with or without #), lengths by the rules for
// dimension values (px, or a percentage).
class RefHints {
	static inline var HTML = "http://www.w3.org/1999/xhtml";

	public static function declarations(el:Element):Array<RefDeclared> {
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
				add("margin-top", length(el.getAttribute("marginheight") ?? el.getAttribute("topmargin")));
				add("margin-bottom", length(el.getAttribute("marginheight") ?? el.getAttribute("bottommargin")));
				add("margin-left", length(el.getAttribute("marginwidth") ?? el.getAttribute("leftmargin")));
				add("margin-right", length(el.getAttribute("marginwidth") ?? el.getAttribute("rightmargin")));
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
		return text == "" ? [] : RefSheet.attribute(text);
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
