package helder.dom;

// The tag names the parser and serializer test, as numbers: an element's
// local name is looked up once, when it is made, and compared as an Int
// after. 0: a name the parser has no rule for.
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

	static var ids:Null<Map<String, Int>> = null;

	public static function id(name:String):Int {
		var m = ids;
		if (m == null) {
			m = ids = new Map();
			for (k in 1...NAMES.length)
				m.set(NAMES[k], k);
		}
		return m.get(name) ?? OTHER;
	}
}
