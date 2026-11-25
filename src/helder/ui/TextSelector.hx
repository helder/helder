package helder.ui;

import helder.os.Mods;
import helder.ui.actions.Keymap;

// Ui.textSelection's pointer and keys. A press on a scope's text starts
// it there (off its texts but in the scope: at the nearest; Shift: the
// selection extended to it), a double click a word, a triple a line, a
// drag after either by words or lines; a drag moves its focus, past a
// scroller's edge scrolling it, faster the farther. Shift and the arrows
// move the focus (a character, a line, from one text to the next); Mod+A
// selects all of the scope the focus is in, or the selection's while the
// focus is where its press left it.
@:allow(helder.ui.Ui)
class TextSelector {
	final ui:Ui;
	// (a drag selecting, by characters (1), words (2) or lines (3) from the press's base; whether it changed it)
	var selecting = false;
	var unit = 1;
	var base:Null<TextSelection> = null;
	var moved = false;
	// (the clicks in a row, the last one's time and place)
	var clicks = 0;
	var clickAt = -1e9;
	var clickX = 0.0;
	var clickY = 0.0;
	// (the focus the press that made the selection left: its keys the selection's)
	var owner:Null<Node> = null;
	var made = false;
	// (a scroller dragged past: stepping, its last step's time)
	var scrolling = false;
	var stepAt = -1.0;
	final bounds = {x: 0.0, y: 0.0, width: 0.0, height: 0.0};

	function new(ui:Ui)
		this.ui = ui;

	// (a press on target: a selection begun, extended, or dropped)
	function press(target:Null<Node>, x:Float, y:Float, button:Int, mods:Int) {
		made = false;
		selecting = false;
		var scope = target == null ? null : scopeOf(target);
		if (scope != null && taken(target, scope)) scope = null;
		if (scope == null || button != 1) {
			// (a right press keeps it: a context menu's Copy)
			if (button != 3 || scope == null) ui.selectText(null);
			return;
		}
		var h = pointAt(scope, x, y, target);
		if (h == null) {
			ui.selectText(null);
			return;
		}
		var time = Ui.now();
		clicks = time - clickAt < 0.45 && Math.abs(x - clickX) < 5 && Math.abs(y - clickY) < 5 ? clicks + 1 : 1;
		clickAt = time;
		clickX = x;
		clickY = y;
		made = true;
		moved = false;
		var s = ui.textSelection;
		if (h.all) {
			ui.selectText(new TextSelection(scope, new TextPoint(h.point.path, 0), new TextPoint(h.point.path, h.text.length)));
			return;
		}
		selecting = true;
		if (mods & Mods.SHIFT != 0 && s != null && s.scope == scope && clicks == 1) {
			unit = 1;
			ui.selectText(new TextSelection(scope, s.anchor, h.point));
			return;
		}
		unit = clicks > 3 ? 3 : clicks;
		var r = range(h.text, h.under, unit);
		base = unit == 1 ? null : new TextSelection(scope, new TextPoint(h.point.path, r.start), new TextPoint(h.point.path, r.end));
		ui.selectText(base ?? new TextSelection(scope, h.point, h.point));
	}

	// (the pointer moved to x, y while pressed)
	function move(x:Float, y:Float) {
		var s = ui.textSelection;
		if (!selecting || s == null) return;
		// (past a scroller's edge: the point at the edge, the scroller stepping)
		var sc = scroller(s);
		if (sc != null) {
			var b = sc.windowBoundsInto(bounds), top = b.y, bottom = b.y + b.height;
			if (y < top || y >= bottom) {
				y = y < top ? top + 1 : bottom - 1;
				if (!scrolling) scroll(sc);
			}
		}
		var h = pointAt(s.scope, x, y);
		if (h == null) return;
		var next = new TextSelection(s.scope, s.anchor, h.point);
		if (base != null) {
			var r = range(h.text, h.under, unit), from = new TextPoint(h.point.path, r.start);
			next = TextPoint.compare(from, base.start()) < 0 ? new TextSelection(s.scope, base.end(), from) : new TextSelection(s.scope, base.start(),
				new TextPoint(h.point.path, r.end));
		}
		if (next.anchor.equals(s.anchor) && next.focus.equals(s.focus)) return;
		moved = true;
		ui.selectText(next);
	}

	// (released: whether a drag selected text, which then clicks nothing)
	function release():Bool {
		var dragged = selecting && moved && ui.textSelection != null && !ui.textSelection.collapsed();
		selecting = false;
		return dragged;
	}

	// (the scroller to step as the drag goes past its edge, each frame
	// until it is back inside, let go or at its end)
	function scroll(sc:Node) {
		scrolling = true;
		stepAt = -1;
		Clock.addFor(sc, t -> {
			var s = ui.textSelection;
			if (!selecting || s == null || scroller(s) != sc) return scrolling = false;
			var b = sc.windowBoundsInto(bounds), y = ui.pointerY;
			var d = y < b.y ? y - b.y : y >= b.y + b.height ? y - b.y - b.height + 1 : 0.0;
			if (d == 0) return scrolling = false;
			var dt = stepAt < 0 ? 1 / 60 : Math.min(0.1, t - stepAt);
			stepAt = t;
			// (20 pixels a second for each past the edge, at most 50 of them)
			var v = (d < 0 ? -1 : 1) * Math.min(Math.abs(d), 50) * 20 * dt;
			var was = sc.scrollY;
			Scrolling.setScroll(ui, sc, false, was + v);
			move(ui.pointerX, y);
			return scrolling = sc.scrollY != was;
		});
	}

	// (the nearest ancestor of its focus's text that scrolls down and up)
	function scroller(s:TextSelection):Null<Node> {
		var n = s.focus.node(s.scope) ?? s.anchor.node(s.scope) ?? s.scope;
		while (n != null && !(n.style.overflowY == Scroll && Scrolling.maxScroll(n, false) > 0))
			n = n.parent;
		return n;
	}

	// (a key the selection takes: Shift and an arrow, Mod+A)
	function key(key:Int, mods:Int):Bool {
		var mod = mods & (Keymap.mac ? Mods.META : Mods.CONTROL) != 0;
		if (mod && (key == "a".code || key == "A".code) && mods & (Mods.SHIFT | Mods.ALT) == 0) return selectAll();
		var s = ui.textSelection;
		if (s == null || mods & Mods.SHIFT == 0 || mods & (Mods.CONTROL | Mods.META | Mods.ALT) != 0 || !owned()) return false;
		var to = switch key {
			case Key.LEFT: step(s, -1);
			case Key.RIGHT: step(s, 1);
			case Key.UP: line(s, -1);
			case Key.DOWN: line(s, 1);
			case _: return false;
		}
		if (to != null) ui.selectText(new TextSelection(s.scope, s.anchor, to));
		return true;
	}

	// (all of the keys' scope: false, none)
	function selectAll():Bool {
		var scope = keyScope();
		if (scope == null) return false;
		ui.selectText(TextSelection.all(scope));
		return true;
	}

	function keyScope():Null<Node> {
		var f = ui.focus, scope = f == null ? null : f.selectionScope();
		if (scope != null) return scope;
		var s = ui.textSelection;
		return s != null && owned() ? s.scope : null;
	}

	function owned():Bool {
		var s = ui.textSelection, f = ui.focus;
		return s != null && (f == null || f == owner || s.scope.contains(f));
	}

	// (a character on, or the next text's start: the break between them one step)
	function step(s:TextSelection, dir:Int):Null<TextPoint> {
		var f = s.focus, n = f.node(s.scope);
		if (n == null) return null;
		var t = n.selectableText(), i = f.index + dir;
		// (a surrogate pair: both halves)
		if (i > 0 && i < t.length && StringTools.fastCodeAt(t, i) & 0xFC00 == 0xDC00) i += dir;
		if (i >= 0 && i <= t.length) return new TextPoint(f.path, i);
		var prev:Null<TextPoint> = null, next:Null<TextPoint> = null;
		TextSelection.texts(s.scope, null, null, TextSelection.MADE, (m, path) -> {
			var o = TextPoint.order(path, f.path);
			if (o < 0) prev = new TextPoint(path, m.selectableText().length) else if (o > 0 && next == null) next = new TextPoint(path, 0);
		});
		return dir < 0 ? prev : next;
	}

	// (the line above or below the focus's caret, at its x: the next text's
	// within 400 pixels; none, the start or the end of its own)
	function line(s:TextSelection, dir:Int):Null<TextPoint> {
		var f = s.focus, n = f.node(s.scope);
		var c = n == null ? null : n.selectableCaret(f.index);
		if (c == null) return null;
		var y = dir < 0 ? c.y - 1 : c.y + c.height + 1;
		for (_ in 0...100) {
			var h = pointAt(s.scope, c.x, y, null, true);
			if (h != null) return h.point;
			y += dir * 4;
		}
		return new TextPoint(f.path, dir < 0 ? 0 : n.selectableText().length);
	}

	// (the scope of a press on target: the outermost selectable node, else
	// a text selectable by its user-select alone)
	function scopeOf(target:Node):Null<Node> {
		var scope = target.selectionScope();
		if (scope != null) return scope;
		var part = partOf(target);
		if (part == null) return null;
		var u = part.userSelect();
		return u == Text || u == All ? part : null;
	}

	// (a press a control takes, not the text: a field's, or under a node
	// that takes presses or the focus, between its text and the scope)
	static function taken(target:Node, scope:Node):Bool {
		var n:Null<Node> = target;
		while (n != null && n != scope) {
			if (n.takesText()) return true;
			var gs = n.gestures;
			if (n.selectableText() == null
				&& (n.focusable || n.onPointerDown != null || n.dragData != null || (gs != null && gs.length > 0))) return true;
			n = n.parent;
		}
		return false;
	}

	// (the text n is in: itself, or the paragraph of its span; null: none, or not selectable)
	static function partOf(n:Null<Node>):Null<Node> {
		while (n != null && n.selectableText() == null)
			n = n.parent;
		return n == null || n.userSelect() == None ? null : n;
	}

	// (the point of scope's text at x, y: the text there's (target: what is
	// under it); else the nearest on its line, the end of the one above it,
	// the first's start (line: on a line or none))
	function pointAt(scope:Node, x:Float, y:Float, ?target:Node, line = false):Null<{point:TextPoint, under:Int, text:String, all:Bool}> {
		var part = line ? null : partOf(target ?? @:privateAccess ui.hit(x, y));
		var path = part == null ? null : TextPoint.pathOf(scope, part);
		if (path != null) return at(part, path, x, y);
		var best:Null<Node> = null, bestPath:Null<Array<Int>> = null, bestD = Math.POSITIVE_INFINITY;
		var above:Null<Node> = null, abovePath:Null<Array<Int>> = null, aboveY = Math.NEGATIVE_INFINITY;
		var first:Null<Node> = null, firstPath:Null<Array<Int>> = null;
		TextSelection.texts(scope, null, null, TextSelection.SHOWN, (n, p) -> {
			var b = n.windowBoundsInto(bounds), bottom = b.y + b.height;
			if (first == null) {
				first = n;
				firstPath = p;
			}
			if (y >= b.y && y < bottom) {
				var d = x < b.x ? b.x - x : x > b.x + b.width ? x - b.x - b.width : 0.0;
				if (d < bestD) {
					best = n;
					bestPath = p;
					bestD = d;
				}
			} else if (bottom <= y && bottom >= aboveY) {
				above = n;
				abovePath = p;
				aboveY = bottom;
			}
		});
		if (best != null) return at(best, bestPath, x, y);
		if (line) return null;
		if (above != null) {
			var t = above.selectableText();
			return {point: new TextPoint(abovePath, t.length), under: t.length - 1, text: t, all: above.userSelect() == All};
		}
		if (first != null) return {point: new TextPoint(firstPath, 0), under: 0, text: first.selectableText(), all: first.userSelect() == All};
		return null;
	}

	function at(part:Node, path:Array<Int>, x:Float, y:Float):{point:TextPoint, under:Int, text:String, all:Bool}
		return {
			point: new TextPoint(path, part.selectableIndex(x, y)),
			under: part.selectableIndex(x, y, true),
			text: part.selectableText(),
			all: part.userSelect() == All
		};

	// (what a click of unit selects around character i of t: itself, its
	// word (letters, digits and marks; else the one character), its line)
	static function range(t:String, i:Int, unit:Int):{start:Int, end:Int} {
		if (i < 0) i = 0;
		if (i > t.length) i = t.length;
		if (unit == 1 || t.length == 0) return {start: i, end: i};
		if (i == t.length) i--;
		if (unit >= 3) {
			var a = i > 0 ? t.lastIndexOf("\n", i - 1) : -1, b = t.indexOf("\n", i);
			return {start: a + 1, end: b < 0 ? t.length : b};
		}
		inline function word(c:Int):Bool
			return c == "_".code || (c >= "0".code && c <= "9".code) || (c >= "a".code && c <= "z".code) || (c >= "A".code && c <= "Z".code) || c > 0x7F
				&& c != 0xA0 && c != 0x3000;
		if (!word(StringTools.fastCodeAt(t, i))) {
			var b = i + 1;
			if (b < t.length && StringTools.fastCodeAt(t, b) & 0xFC00 == 0xDC00) b++;
			return {start: i, end: b};
		}
		var a = i, b = i;
		while (a > 0 && word(StringTools.fastCodeAt(t, a - 1)))
			a--;
		while (b < t.length && word(StringTools.fastCodeAt(t, b)))
			b++;
		return {start: a, end: b};
	}
}
