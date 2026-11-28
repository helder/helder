package helder.ui;

// A theme's token: a custom property (--surface) of a type, a colour
// (Token<Color>), a length in px (Token<Length>) or a number
// (Token<Number>), its value the one the theme in scope gives (Theme.load's
// file). A loaded theme's fields are its tokens, typed: theme.surface goes
// where a colour does, a misspelt one an error when the program is built.
abstract Token<T>(String) to String {
	@:noCompletion public inline function new(name:String)
		this = name;

	public var name(get, never):String;

	inline function get_name():String
		return this;
}

// (a token's types: what a value of it is)
abstract Length(Float) to Float {}
abstract Number(Float) to Float {}
