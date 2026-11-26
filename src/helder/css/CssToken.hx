package helder.css;

// A token of CSS Syntax 3 and where it was read: start and end in the
// text's String units (UTF-16 code units natively and as wasm32-wasi,
// code points on Eval), end exclusive
class CssToken {
	public final kind:CssTokenKind;
	public final start:Int;
	public final end:Int;

	public function new(kind:CssTokenKind, start:Int, end:Int) {
		this.kind = kind;
		this.start = start;
		this.end = end;
	}

	public function toString():String
		return Serializer.token(this);
}

enum CssTokenKind {
	Ident(value:String);
	Function(name:String);
	AtKeyword(name:String);
	// id: the "id" type flag (the value would start an ident), else "unrestricted"
	Hash(value:String, id:Bool);
	Str(value:String);
	BadString;
	Url(value:String);
	BadUrl;
	// one code point
	Delim(value:String);
	// text: the number as written ("+.5e1"), for serialization; integer: the
	// "integer" type flag (no "." nor exponent)
	Number(value:Float, integer:Bool, text:String);
	Percentage(value:Float, integer:Bool, text:String);
	Dimension(value:Float, integer:Bool, text:String, unit:String);
	// only where unicode ranges are allowed (the unicode-range descriptor)
	UnicodeRange(start:Int, end:Int);
	Whitespace;
	Cdo;
	Cdc;
	Colon;
	Semicolon;
	Comma;
	OpenSquare;
	CloseSquare;
	OpenParen;
	CloseParen;
	OpenCurly;
	CloseCurly;
}
