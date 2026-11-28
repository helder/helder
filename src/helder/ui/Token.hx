package helder.ui;

// A theme's token: a custom property (--surface) of a type, a colour
// (Token<Color>), a length in px (Token<Length>) or a number
// (Token<Number>), its value the one the theme in scope gives (Theme.load's
// file). A loaded theme's fields are its tokens, typed: theme.surface goes
// where a colour does, a misspelt one an error when the program is built.
// It is CSS's var(--name) as a string: markup's attributes take it so too.
abstract Token<T>(String) to String {
	@:noCompletion public inline function new(name:String)
		this = "var(--" + name + ")";

	// its name, without the "--"
	public var name(get, never):String;

	inline function get_name():String
		return this.substring(6, this.length - 1);
}

// (a token's types: what a value of it is)
abstract Length(Float) to Float {}
abstract Number(Float) to Float {}
