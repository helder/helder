package helder.os.locale.windows;

import helder.os.locale.LocaleTag;
import helder.os.locale.Decimal;
import hxmc.unsafe.*;

@:hxmc.unsafe(gc)
class Locale {
	public static function preferred():Array<String>
		return Arena.scopedValue(a -> {
			var count:Ptr<Int32> = a.alloc(4), size:Ptr<Int32> = a.alloc(4);
			size.value = 0;
			var tags = [];
			if (Nls.GetUserPreferredUILanguages(8, count, Ptr.nil(), size) != 0 && size.value > 1) {
				var buf:Ptr<UInt16> = a.alloc(size.value * 2);
				if (Nls.GetUserPreferredUILanguages(8, count, buf, size) != 0) {
					var start = 0;
					for (i in 0...size.value) if (buf[i] == 0) {
						if (i == start) break;
						tags.push(wide(buf.add(start * 2), i - start));
						start = i + 1;
					}
				}
			}
			if (tags.length == 0) {
				var locale = a.alloc(170);
				var n = Nls.GetUserDefaultLocaleName(locale, 85);
				if (n > 1) tags.push(wide(locale, n - 1));
			}
			tags;
		});

	public static function date(milliseconds:Float, tag:String, date:Int, time:Int):Null<String>
		return Arena.scopedValue(a -> {
			if (milliseconds < -11644473600000.0 || milliseconds > 910692730085477.0) return null;
			var ticks:Ptr<Int64> = a.alloc(8), utc = a.alloc(16), local = a.alloc(16);
			ticks.value = haxe.Int64.fromFloat(milliseconds + 11644473600000.0) * 10000;
			if (Nls.FileTimeToSystemTime(ticks, utc) == 0 || Nls.SystemTimeToTzSpecificLocalTimeEx(Ptr.nil(), utc, local) == 0) return null;
			var locale = name(a, tag), parts = [];
			if (date != 0) {
				var flags = date >= 3 ? 2 : 1;
				var text = output(a, (buf, n) -> Nls.GetDateFormatEx(locale, flags, local, Ptr.nil(), buf, n, Ptr.nil()));
				if (text == null) return null;
				parts.push(text);
			}
			if (time != 0) {
				var text = output(a, (buf, n) -> Nls.GetTimeFormatEx(locale, time == 1 ? 2 : 0, local, Ptr.nil(), buf, n));
				if (text == null) return null;
				parts.push(text);
			}
			return parts.join(" ");
		});

	public static function number(value:Float, tag:String, decimals:Int, percent:Bool, currency:Null<String>):Null<String> {
		if (!Math.isFinite(value)) return null;
		return Arena.scopedValue(a -> {
			var locale = name(a, tag), money = currency != null;
			var precision = decimals >= 0 ? decimals : percent ? 0 : money ? 2 : 3;
			var symbol = Ptr.nil();
			if (money) {
				var code = info(a, locale, 0x15);
				if (currency == code) {
					if (decimals < 0) precision = integer(a, locale, 0x19, 2);
					currency = info(a, locale, 0x14) ?? currency;
				}
				symbol = a.wstring(currency);
			}
			var text = Decimal.rounded(value, precision, decimals >= 0 || money, percent), point = text.indexOf(".");
			var decimal = info(a, locale, money ? 0x16 : 0xE), group = info(a, locale, money ? 0x17 : 0xF);
			var grouping = info(a, locale, money ? 0x18 : 0x10);
			if (decimal == null || group == null || grouping == null) return null;
			var sizes = grouping.split(";");
			if (sizes[sizes.length - 1] == "0") sizes.pop() else sizes.push("0");
			var fmt = a.alloc(money ? 48 : 40);
			Mem.setI32(fmt, 0, point < 0 ? 0 : text.length - point - 1);
			Mem.setI32(fmt, 4, integer(a, locale, 0x12, 1));
			Mem.setI32(fmt, 8, Std.parseInt(sizes.join("")) ?? 0);
			Mem.setPtr(fmt, 16, a.wstring(decimal));
			Mem.setPtr(fmt, 24, a.wstring(group));
			Mem.setI32(fmt, 32, integer(a, locale, money ? 0x1C : 0x1010, 1));
			if (money) {
				Mem.setI32(fmt, 36, integer(a, locale, 0x1B, 0));
				Mem.setPtr(fmt, 40, symbol);
			}
			var input = a.wstring(text);
			var result = output(a, (buf, n) -> money ? Nls.GetCurrencyFormatEx(locale, 0, input, fmt, buf, n) : Nls.GetNumberFormatEx(locale, 0, input, fmt, buf, n));
			if (!percent || result == null) return result;
			var mark = info(a, locale, 0x76) ?? "%";
			return switch integer(a, locale, 0x75, 1) {
				case 0: result + " " + mark;
				case 2: mark + result;
				case 3: mark + " " + result;
				case _: result + mark;
			};
		});
	}

	static function name(a:Arena, tag:String):Ptr {
		var buf = a.alloc(170);
		var original = a.wstring(LocaleTag.base(tag));
		return Nls.ResolveLocaleName(original, buf, 85) > 1 ? buf : original;
	}

	static function info(a:Arena, locale:Ptr, kind:Int):Null<String>
		return output(a, (buf, n) -> Nls.GetLocaleInfoEx(locale, kind, buf, n));

	static function integer(a:Arena, locale:Ptr, kind:Int, fallback:Int):Int {
		var buf:Ptr<Int32> = a.alloc(4);
		return Nls.GetLocaleInfoEx(locale, kind | 0x20000000, buf, 2) == 0 ? fallback : buf.value;
	}

	static function output(a:Arena, read:(Ptr, Int)->Int):Null<String> {
		var n = read(Ptr.nil(), 0);
		if (n < 1) return null;
		var buf = a.alloc(n * 2);
		n = read(buf, n);
		return n > 0 ? wide(buf, n - 1) : null;
	}

	static function wide(p:Ptr<UInt16>, n:Int):String {
		var s = hxmc.rt.Str.make2(n);
		LibC.memcpy(hxmc.rt.Str.unitsAddr(s), p, (2 * n : Int64));
		return s;
	}
}

@:hxmc.c @:hxmc.fast @:hxmc.lib("kernel32")
private extern class Nls {
	static function GetUserDefaultLocaleName(buffer:Ptr, size:Int):Int;
	static function GetUserPreferredUILanguages(flags:Int, count:Ptr, buffer:Ptr, size:Ptr):Int;
	static function ResolveLocaleName(name:Ptr, buffer:Ptr, size:Int):Int;
	static function GetLocaleInfoEx(locale:Ptr, kind:Int, buffer:Ptr, size:Int):Int;
	static function FileTimeToSystemTime(fileTime:Ptr, time:Ptr):Int;
	static function SystemTimeToTzSpecificLocalTimeEx(zone:Ptr, utc:Ptr, local:Ptr):Int;
	static function GetDateFormatEx(locale:Ptr, flags:Int, time:Ptr, format:Ptr, buffer:Ptr, size:Int, calendar:Ptr):Int;
	static function GetTimeFormatEx(locale:Ptr, flags:Int, time:Ptr, format:Ptr, buffer:Ptr, size:Int):Int;
	static function GetCurrencyFormatEx(locale:Ptr, flags:Int, number:Ptr, format:Ptr, buffer:Ptr, size:Int):Int;
	static function GetNumberFormatEx(locale:Ptr, flags:Int, number:Ptr, format:Ptr, buffer:Ptr, size:Int):Int;
}
