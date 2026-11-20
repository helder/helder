package helder.ui;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;

// StyleFields's NAMES, get and set: for each field of StyleProps that is a
// property of Style both readable and writable (shorthands such as flex,
// gap and outline are written only, through their longhands); getAt and
// setAt by a name's place in NAMES, its id (an integer's switch)
class StyleFieldsMacro {
	public static function build():Array<Field> {
		var fields = Context.getBuildFields();
		var props = switch Context.follow(Context.getType("helder.ui.StyleProps")) {
			case TAnonymous(a): [for (f in a.get().fields) f.name];
			case _: throw "StyleProps";
		}
		var style = switch Context.getType("helder.ui.Style") {
			case TInst(c, _): c.get();
			case _: throw "Style";
		}
		var names:Array<String> = [], types:Array<Type> = [];
		for (f in style.fields.get()) {
			if (!f.isPublic || props.indexOf(f.name) < 0) continue;
			switch f.kind {
				case FVar(read, write):
					if (read == AccNever || read == AccNo || write == AccNever || write == AccNo) continue;
				case _:
					continue;
			}
			names.push(f.name);
			types.push(f.type);
		}
		var getCases:Array<Case> = [for (n in names) {values: [macro $v{n}], expr: macro s.$n}];
		var setCases:Array<Case> = [for (n in names) {values: [macro $v{n}], expr: macro s.$n = v}];
		var getAtCases:Array<Case> = [for (i in 0...names.length) {values: [macro $v{i}], expr: {var n = names[i]; macro s.$n;}}];
		var setAtCases:Array<Case> = [for (i in 0...names.length) {values: [macro $v{i}], expr: {var n = names[i]; macro s.$n = v;}}];
		// (a property against a value as Rules keeps one, Dynamic: a number's,
		// a flag's, an enum abstract's compared unboxed, the others as they are)
		var sameAtCases:Array<Case> = [for (i in 0...names.length) {values: [macro $v{i}], expr: {
			var n = names[i], t = types[i];
			var nullable = isNull(t);
			if (nullable) macro @:privateAccess helder.ui.Rules.same(s.$n, v) else switch Context.followWithAbstracts(t) {
				case TAbstract(_.get() => {name: "Float", pack: []}, _):
					macro {
						var x:Float = s.$n;
						v != null && {
							var y:Float = v;
							x == y || x != x && y != y;
						}
					};
				case TAbstract(_.get() => {name: "Int" | "Bool", pack: []}, _):
					var ct = Context.toComplexType(t);
					macro v != null && s.$n == (v : $ct);
				case _:
					macro @:privateAccess helder.ui.Rules.same(s.$n, v);
			}
		}}];
		var pos = Context.currentPos();
		var nameExprs:Array<Expr> = [for (n in names) macro $v{n}];
		fields.push({
			name: "NAMES",
			access: [APublic, AStatic, AFinal],
			pos: pos,
			kind: FVar(macro :Array<String>, macro $a{nameExprs})
		});
		fields.push({
			name: "get",
			access: [APublic, AStatic],
			pos: pos,
			kind: FFun({
				args: [{name: "s", type: macro :helder.ui.Style}, {name: "name", type: macro :String}],
				ret: macro :Dynamic,
				expr: macro return ${{expr: ESwitch(macro name, getCases, macro null), pos: pos}}
			})
		});
		fields.push({
			name: "set",
			access: [APublic, AStatic],
			pos: pos,
			kind: FFun({
				args: [
					{name: "s", type: macro :helder.ui.Style},
					{name: "name", type: macro :String},
					{name: "v", type: macro :Dynamic}
				],
				ret: macro :Void,
				expr: {expr: ESwitch(macro name, setCases, macro {}), pos: pos}
			})
		});
		fields.push({
			name: "getAt",
			access: [APublic, AStatic],
			pos: pos,
			kind: FFun({
				args: [{name: "s", type: macro :helder.ui.Style}, {name: "id", type: macro :Int}],
				ret: macro :Dynamic,
				expr: macro return ${{expr: ESwitch(macro id, getAtCases, macro null), pos: pos}}
			})
		});
		fields.push({
			name: "setAt",
			access: [APublic, AStatic],
			pos: pos,
			kind: FFun({
				args: [
					{name: "s", type: macro :helder.ui.Style},
					{name: "id", type: macro :Int},
					{name: "v", type: macro :Dynamic}
				],
				ret: macro :Void,
				expr: {expr: ESwitch(macro id, setAtCases, macro {}), pos: pos}
			})
		});
		fields.push({
			name: "sameAt",
			access: [APublic, AStatic],
			pos: pos,
			kind: FFun({
				args: [
					{name: "s", type: macro :helder.ui.Style},
					{name: "id", type: macro :Int},
					{name: "v", type: macro :Dynamic}
				],
				ret: macro :Bool,
				expr: macro return ${{expr: ESwitch(macro id, sameAtCases, macro false), pos: pos}}
			})
		});
		return fields;
	}

	// (a Null<T>, under typedefs and lazy types: Context.follow takes Null off)
	static function isNull(t:Type):Bool
		return switch t {
			case TAbstract(_.get() => {name: "Null", pack: []}, _): true;
			case TType(_.get() => {name: "Null", pack: []}, _): true;
			case TType(d, ps): isNull(haxe.macro.TypeTools.applyTypeParameters(d.get().type, d.get().params, ps));
			case TLazy(f): isNull(f());
			case _: false;
		}
}
#end
