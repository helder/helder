package helder.css;

// name: as written (custom properties are case-sensitive, others are
// the cascade's to fold); value: without the whitespace around it and
// without !important; text: a custom property's value as written in the
// source (null for others)
class CssDeclaration {
	public final name:String;
	public final value:Array<CssValue>;
	public final important:Bool;
	public final text:Null<String>;
	// the name's start to the value's end, in the text's String units
	public final start:Int;
	public final end:Int;

	public function new(name:String, value:Array<CssValue>, important:Bool, text:Null<String>, start:Int, end:Int) {
		this.name = name;
		this.value = value;
		this.important = important;
		this.text = text;
		this.start = start;
		this.end = end;
	}
}
