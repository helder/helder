package helder.os.android;

import helder.os.Settings.SettingsValues;
import hxmc.unsafe.*;

@:hxmc.android
@:hxmc.unsafe(gc)
class AndroidSettings {
	public static function read(v:SettingsValues) {
		MainThread.run(() -> {
			if (Activity.activity.isNull()) return;
			var resources = Jni.obj(Jni.activity, Jni.method(Jni.cls("android.content.Context"), "getResources", "()Landroid/content/res/Resources;"));
			var configuration = Jni.obj(resources, Jni.method(Jni.cls("android.content.res.Resources"), "getConfiguration", "()Landroid/content/res/Configuration;"));
			var cls = Jni.cls("android.content.res.Configuration");
			v.textScale = Jni.JniEnv.GetFloatField(Jni.env, configuration, Jni.field(cls, "fontScale", "F"));
			var orientation = Jni.JniEnv.GetIntField(Jni.env, configuration, Jni.field(cls, "orientation", "I"));
			if (orientation == 1 || orientation == 2) v.orientation = orientation == 1 ? Portrait : Landscape;
			var animator = Jni.cls("android.animation.ValueAnimator");
			v.reducedMotion = !Jni.staticBool(animator, Jni.staticMethod(animator, "areAnimatorsEnabled", "()Z"));
			if (Mem.getI32(Activity.activity, 48) >= 34) {
				var manager = Jni.service("uimode");
				if (!manager.isNull()) {
					var contrast = Jni.float(manager, Jni.method(Jni.cls("android.app.UiModeManager"), "getContrast", "()F"));
					v.contrast = contrast > 0 ? More : contrast < 0 ? Less : Normal;
				}
			}
		});
	}
}
