package helder.pack;

#if macro
import haxe.macro.Expr.Position;
import haxe.macro.Type;
#end

// What a program uses of what its package must declare, read once it is
// generated (after dead code elimination, when the build has it; a dev
// build has every class it typed):
// - services: a class marked @:helder.android.dex("<name>", ...), Glue's
//   app service classes (helder.pack.android.Glue.SERVICES);
// - android: a class marked @:helder.android.permission("<name>", ...),
//   the manifest's permissions;
// - permissions: what is asked of a function marked @:helder.permission
//   (Permissions.status, request; TypeScript's wrapper of it), its first
//   argument a constant ("camera"), with where; any other argument asks
//   for all of them (PERMISSIONS).
// (a TypeScript program's: helder.typescript.Uses, after its lowering)
class Uses {
	public static final PERMISSIONS = ["camera", "microphone", "photos", "location", "notifications"];

	#if macro
	public static function of(types:Array<Type>):{services:Array<String>, android:Array<String>, permissions:Map<String, Position>} {
		var services = [], android = [], permissions = new Map<String, Position>();
		function add(to:Array<String>, meta:MetaAccess, name:String)
			for (m in meta.extract(name))
				for (p in m.params)
					switch p.expr {
						case EConst(CString(s, _)) if (!to.contains(s)): to.push(s);
						case _:
					}
		var marked = new Map<String, Bool>();
		for (t in types)
			switch t {
				case TInst(_.get() => c, _):
					add(services, c.meta, ":helder.android.dex");
					add(android, c.meta, ":helder.android.permission");
					for (f in c.statics.get())
						if (f.meta.has(":helder.permission")) marked.set(f.name, true);
				case _:
			}
		if (!marked.keys().hasNext()) return {services: services, android: android, permissions: permissions};
		function constant(e:TypedExpr):Null<String>
			return switch e.expr {
				case TConst(TString(s)): s;
				case TCast(e, _) | TParenthesis(e) | TMeta(_, e): constant(e);
				case _: null;
			}
		function scan(e:TypedExpr)
			switch e.expr {
				case TCall({expr: TField(_, FStatic(c, _.get() => f))}, args) if ((f.meta.has(":helder.permission") || (c.toString() == "helder.os.TypeScript" && marked.exists(f.name.substr(5))))):
					// (a coroutine's call, transformed: its continuation first)
					var given = [for (a in args) if (!a.expr.match(TLocal({name: "_hx_continuation"}))) a];
					var p = given.length == 0 ? null : constant(given[0]);
					if (p != null && PERMISSIONS.contains(p)) {
						if (!permissions.exists(p)) permissions.set(p, e.pos);
					} else
						for (q in PERMISSIONS)
							if (!permissions.exists(q)) permissions.set(q, e.pos);
					for (a in args)
						scan(a);
				case _:
					haxe.macro.TypedExprTools.iter(e, scan);
			}
		for (t in types)
			switch t {
				case TInst(_.get() => c, _):
					for (f in c.statics.get().concat(c.fields.get())) {
						if (f.meta.has(":helder.permission") || StringTools.startsWith(f.name, "__co_")) continue;
						var e = f.expr();
						if (e != null) scan(e);
					}
					if (c.constructor != null) {
						var e = c.constructor.get().expr();
						if (e != null) scan(e);
					}
					if (c.init != null) scan(c.init);
				case _:
			}
		return {services: services, android: android, permissions: permissions};
	}
#end
}
