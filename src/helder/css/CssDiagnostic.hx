package helder.css;

enum abstract CssSeverity(String) to String {
	var Error = "error";
	var Warning = "warning";
}

// A problem in a style sheet found when it is compiled (CssScope's,
// CssModule's): where, as file:line:column (1-based; columns in the
// text's String units: UTF-16 natively, code points on Eval), and its
// offsets, for a compiler's positions.
typedef CssDiagnostic = {
	file:String,
	line:Int,
	column:Int,
	start:Int,
	end:Int,
	message:String,
	severity:CssSeverity
}

// A text's lines, to turn offsets into lines and columns.
class CssLines {
	final starts:Array<Int> = [0];

	public function new(text:String) {
		for (k in 0...text.length)
			if (StringTools.fastCodeAt(text, k) == "\n".code) starts.push(k + 1);
	}

	// (1-based line and column of an offset)
	public function at(offset:Int):{line:Int, column:Int} {
		var lo = 0, hi = starts.length - 1;
		while (lo < hi) {
			var mid = (lo + hi + 1) >> 1;
			if (starts[mid] <= offset) lo = mid else hi = mid - 1;
		}
		return {line: lo + 1, column: offset - starts[lo] + 1};
	}

	public function line(offset:Int):Int
		return at(offset).line;
}
