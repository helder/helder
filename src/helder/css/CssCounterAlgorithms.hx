package helder.css;

typedef CssCounterAlgorithm = {
	name:String,
	min:Int,
	max:Int,
	negative:Bool,
	minus:String,
	suffix:String,
	fallback:String
}

// The predefined counter styles @counter-style can't say (Counter Styles
// 3 §7): the Chinese, Japanese and Korean longhands, from -9999 to 9999
// (the optional extended forms past them left out: cjk-decimal's), and
// ethiopic-numeric.
class CssCounterAlgorithms {
	static final CJK:Array<Cjk> = [
		cjkStyle("japanese-informal", "〇一二三四五六七八九", "十百千", true, false, "マイナス", "、"),
		cjkStyle("japanese-formal", "零壱弐参四伍六七八九", "拾百阡", false, false, "マイナス", "、"),
		cjkStyle("korean-hangul-formal", "영일이삼사오육칠팔구", "십백천", false, false, "마이너스 ", ", "),
		cjkStyle("korean-hanja-informal", "零一二三四五六七八九", "十百千", true, false, "마이너스 ", ", "),
		cjkStyle("korean-hanja-formal", "零壹貳參四五六七八九", "拾百仟", false, false, "마이너스 ", ", "),
		cjkStyle("simp-chinese-informal", "零一二三四五六七八九", "十百千", true, true, "负", "、"),
		cjkStyle("simp-chinese-formal", "零壹贰叁肆伍陆柒捌玖", "拾佰仟", false, true, "负", "、"),
		cjkStyle("trad-chinese-informal", "零一二三四五六七八九", "十百千", true, true, "負", "、"),
		cjkStyle("trad-chinese-formal", "零壹貳參肆伍陸柒捌玖", "拾佰仟", false, true, "負", "、"),
		cjkStyle("cjk-ideographic", "零一二三四五六七八九", "十百千", true, true, "負", "、")
	];

	public static final STYLES:Array<CssCounterAlgorithm> = [
		for (c in CJK) {
			name: c.name,
			min: -9999,
			max: 9999,
			negative: true,
			minus: c.minus,
			suffix: c.suffix,
			// (Korean's past its range: decimal, as WPT's Korean pages have it)
			fallback: StringTools.startsWith(c.name, "korean") ? "decimal" : "cjk-decimal"
		}
	].concat([{
		name: "ethiopic-numeric",
		min: 1,
		max: 2147483647,
		negative: false,
		minus: "",
		suffix: "/ ",
		fallback: "decimal"
	}]);

	public static function format(name:String, value:Int):Null<String> {
		if (name == "ethiopic-numeric") return ethiopic(value);
		for (c in CJK) if (c.name == name) return cjk(c, value);
		return null;
	}

	// (each digit and its place's marker, thousands to ones: zeros dropped,
	// or in Chinese one zero for a run between digits; informal styles drop
	// the 1 before a marker, Chinese only in 10 to 19)
	static function cjk(c:Cjk, value:Int):String {
		if (value == 0) return c.digits[0];
		var digits = [Std.int(value / 1000) % 10, Std.int(value / 100) % 10, Std.int(value / 10) % 10, value % 10];
		var out = new StringBuf(), zero = false, started = false;
		for (k in 0...4) {
			var d = digits[k], place = 3 - k;
			if (d == 0) {
				if (started) zero = true;
				continue;
			}
			if (zero && c.chinese) out.add(c.digits[0]);
			zero = false;
			var drop = d == 1 && place > 0 && c.informal && (!c.chinese || place == 1 && !started);
			if (!drop) out.add(c.digits[d]);
			if (place > 0) out.add(c.markers[place - 1]);
			started = true;
		}
		return out.toString();
	}

	// (Counter Styles 3 §7.2: two digits a group from the right, tens and
	// ones as their symbols; an odd group's ፻ and an even one's ፼ after it;
	// a group of 1 without its digit where a separator says it, a group of 0
	// without its digits)
	static function ethiopic(value:Int):Null<String> {
		if (value < 1) return null;
		if (value == 1) return "፩";
		var groups = [];
		var v = value;
		while (v > 0) {
			groups.push(v % 100);
			v = Std.int(v / 100);
		}
		var out = new StringBuf();
		var k = groups.length - 1;
		while (k >= 0) {
			var g = groups[k];
			var bare = g == 0 || g == 1 && (k == groups.length - 1 || k % 2 == 1);
			if (!bare) {
				var tens = Std.int(g / 10), ones = g % 10;
				if (tens > 0) out.add(String.fromCharCode(0x1372 + tens - 1));
				if (ones > 0) out.add(String.fromCharCode(0x1369 + ones - 1));
			}
			if (k % 2 == 1 && g != 0) out.add("፻");
			if (k % 2 == 0 && k > 0) out.add("፼");
			k--;
		}
		return out.toString();
	}

	static function cjkStyle(name:String, digits:String, markers:String, informal:Bool, chinese:Bool, minus:String, suffix:String):Cjk
		return {
			name: name,
			digits: [for (k in 0...digits.length) digits.charAt(k)],
			markers: [for (k in 0...markers.length) markers.charAt(k)],
			informal: informal,
			chinese: chinese,
			minus: minus,
			suffix: suffix
		};
}

private typedef Cjk = {name:String, digits:Array<String>, markers:Array<String>, informal:Bool, chinese:Bool, minus:String, suffix:String}
