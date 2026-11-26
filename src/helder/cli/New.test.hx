package helder.cli;

import helder.test.Test;

// helder new: its files in an empty directory, a non-empty one refused
function tests() {
	test("an empty directory: package.json, helder's tsconfig, src/main.tsx, .gitignore", () -> {
		var dir = "bin/cli-new/My App";
		TestCommand.mkdirs(dir);
		for (f in ["package.json", "tsconfig.json", "src/main.tsx", ".gitignore"]) if (sys.FileSystem.exists('$dir/$f')) sys.FileSystem.deleteFile('$dir/$f');
		if (sys.FileSystem.exists('$dir/src')) sys.FileSystem.deleteDirectory('$dir/src');
		equals(New.run(dir), 0);
		var pkg:Dynamic = haxe.Json.parse(sys.io.File.getContent('$dir/package.json'));
		equals([pkg.name, pkg.type], ["my-app", "module"]);
		assert(pkg.dependencies.helder != null && pkg.devDependencies.typescript != null, "helder and typescript");
		equals(Reflect.field(haxe.Json.parse(sys.io.File.getContent('$dir/tsconfig.json')), "extends"), "helder/tsconfig.json");
		assert(sys.io.File.getContent('$dir/src/main.tsx').indexOf("signal(0)") > 0, "a signal");
		equals(sys.io.File.getContent('$dir/.gitignore'), "bin/\nnode_modules/\n");
		equals(New.run(dir), 2);
	});
}
