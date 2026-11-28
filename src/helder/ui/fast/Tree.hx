package helder.ui.fast;

import haxe.ds.ObjectMap;
import helder.ui.Event;
import helder.ui.Key;
import helder.ui.access.AccessNode;
import helder.ui.access.AccessTree;
import helder.ui.access.Role;
import helder.ui.box.Box;
import helder.ui.box.BoxTexts;
import helder.ui.box.BoxTexts.BoxPosition;
import helder.ui.box.BoxPainter;
import helder.ui.box.FontMatch;
import helder.ui.box.Fragments;
import helder.ui.box.HitTest;
import helder.ui.box.PaintOrder;
import helder.ui.box.PaintSpans;
import helder.ui.box.UiPainter;
import helder.ui.flow.BlockFlow;
import helder.ui.flow.Space;

// A fast tree in helder.ui: its root node's boxes laid out at this node's
// size by the engine's block and flex layout, painted from its paint order
// (made again from the last one where boxes kept their fragments, and
// contexts' calls copied from the last paint), hit, hovered, pressed and
// scrolled.
//
//   final tree = new Tree(list, app);  // app: its palette, a Theme
//   UiWindow.run(<UiWindow.Surface title="List">{tree}</UiWindow.Surface>);
class Tree extends helder.ui.Node {
	public final root:Node;
	// the theme its nodes resolve tokens in where none of theirs has one
	public var palette(default, set):Theme;
	@:noCompletion public final fonts = new FontMatch();
	// (the engine's own time, ms: layouts, paints)
	@:noCompletion public var layoutMs = 0.0;
	@:noCompletion public var paintMs = 0.0;

	final fragments = new Fragments();
	final scrolls = new ObjectMap<{}, Array<Float>>();
	final painter = new UiPainter(null, 0, 0);
	final spans = new PaintSpans();
	var order:Null<PaintOrder> = null;
	var spare:Null<PaintOrder> = null;
	var rootFragment = -1;
	var laidWidth = Math.NaN;
	var laidHeight = Math.NaN;
	var docHeight = 0.0;
	var whole = 0;
	var due = true;
	var orderDue = true;
	var orderFresh = false;
	var boxIndex:Null<ObjectMap<Box, Int>> = null;
	// (the nodes under the pointer, innermost first; those pressed)
	var pointed:Array<Node> = [];
	var held:Array<Node> = [];
	// (the node with the focus in it, its ring drawn; a press under way; a field's text dragged over)
	var active:Null<Node> = null;
	var ringed = false;
	var pressing = false;
	var dragging:Null<FieldNode> = null;
	// (its text by box positions, of the last layout; its text boxes in tree order and where each starts in its text)
	var boxTexts:Null<BoxTexts> = null;
	var flat:Null<{text:String, boxes:Array<Box>, starts:Array<Int>, index:ObjectMap<Box, Int>}> = null;

	public function new(root:Node, ?theme:Theme) {
		super("tree");
		this.root = root;
		this.palette = theme ?? Theme.base;
		root.tree = this;
		// (a stop of Tab's; its own nodes' focus drawn inside, not around it)
		focusable = true;
		selectable = true;
		style.outlineStyle = None;
		onWheel = wheeled;
		onPointerMove = moved;
		onPointerLeave = _ -> hover(null);
		onPointerDown = down;
		onPointerUp = up;
		onPointerCancel = _ -> {
			press([]);
			dragging = null;
		}
		onKeyDown = key;
		onTextInput = e -> {
			var f = field();
			if (f != null && e.text != "") {
				f.typed(e.text, ui, this);
				repaint();
				e.stop();
			}
		}
		onFocus = _ -> if (active == null && !pressing) focusOn(first(1), ui != null && ui.focusVisible);
		onBlur = _ -> focusOn(null, false);
	}

	function set_palette(t:Theme):Theme {
		palette = t;
		root.resolve(Resolve.root, t, 0);
		return t;
	}

	// (a change in the tree at a box: what it takes)
	@:allow(helder.ui.fast) function changed(b:Box, level:Int) {
		helder.ui.Ui.accessEpoch++;
		if (level == Resolve.LAYOUT) {
			flat = null;
			var p:Null<Box> = b;
			while (p != null) {
				p.uncache();
				p.inlineCache = null;
				p.cacheWidth = p.minContent = p.maxContent = Math.NaN;
				p = p.parent;
			}
			due = true;
			markDirty();
			return;
		}
		// (the lines it is in keep its old inline style: built again)
		var p:Null<Box> = b;
		while (p != null) {
			p.inlineCache = null;
			p = p.parent;
		}
		if (level == Resolve.ORDER) {
			orderDue = true;
			orderFresh = true;
		}
		spans.fresh = true;
		layerChanged();
		if (ui != null) ui.requestFrame();
	}

	function hit(x:Float, y:Float):Null<Node>
		return rootFragment < 0 ? null : Node.of(HitTest.at(fragments, ordered(), x, y, scrolls)?.box);

	// (a node and its ancestors, innermost first)
	static function chain(n:Null<Node>):Array<Node> {
		var out = [];
		while (n != null) {
			out.push(n);
			n = n.parent;
		}
		return out;
	}

	function hover(n:Null<Node>) {
		var now = chain(n);
		for (o in pointed) if (!now.contains(o)) {
			o.state(Style.HOVER, false);
			if (o.onPointerLeave != null) o.onPointerLeave(Event.of(PointerLeave, this, 0, 0));
		}
		for (o in now) if (!pointed.contains(o)) {
			o.state(Style.HOVER, true);
			if (o.onPointerEnter != null) o.onPointerEnter(Event.of(PointerEnter, this, 0, 0));
		}
		pointed = now;
		// (the pointer's: the nearest that says, a field's text)
		var c:Null<helder.ui.Cursor> = null;
		for (o in now) if ((c = o.props().cursor) != null) break;
		if (c == null && n != null && Std.isOfType(n, FieldNode)) c = Text;
		style.cursor = c;
	}

	function press(now:Array<Node>) {
		for (o in held) if (!now.contains(o)) o.state(Style.PRESSED, false);
		for (o in now) o.state(Style.PRESSED, true);
		held = now;
	}

	@:noCompletion override public function hasContent():Bool
		return true;

	@:allow(helder.ui) override function paintsLive():Bool
		return false;

	@:noCompletion override public function measureContent(text:helder.ui.TextEngine, knownWidth:Float, knownHeight:Float, availWidth:Float,
			availHeight:Float):helder.ui.Size {
		var w = !Math.isNaN(knownWidth) ? knownWidth : Math.isFinite(availWidth) ? availWidth : 800;
		var h = !Math.isNaN(knownHeight) ? knownHeight : ui != null ? ui.height : Math.isFinite(availHeight) ? availHeight : 600;
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
		var b = root.box, space = new Space(fragments, fonts, w, h);
		// (a percentage height on its root: of the tree's, as a document's root's is of the viewport)
		switch b.style.model().height {
			case Percent(p): space.fixedHeight = h * p / 100;
			case _:
		}
		var f = (b.context ?? Node.contexts().flow).layout(b, space);
		var off = BlockFlow.offset(b, w, h);
		fragments.moveTo(f, b.marginLeft + off.x, b.topPositive + b.topNegative + off.y);
		if (fresh) whole = fragments.count;
		rootFragment = f;
		orderDue = true;
		boxIndex = null;
		boxTexts = null;
		docHeight = fragments.y(f) + fragments.height(f) + Math.max(0, b.bottomPositive + b.bottomNegative);
	}

	@:noCompletion override public function paintContent(canvas:helder.ui.Canvas, x:Float, y:Float, width:Float, height:Float) {
		if (rootFragment < 0 || ui == null) return;
		var w = @:privateAccess ui.walk;
		var x0 = Math.max(w.x0, x), y0 = Math.max(w.y0, y), x1 = Math.min(w.x1, x + width), y1 = Math.min(w.y1, y + height);
		if (x1 <= x0 || y1 <= y0) return;
		var t0 = haxe.Timer.stamp();
		var order = ordered();
		canvas.translate(x, y);
		painter.begin(canvas, Math.ceil(width), Math.ceil(height), ui.scale, x0 - x, y0 - y, x1 - x, y1 - y);
		var bp = new BoxPainter(fragments, order, _ -> null);
		bp.scrolls = scrolls;
		bp.spans = spans;
		bp.area = [x0 - x, y0 - y, x1 - x, y1 - y];
		bp.canvasArea = [x0 - x, y0 - y, x1 - x0, y1 - y0];
		bp.paint(painter);
		painter.end();
		marks(canvas);
		canvas.translate(-x, -y);
		paintMs += (haxe.Timer.stamp() - t0) * 1000;
	}

	// Where a node is in the window, as last laid out and scrolled: x, y, width, height (zeros: not laid out).
	public function rectOf(n:Node):Array<Float> {
		var id = fragmentOf(n.box);
		if (id < 0) return [0, 0, 0, 0];
		var p = fragments.absolute(id), x = absX + p.x, y = absY + p.y, b = n.box.parent;
		while (b != null) {
			var o = scrolls.get(Box.scrollKey(b));
			if (o != null) {
				x -= o[0];
				y -= o[1];
			}
			b = b.parent;
		}
		return [x, y, fragments.width(id), fragments.height(id)];
	}

	// (the paint order of the last layout: made again from the one before where boxes kept their fragments)
	function ordered():PaintOrder {
		if (!orderDue && order != null) return order;
		var last = orderFresh ? null : order;
		var made = spare != null ? spare.again(rootFragment, null, last, scrolls) : new PaintOrder(fragments, rootFragment, null, order != null ? order.count : 0,
			null, last, scrolls);
		spare = order;
		order = made;
		orderDue = orderFresh = false;
		return made;
	}

	// (a box's fragment in the last layout; -1: none)
	function fragmentOf(b:Box):Int {
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
		if (rootFragment < 0) return;
		var b = HitTest.at(fragments, ordered(), e.localX, e.localY, scrolls)?.box;
		while (b != null) {
			if (b.style.scrolls && scrollBy(b, e.deltaX, e.deltaY)) {
				layerChanged();
				ui.requestFrame();
				e.preventDefault();
				e.stop();
				return;
			}
			b = b.parent;
		}
	}

	function scrollBy(b:Box, dx:Float, dy:Float):Bool {
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
		var o = scrolls.get(Box.scrollKey(b)) ?? [0.0, 0.0];
		var sx = Math.max(0, Math.min(o[0] + dx, ew - cw)), sy = Math.max(0, Math.min(o[1] + dy, eh - ch));
		if (sx == o[0] && sy == o[1]) return false;
		scrolls.set(Box.scrollKey(b), [sx, sy]);
		// (its content ordered for the pages around the one shown: another page shown, the order made afresh)
		if (PaintOrder.pageOf(fragments, id, sy) != PaintOrder.pageOf(fragments, id, o[1])) {
			orderDue = true;
			orderFresh = true;
		}
		return true;
	}
	// ---- the pointer: hover, presses, a field's caret placed and dragged

	function moved(e:Event) {
		var n = hit(e.localX, e.localY);
		hover(n);
		if (dragging != null) {
			var i = indexIn(dragging, e.localX, e.localY);
			if (i >= 0 && i != dragging.caret) {
				dragging.caret = i;
				repaint();
			}
		}
	}

	function down(e:Event) {
		var n = hit(e.localX, e.localY), at = chain(n);
		pressing = true;
		press(at);
		capture();
		for (o in at) if (o.onPointerDown != null) o.onPointerDown(e);
		// (the focus: the nearest that takes it, its ring not drawn; none: out of the tree's)
		var f = Lambda.find(at, o -> o.focusable);
		focusOn(f, false);
		if (f != null && Std.isOfType(f, FieldNode)) {
			var fd:FieldNode = cast f, i = indexIn(fd, e.localX, e.localY);
			if (i >= 0) {
				fd.caret = i;
				if (e.mods & helder.os.Mods.SHIFT == 0) fd.anchor = i;
			}
			dragging = fd;
			repaint();
		}
		pressing = false;
	}

	function up(e:Event) {
		var at = chain(hit(e.localX, e.localY)), was = held;
		press([]);
		dragging = null;
		for (o in at) if (o.onPointerUp != null) o.onPointerUp(e);
		for (n in was) if (n.onPress != null) {
			if (at.contains(n)) n.onPress(e);
			break;
		}
	}

	// ---- the focus: one of its nodes, Tab's order through them, keys to it

	// Gives n (one of its nodes, or none) the focus in it, its ring drawn or not.
	public function focusOn(n:Null<Node>, ring = true) {
		if (n == active) {
			if (ring != ringed) {
				ringed = ring;
				repaint();
			}
			return;
		}
		var was = active;
		active = n;
		ringed = ring;
		if (was != null) {
			was.state(Style.FOCUS, false);
			if (was.onBlur != null) was.onBlur(Event.of(Blur, this, 0, 0));
		}
		if (n != null) {
			n.state(Style.FOCUS, true);
			if (ui != null && ui.focus != this) ui.setFocus(this, false);
			if (n.onFocus != null) n.onFocus(Event.of(Focus, this, 0, 0));
		}
		helder.ui.Ui.accessEpoch++;
		repaint();
	}

	// (the nodes Tab stops at in order: tabIndex above 0 first, then 0 in tree order)
	function stops():Array<Node> {
		var out = [];
		function walk(n:Node) {
			if (n.box.style.none || n.box.parent == null && n != root) return;
			if (n.focusable && n.tabIndex >= 0) out.push(n);
			for (c in @:privateAccess n.kids) walk(c);
		}
		walk(root);
		var first = [for (n in out) if (n.tabIndex > 0) n];
		first.sort((a, b) -> a.tabIndex - b.tabIndex);
		return first.concat([for (n in out) if (n.tabIndex == 0) n]);
	}

	// (the first stop, or the last: dir -1)
	function first(dir:Int):Null<Node> {
		var s = stops();
		return s.length == 0 ? null : dir > 0 ? s[0] : s[s.length - 1];
	}

	function field():Null<FieldNode>
		return active != null && Std.isOfType(active, FieldNode) ? cast active : null;

	function key(e:Event) {
		var n = active;
		// (its handlers first, the active node's then its ancestors')
		while (n != null && !e.stopped) {
			if (n.onKeyDown != null) n.onKeyDown(e);
			n = n.parent;
		}
		if (e.stopped || e.defaultPrevented) return;
		var f = field();
		if (f != null && f.key(e, ui, this)) {
			e.stop();
			repaint();
			return;
		}
		switch e.key {
			case Key.TAB:
				// (the next stop, else out of the tree: helder.ui's Tab)
				var s = stops(), i = active == null ? -1 : s.indexOf(active);
				var dir = e.mods & helder.os.Mods.SHIFT != 0 ? -1 : 1;
				var j = i < 0 ? (dir > 0 ? 0 : s.length - 1) : i + dir;
				// (the window's only stop: round again, as helder.ui's Tab goes)
				if ((j < 0 || j >= s.length) && s.length > 0 && alone()) j = dir > 0 ? 0 : s.length - 1;
				if (j >= 0 && j < s.length) {
					focusOn(s[j], true);
					reveal(s[j]);
					e.preventDefault();
					e.stop();
				}
			case Key.ENTER | Key.SPACE if (active != null && active.onPress != null && f == null):
				active.onPress(e);
				e.preventDefault();
				e.stop();
			case _:
		}
	}

	// (no other stop of Tab's in its window)
	function alone():Bool {
		if (ui == null) return true;
		function other(n:helder.ui.Node):Bool {
			if (n != this && n.focusable && n.visible()) return true;
			for (c in n.children) if (other(c)) return true;
			return false;
		}
		return !other(ui.root);
	}

	// (n scrolled into its scrollers' views)
	function reveal(n:Node) {
		var id = fragmentOf(n.box);
		if (id < 0) return;
		var b = n.box.parent;
		while (b != null) {
			if (b.style.scrolls) {
				var pid = fragmentOf(b);
				if (pid >= 0) {
					var o = scrolls.get(Box.scrollKey(b)) ?? [0.0, 0.0];
					var top = fragments.absolute(id).y - fragments.absolute(pid).y, h = fragments.height(id), ph = fragments.height(pid);
					var sy = o[1];
					if (top < sy) sy = top else if (top + h > sy + ph) sy = top + h - ph;
					if (sy != o[1]) scrollBy(b, 0, sy - o[1]);
				}
			}
			b = b.parent;
		}
	}

	function repaint() {
		layerChanged();
		if (ui != null) ui.requestFrame();
	}

	// ---- a field's text input (the window's input method's)

	override public function takesText():Bool
		return field() != null;

	override public function textInputArea():Null<helder.os.Rect> {
		var f = field(), c = f == null ? null : caretOf(f);
		return c == null ? null : {x: absX + c.x, y: absY + c.y, width: 1, height: c.height};
	}

	override public function textContext():Null<{text:String, start:Int, end:Int, multiline:Bool, secret:Bool}> {
		var f = field();
		return f == null ? null : {text: f.value, start: f.from(), end: f.to(), multiline: false, secret: false};
	}

	override public function replaceText(start:Int, end:Int, s:String) {
		var f = field();
		if (f == null) return super.replaceText(start, end, s);
		f.anchor = start;
		f.caret = end;
		f.typed(s, ui, this);
		repaint();
	}

	// (a field's caret, in the tree; null: not laid out)
	function caretOf(f:FieldNode):Null<{x:Float, y:Float, height:Float}> {
		var l = linesOf(f);
		if (l == null) return null;
		var u = l.lines.unitOf(f.run, f.value == "" ? 0 : f.caret);
		if (u < 0) return null;
		var c = l.lines.caret(u);
		return {x: l.x + c.x, y: l.y + c.y, height: c.height};
	}

	// (a field's lines, of the last layout, and where their fragment is in the tree, scrolled: its own alone, no
	// index of the tree's text made for a caret)
	function linesOf(f:FieldNode):Null<{lines:helder.ui.flow.BlockText, x:Float, y:Float}> {
		var l = f.box.lines;
		if (rootFragment < 0 || l == null || l.fragment >= fragments.count || fragments.box(l.fragment) != f.box) return null;
		var o = fragments.absolute(l.fragment), s = shift(f.box);
		return {lines: l, x: o.x - s[0], y: o.y - s[1]};
	}

	// (the index in a field's value nearest a point of the tree)
	function indexIn(f:FieldNode, x:Float, y:Float):Int {
		if (f.value == "") return 0;
		var l = linesOf(f), p = l == null ? null : l.lines.hit(x - l.x, y - l.y);
		if (p == null || p.box != f.run) {
			var r = rectOf(f);
			return x < r[0] - absX + r[2] / 2 ? 0 : f.value.length;
		}
		return p.offset;
	}

	// ---- text selected (Ui's selector): its text boxes as one text, blocks apart by a line

	function texts():BoxTexts
		return boxTexts ??= new BoxTexts(fragments, rootFragment < 0 ? null : root.box);

	// (how far its scrollers moved what is in them)
	function shift(b:Box):Array<Float> {
		var sx = 0.0, sy = 0.0, p = b.parent;
		while (p != null) {
			var o = scrolls.get(Box.scrollKey(p));
			if (o != null) {
				sx += o[0];
				sy += o[1];
			}
			p = p.parent;
		}
		return [sx, sy];
	}

	function flatten() {
		if (flat != null) return flat;
		var buf = new StringBuf(), boxes = [], starts = [], index = new ObjectMap<Box, Int>(), n = 0, last:Null<Box> = null;
		function walk(b:Box) {
			if (b.kind == Text) {
				if (Std.isOfType(b.source, FieldNode)) return;
				if (last != null && b.parent != last) {
					buf.add("\n");
					n++;
				}
				last = b.parent;
				index.set(b, boxes.length);
				boxes.push(b);
				starts.push(n);
				buf.add(b.text);
				n += b.text.length;
				return;
			}
			var c = b.first;
			while (c != null) {
				walk(c);
				c = c.next;
			}
		}
		walk(root.box);
		return flat = {text: buf.toString(), boxes: boxes, starts: starts, index: index};
	}

	// (an index in that text as a box position)
	function positionOf(i:Int):Null<BoxPosition> {
		var f = flatten();
		if (f.boxes.length == 0) return null;
		var k = 0;
		while (k + 1 < f.starts.length && f.starts[k + 1] <= i) k++;
		return {box: f.boxes[k], offset: Std.int(Math.max(0, Math.min(i - f.starts[k], f.boxes[k].text.length)))};
	}

	// (no selection begun by a press on what takes presses or the focus)
	override public function selectionScope():Null<helder.ui.Node> {
		if (ui != null && rootFragment >= 0) {
			for (o in chain(hit(ui.pointerX - absX, ui.pointerY - absY))) if (o.focusable || o.onPress != null || o.onPointerDown != null) return null;
		}
		return super.selectionScope();
	}

	@:noCompletion override public function selectableText():Null<String>
		return rootFragment < 0 ? null : flatten().text;

	@:noCompletion override public function selectableIndex(px:Float, py:Float, under = false):Int {
		if (rootFragment < 0) return 0;
		var x = px - absX, y = py - absY, b = HitTest.at(fragments, ordered(), x, y, scrolls)?.box;
		var s = b == null ? [0.0, 0.0] : shift(b), p = texts().position(x + s[0], y + s[1]);
		if (p == null) return 0;
		var f = flatten(), k = f.index.get(p.box);
		return k == null ? 0 : f.starts[k] + p.offset;
	}

	@:noCompletion override public function selectableCaret(i:Int):Null<{x:Float, y:Float, height:Float}> {
		var p = positionOf(i), c = p == null ? null : texts().caret(p);
		if (c == null) return null;
		var s = shift(p.box);
		return {x: absX + c.x - s[0], y: absY + c.y - s[1], height: c.height};
	}

	// (what it draws over its boxes, in the tree's place: the text selected, a field's selection and caret, the focus's ring)
	function marks(canvas:helder.ui.Canvas) {
		var sel = ui.textSelection, f = flat != null || sel != null ? flatten() : null;
		var r = sel == null ? null : sel.rangeIn(this, f.text.length);
		if (r != null && r.start != r.end) {
			var a = positionOf(r.start), z = positionOf(r.end);
			if (a != null && z != null) {
				var s = shift(a.box);
				for (q in texts().rects(a, z)) canvas.rect(q.x - s[0], q.y - s[1], q.width, q.height, 0, ui.selectionColor, 0, 0);
			}
		}
		var fd = field();
		if (fd != null && ui.focus == this) {
			var l = linesOf(fd);
			if (l != null && fd.caret != fd.anchor && fd.value != "") {
				var u0 = l.lines.unitOf(fd.run, fd.from()), u1 = l.lines.unitOf(fd.run, fd.to());
				if (u0 >= 0 && u1 >= 0) for (q in l.lines.selection(u0, u1)) canvas.rect(l.x + q.x, l.y + q.y, q.width, q.height, 0, ui.selectionColor, 0, 0);
			}
			var c = caretOf(fd);
			if (c != null) canvas.rect(Math.round(c.x), c.y, 1.5, c.height, 0, fd.box.style.text.colour, 0, 0);
		}
		if (active != null && ringed && ui.focus == this && ui.focusRingWidth > 0) {
			var id = fragmentOf(active.box);
			if (id >= 0) {
				var p = fragments.absolute(id), s = shift(active.box), o = ui.focusRingOffset + ui.focusRingWidth;
				var radius = active.props().borderRadius ?? 0;
				canvas.rect(p.x - s[0] - o, p.y - s[1] - o, fragments.width(id) + 2 * o, fragments.height(id) + 2 * o, radius > 0 ? radius + o : 0,
					helder.gfx.Color.TRANSPARENT, ui.focusRingWidth, ui.focusRingColor);
			}
		}
	}

	// ---- assistive technology: its nodes with a role, as helder.ui's would be

	@:noCompletion override public function accessFocus():Int
		return active != null && ui != null && ui.focus == this ? idOf(active) : accessId;

	static function idOf(n:Node):Int
		return n.accessId == 0 ? n.accessId = AccessTree.newId() : n.accessId;

	@:noCompletion override public function accessParts():Null<Array<AccessNode>> {
		if (rootFragment < 0) return null;
		var out:Array<AccessNode> = [];
		function visit(n:Node, inName:Bool):Array<Int> {
			var sem = n.semantics;
			if (n.box.style.none || n.box.parent == null && n != root || sem != null && sem.hidden) return [];
			var role:Null<Role> = sem != null ? sem.role : null;
			if (role == null) role = Std.isOfType(n, FieldNode) ? TextInput : Std.isOfType(n, TextNode) ? (inName || (cast n : TextNode).text == "" ? null : Label) : n.focusable
				|| sem != null && sem.live != Off ? Group : null;
			var named = inName || role != null && role.namedByContent();
			if (role == null) return [for (c in @:privateAccess n.kids) for (id in visit(c, named)) id];
			var r = rectOf(n);
			var a:AccessNode = {
				id: idOf(n),
				role: role,
				x: r[0],
				y: r[1],
				width: r[2],
				height: r[3],
				focusable: n.focusable
			};
			out.push(a);
			if (sem != null) {
				a.description = sem.description;
				a.checked = sem.checked;
				a.selected = sem.selected;
				a.expanded = sem.expanded;
				a.level = sem.level;
				a.disabled = sem.disabled;
				a.current = sem.current;
				a.invalid = sem.invalid;
				a.required = sem.required;
				a.modal = sem.modal;
				if (sem.setSize > 0) {
					a.posInSet = sem.posInSet;
					a.setSize = sem.setSize;
				}
				if (sem.live != Off) {
					a.live = sem.live;
					a.liveText = textOf(n);
				}
			}
			a.name = sem != null && sem.label != null ? sem.label : role == Label ? (cast n : TextNode).text : role.namedByContent() ? textOf(n) : "";
			if (Std.isOfType(n, FieldNode)) {
				var f:FieldNode = cast n;
				a.value = f.value;
				a.textStart = f.from();
				a.textEnd = f.to();
				a.caret = f.caret;
			}
			if (!Std.isOfType(n, TextNode)) a.children = [for (c in @:privateAccess n.kids) for (id in visit(c, named)) id];
			return [a.id];
		}
		visit(root, false);
		return out;
	}

	// (the text of the texts in n, space separated: a name from its content)
	static function textOf(n:Node):String {
		var parts = [];
		function walk(m:Node) {
			if (m.box.style.none || m.semantics != null && m.semantics.hidden) return;
			if (Std.isOfType(m, TextNode) && !Std.isOfType(m, FieldNode)) {
				var t = StringTools.trim((cast m : TextNode).text);
				if (t != "") parts.push(t);
				return;
			}
			for (c in @:privateAccess m.kids) walk(c);
		}
		walk(n);
		return parts.join(" ");
	}

	@:noCompletion override public function accessPartAction(id:Int, action:helder.ui.access.AccessAction, value:Null<String>):Bool {
		var n = partOf(root, id);
		if (n == null) return false;
		switch action {
			case Click:
				if (n.onPress == null) return false;
				n.onPress(Event.of(Click, this, 0, 0));
			case Focus:
				if (!n.focusable) return false;
				if (ui != null) ui.focusVisible = true;
				focusOn(n, true);
			case SetValue if (Std.isOfType(n, FieldNode) && value != null):
				var f:FieldNode = cast n;
				f.anchor = 0;
				f.caret = f.value.length;
				f.typed(value, ui, this);
			case ScrollIntoView:
				reveal(n);
			case _:
				return false;
		}
		return true;
	}

	static function partOf(n:Node, id:Int):Null<Node> {
		if (n.accessId == id) return n;
		for (c in @:privateAccess n.kids) {
			var f = partOf(c, id);
			if (f != null) return f;
		}
		return null;
	}
}
