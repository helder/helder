package helder.typescript;

using StringTools;

// What a TypeScript program uses that its package declares, which the
// build's macros cannot see (helder.pack.Uses runs as Haxe's types are
// generated; helder's API is lowered for the program after): the markers
// of the classes whose functions it links, and the permissions it
// requests, read of its own source (a literal's, else all of them).
// Added to the APK's classes.json (-D helder.android.classes:
// helder.pack.android.Classes), or checked against iOS's usage strings
// (-D helder.ios.usage: helder.pack.ios.Usage).
class Uses {
	public static function record(com:context.Common.CommonContext, funcs:Array<String>, sources:Array<String>) {
		var classes = core.Define.rawDefinedValueSafe(com.defines, "helder.android.classes", "");
		var usage = core.Define.rawDefined(com.defines, "helder.ios.usage") ? core.Define.rawDefinedValueSafe(com.defines, "helder.ios.usage", "") : null;
		if (classes == "" && usage == null) return;
		var permissions = requested(sources);
		if (usage != null) {
			var missing = helder.pack.ios.Bundle.missingUsage(permissions, usage == "-" ? [] : usage.split(","));
			if (missing.length > 0)
				throw [
					for (p in missing)
						'iOS needs to be told why the app asks for $p: helder.json\'s targets.ios.usage.$p (Info.plist\'s ${helder.pack.ios.Bundle.usageKey(p)})'
				].join("\n");
		}
		if (classes == "" || !sys.FileSystem.exists(classes)) return;
		var linked = new Map<String, Bool>();
		for (f in funcs) linked.set(f, true);
		var j:Dynamic = haxe.Json.parse(sys.io.File.getContent(classes));
		var services:Array<String> = (j.services : Null<Array<String>>) ?? [], android:Array<String> = (j.permissions : Null<Array<String>>) ?? [];
		function add(to:Array<String>, s:String)
			if (!to.contains(s)) to.push(s);
		for (t in com.types)
			switch t {
				case TClassDecl(c):
					var prefix = hxmc.ir.Lower.nativeName(c) + "_";
					var marked = [for (m in c.clMeta) if (core.ds.Key.asString(m.meta) == ":helder.android.dex" || core.ds.Key.asString(m.meta) == ":helder.android.permission") m];
					if (marked.length == 0 || !Lambda.exists(funcs, f -> f.startsWith(prefix))) continue;
					for (m in marked)
						for (e in m.exprs)
							switch e.expr {
								case EConst(core.Ast.Constant.String(s, _)): add(core.ds.Key.asString(m.meta) == ":helder.android.dex" ? services : android, s);
								case _:
							}
				case _:
			}
		for (p in permissions)
			for (a in helder.pack.android.Glue.permissions(p))
				add(android, a);
		j.services = services;
		j.permissions = android;
		sys.io.File.saveContent(classes, haxe.Json.stringify(j));
	}

	// Permissions.request("camera"): camera; with anything but a literal, all of them
	static function requested(sources:Array<String>):Array<String> {
		var out = [], call = ~/Permissions\s*\.\s*request\s*\(\s*(["'`]?)(\w*)/g;
		for (text in sources) {
			var at = 0;
			while (call.matchSub(text, at)) {
				var p = call.matched(2);
				if (call.matched(1) == "" || !helder.pack.Uses.PERMISSIONS.contains(p)) return helder.pack.Uses.PERMISSIONS.copy();
				if (!out.contains(p)) out.push(p);
				var pos = call.matchedPos();
				at = pos.pos + pos.len;
			}
		}
		return out;
	}
}
