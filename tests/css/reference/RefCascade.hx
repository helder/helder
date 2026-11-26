package reference;

// #321's cascade as it was merged (bee738a8), frozen: the oracle that
// computed styles through CssStyle's groups are checked against.

import helder.css.*;
import reference.RefSheet;
import reference.RefStyle;
import reference.RefStyles;
import reference.RefUserAgent;
import reference.RefHints;
import helder.css.CssTerm;
import helder.css.CssCalc;
import helder.css.CssComputed;

import helder.css.CssMedia;
import helder.dom.Document;
import helder.dom.Element;
import helder.dom.Node;

using StringTools;

typedef RefCascadeOptions = {
	// what @media is evaluated against (CssMedia.PRINT: an A4 page)
	?media:CssMediaContext,
	// a <link>'s or @import's text by its absolute URL; null: not loaded
	?load:(url:String) -> Null<String>,
	// the document's URL, what links and url() resolve against
	?url:String,
	// the user agent's sheet (default: HTML's rendering rules and print's, RefUserAgent)
	?userAgent:RefSheet,
	?user:Array<RefSheet>,
	// author sheets after the document's own
	?author:Array<RefSheet>,
	// HTML's presentational hints (bgcolor, align, width...), as WeasyPrint's -p
	?hints:Bool
}

// A document's computed style: its sheets (the user agent's, the user's,
// then its <style> and <link rel=stylesheet> elements', in tree order,
// and `author`'s), its style attributes, cascaded per element.
//
//   var styles = RefCascade.styles(doc, {load: url -> files.get(url)});
//   styles.computed(el).text("margin-top");        // "16px"
//   styles.computed(el, "before").get("content");  // terms
class RefCascade {
	public static function styles(doc:Document, ?options:RefCascadeOptions):RefStyles {
		var o = options ?? {};
		var sheets:Array<{sheet:RefSheet, media:Null<CssMedia>}> = [];
		sheets.push({sheet: o.userAgent ?? RefUserAgent.sheet(doc.mode == Quirks), media: null});
		for (s in o.user ?? []) sheets.push({sheet: s, media: null});
		for (s in documentSheets(doc, o)) sheets.push(s);
		for (s in o.author ?? []) sheets.push({sheet: s, media: null});
		var hints = o.hints == true;
		return @:privateAccess new RefStyles(doc, sheets, o.media ?? CssMedia.PRINT, hints ? RefHints.declarations : null, hints ? RefUserAgent.hints() : null);
	}

	// The document's own sheets, in tree order, each with its media attribute's query.
	public static function documentSheets(doc:Document, ?options:RefCascadeOptions):Array<{sheet:RefSheet, media:Null<CssMedia>}> {
		var o = options ?? {};
		var out = [];
		var n:Null<Node> = doc.documentElement;
		var base = baseUrl(doc, o.url);
		while (n != null) {
			if (n.nodeType == Node.ELEMENT_NODE) {
				var el:Element = cast n;
				if (el.namespaceURI == HTML || el.namespaceURI == SVG) {
					var media = el.getAttribute("media");
					var m = media == null ? null : CssMedia.text(media);
					switch el.localName {
						case "style":
							var type = el.getAttribute("type");
							if (type == null || type == "" || Css.lower(type) == "text/css")
								out.push({sheet: RefSheet.parse(el.textContent, Author, {url: base, load: o.load}), media: m});
						case "link" if (el.namespaceURI == HTML):
							var rel = " " + Css.lower(el.getAttribute("rel") ?? "").replace("\t", " ").replace("\n", " ") + " ";
							var href = el.getAttribute("href");
							if (rel.indexOf(" stylesheet ") >= 0 && rel.indexOf(" alternate ") < 0 && href != null && href != "" && o.load != null) {
								var url = CssUrl.resolve(base, href);
								var text = o.load(url);
								if (text != null) out.push({sheet: RefSheet.parse(text, Author, {url: url, load: o.load}), media: m});
							}
						case _:
					}
				}
			}
			n = next(n, doc);
		}
		return out;
	}

	static inline var HTML = "http://www.w3.org/1999/xhtml";
	static inline var SVG = "http://www.w3.org/2000/svg";

	// (the document's base: its first <base href>, against its URL)
	static function baseUrl(doc:Document, url:Null<String>):Null<String> {
		var n:Null<Node> = doc.documentElement;
		while (n != null) {
			if (n.nodeType == Node.ELEMENT_NODE) {
				var el:Element = cast n;
				if (el.localName == "base" && el.namespaceURI == HTML && el.hasAttribute("href")) return CssUrl.resolve(url, el.getAttribute("href"));
			}
			n = next(n, doc);
		}
		return url;
	}

	static function next(n:Node, root:Node):Null<Node> {
		if (n.firstChild != null) return n.firstChild;
		while (n != root && n != null) {
			if (n.nextSibling != null) return n.nextSibling;
			n = n.parentNode;
		}
		return null;
	}
}
