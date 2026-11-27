import helder.css.CssCascade;
import helder.css.CssStyle;
import helder.css.CssUserAgentTheme;
import helder.dom.Document;
import helder.dom.Dom;
import helder.dom.Element;
import helder.gfx.Color;
import helder.ui.*;
import helder.view.Render;
import helder.view.graph.Graph;
import sys.io.File;

using StringTools;

// The app user agent sheet (src/helder/css/ua/app.css) against helder.ui
// today (bun run test css-app): example screens (examples/todo, as its
// window has it, with its sheet; examples/mail, its story's) mounted
// headless, each node mirrored as a helder.dom element (its tag, its
// attributes, slot, variant and size, its text; the Style values it holds
// that aren't Style's defaults, its rules' and its own, as its style
// attribute: what the port carries over as the author's), the mirror
// cascaded with app.css as its user agent sheet alone, and each node's
// values compared for the properties both have: what the user agent sheet
// and CSS's inheritance give where helder.ui's defaults do today. It
// reports the differences (bin/css/app-ua.md), it doesn't fail on them.
class AppUaCheck {
	static function main() {
		var report = new StringBuf();
		report.add("# app.css against helder.ui\n\nEach node of each screen, the properties both have: what helder.ui gives it today, and what the mirror computes with app.css (bun run test css-app).\n");
		var total = 0, differing = 0;
		for (screen in [
			{name: "todo", width: 480, height: 560, mount: (ui:Ui) -> {
				ui.theme = Todo.sheet;
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
		Sys.println('css-app: $differing of $total values differ (bin/css/app-ua.md)');
	}

	// (a node as an element: its tag (a field's textfield as the markup's field), attributes, its own style, its text)
	static function mirror(doc:Document, n:Node, parent:Element, path:String, out:Array<{node:Node, el:Element, path:String}>) {
		var tag = n.tag == "textfield" ? "field" : n.tag;
		var el = doc.createElement(tag);
		var attrs:Null<Map<String, String>> = @:privateAccess n.attrs;
		if (attrs != null) for (k => v in attrs) if (k != "style") el.setAttribute(k, v);
		if (n.slot != null) el.setAttribute("slot", n.slot);
		if (n.variant != null) el.setAttribute("variant", n.variant);
		if (n.size != null) el.setAttribute("size", n.size);
		var own = declarations(n);
		if (own != "") el.setAttribute("style", own);
		if (Std.isOfType(n, TextNode)) el.append(doc.createTextNode((cast n : TextNode).text ?? ""));
		parent.append(el);
		var here = '$path > $tag${n.slot == null ? "" : '[${n.slot}]'}';
		out.push({node: n, el: el, path: here});
		for (c in n.children) mirror(doc, c, el, here, out);
	}

	static final DEFAULTS = new Node().style;

	// (the node's Style values that aren't its defaults: its rules' and its own, as CSS)
	static function declarations(n:Node):String {
		var s = n.style, d = DEFAULTS, out = [];
		var mine = layout(s), theirs = layout(d);
		for (k => v in mine) if (theirs.get(k) != v) out.push('$k: $v');
		if (s.color != null) out.push('color: ${color(s.color)}');
		if (s.fontFamily != null) out.push('font-family: ${s.fontFamily}');
		if (s.fontSize != null) out.push('font-size: ${num(s.fontSize)}px');
		if (s.fontWeight != null) out.push('font-weight: ${s.fontWeight}');
		if (s.lineHeightPx != null) out.push('line-height: ${num(s.lineHeightPx)}px') else if (s.lineHeight != null) out.push('line-height: ${num(s.lineHeight)}');
		if (s.textAlign != null) out.push('text-align: ${s.textAlign}');
		return out.join("; ");
	}

	// (what helder.ui gives the node today, as CSS's computed values would say it)
	static function values(n:Node):Map<String, String> {
		var out = layout(n.style);
		var f = n.font();
		out.set("color", color(n.textColor()));
		out.set("font-family", f.family);
		out.set("font-size", num(f.size) + "px");
		out.set("font-weight", Std.string(f.weight));
		out.set("line-height", num(f.lineHeight));
		out.set("text-align", Std.string(n.textAlign()));
		return out;
	}

	// (the non-inherited properties Style holds, as CSS)
	static function layout(s:Style):Map<String, String> {
		var m = new Map<String, String>();
		m.set("display", switch s.display {
			case Flex: "flex";
			case None: "none";
			case Grid: "grid";
			case Block: "block";
			case _: "?";
		});
		m.set("flex-direction", switch s.flexDirection {
			case Column: "column";
			case Row: "row";
			case ColumnReverse: "column-reverse";
			case RowReverse: "row-reverse";
		});
		m.set("flex-wrap", s.flexWrap ? "wrap" : "nowrap");
		m.set("position", switch s.position {
			case Relative: "relative";
			case Absolute: "absolute";
			case Sticky: "sticky";
			case _: "?";
		});
		m.set("justify-content", switch s.justifyContent {
			case Start: "flex-start";
			case End: "flex-end";
			case Center: "center";
			case SpaceBetween: "space-between";
			case SpaceAround: "space-around";
			case SpaceEvenly: "space-evenly";
			case Normal: "normal";
		});
		m.set("align-items", align(s.alignItems));
		m.set("align-self", align(s.alignSelf));
		m.set("flex-grow", num(s.flexGrow));
		m.set("flex-shrink", num(s.flexShrink));
		m.set("flex-basis", dim(s.flexBasis, "auto"));
		m.set("width", dim(s.width, "auto"));
		m.set("height", dim(s.height, "auto"));
		m.set("min-width", dim(s.minWidth, "auto"));
		m.set("min-height", dim(s.minHeight, "auto"));
		m.set("max-width", dim(s.maxWidth, "none"));
		m.set("max-height", dim(s.maxHeight, "none"));
		var zero = helder.os.Edges.ZERO;
		var p:helder.os.Edges = s.padding ?? zero, g:helder.os.Edges = s.margin ?? zero, b = s.borderEdges ?? zero;
		for (side in ["top", "right", "bottom", "left"]) {
			inline function of(e:helder.os.Edges):Float
				return side == "top" ? e.top : side == "right" ? e.right : side == "bottom" ? e.bottom : e.left;
			m.set('padding-$side', num(of(p)) + "px");
			var mv = of(g);
			m.set('margin-$side', Math.isNaN(mv) ? "auto" : num(mv) + "px");
			m.set('border-$side-width', num(of(b)) + "px");
		}
		m.set("border-top-left-radius", num(s.borderRadius) + "px");
		m.set("row-gap", num(s.rowGap) + "px");
		m.set("column-gap", num(s.columnGap) + "px");
		inline function overflow(o:Overflow):String
			return o == Hidden ? "hidden" : o == Scroll ? "scroll" : "visible";
		m.set("overflow-x", overflow(s.overflowX));
		m.set("overflow-y", overflow(s.overflowY));
		m.set("opacity", num(s.opacity));
		m.set("background-color", color(s.background));
		return m;
	}

	static function align(a:Align):String
		return switch a {
			case Auto: "auto";
			case Start: "flex-start";
			case End: "flex-end";
			case Center: "center";
			case Stretch: "stretch";
			case Baseline: "baseline";
		}

	static function dim(d:Dim, auto:String):String
		return switch (d : DimValue) {
			case Auto: auto;
			case Px(v): num(v) + "px";
			case Percent(p): num(p) + "%";
			case Calc(p, px): 'calc(${num(p)}% + ${num(px)}px)';
			case MinContent: "min-content";
			case MaxContent: "max-content";
			case FitContent: "fit-content";
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
