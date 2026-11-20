package helder.os.android;

import helder.os.android.Jni;
import helder.os.android.Native;
import hxmc.unsafe.*;

// Gamepads on Android: the input queue's events of a gamepad or joystick
// source (AndroidWindow hands them here once Gamepads is enabled: no UI
// keys then, nor the system's fallback, B's Back), a slot for each device.
// A pad is there once it sends something or InputDevice lists it, and
// gone when InputDevice no longer has it (asked on the main thread once a
// second). A press and release between two polls is still seen once.
@:hxmc.android @:allow(helder.os.Gamepads)
@:hxmc.unsafe(gc)
class AndroidGamepads {
	static inline var NONE = 0x7fffffff;

	// each slot's device id (InputDevice's: -1 is the virtual one, adb's input)
	static final devices = [for (_ in 0...Gamepads.MAX) NONE];
	static final keys = [for (_ in 0...Gamepads.MAX) [for (_ in 0...Gamepads.BUTTONS) false]];
	static final moved = [for (_ in 0...Gamepads.MAX) [for (_ in 0...Gamepads.BUTTONS) false]];
	static final latched = [for (_ in 0...Gamepads.MAX) [for (_ in 0...Gamepads.BUTTONS) false]];
	static final sticks = [for (_ in 0...Gamepads.MAX) [for (_ in 0...Gamepads.AXES) 0.0]];
	static final lock = new sys.thread.Mutex();
	// (the main thread's last check: every device, the pads among them)
	static var checked:Null<{all:Array<Int>, pads:Array<Int>}> = null;
	static var next = 0.0;

	static function enable() {
		AndroidWindow.padKey = key;
		AndroidWindow.padMotion = motion;
	}

	static function poll() {
		var now = haxe.Timer.stamp();
		if (now >= next) {
			next = now + 1;
			MainThread.post(check);
		}
		lock.acquire();
		var c = checked;
		checked = null;
		lock.release();
		if (c != null) {
			for (i in 0...Gamepads.MAX)
				if (devices[i] != NONE && c.all.indexOf(devices[i]) < 0) devices[i] = NONE;
			for (d in c.pads)
				slot(d);
		}
		for (i in 0...Gamepads.MAX) {
			if (Gamepads.virtual[i]) continue;
			var there = devices[i] != NONE;
			Gamepads.live[i] = there;
			for (b in 0...Gamepads.BUTTONS) {
				Gamepads.buttons[i][b] = there && (keys[i][b] || moved[i][b] || latched[i][b]);
				latched[i][b] = false;
			}
			for (a in 0...Gamepads.AXES)
				Gamepads.axes[i][a] = there ? sticks[i][a] : 0;
		}
	}

	// a device's slot, taken if it has none (-1: all four taken)
	static function slot(device:Int):Int {
		var i = devices.indexOf(device);
		if (i >= 0) return i;
		i = devices.indexOf(NONE);
		if (i < 0) return -1;
		devices[i] = device;
		for (b in 0...Gamepads.BUTTONS)
			keys[i][b] = moved[i][b] = latched[i][b] = false;
		for (a in 0...Gamepads.AXES)
			sticks[i][a] = 0;
		return i;
	}

	// a key of a pad's: whether it is one of the standard layout's
	static function key(ev:Ptr):Bool {
		if (!Activity.pad(Android.AInputEvent_getSource(ev))) return false;
		var b = button(Android.AKeyEvent_getKeyCode(ev));
		if (b < 0) return false;
		var i = slot(Android.AInputEvent_getDeviceId(ev));
		if (i < 0) return true;
		var down = Android.AKeyEvent_getAction(ev) == 0;
		keys[i][b] = down;
		if (down) latched[i][b] = true;
		return true;
	}

	// AKEYCODE_BUTTON_A..., DPAD_* as the standard layout's buttons (-1: none)
	static function button(code:Int):Int
		return switch code {
			case 96: 0;
			case 97: 1;
			case 99: 2;
			case 100: 3;
			case 102: 4;
			case 103: 5;
			case 104: 6;
			case 105: 7;
			case 109: 8;
			case 108: 9;
			case 106: 10;
			case 107: 11;
			case 19: 12;
			case 20: 13;
			case 21: 14;
			case 22: 15;
			case 110: 16;
			case _: -1;
		}

	// a pad's motion (Activity.copyPad's record): the sticks, the triggers
	// (LTRIGGER or BRAKE, RTRIGGER or GAS) and the hat as the pad
	static function motion(r:Ptr) {
		var i = slot(Mem.getI32(r, 4));
		if (i < 0) return;
		inline function at(k:Int):Float
			return Mem.getF32(r, Activity.INPUT_POINTER + k * 4);
		for (a in 0...Gamepads.AXES)
			sticks[i][a] = at(a);
		press(i, 6, Math.max(at(4), at(6)) > 0.5);
		press(i, 7, Math.max(at(5), at(7)) > 0.5);
		press(i, 12, at(9) < -0.5);
		press(i, 13, at(9) > 0.5);
		press(i, 14, at(8) < -0.5);
		press(i, 15, at(8) > 0.5);
	}

	static function press(i:Int, b:Int, down:Bool) {
		moved[i][b] = down;
		if (down) latched[i][b] = true;
	}

	// (the main thread) the devices there, and which are pads
	static function check() {
		Jni.pushFrame();
		try {
			var c = Jni.cls("android.view.InputDevice");
			var ids = Jni.staticObj(c, Jni.staticMethod(c, "getDeviceIds", "()[I"));
			var n = JniEnv.GetArrayLength(Jni.env, ids);
			var all = n == 0 ? [] : Arena.scopedValue(a -> {
				var p = a.alloc(4 * n, 4);
				JniEnv.GetIntArrayRegion(Jni.env, ids, 0, n, p);
				[for (k in 0...n) Mem.getI32(p, 4 * k)];
			});
			var get = Jni.staticMethod(c, "getDevice", "(I)Landroid/view/InputDevice;");
			var sources = Jni.method(c, "getSources", "()I"), virtual = Jni.method(c, "isVirtual", "()Z");
			var pads = all.filter(id -> {
				var d = Jni.staticObj(c, get, id);
				!d.isNull() && !Jni.bool(d, virtual) && Activity.pad(Jni.int(d, sources));
			});
			lock.acquire();
			checked = {all: all, pads: pads};
			lock.release();
		} catch (e:Dynamic) {
			Jni.popFrame();
			throw e;
		}
		Jni.popFrame();
	}
}
