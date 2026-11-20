package helder.os.locale;

import helder.os.objc.Runtime;
import hxmc.objc.Id;
import hxmc.objc.Strings;
import hxmc.unsafe.Int64;

@:hxmc.unsafe(gc)
class AppleLocale {
	public static function preferred():Array<String> {
		var pool = Runtime.objc_autoreleasePoolPush();
		var list = NSLocale.preferredLanguages();
		var tags = [for (i in 0...list.count().toInt()) Strings.ofNSString(cast list.objectAtIndex(i))];
		Runtime.objc_autoreleasePoolPop(pool);
		return tags;
	}

	public static function number(value:Float, tag:String, decimals:Int, percent:Bool, currency:Null<String>):Null<String> {
		var pool = Runtime.objc_autoreleasePoolPush();
		var format = NSNumberFormatter.alloc().init();
		format.setLocale(locale(tag));
		format.setNumberStyle(currency != null ? 2 : percent ? 3 : 1);
		if (currency != null) format.setCurrencyCode(cast Strings.toNSString(currency));
		if (decimals >= 0) {
			format.setMinimumFractionDigits(decimals);
			format.setMaximumFractionDigits(decimals);
		}
		var result = Strings.ofNSString(cast format.stringFromNumber(NSNumber.numberWithDouble(value)));
		Runtime.objc_autoreleasePoolPop(pool);
		return result;
	}

	public static function date(milliseconds:Float, tag:String, date:Int, time:Int):Null<String> {
		var pool = Runtime.objc_autoreleasePoolPush();
		var format = NSDateFormatter.alloc().init();
		format.setLocale(locale(tag));
		format.setDateStyle(date);
		format.setTimeStyle(time);
		var result = Strings.ofNSString(cast format.stringFromDate(NSDate.dateWithTimeIntervalSince1970(milliseconds / 1000)));
		Runtime.objc_autoreleasePoolPop(pool);
		return result;
	}

	static function locale(tag:String):NSLocale
		return NSLocale.localeWithLocaleIdentifier(cast Strings.toNSString(tag));
}

@:hxmc.objc @:hxmc.framework("Foundation") private extern class NSLocale implements Id {
	static function preferredLanguages():NSArray;
	static function localeWithLocaleIdentifier(identifier:Id):NSLocale;
}

@:hxmc.objc @:hxmc.framework("Foundation") private extern class NSArray implements Id {
	function count():Int64;
	function objectAtIndex(i:Int64):Id;
}

@:hxmc.objc @:hxmc.framework("Foundation") private extern class NSNumber implements Id {
	static function numberWithDouble(value:Float):NSNumber;
}

@:hxmc.objc @:hxmc.framework("Foundation") private extern class NSNumberFormatter implements Id {
	static function alloc():NSNumberFormatter;
	function init():NSNumberFormatter;
	function setLocale(locale:NSLocale):Void;
	function setNumberStyle(style:Int64):Void;
	function setCurrencyCode(currency:Id):Void;
	function setMinimumFractionDigits(digits:Int64):Void;
	function setMaximumFractionDigits(digits:Int64):Void;
	function stringFromNumber(value:NSNumber):Id;
}

@:hxmc.objc @:hxmc.framework("Foundation") private extern class NSDate implements Id {
	static function dateWithTimeIntervalSince1970(seconds:Float):NSDate;
}

@:hxmc.objc @:hxmc.framework("Foundation") private extern class NSDateFormatter implements Id {
	static function alloc():NSDateFormatter;
	function init():NSDateFormatter;
	function setLocale(locale:NSLocale):Void;
	function setDateStyle(style:Int64):Void;
	function setTimeStyle(style:Int64):Void;
	function stringFromDate(value:NSDate):Id;
}
