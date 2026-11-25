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
		return switch e.expr {
			case EConst(CString(s, _)) if (values.contains(s)): macro(cast $e : $ct);
			case EConst(CString(s, _)): Context.error('"$s" is not a ${a.name}: ' + values.join(", "), e.pos);
			case _: Context.error('A ${a.name} is one of its values (' + values.join(", ") + '), not any string', e.pos);
		}
	}
}
#end
