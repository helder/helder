package helder.os;

import helder.os.objc.*;
import helder.os.Settings.SettingsValues;

@:hxmc.unsafe(gc)
class SettingsApple {
	public static function mac(v:SettingsValues) {
		helder.os.OsThread.run(() -> {
			var pool = Runtime.objc_autoreleasePoolPush();
			var w = Msg.id(ObjC.cls("NSWorkspace"), ObjC.sel("sharedWorkspace"));
			v.reducedMotion = Msg.b(w, ObjC.sel("accessibilityDisplayShouldReduceMotion"));
			v.contrast = Msg.b(w, ObjC.sel("accessibilityDisplayShouldIncreaseContrast")) ? More : Normal;
			Runtime.objc_autoreleasePoolPop(pool);
		});
	}

	public static function ios(v:SettingsValues) {
		var pool = Runtime.objc_autoreleasePoolPush();
		var controller = helder.os.uikit.UIKitWindow.controllerNow();
		var traits = Msg.id(controller, ObjC.sel("traitCollection"));
		if (!traits.isNull()) v.dark = Msg.i(traits, ObjC.sel("userInterfaceStyle")) == 2;
		var app = Msg.id(ObjC.cls("UIApplication"), ObjC.sel("sharedApplication"));
		var category = Msg.id(app, ObjC.sel("preferredContentSizeCategory"));
		// Use the application's category outside UIKit's own trait callbacks.
		var sizes = Msg.idPtr(ObjC.cls("UITraitCollection"), ObjC.sel("traitCollectionWithPreferredContentSizeCategory:"), category);
		v.textScale = Msg.fFloatPtr(Msg.id(ObjC.cls("UIFontMetrics"), ObjC.sel("defaultMetrics")),
			ObjC.sel("scaledValueForValue:compatibleWithTraitCollection:"), 17, sizes) / 17;
		v.reducedMotion = Accessibility.UIAccessibilityIsReduceMotionEnabled();
		v.contrast = Accessibility.UIAccessibilityDarkerSystemColorsEnabled() ? More : Normal;
		Runtime.objc_autoreleasePoolPop(pool);
	}
}

@:hxmc.c @:hxmc.framework("UIKit")
private extern class Accessibility {
	static function UIAccessibilityIsReduceMotionEnabled():Bool;
	static function UIAccessibilityDarkerSystemColorsEnabled():Bool;
}
