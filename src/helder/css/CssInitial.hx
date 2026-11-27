package helder.css;

import helder.css.CssTerm;
#if macro
import haxe.macro.Expr;
#end

// The properties' initial values, parsed when the program is compiled
// (CssData's, and the prose ones CssShorthands writes out) and kept as
// data (CssSheetData.encodeInitials), read when first asked: a program
// that cascades links no CSS parser for them, nor code per value.
typedef CssInitialValue = {specified:Null<CssSpecified>, of:Null<CssSpecified>}

class CssInitial {
	#if !macro
	static var values:Null<Map<String, CssInitialValue>>;

	// a property's initial value as its table says it (null: none, or prose)
	public static function specified(property:String):Null<CssSpecified> {
		var v = table().get(property);
		return v == null ? null : v.specified;
	}

	// a longhand's initial value, prose written out (CssShorthands.initialTerms)
	public static function of(longhand:String):Null<CssSpecified> {
		var v = table().get(longhand);
		return v == null ? null : v.of;
	}

	static function table():Map<String, CssInitialValue>
		return values ??= CssSheetData.decodeInitials(data());
	#end

	static macro function data():Expr {
		var written:Map<String, String> = @:privateAccess CssShorthands.INITIAL;
		var entries = [];
		for (p in CssData.properties) {
			var specified = p.initial == null ? null : CssValues.parse(p.name, p.initial);
			var text = written.get(p.name) ?? p.initial;
			var of = text == null ? null : CssValues.parse(p.name, text);
			if (specified != null || of != null) entries.push({name: p.name, specified: specified, of: of});
		}
		for (n => text in written)
			if (CssData.properties.filter(p -> p.name == n).length == 0) {
				var of = CssValues.parse(n, text);
				if (of != null) entries.push({name: n, specified: null, of: of});
			}
		return macro $v{CssSheetData.encodeInitials(entries)};
	}
}
