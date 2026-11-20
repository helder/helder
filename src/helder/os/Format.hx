package helder.os;

import helder.os.locale.*;

#if (target.name == "hxmc")
import hxmc.Platform;
#end

enum abstract Style(String) to String {
	var Short = "short";
	var Medium = "medium";
	var Long = "long";
	var Full = "full";
}

typedef NumberOptions = {
	var ?decimals:Int;
	var ?percent:Bool;
	var ?currency:String;
	var ?locale:String;
}

typedef DateOptions = {
	var ?date:Style;
	var ?time:Style;
	var ?locale:String;
}

class Format {
	public static function number(x:Float, ?options:NumberOptions):String {
		var tag = LocaleTag.normalize(options?.locale) ?? Locale.current.peek();
		var given = options?.decimals, decimals = given == null ? -1 : given < 0 ? 0 : given > 20 ? 20 : given;
		var currency = options?.currency?.toUpperCase(), percent = currency == null && options?.percent == true;
		var result:Null<String> = null;
		#if (target.name == "hxmc")
		if (Platform.os() == Platform.WASI) {
			result = LocaleWeb.number(x, tag, decimals, percent, currency);
		} else if (Platform.os() == Platform.WINDOWS) {
			result = WindowsLocale.number(x, tag, decimals, percent, currency);
		} else if (Platform.os() == Platform.MACOS) {
			#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64" || hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64")
			result = AppleLocale.number(x, tag, decimals, percent, currency);
			#end
		} else if (Platform.target() >= 9) {
			result = helder.os.android.AndroidLocale.number(x, tag, decimals, percent, currency);
		}
		#elseif js
		var opts:Dynamic = currency != null ? {style: "currency", currency: currency} : percent ? {style: "percent"} : {};
		if (decimals >= 0) opts.minimumFractionDigits = opts.maximumFractionDigits = decimals;
		result = try js.Syntax.code("new Intl.NumberFormat({0}, {1}).format({2})", tag, opts, x) catch (_:Dynamic) null;
		#end
		return result ?? LocaleFallback.number(x, decimals, percent, currency);
	}

	public static function date(@:typescript.type("Date") d:Date, ?options:DateOptions):String {
		var milliseconds = d.getTime();
		if (!Math.isFinite(milliseconds) || Math.abs(milliseconds) > 8640000000000000.0) return "";
		var tag = LocaleTag.normalize(options?.locale) ?? Locale.current.peek();
		var date = options?.date ?? (options?.time == null ? Medium : null), time = options?.time;
		var result:Null<String> = null;
		#if (target.name == "hxmc")
		var ds = style(date), ts = style(time);
		if (Platform.os() == Platform.WASI) {
			result = LocaleWeb.date(milliseconds, tag, ds, ts);
		} else if (Platform.os() == Platform.WINDOWS) {
			result = WindowsLocale.date(milliseconds, tag, ds, ts);
		} else if (Platform.os() == Platform.MACOS) {
			#if (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64" || hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64")
			result = AppleLocale.date(milliseconds, tag, ds, ts);
			#end
		} else if (Platform.target() >= 9) {
			result = helder.os.android.AndroidLocale.date(milliseconds, tag, ds, ts);
		}
		#elseif js
		var opts:Dynamic = {};
		if (date != null) opts.dateStyle = date;
		if (time != null) opts.timeStyle = time;
		result = try js.Syntax.code("new Intl.DateTimeFormat({0}, {1}).format({2})", tag, opts, milliseconds) catch (_:Dynamic) null;
		#end
		return result ?? LocaleFallback.date(d, style(date), style(time));
	}

	static function style(value:Null<Style>):Int
		return switch value {
			case Short: 1;
			case Medium: 2;
			case Long: 3;
			case Full: 4;
			case _: 0;
		};
}
