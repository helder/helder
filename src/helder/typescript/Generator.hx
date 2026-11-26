package helder.typescript;

import haxe.io.Path;
import sys.FileSystem;

using StringTools;

// helder's TypeScript declaration files (helder.typescript.api.Declarations)
// as its compiler makes them: a compile of their modules' declaration
// classes, the methods typed by their signatures (Signatures), ended once
// the files are written (or checked). Every TypeScript build's start
// (`ensure`) writes them again when the stamp of the last generation is
// stale: a Haxe file it read changed, or the compiler; else it costs a
// stat per file. `<compiler> --declarations [--check] [--cp dir]...
// [pack.Module]...` is the generator's short form (api/declarations.mjs):
// a program's own modules, their declaration classes and class paths given.
class Generator {
	public static inline var DEFINE = "helder.declarations";

	// helder's modules (each written, or typed, `known`, so that what they
	// declare is named as in their own files: a few modules' files are then
	// the same as all of helder's)
	public static final MODULES = ["helder.view.TypeScript", "helder.ui.TypeScript", "helder.web.TypeScript", "helder.canvas.TypeScript",
		"helder.async.TypeScript", "helder.dev.TypeScript", "helder.scenario.TypeScript", "helder.story.TypeScript", "helder.jobs.TypeScript", "helder.asset.TypeScript",
		"helder.scene.TypeScript", "helder.test.TypeScript", "helder.native.TypeScript", "helder.ui.actions.TypeScript", "helder.os.TypeScript",
		"helder.store.TypeScript", "helder.media.TypeScript", "helder.markdown.TypeScript", "helder.scene.view.TypeScript"];

	// the short form's command line
	public static function direct(args:Array<String>, source:String):Array<String> {
		var check = false, cps = [], modules = [];
		while (args.length > 0) switch args.shift() {
			case "--check": check = true;
			case "--cp": cps.push(args.shift());
			case a if (a.startsWith("-")): throw 'unexpected argument $a (<compiler> --declarations [--check] [--cp dir]... [pack.Module]...)';
			case m: modules.push(m);
		}
		return command(source, modules.length > 0 ? modules : MODULES, check, cps, null);
	}

	// (stamp: where the generation writes what it read)
	static function command(source:String, modules:Array<String>, check:Bool, cps:Array<String>, stamp:Null<String>):Array<String> {
		function list(l:Array<String>)
			return "[" + l.map(m -> haxe.Json.stringify(m)).join(", ") + "]";
		var call = 'helder.typescript.api.Declarations.write(${list(modules)}, $check, ${list(MODULES)})';
		var args = ["-D", "hxmc.markup-braces", "-D", DEFINE + "=" + (stamp ?? "1"), "-D", "message.reporting=classic", "-cp", source];
		for (cp in cps) args = args.concat(["-cp", cp]);
		return args.concat(["--macro", call, "--no-output", "--custom-target", "hxmc=" + Path.join([source, "..", "bin", "declarations"])]);
	}

	// A TypeScript build's start: helder's declaration files written again
	// when its stamp is stale (in helder's cache, by its sources' path), by
	// this compiler run on them; never into a package installed (under
	// node_modules: it ships them made). A program's own modules are not
	// (tests/view's TestTypeScript: their class paths are its build's).
	public static function ensure(source:String) {
		#if (hxmc.target != "wasm32-wasi")
		var src = FileSystem.fullPath(source);
		if (~/[\/\\]node_modules[\/\\]/.match(src + "/")) return;
		var stamp = Path.join([helder.compiler.Compiler.cache(), "declarations", haxe.crypto.Md5.encode(src).substr(0, 16)]);
		if (Stamp.fresh(stamp, header())) return;
		var p = new sys.io.Process(Sys.programPath(), command(src, MODULES, false, [], stamp));
		p.stdin.close();
		var err = p.stderr.readAll().toString(), out = p.stdout.readAll().toString();
		var code = p.exitCode();
		p.close();
		if (code == 0) return;
		var errors = [for (l in (out + err).split("\n")) if (l.trim() != "" && l.indexOf(": Warning :") < 0) l.rtrim()];
		throw "helder.typescript: helder's declaration files could not be written\n" + errors.join("\n");
		#end
	}

	// (the compiler that wrote a stamp: its path, size and time)
	static function header():String {
		var exe = FileSystem.fullPath(Sys.programPath());
		return "helder.declarations 1 " + Stamp.entry(exe) + " " + exe;
	}

	// The generation's compile (-D helder.declarations=<stamp>, or 1): what it
	// parses noted, and once the files are written (the init macro's
	// callback after init macros: the next round's, Common's CallbackList),
	// the stamp written and the compile ended, nothing else typed.
	public static function begin(com:context.Common.CommonContext) {
		Signatures.install();
		var stamp = core.Define.rawDefinedValueSafe(com.defines, DEFINE, "1");
		var read = new Map<String, String>();
		var parse = typing.TypeloadParse.parseHook;
		typing.TypeloadParse.parseHook = (com, rfile, p) -> {
			var file = FileSystem.absolutePath(rfile.file);
			if (!read.exists(file)) read.set(file, Stamp.entry(file));
			return parse(com, rfile, p);
		}
		com.callbacks.addAfterInitMacros(() -> com.callbacks.addAfterInitMacros(() -> {
			typing.TypeloadParse.parseHook = parse;
			var failed = compiler.Compiler.hasError(com);
			if (!failed && stamp != "1") {
				// (the directories: a module added to a package's is its module's too)
				for (f in [for (f in read.keys()) f]) {
					var dir = Path.directory(f);
					if (!read.exists(dir)) read.set(dir, Stamp.entry(dir));
				}
				Stamp.write(stamp, header(), read);
			}
			throw new macros.eval.EvalTypes.SysExit(failed ? 1 : 0);
		}));
	}
}
