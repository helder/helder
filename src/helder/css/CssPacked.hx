package helder.css;

// Data as one ASCII string of chars 1 to 127, a plain string constant
// (compiled sheets, CssSheetData; generate.mjs's tables, CssTable and
// CssProperties; CssInitial's values): unsigned numbers as base-64 digits
// (a char of 64 or more carries 6 bits and goes on, one below 64 ends the
// number, plus one), ints zigzagged, strings interned (0 and the string,
// else its index plus one; ASCII as it is, else each code unit as a
// number), floats as ints where whole, else as their text. generate.mjs
// writes the same in JavaScript.
@:allow(helder.css)
class CssPacked {
	final data:String;
	var at = 0;
	final pool:Array<String> = [];

	public function new(data:String)
		this.data = data;

	public function uint():Int {
		var v = 0, shift = 0;
		while (true) {
			var c = StringTools.fastCodeAt(data, at++);
			if (c < 64) return v | ((c - 1) << shift);
			v |= (c - 64) << shift;
			shift += 6;
		}
	}

	public function int():Int {
		var n = uint();
		return (n >>> 1) ^ -(n & 1);
	}

	public function bool():Bool
		return uint() != 0;

	public function str():String {
		var k = uint();
		if (k > 0) return pool[k - 1];
		var n = uint(), len = n >>> 1, s;
		if (n & 1 == 0) {
			s = data.substr(at, len);
			at += len;
		} else {
			var b = new StringBuf();
			for (_ in 0...len) b.addChar(uint());
			s = b.toString();
		}
		pool.push(s);
		return s;
	}

	public function nstr():Null<String>
		return bool() ? str() : null;

	public function float():Float {
		if (uint() == 0) return int();
		return switch str() {
			case "NaN": Math.NaN;
			case "Infinity": Math.POSITIVE_INFINITY;
			case "-Infinity": Math.NEGATIVE_INFINITY;
			case s: Std.parseFloat(s);
		}
	}

	public function list<T>(f:() -> T):Array<T>
		return [for (_ in 0...uint()) f()];

	public function nlist<T>(f:() -> T):Null<Array<T>>
		return bool() ? list(f) : null;

	public function ints():Array<Int>
		return list(int);

	public function strs():Array<String>
		return list(str);

	public function bools():Array<Bool>
		return list(bool);

	public function lists():Array<Array<String>>
		return list(strs);

	public function intLists():Array<Array<Int>>
		return list(ints);
}
