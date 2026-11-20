package helder.os.locale;

// Generated from Unicode CLDR 48.2 by gen-plurals.mjs. See LICENSE.cldr.
class Cardinals {
	public static function select(value:Float, tag:String):String {
		if (!Math.isFinite(value)) return "other";
		var parts = Decimal.plain(Math.abs(value)).split(".");
		var whole = parts[0], i = Std.parseFloat(whole);
		var tail = Std.parseInt(whole.substr(Std.int(Math.max(0, whole.length - 6))));
		var fraction = parts[1] ?? "";
		var v = fraction.length, end = v;
		while (end > 0 && fraction.charCodeAt(end - 1) == "0".code) end--;
		v = end;
		fraction = fraction.substr(0, v);
		var f = v == 0 ? 0.0 : Std.parseFloat(fraction);
		var f100 = v == 0 ? 0 : Std.parseInt(fraction.substr(Std.int(Math.max(0, v - 2))));
		var f10 = f100 % 10;
		var base = tag.split("-");
		var regional = (base.length > 1 ? base[0] + "-" + base[1] : base[0]);
		var rule = switch regional {
			case "pt-PT" | "pt-AO" | "pt-CH" | "pt-CV" | "pt-FR" | "pt-GQ" | "pt-GW" | "pt-LU" | "pt-MO" | "pt-MZ" | "pt-ST" | "pt-TL": "pt-PT";
			case _: base[0];
		};
		switch rule {
			case "af" | "az" | "bg" | "el" | "hu" | "ml" | "mr" | "nb" | "ta" | "te"
				| "tr":
				if ((v == 0 && i == 1)) return "one";
			case "am" | "bn" | "fa" | "gu" | "hi" | "kn":
				if (i == 0 || (v == 0 && i == 1)) return "one";
			case "ar":
				if ((v == 0 && i == 0)) return "zero";
				if ((v == 0 && i == 1)) return "one";
				if ((v == 0 && i == 2)) return "two";
				if ((v == 0 && ((tail % 100) >= 3 && (tail % 100) <= 10))) return "few";
				if ((v == 0 && ((tail % 100) >= 11 && (tail % 100) <= 99))) return "many";
			case "ca" | "it" | "pt-PT":
				if (i == 1 && v == 0) return "one";
				if (!(i == 0) && (tail % 1000000) == 0 && v == 0) return "many";
			case "cs" | "sk":
				if (i == 1 && v == 0) return "one";
				if ((i >= 2 && i <= 4) && v == 0) return "few";
				if (!(v == 0)) return "many";
			case "da":
				if ((v == 0 && i == 1) || !(f == 0) && (i == 0 || i == 1)) return "one";
			case "de" | "en" | "fi" | "nl" | "sv" | "sw" | "ur":
				if (i == 1 && v == 0) return "one";
			case "es":
				if ((v == 0 && i == 1)) return "one";
				if (!(i == 0) && (tail % 1000000) == 0 && v == 0) return "many";
			case "fil":
				if (v == 0 && (i == 1 || i == 2 || i == 3) || v == 0 && !(((tail % 10) == 4 || (tail % 10) == 6 || (tail % 10) == 9)) || !(v == 0) && !((f10 == 4 || f10 == 6 || f10 == 9))) return "one";
			case "fr":
				if ((i == 0 || i == 1)) return "one";
				if (!(i == 0) && (tail % 1000000) == 0 && v == 0) return "many";
			case "he":
				if (i == 1 && v == 0 || i == 0 && !(v == 0)) return "one";
				if (i == 2 && v == 0) return "two";
			case "hr" | "sr":
				if (v == 0 && (tail % 10) == 1 && !((tail % 100) == 11) || f10 == 1 && !(f100 == 11)) return "one";
				if (v == 0 && ((tail % 10) >= 2 && (tail % 10) <= 4) && !(((tail % 100) >= 12 && (tail % 100) <= 14)) || (f10 >= 2 && f10 <= 4) && !((f100 >= 12 && f100 <= 14))) return "few";
			case "lt":
				if ((v == 0 && (tail % 10) == 1) && !((v == 0 && ((tail % 100) >= 11 && (tail % 100) <= 19)))) return "one";
				if ((v == 0 && ((tail % 10) >= 2 && (tail % 10) <= 9)) && !((v == 0 && ((tail % 100) >= 11 && (tail % 100) <= 19)))) return "few";
				if (!(f == 0)) return "many";
			case "lv":
				if ((v == 0 && (tail % 10) == 0) || (v == 0 && ((tail % 100) >= 11 && (tail % 100) <= 19)) || v == 2 && (f100 >= 11 && f100 <= 19)) return "zero";
				if ((v == 0 && (tail % 10) == 1) && !((v == 0 && (tail % 100) == 11)) || v == 2 && f10 == 1 && !(f100 == 11) || !(v == 2) && f10 == 1) return "one";
			case "pl":
				if (i == 1 && v == 0) return "one";
				if (v == 0 && ((tail % 10) >= 2 && (tail % 10) <= 4) && !(((tail % 100) >= 12 && (tail % 100) <= 14))) return "few";
				if (v == 0 && !(i == 1) && ((tail % 10) >= 0 && (tail % 10) <= 1) || v == 0 && ((tail % 10) >= 5 && (tail % 10) <= 9) || v == 0 && ((tail % 100) >= 12 && (tail % 100) <= 14)) return "many";
			case "pt":
				if ((i >= 0 && i <= 1)) return "one";
				if (!(i == 0) && (tail % 1000000) == 0 && v == 0) return "many";
			case "ro":
				if (i == 1 && v == 0) return "one";
				if (!(v == 0) || (v == 0 && i == 0) || !((v == 0 && i == 1)) && (v == 0 && ((tail % 100) >= 1 && (tail % 100) <= 19))) return "few";
			case "ru" | "uk":
				if (v == 0 && (tail % 10) == 1 && !((tail % 100) == 11)) return "one";
				if (v == 0 && ((tail % 10) >= 2 && (tail % 10) <= 4) && !(((tail % 100) >= 12 && (tail % 100) <= 14))) return "few";
				if (v == 0 && (tail % 10) == 0 || v == 0 && ((tail % 10) >= 5 && (tail % 10) <= 9) || v == 0 && ((tail % 100) >= 11 && (tail % 100) <= 14)) return "many";
			case "sl":
				if (v == 0 && (tail % 100) == 1) return "one";
				if (v == 0 && (tail % 100) == 2) return "two";
				if (v == 0 && ((tail % 100) >= 3 && (tail % 100) <= 4) || !(v == 0)) return "few";
			case _:
		}
		return "other";
	}
}
