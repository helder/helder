import haxe.ds.ObjectMap;
import helder.css.CssGroups;
import helder.css.CssIntern;
import helder.css.CssProperties;
import helder.css.CssProperty;
import helder.css.CssStyle;
import helder.css.CssTerm;
import helder.ui.box.Box;
import helder.ui.box.BoxKind;
import helder.ui.box.BoxPainter;
import helder.ui.box.BoxStyle;
import helder.ui.box.FontMatch;
import helder.ui.box.Fragments;
import helder.ui.box.HitTest;
import helder.ui.box.PaintOrder;
import helder.ui.box.UiPainter;
import helder.ui.flow.BlockFlow;
import helder.ui.flow.Contexts;
import helder.ui.flow.FlexFlow;
import helder.ui.flow.Space;

// The engine's box tree made from code, no element behind a box (the
// "fast nodes" prototype, bench only): styles set as computed values
// (each style's values as data, BoxStyles.write's: what an app's typed
// styles would be), boxes made and appended as BoxTree would make them,
// laid out, painted, scrolled and hit by the engine's own contexts,
// PaintOrder, BoxPainter and HitTest. No selector matching, no cascade, no
// CSS parser run; an empty CssStyles behind the styles (option C's: a
// CssStyle reads one).
typedef BoxSpec = {tag:String, attrs:Array<Array<String>>, text:Null<String>, children:Array<BoxSpec>};

// (styles by key: tag|class|the parent's style, "|h" hovered; each a
// computed style made from the initial one and its own values)
class BoxStyles {
	final keys = new Map<String, Int>();
	final styles:Array<BoxStyle> = [];
	final anonymous = new ObjectMap<BoxStyle, BoxStyle>();
	final index = new ObjectMap<BoxStyle, Int>();

	public function new(data:String) {
		var entries = helder.css.CssSheetData.decodeInitials(data);
		var initial = new Map<Int, Array<CssTerm>>(), own = new Map<Int, Map<Int, Array<CssTerm>>>();
		for (name => v in entries) {
			var terms = switch v.specified {
				case Terms(t): t;
				case _: [];
			}
			var tab = name.indexOf("\t"), head = name.substr(0, tab), rest = name.substr(tab + 1);
			if (head == "k") keys.set(rest, Std.int(switch terms {
				case [Number(n, _)]: n;
				case _: -1;
			})) else {
				var p:Int = cast CssProperties.of(rest);
				if (head == "i") initial.set(p, terms) else {
					var i = Std.parseInt(head.substr(1));
					if (!own.exists(i)) own.set(i, new Map());
					own.get(i).set(p, terms);
				}
			}
		}
		var intern = new CssIntern();
		var host = @:privateAccess new helder.css.CssStyles(new helder.dom.Document(), [], {type: "screen", width: 800, height: 600, resolution: 1, color: 8},
			null, null);
		function group(g:Int, values:Null<Map<Int, Array<CssTerm>>>):helder.css.CssGroup {
			var made = CssGroups.make(g);
			for (p in CssProperties.members[g]) {
				var t = values != null && values.exists(p) ? values.get(p) : initial.get(p);
				if (t != null) @:privateAccess made.set(cast p, t, intern);
			}
			return made;
		}
		var initials = [for (g in 0...CssGroups.COUNT) group(g, null)];
		var n = 0;
		for (i in own.keys()) if (i + 1 > n) n = i + 1;
		for (i in 0...n) {
			var values = own.get(i);
			var touched = [for (g in 0...CssGroups.COUNT) false];
			if (values != null) for (p in values.keys()) touched[CssProperties.groupOf(cast p)] = true;
			var groups = [for (g in 0...CssGroups.COUNT) touched[g] ? group(g, values) : initials[g]];
			// (a CssStyle reads its CssStyles: text-indent's terms interned there, font metrics: an empty one, no
			// sheet, no element)
			var css = @:privateAccess new CssStyle(host, groups, new Map());
			var s = new BoxStyle(css);
			index.set(s, styles.length);
			styles.push(s);
		}
	}

	public function of(tag:String, cls:String, parent:Null<BoxStyle>, hovered = false):Null<BoxStyle> {
		var i = keys.get(tag + "|" + cls + "|" + (parent == null ? -1 : index.get(parent)) + (hovered ? "|h" : ""));
		return i == null ? null : styles[i];
	}

	public function anonymousOf(s:BoxStyle):BoxStyle {
		var a = anonymous.get(s);
		if (a == null) anonymous.set(s, a = s.anonymousChild());
		return a;
	}
}

// (a spec's boxes, as BoxTree makes an element's: a flex container's runs
// of inline content in anonymous blocks, a block's beside blocks too)
class BoxBuild {
	public final styles:BoxStyles;
	public final contexts:Contexts;
	// (each element's box: its tag and class, what a hover styles again)
	public final specs = new ObjectMap<Box, {tag:String, cls:String, name:Null<String>}>();
	public var count = 0;

	public function new(styles:BoxStyles) {
		this.styles = styles;
		var flow = new BlockFlow();
		contexts = new Contexts(flow);
		contexts.flex = new FlexFlow(flow);
	}

	public static function classOf(n:BoxSpec):String
		return attr(n, "class") ?? "";

	static function attr(n:BoxSpec, name:String):Null<String> {
		for (a in n.attrs) if (a[0] == name) return a[1];
		return null;
	}

	// (the first box whose spec is named so, data-tag)
	public function named(root:Box, name:String):Box {
		var stack = [root];
		while (stack.length > 0) {
			var b = stack.shift();
			var s = specs.get(b);
			if (s != null && s.name == name) return b;
			var c = b.first;
			while (c != null) {
				stack.push(c);
				c = c.next;
			}
		}
		throw 'no $name';
	}

	// (b's style and its subtree's again, b hovered or not: its element's from its own spec, text and anonymous
	// boxes their element's)
	public function restyle(node:BoxNode, b:Box, parent:Null<BoxStyle>, hovered:Bool) {
		var spec = specs.get(b);
		if (spec == null) return;
		var s = styles.of(spec.tag, spec.cls, parent, hovered) ?? styles.of(spec.tag, spec.cls, parent);
		if (s == null) return;
		if (b.style != s) node.restyled(b, s);
		function inner(x:Box, el:BoxStyle) {
			var c = x.first;
			while (c != null) {
				if (specs.exists(c)) restyle(node, c, el, false) else {
					var cs = c.kind == Text ? el : styles.anonymousOf(el);
					if (c.style != cs) node.restyled(c, cs);
					inner(c, el);
				}
				c = c.next;
			}
		}
		inner(b, s);
	}

	public function make(kind:BoxKind, s:BoxStyle):Box {
		count++;
		var b = new Box(kind, s);
		if (b.container) b.context = contexts.of(s.inner, _ -> {});
		return b;
	}

	public function box(n:BoxSpec, parent:Null<BoxStyle>, out:Array<Box>) {
		var cls = classOf(n), s = styles.of(n.tag, cls, parent);
		if (s == null) throw 'BoxBuild: no style for ${n.tag}|$cls';
		if (s.none) return;
		var kids = [];
		if (n.text != null && n.text.length > 0) kids.push(text(s, n.text));
		for (c in n.children) box(c, s, kids);
		var kind = s.inner == BoxStyle.FLEX || s.inner == BoxStyle.GRID ? Container : s.outer == BoxStyle.INLINE ? Inline : Block;
		var b = make(kind, s);
		b.flags |= Box.MADE;
		specs.set(b, {tag: n.tag, cls: cls, name: attr(n, "data-tag")});
		if (kind == Inline) for (k in kids) b.append(k) else fill(b, kids);
		out.push(b);
	}

	public function text(s:BoxStyle, t:String):Box {
		var b = make(Text, s);
		b.text = t;
		return b;
	}

	public function fill(b:Box, kids:Array<Box>) {
		var flex = b.style.inner == BoxStyle.FLEX || b.style.inner == BoxStyle.GRID;
		if (!flex && !Lambda.exists(kids, block)) {
			for (k in kids) b.append(k);
			return;
		}
		var run = [];
		function wrap() {
			if (run.length > 0) {
				var anon = make(Block, styles.anonymousOf(b.style));
				for (k in run) anon.append(k);
				b.append(anon);
			}
			run = [];
		}
		for (k in kids) if (block(k) || k.floating || k.absolute) {
			wrap();
			b.append(k);
		} else run.push(k);
		wrap();
	}

	static function block(b:Box):Bool
		return b.kind != Inline && b.kind != Text && b.style.outer != BoxStyle.INLINE && !b.floating && !b.absolute;
}

// A box tree in a helder.ui window: laid out at the node's size, painted
// from the engine's paint order (made again from the last where boxes kept
// their fragments), scrolled and hovered.
class BoxNode extends helder.ui.Node {
	public final root:Box;
	public final fonts = new FontMatch();
	public final fragments = new Fragments();
	public final scrolls = new ObjectMap<{}, Array<Float>>();
	public var order(default, null):Null<PaintOrder> = null;
	public var rootFragment(default, null) = -1;
	// (the engine's own work, ms: layouts, paints recorded)
	public var layoutMs = 0.0;
	public var paintMs = 0.0;
	// (the hovered box's style and its subtree's: the bench's)
	public var onHover:Null<Null<Box>->Void> = null;
	final painter = new UiPainter(null, 0, 0);
	var laidWidth = Math.NaN;
	var laidHeight = Math.NaN;
	var docHeight = 0.0;
	var due = true;
	var orderDue = true;
	var orderFresh = false;
	var whole = 0;
	var boxIndex:Null<ObjectMap<Box, Int>> = null;

	final contexts:Contexts;

	public function new(root:Box, contexts:Contexts) {
		super("boxes");
		this.root = root;
		this.contexts = contexts;
		onWheel = wheeled;
		onPointerMove = e -> if (onHover != null && order != null) onHover(HitTest.box(fragments, order, e.localX, e.localY, scrolls));
		onPointerLeave = _ -> if (onHover != null) onHover(null);
	}

	// what a box's change takes: laid out again (it and its ancestors' layouts let go), else painted again
	public function changed(b:Null<Box>, layout:Bool) {
		if (layout) {
			while (b != null) {
				b.uncache();
				b.inlineCache = null;
				b.cacheWidth = b.minContent = b.maxContent = Math.NaN;
				b = b.parent;
			}
			due = true;
			markDirty();
		} else {
			layerChanged();
			if (ui != null) ui.requestFrame();
		}
	}

	// (a style swapped on a box: its paint order's steps may hold what it changed)
	public function restyled(b:Box, s:BoxStyle) {
		@:privateAccess b.style = s;
		orderFresh = true;
	}

	@:noCompletion override public function hasContent():Bool
		return true;

	@:allow(helder.ui) override function paintsLive():Bool
		return false;

	@:noCompletion override public function measureContent(text:helder.ui.TextEngine, knownWidth:Float, knownHeight:Float, availWidth:Float,
			availHeight:Float):helder.ui.Size {
		var w = !Math.isNaN(knownWidth) ? knownWidth : Math.isFinite(availWidth) ? availWidth : 800;
		var h = ui != null ? ui.height : Math.isFinite(availHeight) ? availHeight : 600;
		if (w != laidWidth || h != laidHeight || due) {
			var t0 = haxe.Timer.stamp();
			layout(w, h);
			layoutMs += (haxe.Timer.stamp() - t0) * 1000;
			laidWidth = w;
			laidHeight = h;
			due = false;
		}
		return new helder.ui.Size(w, Math.isNaN(knownHeight) ? Math.max(docHeight, h) : knownHeight);
	}

	function layout(w:Float, h:Float) {
		// (the fragments of the layouts before, kept for the cache, a few times a whole layout's: let go)
		if (fragments.count > 3 * whole + 4096) {
			fragments.clear();
			Box.forgetFragments();
		}
		var fresh = fragments.count == 0;
		var space = new Space(fragments, fonts, w, h);
		var f = (root.context ?? contexts.flow).layout(root, space);
		var off = BlockFlow.offset(root, w, h);
		fragments.moveTo(f, root.marginLeft + off.x, root.topPositive + root.topNegative + off.y);
		if (fresh) whole = fragments.count;
		rootFragment = f;
		orderDue = true;
		boxIndex = null;
		docHeight = fragments.y(f) + fragments.height(f) + Math.max(0, root.bottomPositive + root.bottomNegative);
	}

	@:noCompletion override public function paintContent(canvas:helder.ui.Canvas, x:Float, y:Float, width:Float, height:Float) {
		if (rootFragment < 0 || ui == null) return;
		var w = @:privateAccess ui.walk;
		var x0 = Math.max(w.x0, x), y0 = Math.max(w.y0, y), x1 = Math.min(w.x1, x + width), y1 = Math.min(w.y1, y + height);
		if (x1 <= x0 || y1 <= y0) return;
		var t0 = haxe.Timer.stamp();
		if (orderDue) {
			var last = orderFresh ? null : order;
			order = new PaintOrder(fragments, rootFragment, null, order != null ? order.count : 0, null, last);
			orderDue = orderFresh = false;
		}
		canvas.translate(x, y);
		painter.begin(canvas, Math.ceil(width), Math.ceil(height), ui.scale, x0 - x, y0 - y, x1 - x, y1 - y);
		painter.clear(0xFFFFFFFF);
		var bp = new BoxPainter(fragments, order, _ -> null);
		bp.scrolls = scrolls;
		bp.area = [x0 - x, y0 - y, x1 - x, y1 - y];
		bp.canvasArea = [x0 - x, y0 - y, x1 - x0, y1 - y0];
		bp.paint(painter);
		painter.end();
		canvas.translate(-x, -y);
		paintMs += (haxe.Timer.stamp() - t0) * 1000;
	}

	// a box's fragment in the last layout (-1: none)
	public function fragmentOf(b:Box):Int {
		if (boxIndex == null) {
			var m = new ObjectMap<Box, Int>(), stack = [rootFragment];
			while (stack.length > 0) {
				var id = stack.pop();
				if (fragments.kind(id) == Fragments.BOX && !m.exists(fragments.box(id))) m.set(fragments.box(id), id);
				var c = fragments.first(id);
				while (c >= 0) {
					stack.push(c);
					c = fragments.next(c);
				}
			}
			boxIndex = m;
		}
		return boxIndex.exists(b) ? boxIndex.get(b) : -1;
	}

	// (the innermost scroll container under the wheel that can move: moved, within its content's extent)
	function wheeled(e:helder.ui.Event) {
		if (order == null) return;
		var b = HitTest.box(fragments, order, e.localX, e.localY, scrolls);
		while (b != null) {
			if (b.style.scrolls && b.parent != null && b.parent.parent != null && scrollBy(b, e.deltaX, e.deltaY)) {
				layerChanged();
				ui.requestFrame();
				e.preventDefault();
				e.stop();
				return;
			}
			b = b.parent;
		}
	}

	public function scrollBy(b:Box, dx:Float, dy:Float):Bool {
		var id = fragmentOf(b);
		if (id < 0) return false;
		var m = b.style.model();
		var cw = fragments.width(id) - m.border[1] - m.border[3], ch = fragments.height(id) - m.border[0] - m.border[2];
		var ew = 0.0, eh = 0.0, c = fragments.first(id);
		while (c >= 0) {
			ew = Math.max(ew, fragments.x(c) + fragments.width(c));
			eh = Math.max(eh, fragments.y(c) + fragments.height(c));
			c = fragments.next(c);
		}
		eh += helder.ui.box.Len.Lens.resolve(m.padding[2], cw, 0) - m.border[0];
		ew -= m.border[3];
		var o = scrolls.get(b) ?? [0.0, 0.0];
		var sx = Math.max(0, Math.min(o[0] + dx, ew - cw)), sy = Math.max(0, Math.min(o[1] + dy, eh - ch));
		if (sx == o[0] && sy == o[1]) return false;
		scrolls.set(b, [sx, sy]);
		return true;
	}
}
