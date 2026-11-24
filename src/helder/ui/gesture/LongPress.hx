package helder.ui.gesture;

import helder.os.PointerType;

// A press held still: one pointer down for duration seconds (0.5, iOS's
// and Android's) within the slop wins its arena then, Began (x, y: where),
// so that a scroller's drag, a tap and the click under it lose it; Changed
// as it moves on (a menu's items slid over), Ended at the release,
// Cancelled when the pointer is. Moved past the slop first, it fails and
// the press is the others'. A finger or a pen (mouse: the mouse's left
// button too; a right click is the desktop's context menu). Markup:
// onLongPress.
class LongPress extends Gesture {
	public static inline var DURATION = 0.5;

	public var duration = DURATION;
	public var mouse = false;

	var timer:Null<helder.ui.ScreenContext.Timer> = null;

	override function wants(type:PointerType, button:Int):Bool
		return enabled && pointers == 0 && button == 1 && (mouse || type != Mouse);

	override function added() {
		if (pointers != 1) {
			fail();
			return;
		}
		stop();
		var n = node;
		timer = n == null || n.ui == null ? Clock.after(duration, fire) : n.ui.context.run(() -> Clock.after(duration, fire));
	}

	override function moved() {
		if (active) {
			report(Changed);
			return;
		}
		if (travel() > slop) {
			stop();
			fail();
		}
	}

	override function lifted(cancelled:Bool) {
		stop();
		if (active) report(cancelled ? Cancelled : Ended) else fail();
	}

	override function lost() {
		stop();
		if (active) report(Cancelled);
	}

	function fire() {
		timer = null;
		if (state != Possible || pointers != 1 || !accept()) return;
		report(Began);
	}

	function stop() {
		if (timer != null) timer.cancel();
		timer = null;
	}
}
