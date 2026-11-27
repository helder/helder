package lanes;

import sys.FileSystem;
import sys.io.File;
import lanes.Tools.*;

using StringTools;

private typedef Program = {
	var name:String;
	var dir:String;
	var ?src:String;
	var main:String;
}

class Size {
	public static var laneArgs:Array<String> = [];

	public static final LANES:Array<Lane> = [
		{name: "size", about: "release binary sizes against their baselines (CI; size <program> builds just that program)", run: check}
	];

	static function check() {
		if (!HOST.startsWith("macos-") && !HOST.startsWith("linux-"))
			throw new Failed("size needs Mach-O or ELF symbols (Windows PE/COFF is unsupported)");
		var programs:Array<Program> = haxe.Json.parse(File.getContent("tests/size/programs.json"));
		if (laneArgs.length == 1) {
			var name = laneArgs[0];
			var program = Lambda.find(programs, p -> p.name == name);
			if (program != null) programs = [program];
			else throw new Failed('unknown size program $name (choose ${[for (p in programs) p.name].join(", ")})');
		} else if (laneArgs.length > 1) throw new Failed("usage: bun run test size [program]");

		for (p in programs) {
			var cp = p.src == null ? p.dir : '${p.dir}/${p.src}';
			var args = cps(["src", cp]).concat(["-main", p.main, "-dce", "full", "-D", "helder.release", "-D", "hxmc.symbols",
				"-D", "helder.root=" + FileSystem.fullPath(p.dir)]);
			var out = 'bin/size/${p.name}';
			native(out, args, HOST);
			wasm('$out.wasm', args);
		}
		run(NODE, ["tests/size/report.mjs", HOST].concat(laneArgs));
	}
}
