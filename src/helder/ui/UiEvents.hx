package helder.ui;

import helder.os.Event as OsEvent;
import helder.async.Errors;

// A window's input events to its Ui (UiWindow's, a test's): the pointer,
// the wheel, the keys and text, in its points (k pixels a point), each as
// the compositor routed it (helder.os.Event.routed: ScrollMirror).
@:access(helder.ui.Ui)
class UiEvents {
	// e, as the main thread reads it, to the compositor first (its mirror,
	// under the compositor's lock): what it is to the program (e.routed, e.gesture)
	public static function route(m:ScrollMirror, e:OsEvent):Int {
		var k = m.scale, i:ScrollInput;
		switch e.kind {
			case Scroll:
				i = m.event(Wheel);
				var dx = e.deltaX, dy = e.deltaY;
				if (e.mods & helder.os.Mods.SHIFT != 0 && dx == 0) {
					dx = dy;
					dy = 0;
				}
				i.x = e.x / k;
				i.y = e.y / k;
				i.dx = dx / k;
				i.dy = dy / k;
				i.eased = e.eased;
				i.mods = e.mods;
				i.phase = e.phase;
				i.momentum = e.momentum;
				i.time = e.time;
			case PointerDown | PointerMove | PointerUp | PointerCancel if (e.pointer != null && e.pointer.type != helder.os.PointerType.Mouse):
				var p = e.pointer;
				i = m.event(e.kind == PointerDown ? Down : e.kind == PointerMove ? Move : e.kind == PointerUp ? Up : Cancel);
				i.x = p.x / k;
				i.y = p.y / k;
				i.id = p.id;
				i.time = p.time;
			case MouseDown | MouseMove | MouseUp:
				i = m.event(e.kind == MouseDown ? MouseDown : e.kind == MouseMove ? MouseMove : MouseUp);
				i.x = e.x / k;
				i.y = e.y / k;
				i.key = e.button;
			case KeyDown:
				i = m.event(Key);
				i.key = e.key;
				i.mods = e.mods;
			case _:
				e.routed = e.gesture = 0;
				return 0;
		}
		var r = m.input(i);
		e.routed = r;
		e.gesture = i.gesture;
		return r;
	}

	// e's input to ui (its pixels at k a point), as the compositor routed
	// it (Event.routed: helder.ui.ScrollMirror); a scroll waiting on a
	// question held until its answer (a trackpad's Began before its first move)
	public static function deliver(ui:Ui, e:OsEvent, k:Float) {
		var route = e.routed;
		if (route == ScrollMirror.PENDING) {
			route = ui.resolve(e.gesture);
			if (route < 0) {
				if (e.kind == Scroll) {
					held.push(copy(e));
					return;
				}
				route = ScrollMirror.PROGRAM;
			}
		}
		ui.routed = route;
		ui.routedGesture = e.gesture;
		try
			input(ui, e, k)
		catch (x:haxe.Exception) {
			ui.routed = 0;
			throw Errors.kept(x);
		}
		ui.routed = 0;
		// (a question answered: the scrolls held for it, the program's if it kept them)
		if (route == ScrollMirror.ASK && held.length > 0) {
			var kept = ui.resolve(e.gesture) == ScrollMirror.PROGRAM;
			var mine = [for (h in held) if (h.gesture == e.gesture) h];
			for (h in mine) {
				held.remove(h);
				if (kept) {
					h.routed = ScrollMirror.PROGRAM;
					input(ui, h, k);
				}
			}
		}
	}

	static final held:Array<OsEvent> = [];

	static function copy(e:OsEvent):OsEvent {
		var c = new OsEvent();
		c.kind = e.kind;
		c.window = e.window;
		c.x = e.x;
		c.y = e.y;
		c.deltaX = e.deltaX;
		c.deltaY = e.deltaY;
		c.eased = e.eased;
		c.phase = e.phase;
		c.momentum = e.momentum;
		c.time = e.time;
		c.mods = e.mods;
		c.routed = e.routed;
		c.gesture = e.gesture;
		return c;
	}

	static function input(ui:Ui, e:OsEvent, k:Float) {
		switch e.kind {
			case MouseMove:
				ui.pointerMove(e.x / k, e.y / k);
			case Scroll:
				// (Shift turns a vertical wheel sideways, as browsers do)
				var dx = e.deltaX, dy = e.deltaY;
				if (e.mods & helder.os.Mods.SHIFT != 0 && dx == 0) {
					dx = dy;
					dy = 0;
				}
				var phased = e.phase != 0 || e.momentum != 0;
				ui.wheel(e.x / k, e.y / k, dx / k, dy / k, e.eased, e.mods, e.phase, e.momentum, phased ? ui.eventTime(e.time) : -1);
			case MouseDown:
				ui.pointerDown(e.x / k, e.y / k, e.button);
			case MouseUp:
				ui.pointerUp(e.x / k, e.y / k, e.button);
			// (fingers and pens: the mouse's are its Mouse* events above)
			case PointerDown if (e.pointer.type != helder.os.PointerType.Mouse):
				var p = e.pointer;
				// (a press on the ui's own nodes is the ui's: a game's controls leave it alone)
				if (ui.pointerDown(p.x / k, p.y / k, 1, p.id, p.type, p.pressure, ui.eventTime(p.time))) p.owner = helder.os.PointerOwner.Ui;
			case PointerMove if (e.pointer.type != helder.os.PointerType.Mouse):
				ui.pointerMove(e.pointer.x / k, e.pointer.y / k, e.pointer.id, e.pointer.pressure, ui.eventTime(e.pointer.time));
			case PointerUp if (e.pointer.type != helder.os.PointerType.Mouse):
				ui.pointerUp(e.pointer.x / k, e.pointer.y / k, 1, e.pointer.id, ui.eventTime(e.pointer.time));
			case PointerCancel if (e.pointer.type != helder.os.PointerType.Mouse):
				ui.pointerCancel(e.pointer.id);
			case KeyDown:
				ui.keyDown(e.key, e.mods);
			case KeyUp:
				ui.keyUp(e.key, e.mods);
			case TextInput:
				ui.textInput(e.text);
			case TextEditing:
				ui.composition(e.text, e.x);
			case TextReplace:
				ui.replaceText(e.x, e.y, e.text);
			case TextSelect:
				if (ui.focus != null) ui.focus.select(e.x, e.y);
			case _:
		}
	}

}
