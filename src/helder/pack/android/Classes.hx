package helder.pack.android;

#if macro
import haxe.macro.Context;
import haxe.macro.Type;

// Which of Glue's Java classes an Android build needs, for the APK
// (helder.cli.Android): `--macro helder.pack.android.Classes.write("<file>")`
// writes {"dex", "views", "services", "permissions"} once the program is
// generated (after dead code elimination, when the build has it):
// - dex: a class marked @:helder.android.dex is in it (helder.os.android.Glue:
//   Java's listeners; helder.os.android.TextInput: the input method's Editor);
// - views: the program makes an instance of a class marked
//   @:helder.android.views (Android's views as the activity's content; none
//   is now), which needs org.hxmc.Activity: its window draws views, not
//   the program's surface. Being in the program is not enough: a dev build
//   has every class it typed, and a drawn window needs NativeActivity's
//   surface.
// - services, permissions: the app services' classes and the manifest's
//   permissions they need (helder.pack.Uses: a permission asked for,
//   Glue.permissions of it).
// - maven: the Maven libraries of the classes marked
//   @:helder.android.maven("<group:name[:version]>", "<keep rule>", ...)
//   (no version: Maven.VERSIONS'), each with the keep rules (ProGuard's
//   -keep syntax) naming what the program calls: helder.cli.Android fetches,
//   shrinks and translates them (Maven, Libraries).
class Classes {
	public static function write(file:String) {
		haxe.macro.Compiler.define("helder.android.classes", file);
		Context.onGenerate(types -> {
			var dex = false, views = false;
			var marked = new Map<String, Bool>();
			var maven:Array<{id:String, keep:Array<String>}> = [];
			for (t in types)
				switch t {
					case TInst(c, _):
						var m = c.get().meta;
						for (e in m.extract(":helder.android.maven")) {
							var given = [for (p in e.params) switch p.expr {
								case EConst(CString(s, _)): s;
								case _: Context.error("@:helder.android.maven takes strings: the library, then keep rules", p.pos);
							}];
							if (given.length == 0) Context.error("@:helder.android.maven: which library (group:name[:version])", e.pos);
							var id = Maven.versioned(given[0]);
							if (id == null) Context.error('@:helder.android.maven: ${given[0]} has no version (and none in helder.pack.android.Maven.VERSIONS)', e.pos);
							maven.push({id: id, keep: given.slice(1)});
						}
						if (Lambda.exists(m.extract(":helder.android.dex"), e -> e.params.length == 0)) dex = true;
						if (m.has(":helder.android.views")) marked.set(c.toString(), true);
					case _:
				}
			if (marked.keys().hasNext()) {
				function scan(e:TypedExpr) {
					if (views) return;
					switch e.expr {
						case TNew(c, _, _) if (marked.exists(c.toString())): views = true;
						case _: haxe.macro.TypedExprTools.iter(e, scan);
					}
				}
				function fields(c:ClassType) {
					for (f in c.statics.get().concat(c.fields.get())) {
						var e = f.expr();
						if (e != null) scan(e);
					}
					if (c.constructor != null) {
						var e = c.constructor.get().expr();
						if (e != null) scan(e);
					}
					if (c.init != null) scan(c.init);
				}
				for (t in types)
					switch t {
						case TInst(c, _) if (!views): fields(c.get());
						case _:
					}
			}
			var uses = helder.pack.Uses.of(types);
			var permissions = uses.android.copy();
			for (p in uses.permissions.keys())
				for (a in Glue.permissions(p))
					if (!permissions.contains(a)) permissions.push(a);
			var out:Dynamic = {
				dex: dex || views,
				views: views,
				services: uses.services,
				permissions: permissions
			};
			// (written when a class declares one)
			if (maven.length > 0) out.maven = maven;
			sys.io.File.saveContent(file, haxe.Json.stringify(out));
		});
	}
}
#end
