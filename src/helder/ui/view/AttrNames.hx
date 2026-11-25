package helder.ui.view;

// ui's markup attributes checked when compiling, the same for Haxe's markup
// (AttrMacro) and TypeScript's (helder.typescript's Tsx, from the
// manifest's table): a name none of ui's elements has, and a literal value
// an enum attribute does not take, are errors that say what was meant
class AttrNames {
	// the message for an attribute none of ui's elements has: the name meant (helder.view.Vocabulary's hint, as the planner's)
	public static function unknown(name:String):String
		return helder.view.Vocabulary.attribute("view", name) ?? "markup: no attribute " + name;

	// a value as an enum attribute's literal is matched (lower case, no - or _)
	public static function key(s:String):String
		return StringTools.replace(StringTools.replace(s, "-", ""), "_", "").toLowerCase();

	// the message for a literal value an enum attribute does not take (keys: its values', as key gives them)
	public static function badValue(name:String, value:String, type:String, keys:Array<String>):String
		return 'helder.ui: $name="$value": not a $type (${keys.join(", ")})';
}
