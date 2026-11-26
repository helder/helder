import haxe.Json;
import helder.dom.Document;
import helder.dom.Node;
import helder.ui.flow.InlineBasicStyle;
import helder.ui.flow.InlineConstraints;
import helder.ui.flow.InlineContent;
import helder.ui.flow.InlineLayout;
import helder.ui.flow.InlineValues;

// The differential's layouts (tests/flow/differential.mjs): each case of a
// JSON file (a tree of text, inline boxes, inline-blocks and breaks, every
// element's computed style given) laid out in Ahem by helder.ui.flow, the
// rectangles Chromium's getClientRects would give written as JSON: each
// text node's text runs, each inline box's spans, each atomic's border box,
// and the block's height.
//   InlineDiffCheck <cases.json> <out.json>
class InlineDiffCheck {
	static function main() {
		var args = Sys.args();
		helder.text.SystemFonts.get().add(sys.io.File.getBytes("tests/flow/fixtures/Ahem.ttf"));
		var cases:Array<Dynamic> = Json.parse(sys.io.File.getContent(args[0]));
		var out = [for (c in cases) layout(c)];
		sys.io.File.saveContent(args[1], Json.stringify(out));
	}

	static function layout(c:Dynamic):Dynamic {
		var doc = new Document();
		var ids = new Map<Node, String>();
		var root = style(c.style);
		var content = new InlineContent(root);
		function add(nodes:Array<Dynamic>, parent:InlineBasicStyle) {
			for (n in nodes)
				switch (n.kind : String) {
					case "text":
						var t = doc.createTextNode(n.text);
						ids.set(t, n.id);
						content.addText(n.text, parent, t);
					case "box":
						var e = doc.createElement("span"), s = style(n.style);
						ids.set(e, n.id);
						content.openBox(s, e);
						add(n.children, s);
						content.closeBox(e);
					case "atomic":
						var e = doc.createElement("span");
						ids.set(e, n.id);
						content.addAtomic(n.width, n.height, Math.NaN, style(n.style), e);
					case "br":
						content.addBreak(doc.createElement("br"), parent);
				}
		}
		add(c.children, root);
		content.finish();
		var l = new InlineLayout().layout(content, new InlineConstraints(c.width));
		var rects = new haxe.DynamicAccess<Array<Array<Float>>>();
		inline function put(id:String, x:Float, y:Float, w:Float, h:Float) {
			if (!rects.exists(id)) rects.set(id, []);
			rects.get(id).push([x, y, w, h]);
		}
		var lastText = -1;
		for (f in 0...l.fragments) {
			var item = l.item(f), src = item >= 0 ? content.source(item) : null;
			switch l.kind(f) {
				case TextRun:
					lastText = -1;
					if (l.fragmentWidth(f) > 0 && src != null) {
						put(ids.get(src), l.x(f), l.y(f), l.fragmentWidth(f), l.fragmentHeight(f));
						lastText = f;
					}
				case Hyphen:
					// (Blink's text fragment holds its hyphen)
					if (src != null) {
						var r = rects.get(ids.get(src));
						if (r != null && lastText >= 0) r[r.length - 1][2] += l.fragmentWidth(f);
					}
				case BoxSpan | Atomic:
					if (src != null) put(ids.get(src), l.x(f), l.y(f), l.fragmentWidth(f), l.fragmentHeight(f));
				case _:
			}
		}
		// (FLOW_DEBUG=1: the line boxes too)
		if (Sys.getEnv("FLOW_DEBUG") == "2")
			for (p in 0...content.pieces)
				Sys.println('piece $p: ${content.pieceKind(p)} item ${content.pieceItem(p)} (${content.kind(content.pieceItem(p))}) ${content.pieceStart(p)}-${content.pieceEnd(p)} break ${content.pieceBreak(p)} width ${content.pieceWidth(p)}');
		if (Sys.getEnv("FLOW_DEBUG") != null)
			for (k in 0...l.lines)
				Sys.println('line $k: top ${l.lineTop(k)} height ${l.lineHeight(k)} baseline ${l.lineBaseline(k)} width ${l.lineWidth(k)} left ${l.lineLeft(k)}');
		return {height: l.height, rects: rects};
	}

	static function style(s:Dynamic):InlineBasicStyle {
		var o = new InlineBasicStyle();
		o.families = ["Ahem"];
		o.size = s.fontSize;
		o.height = s.lineHeight == null ? Math.NaN : s.lineHeight;
		var ws:String = s.whiteSpace;
		o.collapse = switch ws {
			case "pre" | "pre-wrap": Preserve;
			case "pre-line": PreserveBreaks;
			case "break-spaces": BreakSpaces;
			case _: Collapse;
		}
		o.wrap = ws == "nowrap" || ws == "pre" ? NoWrap : Wrap;
		o.overflow = switch (s.overflowWrap : String) {
			case "break-word": BreakWord;
			case "anywhere": Anywhere;
			case _: Normal;
		}
		o.breakWord = s.wordBreak == "break-all" ? BreakAll : s.wordBreak == "keep-all" ? KeepAll : Normal;
		o.letters = s.letterSpacing;
		o.words = s.wordSpacing;
		o.vertical = switch (s.verticalAlign : String) {
			case "sub": Sub;
			case "super": Super;
			case "text-top": TextTop;
			case "text-bottom": TextBottom;
			case "middle": Middle;
			case "top": Top;
			case "bottom": Bottom;
			case "length": Length;
			case _: Baseline;
		}
		o.shift = s.verticalShift;
		o.align = switch (s.textAlign : String) {
			case "center": Center;
			case "right": Right;
			case "end": End;
			case "left": Left;
			case "justify": Justify;
			case _: Start;
		}
		o.justify = s.textJustify == "inter-character" ? InterCharacter : Auto;
		o.indent = s.textIndent;
		o.dir = s.direction == "rtl" ? Rtl : Ltr;
		o.bidi = switch (s.unicodeBidi : String) {
			case "embed": Embed;
			case "isolate": Isolate;
			case "bidi-override": BidiOverride;
			case "isolate-override": IsolateOverride;
			case "plaintext": Plaintext;
			case _: Normal;
		}
		o.margins = [s.margin[3], s.margin[1], s.margin[0], s.margin[2]];
		o.borders = [s.border[3], s.border[1], s.border[0], s.border[2]];
		o.paddings = [s.padding[3], s.padding[1], s.padding[0], s.padding[2]];
		return o;
	}
}
