package studio;

import helder.test.Test;

using StringTools;

// The guide stays true: each topic's TypeScript built (natively: its code
// blocks written as their files into a project of their own, outside any
// package, as the studio's Untitled ones are, one program importing them
// all; `helder build`, niced) and its design markup read (DesignFile)
function tests() {
	describe("Guides", () -> {
		test("every topic listed, start the default", () -> {
			equals([for (t in Guides.topics) t.name], ["start", "ui", "game", "design", "assets"]);
			equals(Guides.get(null).startsWith("# Start"), true);
			equals(Guides.get("game").indexOf("Clock.add") > 0, true);
		});
		#if !(hxmc.target == "wasm32-wasi")
		test("each topic's code builds, its design markup reads", () -> {
			var dir = haxe.io.Path.normalize((Sys.getEnv("TMPDIR") ?? Sys.getEnv("TEMP") ?? "/tmp") + "/helder-studio-guide");
			if (sys.FileSystem.exists(dir)) helder.cli.TestCommand.rmrf(dir);
			helder.cli.TestCommand.mkdirs(dir);
			var imports = [], block = ~/```(tsx|ts|helder) file=([^\n]+)\n([\s\S]*?)```/;
			for (t in Guides.topics) {
				var text = t.text;
				while (block.match(text)) {
					var kind = block.matched(1), file = block.matched(2).trim(), code = block.matched(3);
					text = block.matchedRight();
					if (kind == "helder") {
						var d = new DesignFile(code);
						equals(d.frames.length > 0, true);
						continue;
					}
					Files.save('$dir/${t.name}/$file', code);
					imports.push('import "./${t.name}/${haxe.io.Path.withoutExtension(file)}";');
				}
			}
			// (the assets the assets topic names, beside its file)
			helder.cli.TestCommand.mkdirs('$dir/assets/assets');
			sys.io.File.copy("../../tests/ui/svg/shapes.png", '$dir/assets/assets/logo.png');
			sys.io.File.copy("fonts/HankenGrotesk-Medium.ttf", '$dir/assets/assets/Title.ttf');
			sys.io.File.saveBytes('$dir/assets/assets/hit.wav', haxe.io.Bytes.alloc(44));
			Files.save('$dir/main.ts', imports.join("\n") + "\n");
			Starter.config(dir);
			var cli = sys.FileSystem.fullPath("../../src/helder/cli/run.mjs");
			var args = ["node", cli, "build", '$dir/main.ts'];
			var p = Sys.systemName() == "Windows" ? new sys.io.Process(args[0], args.slice(1)) : new sys.io.Process("nice", ["-n", "20"].concat(args));
			var out = p.stdout.readAll().toString() + p.stderr.readAll().toString(), code = p.exitCode();
			p.close();
			var errors = [for (l in out.split("\n")) if (l.contains("ERROR") || l.contains("TS") && l.contains(":")) l].join("\n");
			equals(errors == "" ? code : -1, 0);
			if (code != 0) Sys.println(out);
		}).timeout(300);
		#end
	});
}
