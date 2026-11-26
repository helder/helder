package helder.typescript.check;

import haxe.io.Path;
import sys.FileSystem;

using StringTools;

// The compiler options a program is checked with: the project's
// tsconfig.json (the nearest from the entry's directory up to its
// package.json's), as tsgo parses it (`extends` too), else helder's
// defaults. Options that only change what is checked or emitted pass
// through; those that would change what the program means, or which the
// compiled program cannot have (DOM, node's types), must be helder's values
// or absent, else the build stops at their line.
class Config {
	// what helder compiles: its own tsconfig.json (beside globals.d.ts, the
	// package's `helder/tsconfig.json`, which a project extends), as tsgo parses it
	static final defaults:Map<String, Dynamic> = [];

	static function base(tsgo:Tsgo, file:String):Dynamic {
		if (!defaults.exists(file)) {
			var parsed:Dynamic = tsgo.call("parseConfigFile", {file: file});
			var options:Dynamic = parsed.options;
			if (options == null) throw file + ": TSHX004: helder's tsconfig.json was not read";
			for (f in ["configFilePath", "pathsBasePath"]) Reflect.deleteField(options, f);
			defaults.set(file, options);
		}
		return Reflect.copy(defaults.get(file));
	}

	static inline var TARGET_ES2022 = 9;

	// the options for a program's entry, helder's tsconfig.json under them; its
	// tsconfig.json's path is given to `used` (a watcher follows it)
	public static function options(tsgo:Tsgo, entry:String, helder:String, relative:String->String, ?used:String->Void):Dynamic {
		var options = base(tsgo, helder);
		var file = find(Path.directory(entry));
		if (file == null) return withNoEmit(options);
		if (used != null) used(file);
		var parsed:Dynamic = tsgo.call("parseConfigFile", {file: file});
		var text = sys.io.File.getContent(file), name = relative(file);
		var errors:Array<String> = [];
		var diagnostics:Array<Dynamic> = parsed.errors;
		if (diagnostics != null) for (d in diagnostics) errors.push(name + ":" + (d.startPosition != null ? d.startPosition.line + 1 : 1) + ": TS" + d.code + ": " + d.text);
		var given:Dynamic = parsed.options ?? {};
		function refuse(option:String, why:String)
			errors.push(name + ":" + line(text, option) + ": TSHX004: compilerOptions." + option + ": " + why);
		for (option in Reflect.fields(given)) {
			var v:Dynamic = Reflect.field(given, option);
			switch option {
				case "strict" if (v != true): refuse(option, "helder checks programs in strict mode");
				case "module" if (v != 99 && v != 7 && v != 200): refuse(option, "helder compiles ES modules (esnext, es2022 or preserve)");
				case "moduleResolution" if (v != 100): refuse(option, "helder resolves modules as a bundler does (bundler)");
				case "target" if (v < TARGET_ES2022): refuse(option, "helder's semantics are ES2022's or later (es2022, esnext)");
				case "useDefineForClassFields" if (v != true): refuse(option, "class fields are defined, as ES2022 specifies");
				case "jsx" if (v != 1): refuse(option, "TSX is compiled by helder (preserve)");
				case "types" if ((v : Array<Dynamic>).length > 0): refuse(option, "a helder program has no ambient types (node's, a browser's): import what it uses");
				case "lib":
					var libs:Array<String> = v;
					for (l in libs) if (~/^lib\.(dom|webworker|scripthost)/.match(l)) refuse(option, '$l: a helder program has no DOM; its globals are ECMAScript\'s and helder\'s');
				case "experimentalDecorators" | "emitDecoratorMetadata" if (v == true): refuse(option, "legacy decorators are not supported");
				case "configFilePath" | "pathsBasePath":
				case _:
			}
			if (option != "configFilePath" && option != "pathsBasePath") Reflect.setField(options, option, v);
		}
		if (errors.length > 0) throw errors.join("\n");
		return withNoEmit(options);
	}

	static function withNoEmit(options:Dynamic):Dynamic {
		options.noEmit = true;
		return options;
	}

	// the nearest tsconfig.json at or above dir, not past the package.json's directory
	static function find(dir:String):Null<String> {
		var d = FileSystem.fullPath(dir);
		while (d != null && d != "") {
			if (FileSystem.exists('$d/tsconfig.json')) return Path.normalize('$d/tsconfig.json');
			if (FileSystem.exists('$d/package.json')) return null;
			var up = Path.directory(d);
			if (up == d || up == "") return null;
			d = up;
		}
		return null;
	}

	// the 1-based line where an option is written (1 when it is inherited)
	static function line(text:String, option:String):Int {
		var at = text.indexOf('"$option"');
		return at < 0 ? 1 : text.substr(0, at).split("\n").length;
	}
}
