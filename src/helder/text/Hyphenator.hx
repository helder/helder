package helder.text;

import haxe.ds.Vector;
import helder.text.hyphenation.Patterns;

// Where one language's words may be hyphenated: Liang's algorithm, TeX's, on
// its patterns and exceptions (Hyphenation.get's: helder.text.hyphenation),
// in a trie built when it is made. points(word) gives the breaks; letters
// of either case match, characters the patterns do not know match nothing.
class Hyphenator {
	// its BCP 47 tag, the fewest letters before and after a break (the patterns' own)
	public final language:String;
	public final left:Int;
	public final right:Int;

	// a hyphenator that hyphenates nothing (a TextRun's: none in that run)
	public static final NONE = new Hyphenator(new Patterns("", 1, 1, "", "", ""));

	// (each UTF-16 unit the patterns know: its letter, 2 on (1: a word's edge, "."), UPPER for an upper case one)
	final letters = new IntTable<Int>();
	// (the trie: a node and a letter, node << 8 | letter, to the node after them;
	// each node's values: their offset in pool, -1 none)
	final next = new IntTable<Int>();
	// (the root's: by letter, the start of most walks without a probe)
	final first = new Vector<Int>(256, -1);
	final nodeValues:Array<Int> = [-1];
	// (a pattern's values: their count, then each)
	final pool:Array<Int> = [];
	// (the last word scanned: its letters between its edges, the values between them)
	var word = new Vector<Int>(64);
	var values = new Vector<Int>(64);
	static inline var UPPER = 0x100;
	// (an exception's values: above any pattern's, odd where it breaks)
	static inline var EXCEPTION = 10;

	public function new(p:Patterns) {
		language = p.tag;
		left = p.left;
		right = p.right;
		letters.set(".".code, 1);
		var n = 2, first = true, a = p.alphabet;
		for (i in 0...a.length) {
			var c = StringTools.fastCodeAt(a, i);
			if (c == " ".code) {
				n++;
				first = true;
				continue;
			}
			letters.set(c, first ? n : n | UPPER);
			first = false;
		}
		// (each pattern its shared length, then the rest of its TeX form: "a1b2c")
		var s = p.patterns, cur = new Vector<Int>(64), i = 0;
		while (i < s.length) {
			var len = StringTools.fastCodeAt(s, i++) - 1;
			while (i < s.length) {
				var c = StringTools.fastCodeAt(s, i);
				if (c < 32) break;
				if (len == cur.length) {
					var more = new Vector<Int>(len * 2);
					Vector.blit(cur, 0, more, 0, len);
					cur = more;
				}
				cur[len++] = c;
				i++;
			}
			pattern(cur, len);
		}
		for (e in p.exceptions.split(" "))
			if (e != "") exception(e);
	}

	// the UTF-16 indices of word where it may break (a hyphen after the
	// characters before it), at least left from its start and right from its end
	public function points(word:String):Array<Int> {
		var n = scan(word, 0, word.length), out = [];
		for (p in left...n - right + 1)
			if (breaks(p)) out.push(p);
		return out;
	}

	// (s's units start to end as a word: the values between its letters, n of them)
	@:allow(helder.text.TextLayout)
	function scan(s:String, start:Int, end:Int):Int {
		var n = end - start;
		if (word.length < n + 3) {
			word = new Vector(2 * n + 3);
			values = new Vector(2 * n + 3);
		}
		word[0] = 1;
		for (i in 0...n)
			word[i + 1] = letters.get(StringTools.fastCodeAt(s, start + i), 0) & 0xFF;
		word[n + 1] = 1;
		for (t in 0...n + 3)
			values[t] = 0;
		for (i in 0...n + 2) {
			var node = first[word[i]], j = i;
			while (node > 0) {
				var v = nodeValues[node];
				if (v >= 0)
					for (k in 0...pool[v]) {
						var x = pool[v + 1 + k];
						if (x > values[i + k]) values[i + k] = x;
					}
				if (++j == n + 2) break;
				var l = word[j];
				if (l == 0) break;
				node = next.get(node << 8 | l, -1);
			}
		}
		return n;
	}

	// (after scan: may the word break before its unit p?)
	@:allow(helder.text.TextLayout)
	inline function breaks(p:Int):Bool
		return values[p + 1] & 1 == 1;

	// (whether it is one of the language's letters, in upper case)
	@:allow(helder.text.TextLayout)
	inline function knows(c:Int):Bool
		return letters.get(c, 0) > 1;

	@:allow(helder.text.TextLayout)
	inline function upper(c:Int):Bool
		return letters.get(c, 0) & UPPER != 0;

	function child(node:Int, l:Int):Int {
		var key = node << 8 | l, x = next.get(key, -1);
		if (x < 0) {
			x = nodeValues.length;
			nodeValues.push(-1);
			next.set(key, x);
			if (node == 0) first[l] = x;
		}
		return x;
	}

	function store(node:Int, v:Vector<Int>, count:Int) {
		var at = nodeValues[node];
		if (at >= 0) {
			for (k in 0...count)
				if (v[k] > pool[at + 1 + k]) pool[at + 1 + k] = v[k];
			return;
		}
		nodeValues[node] = pool.length;
		pool.push(count);
		for (k in 0...count)
			pool.push(v[k]);
	}

	function pattern(cur:Vector<Int>, len:Int) {
		var v = new Vector<Int>(len + 2), node = 0, k = 0;
		v[0] = 0;
		for (j in 0...len) {
			var c = cur[j];
			if (c >= "0".code && c <= "9".code) v[k] = c - "0".code else {
				node = child(node, letters.get(c, 0) & 0xFF);
				v[++k] = 0;
			}
		}
		store(node, v, k + 1);
	}

	// (a hyphenated word: the whole word's pattern, its edges matched too)
	function exception(e:String) {
		var v = new Vector<Int>(e.length + 3), node = child(0, 1), k = 0;
		for (t in 0...v.length)
			v[t] = 0;
		for (j in 0...e.length) {
			var c = StringTools.fastCodeAt(e, j);
			if (c == "-".code) {
				v[k + 1] = EXCEPTION + 1;
				continue;
			}
			node = child(node, letters.get(c, 0) & 0xFF);
			k++;
			if (j + 1 < e.length && StringTools.fastCodeAt(e, j + 1) != "-".code) v[k + 1] = EXCEPTION;
		}
		node = child(node, 1);
		v[1] = v[k + 1] = 0;
		store(node, v, k + 3);
	}
}
