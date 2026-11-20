package helder.os.locale;

import helder.os.web.CanvasWindow;
import helder.os.web.Dom;
import hxmc.unsafe.*;

@:hxmc.unsafe(gc)
class LocaleWeb {
	static var changed:Void->Void;

	public static function preferred():Array<String> {
		var handle = Dom.locale_languages();
		return handle == 0 ? LocaleFallback.preferred(Sys.getEnv) : CanvasWindow.take(handle).split(":");
	}

	public static function number(value:Float, tag:String, decimals:Int, percent:Bool, currency:Null<String>):Null<String> {
		var handle = Arena.scopedValue(a -> Dom.locale_number(value, a.cstring(tag), decimals, percent ? 1 : 0, currency == null ? Ptr.nil() : a.cstring(currency)));
		return handle == 0 ? null : CanvasWindow.take(handle);
	}

	public static function date(value:Float, tag:String, date:Int, time:Int):Null<String> {
		var handle = Arena.scopedValue(a -> Dom.locale_date(value, a.cstring(tag), date, time));
		return handle == 0 ? null : CanvasWindow.take(handle);
	}

	public static function watch(refresh:Void->Void) {
		changed = refresh;
		Dom.locale_watch(Callback.addr(languageChanged));
	}

	@:hxmc.callback static function languageChanged():Void
		changed();
}
