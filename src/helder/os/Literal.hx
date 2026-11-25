package helder.os;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;

// A string enum's @:from (`@:from static macro function ofString(e) return
// Literal.of(e)`): a literal checked against the values when compiled, so
// markup's `titlebar="inset"` is a TitleBar and `titlebar="insets"` an error
class Literal {
	public static function of(e:Expr):Expr {
		var t = Context.getExpectedType();
		while (true) switch t {
			case TAbstract(_.get() => {pack: [], name: "Null"}, [inner]) | TType(_.get() => {pack: [], name: "Null"}, [inner]): t = inner;
			case TType(_, _) | TLazy(_): t = Context.follow(t, true);
			case TMono(_.get() => m) if (m != null): t = m;
			case _: break;
		}
		var a = switch t {
			case TAbstract(a, _) if (a.get().impl != null): a.get();
			case _: Context.error("Not a string enum", e.pos);
		}
		var values = [for (f in a.impl.get().statics.get()) if (f.meta.has(":enum")) switch f.expr()?.expr {
			case TConst(TString(s)) | TCast({expr: TConst(TString(s))}, _): s;
			case _: continue;
		}];
		var ct = haxe.macro.TypeTools.toComplexType(t);
		return switch string(e) {
			case null: Context.error('A ${a.name} is one of its values (' + values.join(", ") + '), not any string', e.pos);
			case s if (values.contains(s)): macro(cast $e : $ct);
			case s: Context.error('"$s" is not a ${a.name}: ' + values.join(", "), e.pos);
		}
	}

	// (a literal Haxe typed before the cast, a ternary's branch in a
	// closure: a stored typed expression, a block of the one constant; in a
	// dev build markup's literal is a live one, Literals.string(id, value, anchor))
	static function string(e:Expr):Null<String> {
		return switch e.expr {
			case EConst(CString(s, _)): s;
			case EParenthesis(i): string(i);
			case EMeta({name: ":storedTypedExpr"}, _): typed(Context.typeExpr(e));
			case _: null;
		}
	}

	static function typed(e:TypedExpr):Null<String> {
		return switch e.expr {
			case TConst(TString(s)): s;
			case TParenthesis(i) | TMeta(_, i) | TCast(i, null) | TBlock([i]): typed(i);
			case TCall({expr: TField(_, FStatic(_.get() => {pack: ["helder", "dev"], name: "Literals"}, _.get() => {name: "string"}))}, [_, v, _]): typed(v);
			case _: null;
		}
	}
}
#end
