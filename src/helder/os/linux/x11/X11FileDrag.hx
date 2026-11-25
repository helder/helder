package helder.os.linux.x11;

import helder.os.DragOperation;
import helder.os.UriList;
import helder.os.linux.x11.Xlib;
import hxmc.unsafe.*;

// XDND's source. The pointer and keyboard belong to the drag until the
// release, but the selection stays available until the target is finished.
@:access(helder.os.linux.x11.X11Window)
@:hxmc.unsafe(gc)
class X11FileDrag {
	public static var active(default, null):Null<X11FileDrag>;

	public final window:X11Window;
	final button:Int;
	final bytes:haxe.io.Bytes;
	final allowed:Array<DragOperation>;
	final done:DragOperation->Void;
	final cursor:Int64;

	var target:Int64 = 0;
	var proxy:Int64 = 0;
	var version = 0;
	var position:Null<DragPosition>;
	var sent:Null<DragPosition>;
	var statusPending = false;
	var accepted:DragOperation = None;
	var releaseTime:Null<Int64>;
	var dropped = false;
	var deadline = 0.0;

	function new(window:X11Window, button:Int, cursor:Int64, paths:Array<String>, allowed:Array<DragOperation>, done:DragOperation->Void) {
		this.window = window;
		this.button = button;
		this.cursor = cursor;
		bytes = haxe.io.Bytes.ofString(UriList.encode(paths));
		this.allowed = allowed.copy();
		this.done = done;
	}

	public static function start(w:X11Window, button:Int, time:Int64, state:Int, paths:Array<String>, allowed:Array<DragOperation>,
		done:DragOperation->Void):Bool {
		if (active != null || button == 0) return false;
		var d = X11Window.display, id = w.id, cursor = Xlib.XCreateFontCursor(d, 52); // XC_fleur
		var drag = new X11FileDrag(w, button, cursor, paths, allowed, done);
		if (Xlib.XGrabPointer(d, id, 0, X.PointerMotionMask | X.ButtonPressMask | X.ButtonReleaseMask, 1, 1, 0, cursor, time) != 0) {
			Xlib.XFreeCursor(d, cursor);
			return false;
		}
		if (Xlib.XGrabKeyboard(d, id, 0, 1, 1, time) != 0) {
			Xlib.XUngrabPointer(d, 0);
			Xlib.XFreeCursor(d, cursor);
			return false;
		}
		Xlib.XSetSelectionOwner(d, X11Window.XdndSelection, id, time);
		if (Xlib.XGetSelectionOwner(d, X11Window.XdndSelection) != id) {
			drag.ungrab();
			Xlib.XFlush(d);
			return false;
		}
		active = drag;
		drag.move(time, state);
		return true;
	}

	// Prefer the operation the modifiers ask for, where the app allows it.
	function requested(state:Int):DragOperation {
		var want:DragOperation = switch state & 5 {
			case 5: Link; // Shift + Control
			case 1: Move;
			case _: Copy;
		};
		if (allowed.contains(want)) return want;
		return allowed.contains(Copy) ? Copy : allowed.contains(Move) ? Move : Link;
	}

	static function action(op:DragOperation):Int64
		return switch op {
			case Copy: X11Window.XdndActionCopy;
			case Move: X11Window.XdndActionMove;
			case Link: X11Window.XdndActionLink;
			case None: 0;
		};

	function operation(atom:Int64):DragOperation {
		for (op in allowed)
			if (op != None && action(op) == atom) return op;
		return None;
	}

	// Walk from the root down to the window under the pointer. A reparenting
	// window manager's frame usually has no XdndAware; its client window does.
	function move(time:Int64, state:Int) {
		var d = X11Window.display, root = Xlib.XDefaultRootWindow(d);
		trapWindowErrors(() -> Arena.scoped(a -> {
			var r:Ptr<Int64> = a.alloc(8), child:Ptr<Int64> = a.alloc(8);
			var rx:Ptr<Int32> = a.alloc(4), ry:Ptr<Int32> = a.alloc(4);
			var x:Ptr<Int32> = a.alloc(4), y:Ptr<Int32> = a.alloc(4), keys:Ptr<UInt32> = a.alloc(4);
			if (Xlib.XQueryPointer(d, root, r, child, rx, ry, x, y, keys) == 0) {
				changeTarget(0, 0, 0);
				return;
			}
			var to = child.value, via:Int64 = 0, v = 0;
			if (to == 0) to = root;
			while (to != (0 : Int64)) {
				via = proxyFor(to);
				var aware = X11Window.sourceProperty(via, X11Window.XdndAware);
				if (aware != null && aware.type == X.XA_ATOM && aware.format == 32 && aware.bytes.length >= 8) {
					v = aware.bytes.getInt32(0);
					if (v >= 3) break;
				}
				if (Xlib.XTranslateCoordinates(d, root, to, rx.value, ry.value, x, y, child) == 0 || to == root) break;
				to = child.value;
			}
			if (v < 3) changeTarget(0, 0, 0) else changeTarget(to, via, v < 5 ? v : 5);
			position = {x: rx.value, y: ry.value, time: time, action: requested(state)};
			sendPosition();
		}));
	}

	static function proxyFor(to:Int64):Int64 {
		var proxy = proxyProperty(to);
		return proxy != (0 : Int64) && proxyProperty(proxy) == proxy ? proxy : to;
	}

	static function proxyProperty(to:Int64):Int64 {
		var p = X11Window.sourceProperty(to, X11Window.XdndProxy);
		return p != null && p.type == X.XA_WINDOW && p.format == 32 && p.bytes.length == 8 ? p.bytes.getInt64(0) : 0;
	}

	function changeTarget(to:Int64, via:Int64, v:Int) {
		if (target == to && proxy == via) return;
		if (target != (0 : Int64)) message(X11Window.XdndLeave, 0, 0, 0, 0);
		target = to;
		proxy = via;
		version = v;
		statusPending = false;
		accepted = None;
		if (target != (0 : Int64)) message(X11Window.XdndEnter, version << 24, X11Window.URI_LIST, 0, 0);
	}

	function sendPosition() {
		if (target == 0 || statusPending || position == sent) return;
		var p = position;
		sent = p;
		statusPending = true;
		message(X11Window.XdndPosition, 0, (p.x << 16) | (p.y & 0xFFFF), p.time, action(p.action));
	}

	function message(type:Int64, b:Int64, c:Int64, d:Int64, e:Int64)
		X11Window.sendMessage(proxy, target, type, window.id, b, c, d, e, 0);

	public function clientMessage(m:Ptr<XClientMessageEvent>):Bool {
		var type = m.value.message_type, raw:Ptr<UInt8> = cast m, l:Ptr<Int64> = cast raw.add(56);
		if (type == X11Window.XdndStatus) {
			if (l[0] == target && statusPending && !dropped) {
				statusPending = false;
				accepted = l[1].toInt() & 1 != 0 ? operation(l[4]) : None;
				if (releaseTime != null) dropIfAccepted() else trapWindowErrors(sendPosition);
			}
			return true;
		}
		if (type == X11Window.XdndFinished) {
			if (l[0] == target && dropped) {
				var op = version < 5 ? accepted : l[1].toInt() & 1 != 0 ? operation(l[2]) : None;
				finish(op);
			}
			return true;
		}
		return false;
	}

	public function input(type:Int, event:Ptr<XKeyEvent>):Bool {
		if (releaseTime != null) return type == X.ButtonRelease && event.value.keycode == button;
		switch type {
			case X.MotionNotify:
				move(event.value.time, event.value.state);
				return true;
			case X.ButtonRelease if (event.value.keycode == button):
				releaseTime = event.value.time;
				ungrab();
				deadline = haxe.Timer.stamp() + 1; // the last XdndStatus may still be on its way
				if (!statusPending) dropIfAccepted();
				return true;
			case X.KeyPress | X.KeyRelease:
				var key = Xlib.XLookupKeysym(event, 0).toInt();
				if (type == X.KeyPress && key == 0xFF1B) finish(None) else {
					var bit = switch key {
						case 0xFFE1 | 0xFFE2: 1; // Shift
						case 0xFFE3 | 0xFFE4: 4; // Control
						case _: 0;
					};
					if (bit != 0) move(event.value.time, type == X.KeyPress ? event.value.state | bit : event.value.state & ~bit);
				}
				return true;
			case X.ButtonPress | X.ButtonRelease:
				return true;
			case _:
				return false;
		}
	}

	function dropIfAccepted() {
		if (accepted == None) {
			finish(None);
			return;
		}
		dropped = true;
		deadline = haxe.Timer.stamp() + 5;
		trapWindowErrors(() -> message(X11Window.XdndDrop, 0, releaseTime, 0, 0));
	}

	public function answer(r:Ptr<XSelectionRequestEvent>) {
		trapWindowErrors(() -> Arena.scoped(a -> {
			var property = r.value.property == 0 ? r.value.target : r.value.property, ok = true;
			if (r.value.target == X11Window.URI_LIST) {
				X11Window.sendSelectionBytes(a, r.value.requestor, property, r.value.target, bytes);
			} else if (r.value.target == X11Window.TARGETS) {
				var atoms:Ptr<Int64> = a.alloc(16);
				atoms[0] = X11Window.TARGETS;
				atoms[1] = X11Window.URI_LIST;
				Xlib.XChangeProperty(X11Window.display, r.value.requestor, property, X.XA_ATOM, 32, X.PropModeReplace, atoms, 2);
			} else ok = false;
			X11Window.notifySelection(a, r, ok ? property : 0);
		}));
	}

	function ungrab() {
		var d = X11Window.display;
		Xlib.XUngrabPointer(d, 0);
		Xlib.XUngrabKeyboard(d, 0);
		Xlib.XFreeCursor(d, cursor);
	}

	public function tick() {
		if (deadline > 0 && haxe.Timer.stamp() >= deadline) finish(None);
	}

	public function waitTime(seconds:Float):Float
		return deadline > 0 ? Math.min(seconds, Math.max(0, deadline - haxe.Timer.stamp())) : seconds;

	public function finish(op:DragOperation) {
		active = null;
		var d = X11Window.display;
		if (releaseTime == null) ungrab();
		if (target != (0 : Int64) && !dropped) trapWindowErrors(() -> message(X11Window.XdndLeave, 0, 0, 0, 0));
		if (Xlib.XGetSelectionOwner(d, X11Window.XdndSelection) == window.id) Xlib.XSetSelectionOwner(d, X11Window.XdndSelection, 0, 0);
		Xlib.XFlush(d);
		done(op);
	}

	// The window under the pointer can be destroyed by another client at
	// any time. Only BadWindow from these requests is expected.
	static var previousHandler = Ptr.nil();
	static var firstRequest:Int64 = 0;

	static function trapWindowErrors(f:Void->Void) {
		var d = X11Window.display;
		Xlib.XLockDisplay(d);
		firstRequest = Xlib.XNextRequest(d);
		previousHandler = Xlib.XSetErrorHandler(Callback.addr(windowError));
		f();
		Xlib.XSync(d, 0);
		Xlib.XSetErrorHandler(previousHandler);
		Xlib.XUnlockDisplay(d);
	}

	@:hxmc.callback static function windowError(d:Ptr, event:Ptr<XErrorEvent>):Int {
		if (d == X11Window.display && event.value.serial >= firstRequest && event.value.error_code == 3) return 0; // BadWindow
		return previousHandler.isNull() ? 0 : callErrorHandler(previousHandler, d, event);
	}

	@:hxmc.indirect static extern function callErrorHandler(fn:Ptr, d:Ptr, event:Ptr<XErrorEvent>):Int;
}

private typedef DragPosition = {
	final x:Int;
	final y:Int;
	final time:Int64;
	final action:DragOperation;
}
