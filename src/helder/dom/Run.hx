package helder.dom;

// A string the tokenizer builds: a slice of the input while it is one
// (no buffer, no copy until taken), a buffer once anything else is added.
@:noCompletion class Run {
	var s:String;
	var a = 0;
	var b = 0;
	var buf:Null<StringBuf> = null;

	public function new(s:String)
		this.s = s;

	public inline function reset() {
		a = b = 0;
		buf = null;
	}

	// s[from, to)
	public function sub(from:Int, to:Int) {
		if (from == to) return;
		if (buf == null) {
			if (a == b) {
				a = from;
				b = to;
				return;
			}
			if (b == from) {
				b = to;
				return;
			}
			buf = new StringBuf();
			buf.addSub(s, a, b - a);
		}
		buf.addSub(s, from, to - from);
	}

	public function char(c:Int) {
		if (buf == null) {
			buf = new StringBuf();
			if (a < b) buf.addSub(s, a, b - a);
		}
		buf.addChar(c);
	}

	public function add(t:String) {
		if (t == "") return;
		if (buf == null) {
			buf = new StringBuf();
			if (a < b) buf.addSub(s, a, b - a);
		}
		buf.add(t);
	}

	// as take, a known tag or attribute name as its interned string (no copy)
	public function name():String {
		if (buf == null && a < b) {
			var n = Tags.intern(s, a, b);
			if (n != null) return n;
		}
		return take();
	}

	public function take():String
		return buf != null ? buf.toString() : a == b ? "" : s.substring(a, b);
}
