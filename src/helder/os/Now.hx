package helder.os;

// What a screen's clock is (a preview host's: helder.ui.ScreenContext sets
// these while it is current, a scenario's time and zone; null: the system's).
// TypeScript's Date reads its instant and zone, its timers run on its clock.
class Now {
	// the wall clock (ms since 1970)
	public static var get:Null<Void->Float> = null;
	// the time zone: minutes east of UTC, fixed (a scenario's zone)
	public static var zone:Null<Int> = null;
	// f after ms of the screen's virtual clock; what cancels it
	public static var after:Null<(Float, Void->Void)->(Void->Void)> = null;

	// the wall clock now (ms since 1970): the screen's, else the system's
	// (Haxe's Date.now is hxmc's runtime's and reads the system's: read this)
	public static function time():Float {
		var g = get;
		return g != null ? g() : Date.now().getTime();
	}

	// local time minus UTC at instant t (ms since 1970), in ms: the screen's
	// zone, else the system's
	public static function offset(t:Float):Float {
		var z = zone;
		return z != null ? z * 60000.0 : system(t);
	}

	// the system's local time minus UTC at instant t, in ms
	public static function system(t:Float):Float {
		if (!Math.isFinite(t)) return 0;
		var clamped = Math.max(-8.64e15, Math.min(t, 8.64e15));
		return -Date.fromTime(clamped).getTimezoneOffset() * 60000.0;
	}

	// a zone as written: "UTC", "Z" or a fixed offset ("+05:30", "-08:00");
	// null when it is none of these (a named zone has rules of its own,
	// which helder does not carry: its offsets would differ by the machine's
	// tz data)
	public static function parseZone(s:String):Null<Int> {
		if (s == "UTC" || s == "Z" || s == "GMT") return 0;
		var re = ~/^([+-])(\d\d):?(\d\d)$/;
		if (!re.match(s)) return null;
		var m = Std.parseInt(re.matched(2)) * 60 + Std.parseInt(re.matched(3));
		if (m > 14 * 60) return null;
		return re.matched(1) == "-" ? -m : m;
	}
}
