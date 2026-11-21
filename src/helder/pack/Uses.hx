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
// - plist: a class marked @:helder.ios.plist("<key>", ...), Info.plist's
//   keys set true (helder.os.Paths.documents: the Files app's);
// - frameworks: a class marked @:helder.apple.framework("<name>"), the
//   frameworks of helder's an Apple bundle carries (helder.pack.apple.
//   Frameworks: helder.store.Purchases' HelderStore);
// - permissions: what is asked of a function marked @:helder.permission
//   (Permissions.status, request; TypeScript's wrapper of it), its first
//   argument a constant ("camera"), with where; any other argument asks
//   for all of them (PERMISSIONS); one marked @:helder.permission("<p>")
//   asks for p (Location.current);
// - usage: a function marked @:helder.ios.usage("<p>") needs p's usage
//   string on iOS, and nothing of Android's manifest (Photos.take:
//   Android's own camera app takes the photo; Biometrics.verify, "faceid").
// (a TypeScript program's: helder.typescript.Uses, after its lowering)
class Uses {
	public static final PERMISSIONS = ["camera", "microphone", "photos", "location", "notifications"];

	#if macro
	public static function of(types:Array<Type>):{services:Array<String>, android:Array<String>, plist:Array<String>, frameworks:Array<String>,
		permissions:Map<String, Position>, usage:Map<String, Position>} {
		var services = [], android = [], plist = [], frameworks = [], permissions = new Map<String, Position>(), usage = new Map<String, Position>();
		function add(to:Array<String>, meta:MetaAccess, name:String)
			for (m in meta.extract(name))
				for (p in m.params)
					switch p.expr {
						case EConst(CString(s, _)) if (!to.contains(s)): to.push(s);
						case _:
					}
		// (each marked function's fixed permission or usage: "" for its first argument's)
		var marked = new Map<String, String>(), usages = new Map<String, String>();
		function fixed(meta:MetaAccess, name:String):String {
			var given = [];
			add(given, meta, name);
			return given.length == 0 ? "" : given[0];
		}
		for (t in types)
			switch t {
				case TInst(_.get() => c, _):
					add(services, c.meta, ":helder.android.dex");
					add(android, c.meta, ":helder.android.permission");
					add(plist, c.meta, ":helder.ios.plist");
					add(frameworks, c.meta, ":helder.apple.framework");
					for (f in c.statics.get()) {
						if (f.meta.has(":helder.permission")) marked.set(f.name, fixed(f.meta, ":helder.permission"));
						if (f.meta.has(":helder.ios.usage")) usages.set(f.name, fixed(f.meta, ":helder.ios.usage"));
					}
				case _:
			}
		var out = {services: services, android: android, plist: plist, frameworks: frameworks, permissions: permissions, usage: usage};
		if (!marked.keys().hasNext() && !usages.keys().hasNext()) return out;
		// (f marked, or TypeScript's wrapper of it: __co_<name>)
		function mark(c:ClassType, f:ClassField, of:Map<String, String>):Null<String>
			return f.meta.has(of == marked ? ":helder.permission" : ":helder.ios.usage") ? of.get(f.name) : c.module == "helder.os.TypeScript" ? of.get(f.name.substr(5)) : null;
		function constant(e:TypedExpr):Null<String>
			return switch e.expr {
				case TConst(TString(s)): s;
				case TCast(e, _) | TParenthesis(e) | TMeta(_, e): constant(e);
				case _: null;
			}
		function scan(e:TypedExpr)
			switch e.expr {
				case TCall({expr: TField(_, FStatic(_.get() => c, _.get() => f))}, args) if (mark(c, f, usages) != null):
					var u = mark(c, f, usages);
					if (!usage.exists(u)) usage.set(u, e.pos);
					for (a in args)
						scan(a);
				case TCall({expr: TField(_, FStatic(_.get() => c, _.get() => f))}, args) if (mark(c, f, marked) != null):
					// (a coroutine's call, transformed: its continuation first)
					var given = [for (a in args) if (!a.expr.match(TLocal({name: "_hx_continuation"}))) a];
					var m = mark(c, f, marked);
					var p = m != "" ? m : given.length == 0 ? null : constant(given[0]);
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
						if (f.meta.has(":helder.permission") || f.meta.has(":helder.ios.usage") || StringTools.startsWith(f.name, "__co_")) continue;
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
		return out;
	}
#end
}
