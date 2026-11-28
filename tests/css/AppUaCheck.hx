import helder.css.CssCascade;
import helder.css.CssStyle;
import helder.css.CssUserAgentTheme;
import helder.dom.Document;
import helder.dom.Dom;
import helder.dom.Element;
import helder.gfx.Color;
import helder.ui.*;
import helder.ui.box.BoxStyle;
import helder.ui.box.Len;
import helder.view.Render;
import helder.view.graph.Graph;
import sys.io.File;

using StringTools;

// The app user agent sheet (src/helder/css/ua/app.css) against helder.ui
// today (bun run test css-app): example screens (examples/todo, as its
// window has it; examples/mail, its story's) mounted headless, each node
// mirrored as a helder.dom element (its tag, its attributes, its text; its
// resolved values that aren't a plain node's, and the text its own style
// says, as its style attribute: what the port carries over as the
// author's), the mirror
// cascaded with app.css as its user agent sheet alone, and each node's
// values compared for the properties both have: what the user agent sheet
// and CSS's inheritance give where helder.ui's defaults do today. It
// reports the differences (bin/css/app-ua.md), it doesn't fail on them.
class AppUaCheck {
	static function main() {
		var report = new StringBuf();
		report.add("# app.css against helder.ui\n\nEach node of each screen, the properties both have: what helder.ui gives it today, and what the mirror computes with app.css (bun run test css-app).\n");
		var total = 0, differing = 0, decided = 0;
		for (screen in [
			{name: "todo", width: 480, height: 560, mount: (ui:Ui) -> {
				Render.render(new Todo().view(), ui.root);
			}},
			{name: "mail", width: 860, height: 560, mount: (ui:Ui) -> {
				Render.render(Mail.themed(), ui.root);
			}}
		]) {
			var ui = new Ui(new helder.story.StoryText(), screen.width, screen.height);
			screen.mount(ui);
			Graph.flush();
			ui.update();
			Clock.finish();
			ui.update();
			var doc = Dom.parseXml("<root/>");
			var pairs:Array<{node:Node, el:Element, path:String}> = [];
			for (c in ui.root.children) mirror(doc, c, doc.documentElement, "root", pairs);
			pairs.unshift({node: ui.root, el: doc.documentElement, path: "root"});
			var styles = CssCascade.styles(doc, {userAgent: CssUserAgentTheme.app(), media: {type: "screen", width: screen.width, height: screen.height}});
			var by = new Map<String, Array<String>>();
			for (p in pairs) {
				var helder = values(p.node), css = computed(styles.computed(p.el), helder);
				for (name => v in helder) {
					total++;
					var c = css.get(name);
					if (same(v, c)) continue;
					// (decided, ENGINE.md: <text> and the names on it a block, its runs inline, where helder.ui has a flex box)
					if (name == "display" && v == "flex" && (c == "block" || c == "inline") && TEXT.contains(p.el.localName)) {
						decided++;
						continue;
					}
					differing++;
					if (!by.exists(name)) by.set(name, []);
					by[name].push('${p.path}: helder ${v}, css ${c}');
				}
			}
			report.add('\n## ${screen.name}\n\n${pairs.length} nodes.\n\n| Property | Nodes differing | First ones |\n| --- | ---: | --- |\n');
			var names = [for (k in by.keys()) k];
			names.sort((a, b) -> by[b].length - by[a].length != 0 ? by[b].length - by[a].length : Reflect.compare(a, b));
			for (n in names) report.add('| $n | ${by[n].length} | ${by[n].slice(0, 3).join("; ").replace("|", "\\|")} |\n');
			Sys.println('css-app: ${screen.name}: ${pairs.length} nodes, ${names.length} properties differ somewhere: ${[for (n in names) '$n ${by[n].length}'].join(", ")}');
		}
		sys.FileSystem.createDirectory("bin/css");
		File.saveContent("bin/css/app-ua.md", report.toString());
		report.add('\nDecided, not counted (ENGINE.md): $decided text elements a block (their runs inline) where helder.ui has a flex box.\n');
		Sys.println('css-app: $differing of $total values differ, $decided text displays as decided (bin/css/app-ua.md)');
	}

	// (a node as an element: its tag (a field's textfield as the markup's field), attributes, its own style, its text)
	static function mirror(doc:Document, n:Node, parent:Element, path:String, out:Array<{node:Node, el:Element, path:String}>) {
		var tag = n.tag == "textfield" ? "field" : n.tag;
		var el = doc.createElement(tag);
		var attrs:Null<Map<String, String>> = @:privateAccess n.attrs;
		if (attrs != null) for (k => v in attrs) if (k != "style") el.setAttribute(k, v);
		var own = declarations(n);
		if (own != "") el.setAttribute("style", own);
		if (Std.isOfType(n, TextNode)) el.append(doc.createTextNode((cast n : TextNode).text ?? ""));
		parent.append(el);
		var here = '$path > $tag';
		out.push({node: n, el: el, path: here});
		for (c in n.children) mirror(doc, c, el, here, out);
	}

	static final DEFAULTS = layout(new Node());
	static final TEXT = ["text", "p", "h1", "h2", "h3", "h4", "h5", "h6", "label", "legend", "a", "strong", "em", "code", "span"];

	// (the node's resolved values that aren't a plain node's, and the text its style says, as CSS)
	static function declarations(n:Node):String {
		var p = n.props(), out = [];
		for (k => v in layout(n)) if (DEFAULTS.get(k) != v) out.push('$k: $v');
		if (p.color != null) out.push('color: ${color(n.used.text.colour)}');
		if (p.fontFamily != null) out.push('font-family: ${p.fontFamily}');
		if (p.fontSize != null) out.push('font-size: ${num(n.used.text.size)}px');
		if (p.fontWeight != null) out.push('font-weight: ${p.fontWeight}');
		if (p.lineHeight != null) out.push('line-height: ${num(p.lineHeight)}');
		if (p.textAlign != null) out.push('text-align: ${n.textAlign()}');
		return out.join("; ");
	}

	// (what helder.ui gives the node today, as CSS's computed values would say it)
	static function values(n:Node):Map<String, String> {
		var out = layout(n);
		var f = n.font();
		out.set("color", color(n.textColor()));
		out.set("font-family", f.family);
		out.set("font-size", num(f.size) + "px");
		out.set("font-weight", Std.string(f.weight));
		out.set("line-height", num(f.lineHeight));
		out.set("text-align", Std.string(n.textAlign()));
		return out;
	}

	// (the non-inherited properties its resolved style has, as CSS)
	static function layout(n:Node):Map<String, String> {
		var s = n.used, m = new Map<String, String>();
		m.set("display", s.none ? "none" : s.inner == BoxStyle.FLEX ? "flex" : s.inner == BoxStyle.GRID ? "grid" : s.outer == BoxStyle.INLINE ? "inline" : "block");
		m.set("flex-direction", s.flexDirection);
		m.set("flex-wrap", s.flexWrap);
		m.set("position", s.position);
		m.set("justify-content", s.justifyContent);
		m.set("align-items", s.alignItems);
		m.set("align-self", s.alignSelf);
		m.set("flex-grow", num(s.flexGrow));
		m.set("flex-shrink", num(s.flexShrink));
		m.set("flex-basis", len(s.flexBasis, "auto"));
		m.set("width", len(s.width, "auto"));
		m.set("height", len(s.height, "auto"));
		m.set("min-width", len(s.minWidth, "auto"));
		m.set("min-height", len(s.minHeight, "auto"));
		m.set("max-width", len(s.maxWidth, "none"));
		m.set("max-height", len(s.maxHeight, "none"));
		for (k => side in ["top", "right", "bottom", "left"]) {
			m.set('padding-$side', num(s.paddingPx(k)) + "px");
			m.set('margin-$side', len(s.margin[k], "auto"));
			m.set('border-$side-width', num(s.borderPx(k)) + "px");
		}
		var r = NodePaint.corners(s, n.width, n.height, 0);
		m.set("border-top-left-radius", num(r == null ? 0 : r.topLeft) + "px");
		m.set("row-gap", len(s.rowGap, "normal"));
		m.set("column-gap", len(s.columnGap, "normal"));
		m.set("overflow-x", s.overflowX);
		m.set("overflow-y", s.overflowY);
		m.set("opacity", num(s.opacity));
		m.set("background-color", color(s.backgroundColor));
		return m;
	}

	static function len(l:Len, auto:String):String
		return switch l {
			case Auto: auto;
			case Px(v): num(v) + "px";
			case Percent(p): num(p) + "%";
			case _: Std.string(l);
		}

	static function color(c:Color):String
		return c.a == 255 ? 'rgb(${c.r}, ${c.g}, ${c.b})' : 'rgba(${c.r}, ${c.g}, ${c.b}, ${num(Math.round(c.a / 255 * 100) / 100)})';

	static function num(v:Float):String {
		var r = Math.round(v * 1000) / 1000;
		return r == Std.int(r) ? Std.string(Std.int(r)) : Std.string(r);
	}

	// (the mirror's computed values, for the same properties; line-height as a multiple, start as the line's left)
	static function computed(s:CssStyle, helder:Map<String, String>):Map<String, String> {
		var out = new Map<String, String>();
		for (name in helder.keys()) out.set(name, s.text(name));
		var size = Std.parseFloat(out["font-size"]);
		var lh = out["line-height"];
		if (lh != null && lh.endsWith("px") && size > 0) out["line-height"] = num(Std.parseFloat(lh) / size);
		if (out["text-align"] == "start") out["text-align"] = "left";
		var family = out["font-family"];
		if (family != null) out["font-family"] = family.split(",")[0].trim().replace('"', "");
		return out;
	}

	// (equal once numbers are rounded to two places)
	static function same(a:Null<String>, b:Null<String>):Bool {
		if (a == null || b == null) return a == b;
		inline function norm(s:String):String
			return ~/-?\d+(\.\d+)?/g.map(s, m -> Std.string(Math.round(Std.parseFloat(m.matched(0)) * 100) / 100));
		return norm(a) == norm(b);
	}
}
