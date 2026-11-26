package helder.css;

// A component value: a preserved token, a function, or a simple block.
// open and close are the tokens around a function's or block's values
// (close: null when the text ended first).
enum CssValue {
	Token(token:CssToken);
	Function(name:String, values:Array<CssValue>, open:CssToken, close:Null<CssToken>);
	// open: OpenCurly, OpenSquare or OpenParen
	Block(open:CssToken, values:Array<CssValue>, close:Null<CssToken>);
}
