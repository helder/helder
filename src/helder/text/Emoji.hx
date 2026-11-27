package helder.text;

import helder.text.unicode.EmojiData;

// Unicode's emoji properties (UTS #51, emoji-data.txt): Emoji, a character
// that has an emoji form, and Emoji_Presentation, one shown as an emoji
// unless asked otherwise: what font-variant-emoji's unicode (and normal)
// choose a face by (FontSet.presentation)
class Emoji {
	public static function emoji(cp:Int):Bool
		return within(emojis ??= ranges(EmojiData.emoji), cp);

	public static function presentation(cp:Int):Bool
		return within(presentations ??= ranges(EmojiData.presentation), cp);

	static var emojis:Null<Array<Int>> = null;
	static var presentations:Null<Array<Int>> = null;

	static function ranges(s:String):Array<Int> {
		var out = [];
		for (r in s.split(",")) {
			var d = r.indexOf("-");
			out.push(Std.parseInt("0x" + r.substr(0, d)));
			out.push(Std.parseInt("0x" + r.substr(d + 1)));
		}
		return out;
	}

	static function within(r:Array<Int>, cp:Int):Bool {
		var lo = 0, hi = (r.length >> 1) - 1;
		while (lo <= hi) {
			var mid = (lo + hi) >> 1;
			if (cp < r[2 * mid]) hi = mid - 1 else if (cp > r[2 * mid + 1]) lo = mid + 1 else return true;
		}
		return false;
	}
}
