package helder.os.locale;

class Decimal {
	public static function plain(value:Float):String {
		var text = Std.string(value), exp = text.toLowerCase().indexOf("e");
		if (exp < 0) return text;
		var sign = value < 0 ? "-" : "", start = sign.length;
		var mantissa = text.substring(start, exp), point = mantissa.indexOf(".");
		var digits = mantissa.split(".").join("");
		var shift = Std.parseInt(text.substr(exp + 1));
		var at = (point < 0 ? mantissa.length : point) + shift;
		if (at <= 0) return sign + "0." + StringTools.lpad(digits, "0", digits.length - at);
		if (at >= digits.length) return sign + StringTools.rpad(digits, "0", at);
		return sign + digits.substr(0, at) + "." + digits.substr(at);
	}

	public static function rounded(value:Float, precision:Int, fixed:Bool, percent:Bool):String {
		var parts = plain(Math.abs(value)).split("."), whole = parts[0], fraction = parts[1] ?? "";
		if (percent) {
			fraction = StringTools.rpad(fraction, "0", 2);
			whole += fraction.substr(0, 2);
			while (whole.length > 1 && whole.charCodeAt(0) == "0".code) whole = whole.substr(1);
			fraction = fraction.substr(2);
		}
		var digits = whole + StringTools.rpad(fraction.substr(0, precision), "0", precision);
		if (fraction.length > precision && fraction.charCodeAt(precision) >= "5".code) {
			var at = digits.length - 1;
			while (at >= 0 && digits.charCodeAt(at) == "9".code) at--;
			digits = (at < 0 ? "1" : digits.substr(0, at) + String.fromCharCode(digits.charCodeAt(at) + 1))
				+ StringTools.rpad("", "0", digits.length - at - 1);
		}
		var point = digits.length - precision, end = digits.length;
		if (!fixed)
			while (end > point && digits.charCodeAt(end - 1) == "0".code) end--;
		return (value < 0 ? "-" : "") + digits.substr(0, point) + (end == point ? "" : "." + digits.substring(point, end));
	}
}
