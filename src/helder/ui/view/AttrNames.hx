package helder.ui.view;

// ui's markup attributes checked when compiling, the same for Haxe's markup
// (AttrMacro) and TypeScript's (helder.typescript's Tsx, from the
// manifest's table): a name none of ui's elements has, and a literal value
// an enum attribute does not take, are errors that say what was meant
class AttrNames {
	// (CSS's names that are another's here)
	static final CSS:Map<String, String> = [
		"flex-direction" => "direction", "flexDirection" => "direction", "flex-wrap" => "wrap", "flexWrap" => "wrap", "border-radius" => "radius",
		"borderRadius" => "radius", "background-color" => "background", "backgroundColor" => "background", "box-shadow" => "shadow", "boxShadow" => "shadow",
		"justify-content" => "justify", "justifyContent" => "justify"
	];

	// the message for an attribute none of names is: the name meant, CSS's or the nearest
	public static function unknown(name:String, names:Array<String>):String {
		var meant = CSS.get(name);
		if (meant != null && names.indexOf(meant) < 0) meant = null;
		if (meant == null) {
			var best = 4;
			for (n in names) {
				var d = distance(name.toLowerCase(), n.toLowerCase());
				if (d < best) {
					best = d;
					meant = n;
				}
			}
		}
		return "helder.ui: no attribute " + name + " (not one of NodeRenderer's or Style's)" + (meant == null ? "" : "; did you mean " + meant + "?");
	}

	// a value as an enum attribute's literal is matched (lower case, no - or _)
	public static function key(s:String):String
		return StringTools.replace(StringTools.replace(s, "-", ""), "_", "").toLowerCase();

	// the message for a literal value an enum attribute does not take (keys: its values', as key gives them)
	public static function badValue(name:String, value:String, type:String, keys:Array<String>):String
		return 'helder.ui: $name="$value": not a $type (${keys.join(", ")})';

	// (Levenshtein's)
	static function distance(a:String, b:String):Int {
		var prev = [for (j in 0...b.length + 1) j];
		for (i in 1...a.length + 1) {
			var cur = [i];
			for (j in 1...b.length + 1)
				cur.push(Std.int(Math.min(Math.min(cur[j - 1] + 1, prev[j] + 1), prev[j - 1] + (a.charCodeAt(i - 1) == b.charCodeAt(j - 1) ? 0 : 1))));
			prev = cur;
		}
		return prev[b.length];
	}
}
