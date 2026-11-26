package helder.css;

import helder.css.CssTerm;
#if macro
import haxe.macro.Expr;
#end

// The properties' initial values, parsed when the program is compiled
// (CssData's, and the prose ones CssShorthands writes out): a program
// that cascades links no CSS parser for them.
class CssInitial {
	#if !macro
	// a property's initial value as its table says it (null: none, or prose)
	public static function specified(property:String):Null<CssSpecified>
		return table(property, false);

	// a longhand's initial value, prose written out (CssShorthands.initialTerms)
	public static function of(longhand:String):Null<CssSpecified>
		return table(longhand, true);
	#end

	static macro function table(name:Expr, prose:Bool):Expr {
		var pos = haxe.macro.Context.currentPos();
		var written:Map<String, String> = @:privateAccess CssShorthands.INITIAL;
		var cases = [];
		for (p in CssData.properties) {
			var text = prose ? written.get(p.name) ?? p.initial : p.initial;
			var v = text == null ? null : CssValues.parse(p.name, text);
			if (v != null) cases.push({values: [macro $v{p.name}], expr: @:privateAccess CssTheme.value(v, pos)});
		}
		for (n => text in written)
			if (prose && CssData.properties.filter(p -> p.name == n).length == 0) {
				var v = CssValues.parse(n, text);
				if (v != null) cases.push({values: [macro $v{n}], expr: @:privateAccess CssTheme.value(v, pos)});
			}
		return {expr: ESwitch(name, cases, macro null), pos: pos};
	}
}
