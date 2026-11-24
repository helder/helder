package helder.ui;

import helder.ui.actions.Keymap;

// The input shared by a VirtualGrid and a VirtualList with a Selection.
@:noCompletion
class SelectionInput {
	public var onActivate:Null<Array<Int>->Void>;
	public var onContextMenu:Null<(Int, Float, Float)->Void>;
	public var textOf:Null<Int->String>;
	public var onEmptyClick:Null<Void->Void>;

	final view:VirtualScroll;
	final selection:Selection;
	final count:Void->Int;
	final itemAt:Node->Int;
	final nodeAt:Int->Null<Node>;
	final move:(Int, Int)->Null<Int>;
	var pressed = -1;
	var pointer = -1;
	var pressedX = 0.0;
	var pressedY = 0.0;
	var moved = false;
	// (a plain press on a selected item: chosen on release, without a drag)
	var held = false;
	var lastClick:Null<String>;
	var clickAt = -1e9;
	var clickX = 0.0;
	var clickY = 0.0;
	var clickMods = 0;
	var typed = "";
	var typedAt = -1e9;

	public function new(view:VirtualScroll, selection:Selection, count:Void->Int, itemAt:Node->Int, nodeAt:Int->Null<Node>, move:(Int, Int)->Null<Int>) {
		this.view = view;
		this.selection = selection;
		this.count = count;
		this.itemAt = itemAt;
		this.nodeAt = nodeAt;
		this.move = move;
		view.onPointerDown = down;
		view.onPointerMove = motion;
		view.onPointerCancel = e -> {
			if (e.pointerId == pointer) pointer = -1;
		};
		view.onClick = click;
		view.onKeyDown = key;
		view.onTextInput = type;
		var focusIn = view.onFocusIn;
		view.onFocusIn = e -> {
			if (focusIn != null) focusIn(e);
			var i = indexAtFocus(e.target);
			if (i >= 0) selection.moveFocus(i);
		};
		view.onFocusOut = _ -> if (!view.focusWithin()) typed = "";
	}

	public static function secondary(mods:Int):Bool
		return mods & (Keymap.mac ? Key.MOD_META : Key.MOD_CONTROL) != 0;

	public static function dragged(x:Float, y:Float, fromX:Float, fromY:Float):Bool {
		var dx = x - fromX, dy = y - fromY;
		return dx * dx + dy * dy >= 16;
	}

	function down(e:Event) {
		if (e.defaultPrevented || !e.isPrimary) return;
		var i = itemAt(e.target);
		if (e.button == 3 && i >= 0 && onContextMenu != null) {
			if (!selection.has(selection.keyOf(i))) selection.select(i);
			onContextMenu(i, e.x, e.y);
			return;
		}
		if (e.button != 1) return;
		pointer = e.pointerId;
		pressed = i;
		pressedX = e.x;
		pressedY = e.y;
		moved = false;
		held = i >= 0 && selection.has(selection.keyOf(i)) && e.mods & Key.MOD_SHIFT == 0 && !secondary(e.mods);
		if (i >= 0 && !held) choose(i, e.mods);
	}

	function choose(i:Int, mods:Int) {
		if (mods & Key.MOD_SHIFT != 0) selection.extend(i)
		else if (secondary(mods)) selection.toggle(i)
		else selection.select(i);
	}

	function motion(e:Event) {
		if (e.pointerId == pointer && !moved && dragged(e.x, e.y, pressedX, pressedY)) {
			moved = true;
			lastClick = null;
		}
	}

	function click(e:Event) {
		if (e.defaultPrevented || e.button != 1 || pointer != e.pointerId) return;
		pointer = -1;
		var i = itemAt(e.target);
		if (moved || dragged(e.x, e.y, pressedX, pressedY) || i != pressed) {
			lastClick = null;
			return;
		}
		if (i < 0) {
			lastClick = null;
			if (onEmptyClick != null) onEmptyClick();
			return;
		}
		var k = selection.keyOf(i), t = Ui.now();
		if (lastClick == k && clickMods == e.mods && t - clickAt < 0.45 && Math.abs(e.x - clickX) < 5 && Math.abs(e.y - clickY) < 5 && onActivate != null) {
			lastClick = null;
			activate();
			return;
		}
		lastClick = k;
		clickAt = t;
		clickX = e.x;
		clickY = e.y;
		clickMods = e.mods;
		if (held) selection.select(i);
	}

	function activate() {
		if (onActivate != null) onActivate(selection.indices());
	}

	// A control inside an item keeps its own keyboard.
	function indexAtFocus(target:Node):Int {
		if (target == view) return -1;
		var i = itemAt(target);
		return i >= 0 && nodeAt(i) == target ? i : -2;
	}

	function key(e:Event) {
		if (e.defaultPrevented || e.mods & Key.MOD_ALT != 0) return;
		var mod = secondary(e.mods);
		if (!mod && e.mods & (Key.MOD_CONTROL | Key.MOD_META) != 0) return;
		var at = indexAtFocus(e.target);
		if (at == -2) return;
		var n = count(), i = selection.focusIndex();
		if (i < 0) i = at;
		switch e.key {
			case "a".code if (mod): selection.selectAll();
			case Key.ESCAPE: selection.clear();
			case Key.ENTER if (onActivate != null): activate();
			case Key.SPACE if (mod && i >= 0): selection.toggle(i);
			case _:
				var to = move(i, e.key);
				if (to == null || n == 0) return;
				to = Std.int(Math.max(0, Math.min(n - 1, to)));
				if (e.mods & Key.MOD_SHIFT != 0) {
					if (selection.focus == null) selection.moveFocus(i);
					selection.extend(to);
				} else if (!mod) selection.select(to);
				selection.moveFocus(to);
				view.focusIndex(to);
		}
		typed = "";
		e.preventDefault();
		e.stop();
	}

	function type(e:Event) {
		if (e.defaultPrevented || textOf == null || e.text == "" || indexAtFocus(e.target) == -2) return;
		for (i in 0...e.text.length)
			if (e.text.charCodeAt(i) < 32 || e.text.charCodeAt(i) == 127) return;
		var now = Ui.now();
		typed = (now - typedAt < 1 ? typed : "") + e.text.toLowerCase();
		typedAt = now;
		var start = selection.focusIndex(), n = count();
		if (start < 0) start = 0;
		for (j in 0...n) {
			var i = (start + j) % n;
			if (StringTools.startsWith(textOf(i).toLowerCase(), typed)) {
				selection.select(i);
				view.focusIndex(i);
				break;
			}
		}
		e.stop();
	}

	public static function decorate(node:Node, selection:Selection, key:String) {
		var on = selection.has(key);
		node.semantics.selected = on;
		node.setAttr("data-selected", on ? "true" : "false");
		node.setAttr("data-focused", selection.focus == key ? "true" : "false");
	}
}
