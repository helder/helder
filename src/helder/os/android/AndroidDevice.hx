package helder.os.android;

import helder.os.DeviceInfo.DeviceDetails;
import hxmc.unsafe.*;

// android.os.Build's model and manufacturer, Build.VERSION's release; a
// tablet when the screen's smallest width is 600 dp or more (the system's
// own split, Configuration.smallestScreenWidthDp).
@:hxmc.android
@:hxmc.unsafe(gc)
class AndroidDevice {
	public static function info():DeviceDetails {
		var d:DeviceDetails = {model: "", manufacturer: "", os: "Android", osVersion: "", kind: Phone};
		MainThread.run(() -> try {
			var build = Jni.cls("android.os.Build");
			d.model = Jni.staticString(build, "MODEL");
			d.manufacturer = Jni.staticString(build, "MANUFACTURER");
			d.osVersion = Jni.staticString(Jni.cls("android.os.Build$VERSION"), "RELEASE");
			if (Activity.activity.isNull()) return;
			var resources = Jni.obj(Jni.activity, Jni.method(Jni.cls("android.content.Context"), "getResources", "()Landroid/content/res/Resources;"));
			var configuration = Jni.obj(resources, Jni.method(Jni.cls("android.content.res.Resources"), "getConfiguration", "()Landroid/content/res/Configuration;"));
			if (Jni.JniEnv.GetIntField(Jni.env, configuration, Jni.field(Jni.cls("android.content.res.Configuration"), "smallestScreenWidthDp", "I")) >= 600)
				d.kind = Tablet;
		} catch (e:Dynamic) Sys.println("helder.os: DeviceInfo.get: " + Std.string(e)));
		return d;
	}
}
