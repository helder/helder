package helder.os.android;

import hxmc.unsafe.*;

@:hxmc.android
@:hxmc.unsafe(gc)
class AndroidLocale {
	public static function preferred():Array<String>
		return read([], () -> {
			var cls = Jni.cls("android.os.LocaleList");
			var list = Jni.staticObj(cls, Jni.staticMethod(cls, "getDefault", "()Landroid/os/LocaleList;"));
			var n = Jni.int(list, Jni.method(cls, "size", "()I"));
			var get = Jni.method(cls, "get", "(I)Ljava/util/Locale;");
			var tag = Jni.method(Jni.cls("java.util.Locale"), "toLanguageTag", "()Ljava/lang/String;");
			var values = [];
			for (i in 0...n) {
				var locale = Jni.obj(list, get, i), text = Jni.obj(locale, tag);
				values.push(Jni.fromString(text));
				Jni.deleteLocal(text);
				Jni.deleteLocal(locale);
			}
			return values;
		});

	public static function number(value:Float, tag:String, decimals:Int, percent:Bool, currency:Null<String>):Null<String>
		return read(null, () -> {
			var cls = Jni.cls("java.text.NumberFormat");
			var method = currency != null ? "getCurrencyInstance" : percent ? "getPercentInstance" : "getNumberInstance";
			var f = Jni.staticObj(cls, Jni.staticMethod(cls, method, "(Ljava/util/Locale;)Ljava/text/NumberFormat;"), locale(tag).toI64());
			var digits = decimals;
			if (currency != null) {
				var c = Jni.cls("java.util.Currency");
				var unit = Jni.staticObj(c, Jni.staticMethod(c, "getInstance", "(Ljava/lang/String;)Ljava/util/Currency;"), Jni.string(currency).toI64());
				Jni.call(f, Jni.method(cls, "setCurrency", "(Ljava/util/Currency;)V"), unit.toI64());
				if (digits < 0) digits = Jni.int(unit, Jni.method(c, "getDefaultFractionDigits", "()I"));
			}
			if (digits >= 0) {
				Jni.call(f, Jni.method(cls, "setMinimumFractionDigits", "(I)V"), digits);
				Jni.call(f, Jni.method(cls, "setMaximumFractionDigits", "(I)V"), digits);
			}
			return Jni.fromString(Jni.obj(f, Jni.method(cls, "format", "(D)Ljava/lang/String;"), haxe.io.FPHelper.doubleToI64(value)));
		});

	public static function date(milliseconds:Float, tag:String, date:Int, time:Int):Null<String>
		return read(null, () -> {
			var cls = Jni.cls("java.text.DateFormat"), l = locale(tag);
			var ds:hxmc.unsafe.Int64 = 4 - date, ts:hxmc.unsafe.Int64 = 4 - time;
			var selected = date != 0 ? ds : ts;
			var f = date != 0 && time != 0
				? Jni.staticObj(cls, Jni.staticMethod(cls, "getDateTimeInstance", "(IILjava/util/Locale;)Ljava/text/DateFormat;"), ds, ts, l.toI64())
				: Jni.staticObj(cls, Jni.staticMethod(cls, date != 0 ? "getDateInstance" : "getTimeInstance", "(ILjava/util/Locale;)Ljava/text/DateFormat;"),
					selected, l.toI64());
			var d = Jni.cls("java.util.Date");
			var value = Jni.newObject(d, Jni.method(d, "<init>", "(J)V"), haxe.Int64.fromFloat(milliseconds));
			return Jni.fromString(Jni.obj(f, Jni.method(cls, "format", "(Ljava/util/Date;)Ljava/lang/String;"), value.toI64()));
		});

	static function locale(tag:String):Ptr {
		var cls = Jni.cls("java.util.Locale");
		return Jni.staticObj(cls, Jni.staticMethod(cls, "forLanguageTag", "(Ljava/lang/String;)Ljava/util/Locale;"), Jni.string(tag).toI64());
	}

	static function read<T>(fallback:T, fn:Void->T):T {
		if (Activity.activity.isNull()) return fallback;
		var value = fallback;
		MainThread.run(() -> {
			Jni.pushFrame();
			try value = fn() catch (error:Dynamic) {
				Jni.popFrame();
				throw error;
			}
			Jni.popFrame();
		});
		return value;
	}
}
