package lanes;

import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import lanes.Tools.*;

using StringTools;

class Scene {
	public static final LANES:Array<Lane> = [
		{name: "3d", about: "helder.scene and helder.physics against golden frames", run: scene},
		{name: "3d-web", about: "helder.scene's frames on WebGPU and WebGL2", run: sceneWeb}
	];

	static function scene() {
		var cp = sceneCp();
		var tests = ["SceneCheck", "GltfCheck", "PhysicsCheck"];
		// (the lane's programs built at once first: below, each call finds its build)
		pack();
		var g = GFX_TARGET, ui = cps(["src", "tests/3d-ui"]);
		prebuild([for (t in tests) {out: exePath('bin/3d/$t', HOST), args: cp.concat(["-main", t])}].concat([
			for (t in tests.concat(["InputCheck"])) {out: 'bin/3d/$t.wasm', args: cp.concat(["-main", t]).concat(targetArgs("wasm32-wasi"))}
		]).concat([
			for (m in ["RenderCheck", "GltfViewer", "Orbits", "Showroom", "Falling", "Walker", "Chains", "InputCheck"])
				{out: exePath('bin/3d/$g/$m', g), args: cp.concat(["-main", m]).concat(targetArgs(g))}
		]).concat([
			{out: exePath('bin/3d/$g/SceneUiCheck', g), args: ui.concat(["-main", "SceneUiCheck"]).concat(targetArgs(g))},
			{out: exePath('bin/3d/$g/SurfaceCheck', g), args: cps(["src", "tests/gfx", "tests/3d-ui"]).concat(["-main", "SurfaceCheck"]).concat(targetArgs(g))}
		]));
		for (t in tests)
			interp(cp, t);
		for (t in tests) {
			exe('bin/3d/$t', cp.concat(["-main", t]));
			run(exePath('bin/3d/$t', HOST), []);
		}
		for (t in tests) {
			wasm('bin/3d/$t.wasm', cp.concat(["-main", t]));
			wasi('bin/3d/$t.wasm');
		}
		pack();
		var t = GFX_TARGET;
		for (m in ["RenderCheck", "GltfViewer", "Orbits", "Showroom", "Falling", "Walker", "Chains", "InputCheck"])
			native('bin/3d/$t/$m', cp.concat(["-main", m]), t);
		wasm("bin/3d/InputCheck.wasm", cp.concat(["-main", "InputCheck"]));
		run(exePath('bin/3d/$t/InputCheck', t), []);
		wasi("bin/3d/InputCheck.wasm");
		// (helder.scene.view: view's markup on the scene graph; natively: its meshes import gfx, which node lacks)
		native('bin/3d/$t/SceneUiCheck', cps(["src", "tests/3d-ui"]).concat(["-main", "SceneUiCheck"]), t);
		run(exePath('bin/3d/$t/SceneUiCheck', t), []);
		// (the boundary tags in windows: <Surface>s, a <Scene> box, picking through it, <Ui>; Xvfb)
		native('bin/3d/$t/SurfaceCheck', cps(["src", "tests/gfx", "tests/3d-ui"]).concat(["-main", "SurfaceCheck"]), t);
		shell('LIBGL_ALWAYS_SOFTWARE=1 $XVFB -a -s "-screen 0 640x480x24" ' + exePath('bin/3d/$t/SurfaceCheck', t));
		run("sh", ["tests/3d/check.sh", 'bin/3d/$t']);
		sceneTs(t);
		sceneProps();
		// (Model.of's files in the executable's data, helder.asset's Bundle: it
		// alone in a directory, run from it, nothing beside it)
		var exe = Path.withoutDirectory(exePath("bin/3d/alone/RenderCheck", t));
		rmrf("bin/3d/alone");
		mkdirs("bin/3d/alone");
		shell('cp ${exePath('bin/3d/$t/RenderCheck', t)} bin/3d/alone/$exe');
		if (FileSystem.readDirectory("bin/3d/alone").join(",") != exe) throw new Failed("bin/3d/alone: not the executable alone");
		shell('cd bin/3d/alone && LIBGL_ALWAYS_SOFTWARE=1 HXMC_GFX_SOFTWARE=1 env -u DISPLAY ./$exe skin ../../../tests/3d/skin.png ../skin-alone.png');
		// (Model.of: a name the file does not have is a compile error)
		var r = build(cp.concat(cps(["tests/3d/reject"])).concat(["-main", "ModelTypo", "--custom-target", "hxmc=bin/3d/ModelTypo"]), "bin/3d/ModelTypo.log");
		if (r.code == 0 || !r.log.contains("has no field bal"))
			throw new Failed("ModelTypo: expected the error \"has no field bal\":\n" + r.log);
		// (markup: what SceneProps reject when compiling, each its errors as
		// its "// expect:" lines say: a prop its element does not take, a
		// value not of its prop's type)
		sceneRejects();
		// (markup links the tags it names alone: a box in the standard
		// material holds no other generator, shading model or factory, and
		// adds within its budget over the same mesh in code; Linux: nm)
		if (Sys.systemName() == "Linux") {
			var size = cps(["src", "tests/3d/size"]).concat(["-main", "MarkupSize", "-dce", "full"]);
			for (m in [{name: "tiny", d: "markup_tiny"}, {name: "all", d: "markup_all"}, {name: "code", d: "markup_code"}]) {
				var args = size.concat(["-D", m.d]);
				native('bin/3d/size/${m.name}', args, HOST);
				wasm('bin/3d/size/${m.name}.wasm', args);
				if (m.name != "code") native('bin/3d/size/${m.name}-sym', args.concat(["-D", "hxmc.symbols"]), HOST);
			}
			run(NODE, ["tests/3d/size/markup.mjs", "bin/3d/size"]);
		}
	}

	static function sceneRejects() {
		var dir = "tests/3d-ui/reject";
		for (f in FileSystem.readDirectory(dir)) {
			if (!f.endsWith(".hx")) continue;
			var main = f.substr(0, f.length - 3);
			var expect = [for (l in File.getContent('$dir/$f').split("\n")) if (l.startsWith("// expect: ")) l.substr(11).trim()];
			var r = build(cps(["src", dir]).concat(["-main", main, "--custom-target", 'hxmc=bin/3d/reject/$main']), 'bin/3d/reject/$main.log');
			var log = r.log.split("\\").join("/");
			for (e in expect)
				if (r.code == 0 || !log.contains(e)) throw new Failed('$main: expected the error "$e":\n' + r.log);
			Sys.println('$main: rejected');
		}
	}

	// helder/scene from TypeScript (tests/3d/ts/frames.ts, examples/ts-scene's
	// scenes): its frames headless as RenderCheck's, glow against Haxe's glow.png,
	// tsscene against tsscene.png (which check.sh's Haxe twin matches too)
	static function sceneTs(t:String) {
		var compiler = StringTools.trim(output(NODE, ["src/helder/compiler/build.mjs", "--quiet"]));
		var cp = sceneTsPaths();
		var exe = exePath('bin/3d/$t/ts-frames', t);
		mkdirs(Path.directory(exe));
		run(compiler, ["tests/3d/ts/frames.ts", "-o", exe].concat(cp).concat(targetArgs(t)));
		for (s in ["glow", "tsscene", "primitives", "toon"])
			shell('LIBGL_ALWAYS_SOFTWARE=1 HXMC_GFX_SOFTWARE=1 env -u DISPLAY $exe $s tests/3d/$s.png bin/3d/$t/ts-$s.png');
	}

	// a <Scene> of TypeScript's markup given helder/gfx's vec3, vec4 and Quat
	// (tests/3d/ts/props.tsx): run headless (it threw before SceneRenderer
	// took them as Haxe's values), the sphere a vec3 placed right of the
	// centre red, its mirror left of it the background
	static function sceneProps() {
		var png = "bin/3d/ts-props.png";
		shell('LIBGL_ALWAYS_SOFTWARE=1 env -u DISPLAY ${helderCli()} run --headless tests/3d/ts/props.tsx --snap $png --at 0.5');
		var at = pixels(png);
		var sphere = at(215, 120), left = at(105, 120);
		if (!(sphere.r > 200 && sphere.g < 60 && sphere.b < 60)) throw new Failed('tests/3d/ts/props.tsx: the sphere at (215, 120) is not red: $sphere');
		if (!(left.r < 60 && left.g < 60 && left.b < 60)) throw new Failed('tests/3d/ts/props.tsx: (105, 120) is not the background: $left');
		Sys.println("tests/3d/ts/props.tsx: drawn, the sphere where its vec3 put it");
	}

	// (a PNG's pixels, 8-bit RGB or RGBA, not interlaced: a reader of (x, y))
	static function pixels(path:String):(x:Int, y:Int) -> {r:Int, g:Int, b:Int} {
		var d = File.getBytes(path), i = 8, w = 0, h = 0, bpp = 4;
		var idat = new haxe.io.BytesBuffer();
		while (i < d.length) {
			var n = (d.get(i) << 24) | (d.get(i + 1) << 16) | (d.get(i + 2) << 8) | d.get(i + 3), kind = d.getString(i + 4, 4);
			if (kind == "IHDR") {
				w = (d.get(i + 8) << 24) | (d.get(i + 9) << 16) | (d.get(i + 10) << 8) | d.get(i + 11);
				h = (d.get(i + 12) << 24) | (d.get(i + 13) << 16) | (d.get(i + 14) << 8) | d.get(i + 15);
				bpp = d.get(i + 17) == 6 ? 4 : 3;
			} else if (kind == "IDAT") idat.addBytes(d, i + 8, n);
			i += 12 + n;
		}
		var raw = haxe.zip.Uncompress.run(idat.getBytes()), stride = w * bpp;
		var rows = haxe.io.Bytes.alloc(stride * h), prev = haxe.io.Bytes.alloc(stride), p = 0;
		for (y in 0...h) {
			var f = raw.get(p++), line = haxe.io.Bytes.alloc(stride);
			line.blit(0, raw, p, stride);
			p += stride;
			for (x in 0...stride) {
				var a = x >= bpp ? line.get(x - bpp) : 0, b = prev.get(x), c = x >= bpp ? prev.get(x - bpp) : 0;
				var v = line.get(x) + switch f {
					case 1: a;
					case 2: b;
					case 3: (a + b) >> 1;
					case 4:
						var pa = Std.int(Math.abs(b - c)), pb = Std.int(Math.abs(a - c)), pc = Std.int(Math.abs(a + b - 2 * c));
						pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
					case _: 0;
				}
				line.set(x, v & 255);
			}
			rows.blit(y * stride, line, 0, stride);
			prev = line;
		}
		return (x, y) -> {r: rows.get(y * stride + x * bpp), g: rows.get(y * stride + x * bpp + 1), b: rows.get(y * stride + x * bpp + 2)};
	}

	static function sceneWeb() {
		pack();
		// (Model.of's files beside the module, helder.asset's Bundle: fetched by
		// browser.mjs before main; Lazy's at run time)
		rmrf("bin/3d/assets");
		wasm("bin/3d/SceneWebCheck.wasm", sceneCp().concat(["-main", "SceneWebCheck", "-D", "helder.asset.out=bin/3d/SceneWebCheck.wasm"]));
		run(NODE, ["tests/3d/web.mjs", "bin/3d/SceneWebCheck.wasm", "bin/3d"].concat(shardArgs()));
	}
}
