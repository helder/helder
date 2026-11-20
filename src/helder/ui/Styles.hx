package helder.ui;

// A style given untyped as StyleProps: a TypeScript program's, its values
// as markup's attributes write them ("row", "0 12", "#3b82f6", "scale(0.97)",
// numbers; kebab-case names too), parsed once: a sheet's rules when it is
// first used (Rules), a look's recipes when it is compiled
// (helder.ui.controls). A value already of its property's type (Haxe's) is
// kept as it is.
class Styles {
	static final STRINGS = ["fontFamily", "page", "gridArea", "fontFeatureSettings", "fontVariantNumeric"];
	static final FLOATS = [
		"grow", "shrink", "aspectRatio", "paddingTop", "paddingRight", "paddingBottom", "paddingLeft", "marginTop", "marginRight", "marginBottom", "marginLeft",
		"borderWidth", "rowGap", "columnGap", "letterSpacing", "letterSpacingEm", "wordSpacing", "radius", "opacity", "ringWidth", "ringOffsetWidth",
		"outlineWidth", "outlineOffset", "fontSize", "lineHeight", "lineHeightPx", "gap", "flex"
	];
	static final DIMS = ["basis", "width", "height", "minWidth", "minHeight", "maxWidth", "maxHeight", "left", "top", "right", "bottom", "inset",
		"textDecorationThickness", "textUnderlineOffset"];
	static final EDGES = ["padding", "margin", "borders"];
	// (objects and lists: a string or a list of numbers and strings parsed)
	static final OBJECTS = ["textShadow", "shadow", "backgroundImage", "transform", "transition", "corners", "transformOrigin", "gridTemplateColumns",
		"gridTemplateRows", "gridAutoColumns", "gridAutoRows", "gridColumn", "gridRow", "gridTemplateAreas"];
	// (shorthands not kept as themselves, and the longhands they set)
	static final SIDES = [
		"padding" => ["paddingTop", "paddingRight", "paddingBottom", "paddingLeft"],
		"margin" => ["marginTop", "marginRight", "marginBottom", "marginLeft"],
		"gap" => ["rowGap", "columnGap"],
		"inset" => ["top", "right", "bottom", "left"]
	];

	// o's properties as StyleProps
	public static function of(o:Dynamic):StyleProps {
		var out:Dynamic = {};
		var scratch:Null<Style> = null;
		for (key in Reflect.fields(o)) {
			var name = camel(key), v:Dynamic = Reflect.field(o, key);
			if (v == null) continue;
			if (typed(name, v)) {
				// (a number as its property stores it: JavaScript's are floats)
				var number = Std.isOfType(v, Float) || Std.isOfType(v, Int);
				Reflect.setField(out, name, !number ? v : FLOATS.indexOf(name) >= 0 ? (v : Float) : (Std.int(v) : Dynamic));
				continue;
			}
			if (scratch == null) scratch = new Node().style;
			if (!helder.ui.view.StyleAttrs.apply(scratch, name, v)) throw 'helder.ui: no style property $key';
			var sides = SIDES.get(name);
			if (sides != null) {
				for (s in sides)
					Reflect.setField(out, s, StyleFields.get(scratch, s));
			} else if (StyleFields.NAMES.indexOf(name) >= 0) Reflect.setField(out, name, StyleFields.get(scratch, name));
			else throw 'helder.ui: $key is written through its longhands only';
		}
		return out;
	}

	// (whether v is already a value of the property's type)
	static function typed(name:String, v:Dynamic):Bool {
		if (STRINGS.indexOf(name) >= 0 || Std.isOfType(v, Bool)) return true;
		if (Std.isOfType(v, String)) return false;
		var number = Std.isOfType(v, Float) || Std.isOfType(v, Int);
		if (DIMS.indexOf(name) >= 0) return Std.isOfType(v, DimValue);
		if (EDGES.indexOf(name) >= 0) return Std.isOfType(v, Edges);
		if (OBJECTS.indexOf(name) >= 0) {
			if (number) return false;
			if (!Std.isOfType(v, Array)) return true;
			var a:Array<Dynamic> = v;
			return a.length > 0 && !(Std.isOfType(a[0], String) || Std.isOfType(a[0], Float) || Std.isOfType(a[0], Int));
		}
		// (a number: an enum's, an integer's, a float's, a colour's bits)
		return number;
	}

	static function camel(n:String):String {
		if (n.indexOf("-") < 0) return n;
		var parts = n.split("-");
		return parts[0] + [for (p in parts.slice(1)) p.charAt(0).toUpperCase() + p.substr(1)].join("");
	}
}
