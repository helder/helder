package studio;

import helder.test.Test;

function tests() {
	describe("Starter", () -> {
		test("a tsconfig.json of the studio's: the helder it maps", () -> {
			equals(Starter.written(Starter.configText("/old/src")), "/old/src");
			equals(Starter.written('{"compilerOptions": {"paths": {"helder/*": ["/a/helder/*/index.d.ts"]}}}'), null);
			equals(Starter.written('{"compilerOptions": {"strict": true, "paths": {}}}'), null);
			equals(Starter.written("not json"), null);
		});
		#if !(hxmc.target == "wasm32-wasi")
		test("another helder's, written again; the user's own kept", () -> Temp.within("helder-starter", dir -> {
			Files.save('$dir/tsconfig.json', Starter.configText("/old/src"));
			Starter.config(dir);
			equals(Starter.written(Files.read('$dir/tsconfig.json')), BuildInfo.helderSrc());
			var own = '{"compilerOptions": {"strict": true}}\n';
			Files.save('$dir/tsconfig.json', own);
			Starter.config(dir);
			equals(Files.read('$dir/tsconfig.json'), own);
		}));
		#end
	});
}
