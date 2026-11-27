package helder.ui.box;

import haxe.io.Bytes;
import helder.canvas.Bitmap;
import helder.canvas.Svg;
import helder.css.CssProperties;
import helder.css.CssProperty;
import helder.css.CssStyle;
import helder.css.CssStyles;
import helder.css.CssTerm;
import helder.dom.Element;

using StringTools;

// What a document's images are besides a host's rasters: data: URLs
// (decoded here, a host's loader never sees them), SVG files read as text
// and drawn as vectors (helder.canvas's Svg), and an HTML document's inline
// <svg>, built from its DOM with each element's paint as the cascade
// computed it (sheets, style attributes, presentation attributes).
class BoxImages {
	static inline var SVG = "http://www.w3.org/2000/svg";

	// a data: URL's type and bytes (base64 or percent-encoded); null: not one
	public static function data(url:String):Null<{type:String, bytes:Bytes}> {
		if (!url.startsWith("data:")) return null;
		var comma = url.indexOf(",");
		if (comma < 0) return null;
		var head = url.substring(5, comma), body = url.substr(comma + 1);
		var base64 = head.toLowerCase().endsWith(";base64");
		var type = head.split(";")[0].trim().toLowerCase();
		var bytes = try base64 ? haxe.crypto.Base64.decode(body.split("%20").join("").replace(" ", "")) : Bytes.ofString(body.urlDecode()) catch (_:Dynamic) null;
		return bytes == null ? null : {type: type == "" ? "text/plain" : type, bytes: bytes};
	}

	// a data: URL's raster image, null where it is none (or SVG)
	public static function raster(url:String):Null<Bitmap> {
		var d = data(url);
		if (d == null || d.type == "image/svg+xml") return null;
		return try Bitmap.fromImage(helder.image.Image.decode(d.bytes)) catch (_:Dynamic) null;
	}

	// an SVG image by its URL (absolute): a data: URL of image/svg+xml, or a
	// path ending in .svg read by load; null: not one, or not read
	public static function svg(url:String, load:Null<String->Null<String>>):Null<Svg> {
		var d = data(url), text:Null<String> = null;
		if (d != null) {
			if (d.type != "image/svg+xml") return null;
			text = d.bytes.toString();
		} else {
			var path = url.split("#")[0].split("?")[0].toLowerCase();
			if (!path.endsWith(".svg") || load == null) return null;
			text = try load(url) catch (_:Dynamic) null;
		}
		return text == null ? null : try Svg.read(text) catch (_:Dynamic) null;
	}

	// An inline svg element's drawing: its elements as SVG, each one's paint
	// written where the cascade made it other than its parent's (inherited
	// as SVG inherits, a use's content from the use), currentcolor as the
	// element's color.
	public static function of(el:Element, styles:CssStyles):Null<Svg> {
		var root = Xml.createElement("svg");
		copy(el, root, styles, null);
		return try Svg.of(root) catch (_:Dynamic) null;
	}

	static function copy(el:Element, into:Xml, styles:CssStyles, parent:Null<CssStyle>) {
		var s = styles.computed(el);
		for (name in el.getAttributeNames())
			if (name != "style" && !INHERITED.contains(name) && !OWN.contains(name)) into.set(name, el.getAttribute(name));
		for (name in INHERITED) {
			var v = text(s, name);
			if (v != null && (parent == null || v != text(parent, name))) into.set(name, v);
		}
		for (name in OWN) {
			var v = text(s, name);
			if (v != null && v != (name == "stop-color" ? "rgba(0, 0, 0, 1)" : "1")) into.set(name, v);
		}
		if (s.keyword(Display) == "none") into.set("display", "none");
		var c = el.firstElementChild;
		while (c != null) {
			if (c.namespaceURI == SVG) {
				var x = Xml.createElement(c.localName);
				into.addChild(x);
				copy(c, x, styles, s);
			}
			c = c.nextElementSibling;
		}
	}

	// (a property's computed value as SVG writes it: colours as rgba(), lengths as numbers)
	static function text(s:CssStyle, name:String):Null<String> {
		var p = CssProperties.of(name);
		if (p == null) return null;
		var terms = s.terms(p);
		return switch name {
			case "fill" | "stroke" | "stop-color":
				switch terms {
					case [Keyword("none")]: "none";
					case _ if (terms.length > 0 && terms[0].match(Url(_, _))): switch terms[0] {
							case Url(u, _): 'url($u)';
							case _: null;
						}
					case [Color(_)]:
						var c = s.color(p);
						c.keyword != null ? null : 'rgba(${Math.round(c.r * 255)}, ${Math.round(c.g * 255)}, ${Math.round(c.b * 255)}, ${c.a})';
					case _: null;
				}
			case _: ~/(\d)px\b/g.replace(s.written(p), "$1");
		}
	}

	static final INHERITED = [
		"fill", "fill-opacity", "fill-rule", "stroke", "stroke-width", "stroke-opacity", "stroke-linecap", "stroke-linejoin", "stroke-miterlimit",
		"stroke-dasharray", "stroke-dashoffset"
	];
	static final OWN = ["opacity", "stop-color", "stop-opacity"];
}
