package helder.cli;

import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

// helder new [dir]: a TypeScript project to start from, in an empty
// directory: its package.json (helder, and TypeScript's checker helder
// asks for), a tsconfig.json extending helder's (the editor checks what
// the build does), src/main.tsx (a window, a signal and a button) and a
// .gitignore.
class New {
	public static function run(dir:String):Int {
		if (FileSystem.exists(dir) && (!FileSystem.isDirectory(dir) || FileSystem.readDirectory(dir).length > 0)) {
			Term.err(Style.usage('helder new: $dir is not empty'));
			return 2;
		}
		TestCommand.mkdirs(dir);
		var pkg = own();
		for (file => text in files(name(dir), pkg.version, pkg.typescript)) {
			var path = '$dir/$file';
			TestCommand.mkdirs(Path.directory(path));
			File.saveContent(path, text);
		}
		Term.out(Style.status("created", Ok, dir));
		Term.out('  cd $dir && npm install && npx helder dev');
		return 0;
	}

	// (the directory's name, as npm takes one)
	public static function name(dir:String):String {
		var base = Path.withoutDirectory(Path.removeTrailingSlashes(FileSystem.fullPath(dir) ?? dir));
		var slug = ~/[^a-z0-9._-]+/g.replace(base.toLowerCase(), "-");
		return slug == "" || slug == "-" ? "app" : slug;
	}

	public static function files(name:String, version:String, typescript:String):Map<String, String> {
		var pkg = '{\n\t"name": "$name",\n\t"private": true,\n\t"type": "module",\n\t"scripts": {\n\t\t"dev": "helder dev",\n\t\t"build": "helder build"\n\t},\n'
			+ '\t"dependencies": {\n\t\t"helder": "$version"\n\t},\n\t"devDependencies": {\n\t\t"typescript": "$typescript"\n\t}\n}\n';
		return [
			"package.json" => pkg,
			"tsconfig.json" => '{\n\t"extends": "helder/tsconfig.json"\n}\n',
			"src/main.tsx" => MAIN,
			".gitignore" => "bin/\nnode_modules/\n"
		];
	}

	// (the helder this CLI is, as Entry finds it: its package.json's version and TypeScript's range)
	static function own():{version:String, typescript:String} {
		var src = Path.directory(Sys.programPath()) + "/../../src", env = Sys.getEnv("HELDER_SRC");
		if (!FileSystem.exists('$src/helder/dev/Hot.hx') && env != null && env != "") src = env;
		var json:Dynamic = try haxe.Json.parse(File.getContent('$src/../package.json')) catch (_:Dynamic) null;
		var range:Null<String> = json?.peerDependencies?.typescript;
		return {version: json?.version ?? "latest", typescript: range ?? ">=7.1.0-0"};
	}

	static inline var MAIN = "import {signal} from 'helder/view'
import {UiWindow, Surface} from 'helder/ui'

const count = signal(0)

UiWindow.run(
  <Surface title='Counter' width={320} height={200}>
    <view flexGrow={1} alignItems='center' justifyContent='center' rowGap={12}>
      <text fontSize={32}>{count}</text>
      <button padding='8 16' onPress={() => count(c => c + 1)}>+1</button>
    </view>
  </Surface>
)
";
}
