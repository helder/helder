package helder.typescript.check;

import helder.typescript.check.Ast;
import helder.typescript.check.Kind;
import helder.typescript.check.Syntax;

// The entry file and the files it imports, parsed, bound and checked by tsgo.
// Everything lowering needs is fetched up front: the files' ASTs, the symbols
// of their identifiers, their types and the targets of their module specifiers. A
// compilation server (`helder dev`) keeps its tsgo running between builds;
// a one-shot build stops it before code generation.
class Project {
	public final path:String;
	public var file(default, null):SourceFile;
	// (every program file that is not a declaration file)
	public final files:Array<SourceFile> = [];
	// (the declaration files the program and they import: helder's API, lower.Api)
	public final declarations:Array<SourceFile> = [];
	public final isJS:Bool;
	public var types(default, null):Types;
	final modules:Map<Node, String> = [];

	// the program's source files the last check found, also when it failed
	// (what a watcher follows)
	public static var read(default, null):Array<String> = [];

	static var session:Null<{key:String, tsgo:Tsgo, tables:Tables}> = null;

	// (checked: after, given the project while tsgo is up, asks what the lowering needs beyond it)
	public static function check(entry:String, globals:String, ?after:Project->Void):Project {
		read = [haxe.io.Path.normalize(sys.FileSystem.fullPath(entry))];
		var found = Tsgo.find(haxe.io.Path.directory(entry));
		// (the worker's tsgo is one session for every directory: its paths are absolute)
		var key = found.exe + "\n" + #if (hxmc.target == "wasm32-wasi") "/" #else Sys.getCwd() #end;
		if (session != null && session.key != key) {
			session.tsgo.close();
			session = null;
		}
		if (session == null) {
			var tsgo = new Tsgo(found.exe, Sys.getCwd());
			tsgo.call("initialize", null);
			session = {key: key, tsgo: tsgo, tables: Tables.load(found.typescript)};
		}
		var s = session;
		try {
			var project = new Project(entry, globals, s.tsgo, s.tables);
			if (after != null) after(project);
			if (!hxmc.Driver.resident) stop();
			return project;
		} catch (e:Dynamic) {
			// (a broken pipe is not kept for the next build)
			if (!hxmc.Driver.resident || !Std.isOfType(e, String) || StringTools.startsWith(e, "TSHX003")) stop();
			throw e;
		}
	}

	public static function stop() {
		if (session != null) session.tsgo.close();
		session = null;
		last = null;
	}

	// The last build's snapshot, kept by a compilation server: the next build
	// with the same entry and options updates it with the files that changed
	// since (by size and time), so tsgo reparses and rechecks only what they
	// affect; none changed, it is used as it is. A module it could not find
	// (TS2307) is looked for again: tsgo keeps the failed lookup, and the file
	// made since is none of those read (deleted then made again, or new).
	static var last:Null<{key:String, base:String, roots:Array<String>, snapshot:Int, project:Dynamic, stamps:Map<String, String>, unresolved:Bool}> = null;

	static function stamp(file:String):String {
		var s = try sys.FileSystem.stat(file) catch (_:Dynamic) return "";
		return s.size + "@" + s.mtime.getTime();
	}

	static function snapshot(tsgo:Tsgo, key:String, roots:Array<String>, options:Dynamic):{snapshot:Int, project:Dynamic} {
		var previous = last;
		last = null;
		if (previous != null && previous.key == key) {
			var changed = [], deleted = [];
			for (f => s in previous.stamps) {
				var now = stamp(f);
				if (now == "") deleted.push(f) else if (now != s) changed.push(f);
			}
			if (changed.length == 0 && deleted.length == 0 && !previous.unresolved) return {snapshot: previous.snapshot, project: previous.project};
			var files:Dynamic = previous.unresolved ? {invalidateAll: true} : {changed: changed, deleted: deleted};
			var r:Dynamic = tsgo.call("updateSnapshot", {snapshot: previous.snapshot, changes: {fileNotifications: files, ensurePrograms: true}});
			// (the same snapshot again: taken once more, given back once)
			tsgo.call("release", {snapshot: r.snapshot == previous.snapshot ? r.snapshot : previous.snapshot});
			return {snapshot: r.snapshot, project: previous.project};
		}
		if (previous != null) tsgo.call("release", {snapshot: previous.snapshot});
		var r:Dynamic = tsgo.call("createSnapshot", {createPrograms: [{rootFiles: roots, compilerOptions: options}]});
		// (a project is named by its handle since 7.1's nightlies of November 2026, by its id before)
		var p:Dynamic = r.projects[0];
		return {snapshot: r.snapshot, project: p.handle != null ? p.handle : p.id};
	}

	function new(entry:String, globals:String, tsgo:Tsgo, tables:Tables) {
		var absolute = haxe.io.Path.normalize(sys.FileSystem.fullPath(entry));
		path = relative(absolute);
		isJS = ~/\.[cm]?jsx?$/.match(absolute);
		if (!sys.FileSystem.exists(absolute)) throw path + ": TSHX002: input file not found";
		var options = Config.options(tsgo, absolute, haxe.io.Path.join([haxe.io.Path.directory(globals), "tsconfig.json"]), relative, f -> config = f);
		var base = absolute + "\n" + haxe.Json.stringify(options);
		// (a package's implementation is one of the program's roots, as an
		// allowJs file is: the last build's roots tried first)
		var roots = last != null && last.base == base ? last.roots : [absolute, globals];
		var at:Null<{snapshot:Int, project:Dynamic}> = null;
		// (kept for the next build, a failed one's too: its files are watched;
		// its declaration files' too, those on disk: helder's are written
		// again by a build, Generator)
		function keep() {
			var stamps = [for (f in read) f => stamp(f)];
			for (f in declared) {
				var s = stamp(f);
				if (s != "") stamps.set(f, s);
			}
			last = {key: base + "\n" + roots.join("\n"), base: base, roots: roots, snapshot: at.snapshot, project: at.project, stamps: stamps, unresolved: unresolved};
		}
		try {
			while (true) {
				at = snapshot(tsgo, base + "\n" + roots.join("\n"), roots, options);
				var needed = walk(tsgo, tables, cast at, absolute, globals, options);
				if (needed.join("\n") == roots.join("\n")) break;
				tsgo.call("release", {snapshot: at.snapshot});
				roots = needed;
			}
			load(tsgo, tables, cast at, absolute, globals);
		} catch (e:Dynamic) {
			if (at != null) keep();
			throw e;
		}
		keep();
	}

	var config:Null<String> = null;
	// (the program's declaration files, the libraries' among them)
	var declared:Array<String> = [];
	// (a module not found: TS2307, TS2792)
	var unresolved = false;
	// (the files walk parsed, by name: a specifier's node is the key of modules)
	var parsed:Map<String, SourceFile> = [];

	static function declaration(file:String):Bool
		return ~/\.d\.[cm]?ts$/.match(file);

	static function script(file:String):Bool
		return ~/\.[cm]?jsx?$/.match(file);

	function parse(tsgo:Tsgo, tables:Tables, at:{snapshot:Int, project:Dynamic}, name:String):SourceFile {
		var sf = parsed.get(name);
		if (sf == null) parsed.set(name, sf = new SourceFile(name, tsgo.request("getSourceFile", haxe.Json.stringify({snapshot: at.snapshot, project: at.project, file: name})), tables));
		return sf;
	}

	function resolved(tsgo:Tsgo, at:{snapshot:Int, project:Dynamic}, file:String, specifier:Node):Dynamic
		return tsgo.call("getResolvedModule", {snapshot: at.snapshot, project: at.project, file: file, moduleName: specifier.text, mode: 99});

	// The files the entry reaches through its imports, parsed, their module
	// specifiers resolved; the roots the program needs: the entry, the
	// globals and the packages' implementations. TypeScript resolves a
	// package to its types (a .d.ts, which declares and runs nothing), a
	// bundler to its JavaScript: the same specifier resolved again without the
	// types condition (tsgo's resolver, noDtsResolution) is what is compiled,
	// the declaration file its importers' types.
	function walk(tsgo:Tsgo, tables:Tables, at:{snapshot:Int, project:Dynamic}, absolute:String, globals:String, options:Dynamic):Array<String> {
		modules.clear();
		parsed = [];
		var names:Array<String> = tsgo.call("getSourceFileNames", at);
		var program = [for (n in names) n => true];
		var needed = [absolute, globals], importers = new Map<String, Node>();
		var seen = [absolute => true], queue = [absolute];
		var resolver:Null<Int> = null;
		function implementation(file:String, specifier:Node, types:Null<String>):Null<String> {
			if (resolver == null) {
				var o:Dynamic = Reflect.copy(options);
				o.allowJs = true;
				o.noDtsResolution = true;
				o.customConditions = ((o.customConditions : Array<String>) ?? []).concat(["module"]);
				resolver = tsgo.call("createModuleResolver", {compilerOptions: o});
			}
			var r:Dynamic = tsgo.call("resolveModuleName", {resolver: resolver, moduleName: specifier.text, containingDirectory: haxe.io.Path.directory(file), resolutionMode: 99});
			var found:Null<String> = r != null && r.resolvedModule != null ? r.resolvedModule.resolvedFileName : null;
			if (found != null && script(found)) return Packages.moduleField(specifier.text, found);
			if (types != null) {
				var stem = ~/\.d\.([cm]?)ts$/;
				if (stem.match(types)) for (ext in ['.${stem.matched(1)}js', ".js", ".mjs"]) {
					var sibling = stem.matchedLeft() + ext;
					if (sys.FileSystem.exists(sibling)) return sibling;
				}
			}
			return null;
		}
		try {
			while (queue.length > 0) {
				var name = queue.shift();
				var sf = parse(tsgo, tables, at, name);
				var from = importers.get(name);
				if (from != null && Packages.commonJS(sf)) fail(from, Packages.name(from.text, relative(name)) + " is CommonJS, which helder does not compile yet");
				for (i in 1...sf.count) switch sf.kindAt(i) {
					case KindImportDeclaration | KindExportDeclaration:
						var n = sf.node(i), specifier = n.moduleSpecifier();
						if (specifier == null || specifier.kind != KindStringLiteral) continue;
						var r = resolved(tsgo, at, name, specifier);
						if (r == null || r.resolvedFileName == null) continue;
						var target:String = r.resolvedFileName;
						var types = declaration(target);
						if (types ? !Packages.helders(target, globals) : script(target) && r.isExternalLibraryImport == true) {
							var js = implementation(name, specifier, types ? target : null);
							if (js == null) {
								// (a package of types only: nothing to run)
								if (types && (Packages.typeOnly(n) || !Packages.declaresValues(parse(tsgo, tables, at, target)))) {
									modules.set(specifier, target);
									continue;
								}
								fail(specifier, Packages.name(specifier.text, relative(target)) + " has no JavaScript implementation (" + relative(target) + " declares it)");
							}
							target = js;
							if (needed.indexOf(js) < 0) needed.push(js);
						}
						modules.set(specifier, target);
						if (script(target) && !importers.exists(target)) importers.set(target, specifier);
						if (!declaration(target) && program.exists(target) && !seen.exists(target)) {
							seen.set(target, true);
							queue.push(target);
						}
					case _:
				}
			}
		} catch (e:Dynamic) {
			if (resolver != null) tsgo.call("releaseModuleResolver", {resolver: resolver});
			throw e;
		}
		if (resolver != null) tsgo.call("releaseModuleResolver", {resolver: resolver});
		return needed;
	}

	function load(tsgo:Tsgo, tables:Tables, at:{snapshot:Int, project:Dynamic}, absolute:String, globals:String) {
		var names:Array<String> = tsgo.call("getSourceFileNames", at);
		var sources = [for (n in names) if (!declaration(n) && n != globals) n];
		declared = [for (n in names) if (declaration(n)) n];
		read = sources.copy();
		if (config != null) read.push(config);
		var errors:Array<String> = [];
		function report(list:Array<Dynamic>)
			if (list != null) for (d in list) {
				var where = d.fileName == null ? path : relative(d.fileName) + ":" + (d.startPosition.line + 1);
				if (d.fileName != null && d.startPosition != null && d.endPosition != null && d.startPosition.line == d.endPosition.line)
					where += ": characters " + d.startPosition.character + "-" + d.endPosition.character + " ";
				if (d.code == 2307 || d.code == 2792) unresolved = true;
				errors.push(where + ": TS" + d.code + ": " + message(d));
			}
		report(tsgo.call("getProgramDiagnostics", at));
		report(tsgo.call("getSyntacticDiagnostics", {snapshot: at.snapshot, project: at.project, files: sources}));
		var checked = [for (n in sources) if (!script(n)) n];
		if (errors.length == 0 && checked.length > 0)
			report(tsgo.call("getSemanticDiagnostics", {snapshot: at.snapshot, project: at.project, files: checked}));
		if (errors.length > 0) throw errors.join("\n");
		types = new Types(tsgo, at, tables);
		var pending:Array<String> = [], seen = new Map<String, Bool>();
		function load(name:String, program:Bool) {
			var walked = parsed.exists(name);
			var sf = parse(tsgo, tables, at, name);
			(program ? files : declarations).push(sf);
			if (name == absolute) file = sf;
			symbols(tsgo, at, sf);
			if (program) types.load(sf);
			for (i in 1...sf.count) switch sf.kindAt(i) {
				case KindImportDeclaration | KindExportDeclaration:
					var specifier = sf.node(i).moduleSpecifier();
					if (specifier != null && specifier.kind == KindStringLiteral) {
						// (walk resolved the specifiers of the files the entry reaches)
						if (!walked || !program) {
							var r:Dynamic = resolved(tsgo, at, name, specifier);
							if (r != null && r.resolvedFileName != null) modules.set(specifier, r.resolvedFileName);
						}
						var target = modules.get(specifier);
						if (target != null && StringTools.endsWith(target, ".d.ts") && !seen.exists(target)) {
							seen.set(target, true);
							pending.push(target);
						}
					}
				case _:
			}
		}
		for (name in sources) load(name, true);
		while (pending.length > 0) load(pending.shift(), false);
		if (file == null) throw path + ": TSHX002: input file not found";
	}

	static function message(d:Dynamic):String {
		var text:String = d.text;
		var chain:Array<Dynamic> = d.messageChain;
		if (chain != null) for (c in chain) text += " " + message(c);
		return text;
	}

	// Asks the checker which symbol every identifier refers to, in one request.
	function symbols(tsgo:Tsgo, at:{snapshot:Int, project:Dynamic}, sf:SourceFile) {
		var ids = [for (i in 1...sf.count) if (sf.kindAt(i) == KindIdentifier) i];
		if (ids.length == 0) return;
		var result:Array<Dynamic> = tsgo.call("getSymbolsAtLocations", {snapshot: at.snapshot, project: at.project, locations: [for (i in ids) sf.location(i)]});
		for (j in 0...ids.length) if (result[j] != null) sf.symbols.set(ids[j], Std.string(result[j].reference != null ? result[j].reference.id : result[j].id));
	}

	// a path as messages show it: relative to the working directory when under it
	public static function relative(file:String):String {
		var cwd = haxe.io.Path.addTrailingSlash(haxe.io.Path.normalize(Sys.getCwd()));
		return StringTools.startsWith(file, cwd) ? file.substr(cwd.length) : file;
	}

	// The file a module specifier resolves to, or null.
	public function resolve(specifier:Node):Null<String>
		return modules.get(specifier);

	public function fail(n:Node, message:String):Dynamic {
		if (n == null) throw path + ":0: TSHX001: " + message;
		throw relative(n.file.path) + ":" + n.file.line(n.file.skipTrivia(n.pos)) + ": TSHX001: " + message;
	}
}
