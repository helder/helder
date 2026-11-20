package helder.os;

import helder.os.objc.*;
import hxmc.Platform;
import hxmc.unsafe.*;

// Gamepads on macOS and iOS: GameController's controllers with an extended
// gamepad, read at each poll (a message to nil is nil: a pad gone, a
// button it lacks). GameController is loaded at the first poll
// (a program that never enables pads does not load it). A pad keeps its
// slot while it stays in GCController.controllers.
@:allow(helder.os.Gamepads)
@:hxmc.unsafe(gc)
class GamepadsApple {
	static final pads:Array<Ptr> = [for (_ in 0...Gamepads.MAX) Ptr.nil()];
	static var sels:Array<Ptr> = [];

	static function load() {
		Posix.dlopen(Mem.cstr("/System/Library/Frameworks/GameController.framework/GameController"), 1);
		// the extended gamepad's buttons in the standard order (nil: the dpad's, read apart)
		sels = [
			ObjC.sel("buttonA"), ObjC.sel("buttonB"), ObjC.sel("buttonX"), ObjC.sel("buttonY"), ObjC.sel("leftShoulder"), ObjC.sel("rightShoulder"),
			ObjC.sel("leftTrigger"), ObjC.sel("rightTrigger"), ObjC.sel("buttonOptions"), ObjC.sel("buttonMenu"), ObjC.sel("leftThumbstickButton"),
			ObjC.sel("rightThumbstickButton"), Ptr.nil(), Ptr.nil(), Ptr.nil(), Ptr.nil(), ObjC.sel("buttonHome")
		];
		// (macOS 11.3: pads read while another app's window is key)
		var c = ObjC.cls("GCController"), monitor = ObjC.sel("setShouldMonitorBackgroundEvents:");
		if (Platform.apple() == 0 && !c.isNull() && Msg.bPtr(c, ObjC.sel("respondsToSelector:"), monitor)) Msg.vBool(c, monitor, true);
	}

	static function poll() {
		if (sels.length == 0) load();
		var pool = Runtime.objc_autoreleasePoolPush();
		var list = Msg.id(ObjC.cls("GCController"), ObjC.sel("controllers"));
		var n = Msg.i(list, ObjC.sel("count")).toInt();
		for (i in 0...Gamepads.MAX)
			if (!pads[i].isNull() && !Msg.bPtr(list, ObjC.sel("containsObject:"), pads[i])) pads[i] = Ptr.nil();
		for (k in 0...n) {
			var c = Msg.idInt(list, ObjC.sel("objectAtIndex:"), k);
			if (slot(c) >= 0 || Msg.id(c, ObjC.sel("extendedGamepad")).isNull()) continue;
			var free = slot(Ptr.nil());
			if (free >= 0) pads[free] = c;
		}
		for (i in 0...Gamepads.MAX)
			if (!Gamepads.virtual[i]) read(i, Msg.id(pads[i], ObjC.sel("extendedGamepad")));
		Runtime.objc_autoreleasePoolPop(pool);
	}

	static function slot(c:Ptr):Int {
		for (i in 0...Gamepads.MAX)
			if (pads[i] == c) return i;
		return -1;
	}

	static function read(i:Int, g:Ptr) {
		var buttons = Gamepads.buttons[i], axes = Gamepads.axes[i];
		Gamepads.live[i] = !g.isNull();
		for (b in 0...Gamepads.BUTTONS)
			buttons[b] = !g.isNull() && !sels[b].isNull() && pressed(Msg.id(g, sels[b]), b == 6 || b == 7);
		var dpad = Msg.id(g, ObjC.sel("dpad"));
		buttons[12] = pressed(Msg.id(dpad, ObjC.sel("up")), false);
		buttons[13] = pressed(Msg.id(dpad, ObjC.sel("down")), false);
		buttons[14] = pressed(Msg.id(dpad, ObjC.sel("left")), false);
		buttons[15] = pressed(Msg.id(dpad, ObjC.sel("right")), false);
		var left = Msg.id(g, ObjC.sel("leftThumbstick")), right = Msg.id(g, ObjC.sel("rightThumbstick"));
		// (GameController's y is up, the standard layout's down)
		axes[0] = value(Msg.id(left, ObjC.sel("xAxis")));
		axes[1] = -value(Msg.id(left, ObjC.sel("yAxis")));
		axes[2] = value(Msg.id(right, ObjC.sel("xAxis")));
		axes[3] = -value(Msg.id(right, ObjC.sel("yAxis")));
	}

	// (a button missing on this pad, nil: released; a trigger past half way)
	static function pressed(button:Ptr, analog:Bool):Bool {
		if (button.isNull()) return false;
		return analog ? (Msg.f32(button, ObjC.sel("value")) : Float) > 0.5 : Msg.b(button, ObjC.sel("isPressed"));
	}

	static function value(axis:Ptr):Float
		return axis.isNull() ? 0 : Msg.f32(axis, ObjC.sel("value"));
}
