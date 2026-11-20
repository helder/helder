package helder.os.android;

import hxmc.unsafe.*;

// The status bar's icons and whether it shows (helder.os.StatusBar), on the
// main thread: WindowInsetsController's appearance (light bars: dark
// icons) and statusBars() hidden or shown (API 30), else the decor view's
// SYSTEM_UI_FLAG_LIGHT_STATUS_BAR, _LIGHT_NAVIGATION_BAR and _FULLSCREEN.
@:hxmc.android
@:hxmc.unsafe(gc)
class AndroidStatusBar {
	// light: light icons (over a dark app)
	public static function set(light:Bool, hidden:Bool)
		MainThread.post(() -> try {
			if (Activity.activity.isNull()) return;
			var win = Jni.obj(Jni.activity, Jni.method(Jni.cls("android.app.Activity"), "getWindow", "()Landroid/view/Window;"));
			var wc = Jni.cls("android.view.Window");
			if (AndroidPermissions.sdk() >= 30) {
				var ctl = Jni.obj(win, Jni.method(wc, "getInsetsController", "()Landroid/view/WindowInsetsController;"));
				var ic = Jni.cls("android.view.WindowInsetsController"), t = Jni.cls("android.view.WindowInsets$Type");
				// (APPEARANCE_LIGHT_STATUS_BARS | APPEARANCE_LIGHT_NAVIGATION_BARS)
				Jni.call(ctl, Jni.method(ic, "setSystemBarsAppearance", "(II)V"), light ? 0 : 24, 24);
				var bars = Jni.staticInt(t, Jni.staticMethod(t, "statusBars", "()I"));
				Jni.call(ctl, Jni.method(ic, hidden ? "hide" : "show", "(I)V"), bars);
			} else {
				var view = Jni.cls("android.view.View");
				var decor = Jni.obj(win, Jni.method(wc, "getDecorView", "()Landroid/view/View;"));
				var v = Jni.int(decor, Jni.method(view, "getSystemUiVisibility", "()I"));
				v = light ? v & ~0x2010 : v | 0x2010;
				v = hidden ? v | 4 : v & ~4;
				Jni.call(decor, Jni.method(view, "setSystemUiVisibility", "(I)V"), v);
			}
		} catch (e:Dynamic) Sys.println("helder.os: StatusBar: " + Std.string(e)));
}
