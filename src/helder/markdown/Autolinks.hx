package helder.markdown;

import helder.markdown.Doc;
import helder.markdown.Scan.*;

using StringTools;

// GFM's extended autolinks in a text outside links: www.x.org (http://),
// http://, https:// and ftp:// with a valid domain (periods between segments of
// letters, digits, - and _, none in the last two), up to whitespace or
// "<", trailing punctuation, an unbalanced ")" and an entity-like "&x;"
// left out; and me@x.org (mailto:)
class Autolinks {
	public static function split(t:String, out:Array<Inline>) {
		if (t.indexOf("www.") < 0 && t.indexOf("://") < 0 && t.indexOf("@") < 0) {
			out.push(Text(t));
			return;
		}
		var i = 0, from = 0;
		while (Scan.tick() && i < t.length) {
			var c = t.fastCodeAt(i);
			var start = i, end = -1, prefix = "";
			if ((c == "w".code || c == "h".code || c == "f".code) && boundary(t, i)) {
				var rest = if (t.substr(i, 4) == "www.") {
					prefix = "http://";
					i;
				} else if (t.substr(i, 7) == "http://") i + 7 else if (t.substr(i, 8) == "https://") i + 8 else if (t.substr(i, 6) == "ftp://") i + 6 else -1;
				if (rest >= 0) {
					var d = domain(t, rest);
					if (d > rest) end = trail(t, start, path(t, d));
				}
			} else if (c == "@".code) {
				var l = i;
				while (Scan.tick() && l > from && isLocal(t.fastCodeAt(l - 1)))
					l--;
				var d = i + 1;
				while (Scan.tick() && (d < t.length && (isAlnum(t.fastCodeAt(d)) || t.fastCodeAt(d) == "-".code || t.fastCodeAt(d) == "_".code || t.fastCodeAt(d) == ".".code)))
					d++;
				while (Scan.tick() && d > i + 1 && t.fastCodeAt(d - 1) == ".".code)
					d--;
				var host = t.substring(i + 1, d);
				var last = d > i + 1 ? t.fastCodeAt(d - 1) : 0;
				if (l < i && host.indexOf(".") > 0 && last != "-".code && last != "_".code) {
					start = l;
					end = d;
					prefix = "mailto:";
				}
			}
			if (end > start) {
				if (start > from) out.push(Text(t.substring(from, start)));
				var text = t.substring(start, end);
				out.push(Autolink(prefix + text, text));
				from = i = end;
			} else i++;
		}
		if (from < t.length) out.push(Text(t.substr(from)));
	}

	static function boundary(t:String, i:Int):Bool {
		if (i == 0) return true;
		var p = t.fastCodeAt(i - 1);
		return isWhite(p) || p == "*".code || p == "_".code || p == "~".code || p == "(".code;
	}

	static inline function isLocal(c:Int):Bool
		return isAlnum(c) || c == ".".code || c == "-".code || c == "_".code || c == "+".code;

	// the end of a valid domain at i (i: none)
	static function domain(t:String, i:Int):Int {
		var j = i, periods = 0, lastUnder = false, prevUnder = false, segUnder = false;
		while (Scan.tick() && j < t.length) {
			var c = t.fastCodeAt(j);
			if (c == ".".code) {
				if (j + 1 >= t.length || !(isAlnum(t.fastCodeAt(j + 1)) || t.fastCodeAt(j + 1) == "-".code || t.fastCodeAt(j + 1) == "_".code)) break;
				periods++;
				prevUnder = lastUnder;
				lastUnder = segUnder;
				segUnder = false;
			} else if (c == "_".code) segUnder = true;
			else if (!(isAlnum(c) || c == "-".code || c >= 128)) break;
			j++;
		}
		if (j == i || periods == 0 || segUnder || lastUnder) return i;
		return j;
	}

	static function path(t:String, i:Int):Int {
		var j = i;
		while (Scan.tick() && j < t.length && !isWhite(t.fastCodeAt(j)) && t.fastCodeAt(j) != "<".code)
			j++;
		return j;
	}

	static function trail(t:String, start:Int, end:Int):Int {
		while (Scan.tick() && end > start) {
			var c = t.fastCodeAt(end - 1);
			if ("?!.,:*_~'\"".indexOf(String.fromCharCode(c)) >= 0) end--;
			else if (c == ")".code) {
				var open = 0, close = 0;
				for (k in start...end) {
					Scan.tick();
					var d = t.fastCodeAt(k);
					if (d == "(".code) open++ else if (d == ")".code) close++;
				}
				if (close > open) end-- else break;
			} else if (c == ";".code) {
				var k = end - 2;
				while (Scan.tick() && k > start && isAlnum(t.fastCodeAt(k)))
					k--;
				if (k < end - 2 && t.fastCodeAt(k) == "&".code) end = k else break;
			} else break;
		}
		return end;
	}
}
