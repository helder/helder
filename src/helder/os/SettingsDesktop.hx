package helder.os;

import helder.os.Settings.SettingsValues;
import helder.os.win32.User32;
import hxmc.Platform;
import hxmc.unsafe.*;

@:hxmc.unsafe(gc)
class SettingsDesktop {
	public static function windows(v:SettingsValues) {
		Arena.scoped(a -> {
			var data:Ptr<Int32> = a.alloc(4), size:Ptr<Int32> = a.alloc(4);
			size.value = 4;
			var hkcu = Ptr.ofI64(haxe.Int64.make(0xFFFFFFFF, 0x80000001));
			if (Advapi32.RegGetValueW(hkcu, a.wstring("Software\\Microsoft\\Accessibility"), a.wstring("TextScaleFactor"), 0x10,
				Ptr.nil(), data, size) == 0 && data.value > 0) v.textScale = data.value / 100;
			if (User32.SystemParametersInfoW(0x1042, 0, data, 0) != 0) v.reducedMotion = data.value == 0;
			// HIGHCONTRASTW: length, flags, scheme pointer.
			var hc:Ptr<Int32> = a.alloc(16);
			hc[0] = 16;
			if (User32.SystemParametersInfoW(0x42, 16, hc, 0) != 0 && hc[1] & 1 != 0) v.contrast = More;
		});
	}

	public static function linux(v:SettingsValues) {
		if (Platform.os() == Platform.LINUX) {
			if (Platform.target() >= 2 && Platform.target() < 9) {
				var ui = GnomeSettings.interfaceSettings, access = GnomeSettings.accessibilitySettings;
				if (!ui.isNull()) {
					v.textScale = Gio.g_settings_get_double(ui, Mem.cstr("text-scaling-factor"));
					v.reducedMotion = Gio.g_settings_get_boolean(ui, Mem.cstr("enable-animations")) == 0;
				}
				if (!access.isNull() && Gio.g_settings_get_boolean(access, Mem.cstr("high-contrast")) != 0) v.contrast = More;
				if (GnomeSettings.colorScheme) {
					var scheme = Gio.g_settings_get_enum(ui, Mem.cstr("color-scheme"));
					if (scheme != 0) v.dark = scheme == 1;
				}
			}
		}
	}
}

@:hxmc.unsafe(gc)
private class GnomeSettings {
	static final loaded = Gio.load("libgio-2.0.so.0") == null;
	public static var colorScheme(default, null) = false;
	public static final interfaceSettings = open("org.gnome.desktop.interface", ["text-scaling-factor", "enable-animations"]);
	public static final accessibilitySettings = open("org.gnome.desktop.a11y.interface", ["high-contrast"]);

	static function open(name:String, keys:Array<String>):Ptr {
		if (!loaded) return Ptr.nil();
		var source = Gio.g_settings_schema_source_get_default();
		if (source.isNull()) return Ptr.nil();
		var schema = Arena.scopedValue(a -> Gio.g_settings_schema_source_lookup(source, a.cstring(name), 1));
		if (schema.isNull()) return Ptr.nil();
		var available = Arena.scopedValue(a -> Lambda.foreach(keys, k -> Gio.g_settings_schema_has_key(schema, a.cstring(k)) != 0));
		if (name == "org.gnome.desktop.interface") colorScheme = available && Gio.g_settings_schema_has_key(schema, Mem.cstr("color-scheme")) != 0;
		var settings = available ? Gio.g_settings_new_full(schema, Ptr.nil(), Ptr.nil()) : Ptr.nil();
		Gio.g_settings_schema_unref(schema);
		return settings;
	}
}

@:build(helder.os.Dl.build())
@:hxmc.unsafe(gc)
private class Gio {
	static function g_settings_schema_source_get_default():Ptr;
	static function g_settings_schema_source_lookup(source:Ptr, id:Ptr, recursive:Int):Ptr;
	static function g_settings_schema_has_key(schema:Ptr, key:Ptr):Int;
	static function g_settings_schema_unref(schema:Ptr):Void;
	static function g_settings_new_full(schema:Ptr, backend:Ptr, path:Ptr):Ptr;
	static function g_settings_get_double(settings:Ptr, key:Ptr):Float;
	static function g_settings_get_boolean(settings:Ptr, key:Ptr):Int;
	static function g_settings_get_enum(settings:Ptr, key:Ptr):Int;
}
