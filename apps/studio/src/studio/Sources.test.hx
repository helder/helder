package studio;

import helder.test.Test;

// A frame's key reads its story's file and what that imports: an edit to
// one story's file, or to a module only it imports, leaves the others';
// an edit to what both import, or to an asset, changes both
function tests() {
	describe("Sources", () -> {
		#if !(hxmc.target == "wasm32-wasi")
		test("a story's key: its file and its imports", () -> {
			var dir = haxe.io.Path.normalize((Sys.getEnv("TMPDIR") ?? Sys.getEnv("TEMP") ?? "/tmp") + "/helder-studio-sources");
			if (sys.FileSystem.exists(dir)) helder.cli.TestCommand.rmrf(dir);
			Files.save('$dir/a.story.tsx', 'import { A } from "./a";\nimport { theme } from "./src/theme.js";\nimport { x } from "../outside";\n');
			Files.save('$dir/a.tsx', 'export const A = 1;\n');
			Files.save('$dir/b.story.tsx', 'export * from "./src/theme";\n');
			Files.save('$dir/src/theme.ts', 'export const theme = 1;\n');
			Files.save('$dir/logo.png', "png");
			function keys() {
				var s = new Sources(dir, []);
				return [s.key('$dir/a.story.tsx', "A"), s.key('$dir/b.story.tsx', "B")];
			}
			var k0 = keys();
			Files.save('$dir/a.tsx', 'export const A = 2;\n');
			var k1 = keys();
			equals([k1[0] != k0[0], k1[1] == k0[1]], [true, true]);
			Files.save('$dir/b.story.tsx', 'export * from "./src/theme";\n// b\n');
			var k2 = keys();
			equals([k2[0] == k1[0], k2[1] != k1[1]], [true, true]);
			Files.save('$dir/src/theme.ts', 'export const theme = 2;\n');
			var k3 = keys();
			equals([k3[0] != k2[0], k3[1] != k2[1]], [true, true]);
			Files.save('$dir/logo.png', "png!");
			var k4 = keys();
			equals([k4[0] != k3[0], k4[1] != k3[1]], [true, true]);
		});
		test("Haxe: its package's files and its imports", () -> {
			var dir = haxe.io.Path.normalize((Sys.getEnv("TMPDIR") ?? Sys.getEnv("TEMP") ?? "/tmp") + "/helder-studio-sources-hx");
			if (sys.FileSystem.exists(dir)) helder.cli.TestCommand.rmrf(dir);
			Files.save('$dir/app/Todo.story.hx', 'package app;\nimport ui.Button;\n');
			Files.save('$dir/app/Todo.hx', 'package app;\n');
			Files.save('$dir/ui/Button.hx', 'package ui;\n');
			Files.save('$dir/other/Other.story.hx', 'package other;\n');
			function keys() {
				var s = new Sources(dir, [dir]);
				return [s.key('$dir/app/Todo.story.hx', "T"), s.key('$dir/other/Other.story.hx', "O")];
			}
			var k0 = keys();
			Files.save('$dir/ui/Button.hx', 'package ui;\n// b\n');
			var k1 = keys();
			Files.save('$dir/app/Todo.hx', 'package app;\n// t\n');
			var k2 = keys();
			equals([k1[0] != k0[0], k1[1] == k0[1], k2[0] != k1[0], k2[1] == k1[1]], [true, true, true, true]);
		});
		#end
	});
}
