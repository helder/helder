package helder.test;

// Generators for properties (`import helder.test.Gen;`): a Gen is a function
// drawing a value from a case's choices, so one of your own is a lambda
// drawing from others:
//
//   final point:Gen<{x:Int, y:Int}> = c -> {x: c.draw(int(0, 9)), y: c.draw(int(0, 9))};
//   final words = array(string(pick(["a", "b"]), 1, 4), 1, 5).map(w -> w.join(" "));
//
// Each one shrinks to its simplest value: an int to 0 (or its bound
// nearest to it), an array to fewer items, a pick or oneOf to its first.
abstract Gen<T>(Choices->T) from Choices->T to Choices->T {
	// its values through f
	public function map<R>(f:T->R):Gen<R> {
		var g:Choices->T = this;
		return c -> f(c.draw(g));
	}

	// its values for which ok holds (three draws, else the case is rejected)
	public function filter(ok:T->Bool):Gen<T> {
		var g:Choices->T = this;
		return c -> {
			for (_ in 0...3) {
				var v = c.draw(g);
				if (ok(v)) return v;
			}
			c.reject();
		};
	}
}

// an int in min...=max, shrinking to 0 or the bound nearest to it
function int(min:Int, max:Int):Gen<Int> {
	if (min > max) throw new haxe.Exception('int($min, $max): min above max');
	var span = (max : Float) - min;
	if (span > 0x7FFFFFFF) return c -> {
		// (wider than a choice: a sign and a magnitude, clamped; 0 is inside)
		var m = c.choice(1) == 1 ? -c.choice(0x7FFFFFFF) : c.choice(0x7FFFFFFF);
		m < min ? min : m > max ? max : m;
	}
	var n = Std.int(span);
	if (min >= 0) return c -> min + c.choice(n);
	if (max <= 0) return c -> max - c.choice(n);
	// (0, 1, -1, 2, -2 ... then the longer side's rest)
	var near = -min < max ? -min : max;
	return c -> {
		var k = c.choice(n);
		if (k <= 2 * near) k % 2 == 1 ? (k + 1) >> 1 : -(k >> 1) else {
			var far = near + k - 2 * near;
			-min > max ? -far : far;
		}
	}
}

// a finite float in min...=max: an int part and a fraction, shrinking to
// round numbers near 0 (min, max and 0 often drawn: the int part's
// bounds clamped, its 0); a range with no int in Int's range, a fraction
// of it
function float(min:Float, max:Float):Gen<Float> {
	if (!(min <= max) || !Math.isFinite(min) || !Math.isFinite(max)) throw new haxe.Exception('float($min, $max): not a finite range');
	var lo = Math.max(Math.ffloor(min), -2147483647.0), hi = Math.min(Math.fceil(max), 2147483647.0);
	if (lo > hi) return c -> min + (max - min) * (c.choice(0x7FFFFFFF) / 2147483647.0);
	var whole = int(Std.int(lo), Std.int(hi));
	return c -> {
		var v = c.draw(whole) + c.choice(0xFFFFFF) / 16777216.0;
		v < min ? min : v > max ? max : v;
	}
}

// true or false, shrinking to false
function bool():Gen<Bool>
	return c -> c.choice(1) == 1;

// always v
function constant<T>(v:T):Gen<T>
	return _ -> v;

// one of values, shrinking to the first
function pick<T>(values:Array<T>):Gen<T> {
	if (values.length == 0) throw new haxe.Exception("pick: no values");
	return c -> values[c.choice(values.length - 1)];
}

// a value of one of gens, shrinking to the first's
function oneOf<T>(gens:Array<Gen<T>>):Gen<T> {
	if (gens.length == 0) throw new haxe.Exception("oneOf: no generators");
	return c -> c.draw(gens[c.choice(gens.length - 1)]);
}

// min to max items of item, shrinking to fewer (each one a choice to go
// on, then the item: deleting both takes the item out). Mostly short,
// sometimes up to max.
function array<T>(item:Gen<T>, min = 0, max = 100):Gen<Array<T>>
	return c -> {
		var out = [for (_ in 0...min) c.draw(item)];
		var p = 1 - 1 / (c.roll(1 / 16) ? Math.max(2, max / 2) : 6);
		while (out.length < max) {
			var start = c.values.length;
			if (!c.weighted(p)) break;
			out.push(c.draw(item));
			c.span(start);
		}
		out;
	}

// a string of min to max characters of char (char(): letters mostly, and
// whitespace, line ends, right-to-left, combining marks, emoji, other
// scripts), sometimes long
function string(?chars:Gen<String>, min = 0, max = 2000):Gen<String> {
	var items = array(chars ?? char(), min, max);
	return c -> c.draw(items).join("");
}

// a character (sometimes a few code points: an emoji's sequence, a
// letter and its mark), ASCII's letters, digits and punctuation mostly;
// nul: NUL and control characters too
function char(nul = false):Gen<String> {
	var classes = nul ? CHARS : CHARS.slice(0, CHARS.length - 1);
	var weights = nul ? [60, 10, 6, 6, 6, 8, 4] : [60, 10, 6, 6, 6, 8];
	return c -> {
		var set = classes[c.weightedChoice(weights)];
		set[c.choice(set.length - 1)];
	}
}

// base, or extend's value of a smaller one, at most depth levels deep
// (shrinking to base)
function recursive<T>(base:Gen<T>, extend:Gen<T>->Gen<T>, depth = 3):Gen<T>
	return depth <= 0 ? base : oneOf([base, extend(recursive(base, extend, depth - 1))]);

// (char's classes, the simplest first: "a" is char's 0)
private final CHARS:Array<Array<String>> = [
	"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .,:;!?'\"()[]{}<>-_+=*/\\|&^%$#@~`".split(""),
	[" ", "\n", "\t", "\r\n", "\r", " ", " ", "　"],
	["א", "ש", "ת", "ا", "ب", "ع", "‏", "‮", "؜"],
	["é", "à", "ö", "́", "‍", "‌", "️", "ṇ̃"],
	["😀", "👍🏽", "👨‍👩‍👧", "🇧🇪", "❤️", "🏳️‍🌈", "𝔸"],
	["é", "ß", "中", "文", "ω", "ж", "क्", "�", "﻿", "ﬁ"],
	["\x00", "\x01", "\x1B", "\x7F", "\x0B", "\x0C"]
];
