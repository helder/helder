package helder.os.android;

import helder.os.android.Jni;
import hxmc.unsafe.*;

// A drag's glide by Android's own physics (helder.ui's TouchScroll on
// Android, UiWindow's native scrolling): the drag's speed a
// VelocityTracker's (the moves as MotionEvents, in pixels), a fling past
// ViewConfiguration's least speed (capped at its most) an OverScroller's
// (its spline, its friction, the screen's density), stepped each frame
// (computeScrollOffset: the system's clock). The calls are the program
// thread's own JNIEnv (the thread is attached for good: Activity's
// programThread), the framework's classes global references. Where any
// of it fails, helder's own glide (Glide's).
@:hxmc.android
@:hxmc.unsafe(gc)
class AndroidGlide extends Glide {
	static var ready = false;
	static var ok = false;
	static var env = Ptr.nil();
	static var args = Ptr.nil();
	static var density = 1.0;
	static var minFling = 50.0;
	static var maxFling = 8000.0;
	static var motionEvent = Ptr.nil();
	static var obtainEvent = Ptr.nil();
	static var recycle = Ptr.nil();
	static var addMovement = Ptr.nil();
	static var clear = Ptr.nil();
	static var computeVelocity = Ptr.nil();
	static var xVelocity = Ptr.nil();
	static var yVelocity = Ptr.nil();
	static var fling = Ptr.nil();
	static var compute = Ptr.nil();
	static var currX = Ptr.nil();
	static var currY = Ptr.nil();
	static var finish = Ptr.nil();

	var tracker = Ptr.nil();
	var scroller = Ptr.nil();
	// the finger where the scroll put it (pixels), the drag's start and last move (ms)
	var px = 0.0;
	var py = 0.0;
	var downAt = 0.0;
	var movedAt = 0.0;
	var flinging = false;
	var lastX = 0;
	var lastY = 0;

	public function new() {
		super();
		if (!ready) init();
		if (!ok) return;
		var vt = cls("android/view/VelocityTracker");
		tracker = keep(JniEnv.CallStaticObjectMethodA(env, vt, JniEnv.GetStaticMethodID(env, vt, Mem.cstr("obtain"), Mem.cstr("()Landroid/view/VelocityTracker;")), args));
		var os = cls("android/widget/OverScroller");
		scroller = keep(JniEnv.NewObjectA(env, os, JniEnv.GetMethodID(env, os, Mem.cstr("<init>"), Mem.cstr("(Landroid/content/Context;)V")), set1(Jni.activity.toI64())));
		if (tracker.isNull() || scroller.isNull()) ok = false;
	}

	static function init() {
		ready = true;
		var a = Activity.activity;
		if (a.isNull()) return;
		var out:Ptr<Ptr> = LibC.malloc(8);
		if (JavaVm.GetEnv(Mem.getPtr(a, 8), out, 0x10006) != 0) return;
		env = out.value;
		args = LibC.malloc(128);
		var ctx = Jni.activity;
		// (the screen's density, ViewConfiguration's fling speeds: pixels a second)
		var res = JniEnv.CallObjectMethodA(env, ctx, method("android/content/Context", "getResources", "()Landroid/content/res/Resources;"), args);
		if (failed() || res.isNull()) return;
		var dm = JniEnv.CallObjectMethodA(env, res, method("android/content/res/Resources", "getDisplayMetrics", "()Landroid/util/DisplayMetrics;"), args);
		if (failed() || dm.isNull()) return;
		var dmc = cls("android/util/DisplayMetrics");
		density = JniEnv.GetFloatField(env, dm, JniEnv.GetFieldID(env, dmc, Mem.cstr("density"), Mem.cstr("F")));
		if (density <= 0) density = 1;
		var vcc = cls("android/view/ViewConfiguration");
		var vc = JniEnv.CallStaticObjectMethodA(env, vcc, JniEnv.GetStaticMethodID(env, vcc, Mem.cstr("get"), Mem.cstr("(Landroid/content/Context;)Landroid/view/ViewConfiguration;")),
			set1(ctx.toI64()));
		if (failed() || vc.isNull()) return;
		minFling = JniEnv.CallIntMethodA(env, vc, method("android/view/ViewConfiguration", "getScaledMinimumFlingVelocity", "()I"), args);
		maxFling = JniEnv.CallIntMethodA(env, vc, method("android/view/ViewConfiguration", "getScaledMaximumFlingVelocity", "()I"), args);
		motionEvent = cls("android/view/MotionEvent");
		obtainEvent = JniEnv.GetStaticMethodID(env, motionEvent, Mem.cstr("obtain"), Mem.cstr("(JJIFFI)Landroid/view/MotionEvent;"));
		recycle = method("android/view/MotionEvent", "recycle", "()V");
		addMovement = method("android/view/VelocityTracker", "addMovement", "(Landroid/view/MotionEvent;)V");
		clear = method("android/view/VelocityTracker", "clear", "()V");
		computeVelocity = method("android/view/VelocityTracker", "computeCurrentVelocity", "(IF)V");
		xVelocity = method("android/view/VelocityTracker", "getXVelocity", "()F");
		yVelocity = method("android/view/VelocityTracker", "getYVelocity", "()F");
		fling = method("android/widget/OverScroller", "fling", "(IIIIIIII)V");
		compute = method("android/widget/OverScroller", "computeScrollOffset", "()Z");
		currX = method("android/widget/OverScroller", "getCurrX", "()I");
		currY = method("android/widget/OverScroller", "getCurrY", "()I");
		finish = method("android/widget/OverScroller", "forceFinished", "(Z)V");
		ok = !failed();
	}

	// (a framework class, a global reference)
	static function cls(name:String):Ptr {
		var c = Arena.scopedValue(a -> JniEnv.FindClass(env, a.cstring(name)));
		if (failed() || c.isNull()) return Ptr.nil();
		return JniEnv.NewGlobalRef(env, c);
	}

	static function method(c:String, name:String, sig:String):Ptr {
		var k = cls(c);
		var m = Arena.scopedValue(a -> JniEnv.GetMethodID(env, k, a.cstring(name), a.cstring(sig)));
		failed();
		return m;
	}

	static function keep(o:Ptr):Ptr {
		if (failed() || o.isNull()) return Ptr.nil();
		return JniEnv.NewGlobalRef(env, o);
	}

	// (a Java exception: described in logcat, cleared, and this glide helder's own)
	static function failed():Bool {
		if (JniEnv.ExceptionCheck(env) == 0) return false;
		JniEnv.ExceptionDescribe(env);
		JniEnv.ExceptionClear(env);
		ok = false;
		return true;
	}

	static function set1(a:Int64):Ptr {
		Mem.setI64(args, 0, a);
		return args;
	}

	// (a jfloat's bits in the low half)
	static function f(x:Float):Int64 {
		var p = args.add(120);
		Mem.setI64(p, 0, 0);
		Mem.setF32(p, 0, x);
		return Mem.getI64(p, 0);
	}

	// the finger's position now (ACTION_DOWN 0, UP 1, MOVE 2) to the tracker
	function track(action:Int, time:Float) {
		var x = f(px), y = f(py);
		Mem.setI64(args, 0, Std.int(downAt));
		Mem.setI64(args, 8, Std.int(time));
		Mem.setI64(args, 16, action);
		Mem.setI64(args, 24, x);
		Mem.setI64(args, 32, y);
		Mem.setI64(args, 40, 0);
		var e = JniEnv.CallStaticObjectMethodA(env, motionEvent, obtainEvent, args);
		if (failed() || e.isNull()) return;
		JniEnv.CallVoidMethodA(env, tracker, addMovement, set1(e.toI64()));
		failed();
		JniEnv.CallVoidMethodA(env, e, recycle, args);
		JniEnv.DeleteLocalRef(env, e);
		failed();
	}

	override function get_gliding():Bool
		return ok ? flinging : super.get_gliding();

	override public function start(time:Float) {
		if (!ok) return super.start(time);
		stop();
		JniEnv.CallVoidMethodA(env, tracker, clear, args);
		if (failed()) return super.start(time);
		px = py = 0;
		downAt = movedAt = time;
		track(0, time);
	}

	override public function move(dx:Float, dy:Float, time:Float) {
		super.move(dx, dy, time);
		if (!ok) return;
		// (the content follows the finger: the finger moved the other way, in pixels)
		px -= dx * density;
		py -= dy * density;
		movedAt = time;
		track(2, time);
	}

	override public function release(time:Float):Bool {
		if (!ok) return super.release(time);
		track(1, time);
		Mem.setI64(args, 0, 1000);
		Mem.setI64(args, 8, f(maxFling));
		JniEnv.CallVoidMethodA(env, tracker, computeVelocity, args);
		if (failed()) return super.release(time);
		var vx:Float = JniEnv.CallFloatMethodA(env, tracker, xVelocity, args), vy:Float = JniEnv.CallFloatMethodA(env, tracker, yVelocity, args);
		if (failed()) return super.release(time);
		// (under the least fling speed on both axes: none, as a view's)
		if (Math.abs(vx) < minFling && Math.abs(vy) < minFling) return false;
		var big = 1 << 30;
		for (i => v in [0, 0, Std.int(-vx), Std.int(-vy), -big, big, -big, big])
			Mem.setI64(args, i * 8, v);
		JniEnv.CallVoidMethodA(env, scroller, fling, args);
		if (failed()) return super.release(time);
		lastX = lastY = 0;
		flinging = true;
		return true;
	}

	override public function step(now:Float):Bool {
		if (!ok) return super.step(now);
		if (!flinging) return false;
		var going = JniEnv.CallBooleanMethodA(env, scroller, compute, args) & 0xff != 0;
		if (failed() || !going) {
			flinging = false;
			return false;
		}
		var cx = JniEnv.CallIntMethodA(env, scroller, currX, args), cy = JniEnv.CallIntMethodA(env, scroller, currY, args);
		if (failed()) {
			flinging = false;
			return false;
		}
		var sx = (cx - lastX) / density, sy = (cy - lastY) / density;
		lastX = cx;
		lastY = cy;
		if (sx == 0 && sy == 0) return false;
		dx = sx;
		dy = sy;
		return true;
	}

	override public function stop() {
		super.stop();
		if (!ok || !flinging) return;
		flinging = false;
		JniEnv.CallVoidMethodA(env, scroller, finish, set1(1));
		failed();
	}
}
