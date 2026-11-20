package helder.os.locale;

class LocaleFallback {
	public static function environment(category:String, read:String->Null<String>):Null<String> {
		for (key in ["LC_ALL", category, "LANG"]) {
			var value = read(key);
			if (value != null && value != "") return value;
		}
		return null;
	}

	public static function preferred(read:String->Null<String>):Array<String> {
		var messages = environment("LC_MESSAGES", read);
		var languages = read("LANGUAGE");
		var tags = (messages == null || LocaleTag.normalize(messages) != null) && languages != null ? languages.split(":") : [];
		if (messages != null) tags.push(messages);
		return tags;
	}

	public static function number(value:Float, decimals:Int, percent:Bool, currency:Null<String>):String {
		if (Math.isNaN(value)) return "NaN";
		if (!Math.isFinite(value)) return value < 0 ? "-∞" : "∞";
		var precision = decimals < 0 ? (currency != null ? 2 : percent ? 0 : 3) : decimals;
		var parts = Decimal.rounded(value, precision, decimals >= 0 || currency != null, percent).split(".");
		var whole = parts[0], start = whole.charAt(0) == "-" ? 1 : 0;
		var out = new StringBuf();
		if (start != 0) out.add("-");
		if (currency != null) out.add(currency + " ");
		for (i in start...whole.length) {
			if (i > start && (whole.length - i) % 3 == 0) out.add(",");
			out.add(whole.charAt(i));
		}
		if (parts.length > 1) out.add("." + parts[1]);
		if (percent) out.add("%");
		return out.toString();
	}

	public static function date(d:Date, date:Int, time:Int):String {
		var parts = [];
		if (date != 0) parts.push(d.getFullYear() + "-" + two(d.getMonth() + 1) + "-" + two(d.getDate()));
		if (time != 0) parts.push(two(d.getHours()) + ":" + two(d.getMinutes()) + (time == 1 ? "" : ":" + two(d.getSeconds())));
		return parts.join(" ");
	}

	static function two(n:Int):String
		return StringTools.lpad(Std.string(n), "0", 2);
}
