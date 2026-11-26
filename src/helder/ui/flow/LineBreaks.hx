package helder.ui.flow;

import haxe.ds.Vector;
import haxe.io.Bytes;

// Line breaking opportunities, UAX #14 (Unicode 17's rules, LB1 to LB31,
// LineBreakData's classes) with CSS Text 3's tailorings: line-break
// (strict: CJ as NS; normal and loose: as ID; loose: iteration marks and
// the prolonged sound mark as ID too; anywhere: a break between any two
// typographic character units), word-break (break-all: letters and digits
// as ID; keep-all: none between them). Checked against Unicode's
// LineBreakTest.txt (LineBreaks.test.hx).
//
// analyze writes a status before each UTF-16 unit of a text (and its end):
// NONE, ALLOWED or FORCED, CLUSTER set where a unit begins (after LB9's
// marks, a unit is a character and the marks it carries).
class LineBreaks {
	public static inline var NONE = 0;
	public static inline var ALLOWED = 1;
	public static inline var FORCED = 2;
	public static inline var STATUS = 3;
	public static inline var CLUSTER = 4;

	// options per UTF-16 unit (analyze's opts): line-break's and word-break's
	public static inline var STRICT = 1;
	public static inline var LOOSE = 2;
	public static inline var ANYWHERE = 4;
	public static inline var BREAK_ALL = 8;
	public static inline var KEEP_ALL = 16;
	// an atomic inline's U+FFFC: a break before and after it (CSS Text 3 §5.1)
	public static inline var ATOMIC = 32;

	public static inline var XX = 0;
	public static inline var BK = 1;
	public static inline var CR = 2;
	public static inline var LF = 3;
	public static inline var CM = 4;
	public static inline var NL = 5;
	public static inline var SG = 6;
	public static inline var WJ = 7;
	public static inline var ZW = 8;
	public static inline var GL = 9;
	public static inline var SP = 10;
	public static inline var ZWJ = 11;
	public static inline var B2 = 12;
	public static inline var BA = 13;
	public static inline var BB = 14;
	public static inline var HY = 15;
	public static inline var HH = 16;
	public static inline var CB = 17;
	public static inline var CL = 18;
	public static inline var CP = 19;
	public static inline var EX = 20;
	public static inline var IN = 21;
	public static inline var NS = 22;
	public static inline var OP = 23;
	public static inline var QU = 24;
	public static inline var IS = 25;
	public static inline var NU = 26;
	public static inline var PO = 27;
	public static inline var PR = 28;
	public static inline var SY = 29;
	public static inline var AI = 30;
	public static inline var AK = 31;
	public static inline var AL = 32;
	public static inline var AP = 33;
	public static inline var AS = 34;
	public static inline var CJ = 35;
	public static inline var EB = 36;
	public static inline var EM = 37;
	public static inline var H2 = 38;
	public static inline var H3 = 39;
	public static inline var HL = 40;
	public static inline var ID = 41;
	public static inline var JL = 42;
	public static inline var JV = 43;
	public static inline var JT = 44;
	public static inline var RI = 45;
	public static inline var SA = 46;
	public static inline var VF = 47;
	public static inline var VI = 48;

	// (a value's flags above its class: generate.mjs's)
	static inline var EA = 1 << 6;
	static inline var PI = 2 << 6;
	static inline var PF = 4 << 6;
	static inline var PICT_CN = 8 << 6;
	static inline var MN = 16 << 6;
	static inline var MC = 32 << 6;
	static inline var CLASS = 63;

	// a code point's Line_Break class
	public static inline function classOf(c:Int):Int
		return valueOf(c) & CLASS;

	// whether its East_Asian_Width is F, W or H
	public static inline function wide(c:Int):Bool
		return valueOf(c) & EA != 0;

	static var bmp:Null<Bytes> = null;
	static var starts:Null<Vector<Int>> = null;
	static var values:Null<Vector<Int>> = null;

	static function valueOf(c:Int):Int {
		if (bmp == null) decode();
		if (c < 0x10000) return bmp.getUInt16(c << 1);
		var lo = 0, hi = starts.length - 1;
		while (lo < hi) {
			var mid = (lo + hi + 1) >> 1;
			if (starts[mid] <= c) lo = mid else hi = mid - 1;
		}
		return values[lo];
	}

	static function decode() {
		var s = LineBreakData.runs(), runs = s.split(",");
		var st = new Vector<Int>(runs.length), vs = new Vector<Int>(runs.length);
		var b = Bytes.alloc(0x20000), at = 0;
		for (k in 0...runs.length) {
			var r = runs[k], dot = r.indexOf(".");
			var len = base36(r, 0, dot), v = base36(r, dot + 1, r.length);
			st[k] = at;
			vs[k] = v;
			var e = at + len;
			for (c in at...(e < 0x10000 ? e : 0x10000))
				b.setUInt16(c << 1, v);
			at = e;
		}
		starts = st;
		values = vs;
		bmp = b;
	}

	static function base36(s:String, from:Int, to:Int):Int {
		var n = 0;
		for (i in from...to) {
			var c = StringTools.fastCodeAt(s, i);
			n = n * 36 + (c <= "9".code ? c - "0".code : c - "a".code + 10);
		}
		return n;
	}

	// (the units, after LB9 and LB10: each its value (class and flags), the
	// first UTF-16 unit of its character; whether its last character is a ZWJ)
	var cls = new Vector<Int>(64);
	var unitAt = new Vector<Int>(64);
	var zwj = new Vector<Bool>(64);
	var opt = new Vector<Int>(64);
	// (forward states: after NU (SY|IS)*, after it and CL or CP; the unit before a run of spaces)
	var num = new Vector<Int>(64);
	var beforeSp = new Vector<Int>(64);
	var riRun = new Vector<Int>(64);
	var units = 0;

	public function new() {}

	// the opportunities before each UTF-16 unit of text[start...end] into
	// out[start...end] (out[end]: the end's, FORCED only after a BK, CR, LF
	// or NL, else NONE: the caller decides what follows); opts: each unit's
	// options (STRICT, BREAK_ALL...; null: none)
	public function analyze(text:String, start:Int, end:Int, out:Bytes, ?opts:Bytes) {
		units = 0;
		var i = start;
		while (i < end) {
			var c = StringTools.fastCodeAt(text, i), len = 1;
			if (c >= 0xD800 && c < 0xDC00 && i + 1 < end) {
				var d = StringTools.fastCodeAt(text, i + 1);
				if (d >= 0xDC00 && d < 0xE000) {
					c = 0x10000 + ((c - 0xD800) << 10) + (d - 0xDC00);
					len = 2;
				}
			}
			var o = opts == null ? 0 : opts.get(i);
			var v = valueOf(c), k = v & CLASS;
			if (k == SA && v & (MN | MC) != 0) k = CM;
			for (j in i...i + len)
				out.set(j, NONE);
			// LB9: a mark joins the character before it, unless that is a break or space; LB10: else it is AL
			if ((k == CM || k == ZWJ) && units > 0 && o & ATOMIC == 0) {
				var p = cls[units - 1] & CLASS;
				if (p != BK && p != CR && p != LF && p != NL && p != SP && p != ZW && opt[units - 1] & ATOMIC == 0) {
					zwj[units - 1] = k == ZWJ;
					i += len;
					continue;
				}
			}
			room(units + 1);
			cls[units] = resolve(c, v, o);
			unitAt[units] = i;
			zwj[units] = k == ZWJ;
			opt[units] = o;
			units++;
			i += len;
		}
		out.set(end, NONE);
		if (units == 0) return;
		states();
		for (u in 1...units) {
			var s = pair(u);
			// (a cluster: not after a joiner, nor between a flag's two regional indicators)
			var c = zwj[u - 1] || at(u) == RI && riRun[u - 1] & 1 == 1 ? 0 : CLUSTER;
			var o = opt[u] | opt[u - 1];
			if (s != FORCED) {
				// (an atomic inline: a break on both sides, whatever is next to it)
				if (opt[u] & ATOMIC != 0 || opt[u - 1] & ATOMIC != 0) s = ALLOWED;
				else if (opt[u] & opt[u - 1] & KEEP_ALL != 0 && s == ALLOWED && letter(u - 1) && letter(u)) s = NONE;
				else if (o & ANYWHERE != 0) s = ALLOWED;
			}
			out.set(unitAt[u], c | s);
		}
		out.set(unitAt[0], CLUSTER);
		var last = cls[units - 1] & CLASS;
		if (last == BK || last == CR || last == LF || last == NL) out.set(end, FORCED);
	}

	function room(n:Int) {
		if (n <= cls.length) return;
		var m = n * 2;
		cls = grow(cls, m);
		unitAt = grow(unitAt, m);
		opt = grow(opt, m);
		num = grow(num, m);
		beforeSp = grow(beforeSp, m);
		riRun = grow(riRun, m);
		var z = new Vector<Bool>(m);
		Vector.blit(zwj, 0, z, 0, zwj.length);
		zwj = z;
	}

	static function grow(v:Vector<Int>, n:Int):Vector<Int> {
		var w = new Vector<Int>(n);
		Vector.blit(v, 0, w, 0, v.length);
		return w;
	}

	// LB1 and CSS's classes: AI, SG and XX as AL, SA as AL (its marks CM, analyze's),
	// CJ as NS when strict else ID; break-all's letters and digits as ID
	static function resolve(c:Int, v:Int, o:Int):Int {
		var k = v & CLASS, f = v & ~CLASS;
		if (c == 0x25CC) f |= CIRCLE;
		switch k {
			case AI | SG | XX:
				k = AL;
			case SA:
				// (its marks reach here only unattached: LB10's AL)
				k = AL;
			case CJ:
				k = o & STRICT != 0 ? NS : ID;
			case NS if (o & LOOSE != 0 && (c == 0x3005 || c == 0x303B || c == 0x309D || c == 0x309E || c == 0x30FD || c == 0x30FE || c == 0x30FC || c == 0xFF70)):
				// (loose: iteration marks and the prolonged sound mark may start a line)
				k = ID;
			case CM | ZWJ:
				k = AL;
			case _:
		}
		if (o & BREAK_ALL != 0 && (k == AL || k == HL || k == NU)) k = ID;
		return k | f;
	}

	// (letters and digits, keep-all's: no break between two of them)
	inline function letter(u:Int):Bool {
		var k = cls[u] & CLASS;
		return k == AL || k == HL || k == NU || k == ID || k == H2 || k == H3 || k == JL || k == JV || k == JT || k == AK || k == AS;
	}

	// (each unit's context: num[u] 1 after NU (SY|IS)*, 2 after that and CL
	// or CP, counted up to and including u; beforeSp[u] the last unit before
	// u that is not a space (-1: the start); riRun[u] the regional
	// indicators ending at u)
	function states() {
		var n = 0, last = -1, ri = 0;
		for (u in 0...units) {
			var k = cls[u] & CLASS;
			beforeSp[u] = last;
			if (k != SP) last = u;
			n = k == NU ? 1 : (k == SY || k == IS) && n == 1 ? 1 : (k == CL || k == CP) && n == 1 ? 2 : 0;
			num[u] = n;
			ri = k == RI ? ri + 1 : 0;
			riRun[u] = ri;
		}
	}

	inline function at(u:Int):Int
		return u < 0 || u >= units ? -1 : cls[u] & CLASS;

	inline function flags(u:Int):Int
		return u < 0 || u >= units ? 0 : cls[u];

	// the status of the boundary before unit u (u > 0): the rules in order
	function pair(u:Int):Int {
		var a = cls[u - 1] & CLASS, b = cls[u] & CLASS, fa = cls[u - 1], fb = cls[u];
		// LB4, LB5
		if (a == BK) return FORCED;
		if (a == CR) return b == LF ? NONE : FORCED;
		if (a == LF || a == NL) return FORCED;
		// LB6, LB7
		if (b == BK || b == CR || b == LF || b == NL || b == SP || b == ZW) return NONE;
		// LB8: ZW SP* ÷
		var ns = a == SP ? beforeSp[u - 1] : u - 1;
		if (ns >= 0 && at(ns) == ZW) return ALLOWED;
		// LB8a
		if (zwj[u - 1]) return NONE;
		// LB11
		if (a == WJ || b == WJ) return NONE;
		// LB12, LB12a
		if (a == GL) return NONE;
		if (b == GL && a != SP && a != BA && a != HY && a != HH) return NONE;
		// LB13
		if (b == EX || b == CL || b == CP || b == SY) return NONE;
		// LB14: OP SP* ×
		var before = at(ns);
		if (before == OP) return NONE;
		// LB15a: (sot | BK | CR | LF | NL | OP | QU | GL | SP | ZW) QU_Pi SP* ×
		if (before == QU && flags(ns) & PI != 0) {
			var p = at(ns - 1);
			if (p < 0 || p == BK || p == CR || p == LF || p == NL || p == OP || p == QU || p == GL || p == SP || p == ZW) return NONE;
		}
		// LB15b: × QU_Pf (SP | GL | WJ | CL | QU | CP | EX | IS | SY | BK | CR | LF | NL | ZW | eot)
		if (b == QU && fb & PF != 0) {
			var n = at(u + 1);
			if (n < 0 || n == SP || n == GL || n == WJ || n == CL || n == QU || n == CP || n == EX || n == IS || n == SY || n == BK || n == CR || n == LF
				|| n == NL || n == ZW)
				return NONE;
		}
		// LB15c, LB15d
		if (a == SP && b == IS && at(u + 1) == NU) return ALLOWED;
		if (b == IS) return NONE;
		// LB16: (CL | CP) SP* × NS
		if ((before == CL || before == CP) && b == NS) return NONE;
		// LB17: B2 SP* × B2
		if (before == B2 && b == B2) return NONE;
		// LB18
		if (a == SP) return ALLOWED;
		// LB19, LB19a
		if (b == QU && fb & PI == 0) return NONE;
		if (a == QU && fa & PF == 0) return NONE;
		if (b == QU) {
			if (fa & EA == 0) return NONE;
			if (u + 1 >= units || flags(u + 1) & EA == 0) return NONE;
		}
		if (a == QU) {
			if (fb & EA == 0) return NONE;
			if (u - 2 < 0 || flags(u - 2) & EA == 0) return NONE;
		}
		// LB20
		if (b == CB || a == CB) return ALLOWED;
		// LB20a: (sot | BK | CR | LF | NL | SP | ZW | CB | GL) (HY | HH) × (AL | HL)
		if ((a == HY || a == HH) && (b == AL || b == HL)) {
			var p = at(u - 2);
			if (p < 0 || p == BK || p == CR || p == LF || p == NL || p == SP || p == ZW || p == CB || p == GL) return NONE;
		}
		// LB21
		if (b == BA || b == HH || b == HY || b == NS || a == BB) return NONE;
		// LB21a: HL (HY | HH) × [^HL]
		if ((a == HY || a == HH) && at(u - 2) == HL && b != HL) return NONE;
		// LB21b
		if (a == SY && b == HL) return NONE;
		// LB22
		if (b == IN) return NONE;
		// LB23, LB23a, LB24
		if ((a == AL || a == HL) && b == NU || a == NU && (b == AL || b == HL)) return NONE;
		if (a == PR && (b == ID || b == EB || b == EM) || (a == ID || a == EB || a == EM) && b == PO) return NONE;
		if ((a == PR || a == PO) && (b == AL || b == HL) || (a == AL || a == HL) && (b == PR || b == PO)) return NONE;
		// LB25 (its regular expressions' form)
		if ((b == PO || b == PR) && num[u - 1] != 0) return NONE;
		if ((a == PO || a == PR) && (b == NU || b == OP && (at(u + 1) == NU || at(u + 1) == IS && at(u + 2) == NU))) return NONE;
		if ((a == HY || a == IS) && b == NU) return NONE;
		if (b == NU && num[u - 1] == 1) return NONE;
		// LB26, LB27
		if (a == JL && (b == JL || b == JV || b == H2 || b == H3)) return NONE;
		if ((a == JV || a == H2) && (b == JV || b == JT)) return NONE;
		if ((a == JT || a == H3) && b == JT) return NONE;
		if ((a == JL || a == JV || a == JT || a == H2 || a == H3) && b == PO) return NONE;
		if (a == PR && (b == JL || b == JV || b == JT || b == H2 || b == H3)) return NONE;
		// LB28
		if ((a == AL || a == HL) && (b == AL || b == HL)) return NONE;
		// LB28a (◌, U+25CC, with AK)
		var aks = a == AK || a == AS || dotted(u - 1), bks = b == AK || b == AS || dotted(u);
		if (a == AP && bks) return NONE;
		if (aks && (b == VF || b == VI)) return NONE;
		if (a == VI && (b == AK || dotted(u)) && (at(u - 2) == AK || at(u - 2) == AS || dotted(u - 2))) return NONE;
		if (aks && bks && at(u + 1) == VF) return NONE;
		// LB29, LB30
		if (a == IS && (b == AL || b == HL)) return NONE;
		if ((a == AL || a == HL || a == NU) && b == OP && fb & EA == 0) return NONE;
		if (a == CP && fa & EA == 0 && (b == AL || b == HL || b == NU)) return NONE;
		// LB30a: regional indicators in pairs
		if (a == RI && b == RI && riRun[u - 1] & 1 == 1) return NONE;
		// LB30b
		if (b == EM && (a == EB || fa & PICT_CN != 0)) return NONE;
		return ALLOWED;
	}

	// (U+25CC, LB28a's dotted circle)
	inline function dotted(u:Int):Bool
		return u >= 0 && u < units && cls[u] & CLASS == AL && cls[u] & CIRCLE != 0;

	// (the dotted circle's mark on its value: resolve's)
	static inline var CIRCLE = 64 << 6;
}
