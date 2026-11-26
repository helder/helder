package helder.dom;

// The tag names the parser and serializer test, as numbers: an element's
// local name is looked up once, when it is made, and compared as an Int
// after. 0: a name the parser has no rule for. The tokenizer reads tag and
// attribute names it knows straight from the input (find, intern): no copy,
// no hash of a new string.
@:noCompletion class Tags {
	public static inline var OTHER = 0;
	public static inline var A = 1;
	public static inline var ADDRESS = 2;
	public static inline var APPLET = 3;
	public static inline var AREA = 4;
	public static inline var ARTICLE = 5;
	public static inline var ASIDE = 6;
	public static inline var B = 7;
	public static inline var BASE = 8;
	public static inline var BASEFONT = 9;
	public static inline var BGSOUND = 10;
	public static inline var BIG = 11;
	public static inline var BLOCKQUOTE = 12;
	public static inline var BODY = 13;
	public static inline var BR = 14;
	public static inline var BUTTON = 15;
	public static inline var CAPTION = 16;
	public static inline var CENTER = 17;
	public static inline var CODE = 18;
	public static inline var COL = 19;
	public static inline var COLGROUP = 20;
	public static inline var DD = 21;
	public static inline var DETAILS = 22;
	public static inline var DIALOG = 23;
	public static inline var DIR = 24;
	public static inline var DIV = 25;
	public static inline var DL = 26;
	public static inline var DT = 27;
	public static inline var EM = 28;
	public static inline var EMBED = 29;
	public static inline var FIELDSET = 30;
	public static inline var FIGCAPTION = 31;
	public static inline var FIGURE = 32;
	public static inline var FONT = 33;
	public static inline var FOOTER = 34;
	public static inline var FORM = 35;
	public static inline var FRAME = 36;
	public static inline var FRAMESET = 37;
	public static inline var H1 = 38;
	public static inline var H2 = 39;
	public static inline var H3 = 40;
	public static inline var H4 = 41;
	public static inline var H5 = 42;
	public static inline var H6 = 43;
	public static inline var HEAD = 44;
	public static inline var HEADER = 45;
	public static inline var HGROUP = 46;
	public static inline var HR = 47;
	public static inline var HTML = 48;
	public static inline var I = 49;
	public static inline var IFRAME = 50;
	public static inline var IMAGE = 51;
	public static inline var IMG = 52;
	public static inline var INPUT = 53;
	public static inline var KEYGEN = 54;
	public static inline var LI = 55;
	public static inline var LINK = 56;
	public static inline var LISTING = 57;
	public static inline var MAIN = 58;
	public static inline var MARQUEE = 59;
	public static inline var MATH = 60;
	public static inline var MENU = 61;
	public static inline var META = 62;
	public static inline var NAV = 63;
	public static inline var NOBR = 64;
	public static inline var NOEMBED = 65;
	public static inline var NOFRAMES = 66;
	public static inline var NOSCRIPT = 67;
	public static inline var OBJECT = 68;
	public static inline var OL = 69;
	public static inline var OPTGROUP = 70;
	public static inline var OPTION = 71;
	public static inline var P = 72;
	public static inline var PARAM = 73;
	public static inline var PLAINTEXT = 74;
	public static inline var PRE = 75;
	public static inline var RB = 76;
	public static inline var RP = 77;
	public static inline var RT = 78;
	public static inline var RTC = 79;
	public static inline var RUBY = 80;
	public static inline var S = 81;
	public static inline var SCRIPT = 82;
	public static inline var SEARCH = 83;
	public static inline var SECTION = 84;
	public static inline var SELECT = 85;
	public static inline var SMALL = 86;
	public static inline var SOURCE = 87;
	public static inline var SPAN = 88;
	public static inline var STRIKE = 89;
	public static inline var STRONG = 90;
	public static inline var STYLE = 91;
	public static inline var SUB = 92;
	public static inline var SUMMARY = 93;
	public static inline var SUP = 94;
	public static inline var SVG = 95;
	public static inline var TABLE = 96;
	public static inline var TBODY = 97;
	public static inline var TD = 98;
	public static inline var TEMPLATE = 99;
	public static inline var TEXTAREA = 100;
	public static inline var TFOOT = 101;
	public static inline var TH = 102;
	public static inline var THEAD = 103;
	public static inline var TITLE = 104;
	public static inline var TR = 105;
	public static inline var TRACK = 106;
	public static inline var TT = 107;
	public static inline var U = 108;
	public static inline var UL = 109;
	public static inline var VAR = 110;
	public static inline var WBR = 111;
	public static inline var XMP = 112;
	public static inline var MGLYPH = 113;
	public static inline var MALIGNMARK = 114;
	public static inline var ANNOTATION_XML = 115;
	public static inline var MI = 116;
	public static inline var MO = 117;
	public static inline var MN = 118;
	public static inline var MS = 119;
	public static inline var MTEXT = 120;
	public static inline var FOREIGN_OBJECT = 121;
	public static inline var DESC = 122;

	static final NAMES = [
		"", "a", "address", "applet", "area", "article", "aside", "b", "base", "basefont", "bgsound", "big", "blockquote", "body", "br", "button", "caption",
		"center", "code", "col", "colgroup", "dd", "details", "dialog", "dir", "div", "dl", "dt", "em", "embed", "fieldset", "figcaption", "figure", "font",
		"footer", "form", "frame", "frameset", "h1", "h2", "h3", "h4", "h5", "h6", "head", "header", "hgroup", "hr", "html", "i", "iframe", "image", "img",
		"input", "keygen", "li", "link", "listing", "main", "marquee", "math", "menu", "meta", "nav", "nobr", "noembed", "noframes", "noscript", "object",
		"ol", "optgroup", "option", "p", "param", "plaintext", "pre", "rb", "rp", "rt", "rtc", "ruby", "s", "script", "search", "section", "select",
		"small", "source", "span", "strike", "strong", "style", "sub", "summary", "sup", "svg", "table", "tbody", "td", "template", "textarea", "tfoot",
		"th", "thead", "title", "tr", "track", "tt", "u", "ul", "var", "wbr", "xmp", "mglyph", "malignmark", "annotation-xml", "mi", "mo", "mn", "ms",
		"mtext", "foreignObject", "desc"
	];

	// (common attribute names: interned as the tag names are, read from the input without a copy)
	static final ATTRS = [
		"id", "class", "style", "href", "src", "alt", "title", "type", "name", "value", "rel", "content", "lang", "width", "height", "charset", "action",
		"method", "for", "target", "role", "tabindex", "dir", "colspan", "rowspan", "align", "valign", "border", "cellpadding", "cellspacing", "hidden",
		"disabled", "checked", "selected", "readonly", "placeholder", "aria-hidden", "aria-label", "aria-labelledby", "aria-describedby", "aria-expanded",
		"onclick", "srcset", "sizes", "loading", "decoding", "crossorigin", "integrity", "async", "defer", "media", "property", "itemprop", "itemscope",
		"itemtype", "http-equiv", "xmlns", "xml:lang", "xlink:href", "viewbox", "d", "fill", "stroke", "transform", "x", "y", "cx", "cy", "r", "points",
		"stroke-width", "data-mw", "data-id", "data-x", "dfn", "data-lt", "data-dfn-type", "data-export", "data-noexport", "start", "label", "size",
		"maxlength", "pattern", "required", "autocomplete", "autofocus", "accept", "enctype", "novalidate", "headers", "scope", "datetime", "cite",
		"download", "ping", "referrerpolicy", "sandbox", "allow", "frameborder", "usemap", "ismap", "shape", "coords", "poster", "preload", "controls",
		"autoplay", "loop", "muted", "kind", "srclang", "default", "nonce", "translate", "spellcheck", "contenteditable", "draggable", "accesskey", "slot",
		"is", "part", "inert", "popover", "open", "wrap", "rows", "cols", "span", "summary", "abbr", "axis", "nowrap", "bgcolor", "color", "face",
		"background", "link", "vlink", "alink", "text", "compact", "noshade", "clear", "encoding", "definitionurl"
	];

	static inline var SLOTS = 1024;

	// the names (tags, then attributes) by a hash of their units, open addressing (-1: empty)
	static var table:Null<Array<Int>> = null;
	static var all:Array<String> = [];

	// (a name's hash: its length, first two and last units; the comparison settles the rest)
	static inline function hash(s:String, from:Int, to:Int):Int {
		var n = to - from;
		if (n == 0) return 0;
		return n * 7919 ^ StringTools.fastCodeAt(s, from) * 131 ^ (n > 1 ? StringTools.fastCodeAt(s, from + 1) * 17 : 0) ^ StringTools.fastCodeAt(s, to - 1) * 1031;
	}

	static function build():Array<Int> {
		all = NAMES.concat(ATTRS);
		var t = [for (_ in 0...SLOTS) -1];
		for (k in 1...all.length) {
			var n = all[k];
			var slot = hash(n, 0, n.length) & (SLOTS - 1);
			while (t[slot] >= 0)
				slot = (slot + 1) & (SLOTS - 1);
			t[slot] = k;
		}
		return t;
	}

	// the index of s[from, to) among the names (0: none)
	public static function find(s:String, from:Int, to:Int):Int {
		var t = table;
		if (t == null) t = table = build();
		var slot = hash(s, from, to) & (SLOTS - 1), n = to - from;
		while (true) {
			var k = t[slot];
			if (k < 0) return 0;
			var name = all[k];
			if (name.length == n) {
				var i = 0;
				while (i < n && StringTools.fastCodeAt(name, i) == StringTools.fastCodeAt(s, from + i))
					i++;
				if (i == n) return k;
			}
			slot = (slot + 1) & (SLOTS - 1);
		}
	}

	// the name of an index find gave
	public static inline function name(k:Int):String
		return all[k];

	// s[from, to) as its interned string, if it is a known name (null: not one)
	public static function intern(s:String, from:Int, to:Int):Null<String> {
		var k = find(s, from, to);
		return k == 0 ? null : all[k];
	}

	public static function id(name:String):Int {
		var k = find(name, 0, name.length);
		return k < NAMES.length ? k : OTHER;
	}
}
