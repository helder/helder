package helder.os;

import helder.os.locale.Cardinals;
import helder.os.locale.LocaleTag;

enum abstract PluralCategory(String) to String {
	var Zero = "zero";
	var One = "one";
	var Two = "two";
	var Few = "few";
	var Many = "many";
	var Other = "other";
}

class Plural {
	public static function category(locale:String, n:Float):PluralCategory
		return cast Cardinals.select(n, LocaleTag.normalize(locale) ?? "");
}
