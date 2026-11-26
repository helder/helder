package helder.typescript;

import core.TType;
import typing.TypeloadFields;

using core.TFunctions;

// The declaration files' generator's typing (Generator): under -D
// helder.declarations a method whose type is written in full (a Void
// result left out, an argument's type its literal default's) is not
// typed, its expression a function of its arguments (their metadata kept:
// @:typescript.type) whose body only throws (hxmc's
// TypeBinding.untypedBodyHook), so the generator types the signatures it
// prints and nothing they do not reach (a material's body names its
// shader, whose final runs the shader macro: seconds each). Its default
// values are not typed either (a default naming an enum abstract's value,
// Color.BLACK, typed with the signature finds it not built yet); an
// optional argument's is null.
class Signatures {
	static var installed = false;

	public static function install() {
		if (installed) return;
		installed = true;
		var hook = TypeBinding.untypedBodyHook;
		TypeBinding.untypedBodyHook = (ctx, c, cf, fctx, args, t, ret, e, p) -> {
			var body = hook == null ? null : hook(ctx, c, cf, fctx, args, t, ret, e, p);
			body != null ? body : stub(ctx, c, cf, fctx, args, t, ret, e, p);
		}
	}

	static function stub(ctx:context.Typecore.Typer, c:TClass, cf:TClassField, fctx:FieldInitCtx, args:typing.FunctionArguments, t:T, ret:T,
			e:core.Ast.Expr, p:core.Globals.Pos):Null<TExpr> {
		if (ctx.com.isMacroContext || !core.Define.rawDefined(ctx.com.defines, Generator.DEFINE)) return null;
		if (fctx.isMacro || fctx.isExtern || fctx.isGeneric) return null;
		if (fctx.isInline || !fctx.fieldKind.match(CfrStatic | CfrMember | CfrConstructor)) return null;
		if (!cf.cfKind.match(Method(MethNormal)) || cf.cfOverloads.length > 0) return null;
		if (cf.cfMeta.length > 0 && (core.Meta.has(Overload, cf.cfMeta) || TypeloadFields.getCoroConfig(ctx, cf.cfMeta) != null)) return null;
		var syntax = @:privateAccess args.syntax, typed = @:privateAccess args.withDefault;
		var offset = typed.length - syntax.length;
		// (an argument of no type written, its default a literal: the literal's type, as Haxe infers it)
		for (i in 0...syntax.length) if (syntax[i].type == null && syntax[i].expr != null) {
			var basic = literal(ctx, syntax[i].expr);
			if (basic != null) context.Typecore.unify(ctx, basic, typed[i + offset].type, p);
		}
		// (no result written: Void when the body returns no value, as Haxe infers it)
		var void = switch ret {
			case TMono(m) if (m.tmType == null): m;
			case _: null;
		}
		if (!full(t, void) || void != null && !returnsNothing(e)) return null;
		if (void != null) context.Typecore.unify(ctx, ctx.t.tvoid, ret, p);
		var vars = [for (i in 0...typed.length) {
			var v = core.TFunctions.allocVar(VUser(TVOArgument), typed[i].name, typed[i].type, i < offset ? p : syntax[i - offset].name.pos);
			if (i >= offset) v.vMeta = syntax[i - offset].meta;
			// (an optional one's default null: what a subclass's inherited constructor takes as optional)
			{variable: v, defaultValue: typed[i].expr == null ? null : core.Texpr.Builder.makeNull(typed[i].type, p)};
		}];
		var msg = core.Globals.sTypePath(c.clPath) + "." + cf.cfName + ": not typed (" + Generator.DEFINE + ")";
		var tf:TFunc = {
			tfArgs: haxe.ds.Vector.fromArrayCopy(vars),
			tfType: ret,
			tfExpr: core.TFunctions.mk(TThrow(core.TFunctions.mk(TConst(TString(msg)), ctx.t.tstring, p)), ctx.t.tvoid, p)
		};
		return core.TFunctions.mk(TFunction(tf), t, p);
	}

	// (nothing left to infer, but the result void)
	static function full(t:T, void:Null<TMono>):Bool {
		switch t {
			case TFun(s):
				for (a in s.args) if (!full(a.type, void)) return false;
				return full(s.ret, void);
			case TMono(m):
				return m.tmType != null ? full(m.tmType, void) : m == void;
			case _:
				return true;
		}
	}

	static function literal(ctx:context.Typecore.Typer, e:core.Ast.Expr):Null<T>
		return switch e.expr {
			case EConst(Int(_, null)): ctx.t.tint;
			case EConst(Float(_, null)): ctx.t.tfloat;
			case EConst(String(_, _)): ctx.t.tstring;
			case EConst(Ident("true" | "false")): ctx.t.tbool;
			case EUnop(Neg, Prefix, v): literal(ctx, v);
			case _: null;
		}

	static function returnsNothing(e:core.Ast.Expr):Bool {
		function loop(e:core.Ast.Expr)
			switch e.expr {
				case EReturn(v) if (v != null): throw core.ds.Exit.raise();
				case EFunction(_, _):
				case _: core.Ast.iterExpr(loop, e);
			}
		return try {
			loop(e);
			true;
		} catch (_:core.ds.Exit) false;
	}
}
