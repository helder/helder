package lanes;

import sys.io.Process;
import lanes.Tools.*;

using StringTools;

class Gfx {
	public static final LANES:Array<Lane> = [
		{name: "gfx-shader", about: "shader definitions on Eval and their emitted code", run: gfxShader},
		{name: "gfx", about: "helder.gfx's examples against golden images", run: gfx},
		{name: "gfx-shared", about: "helder.gfx's shared textures between two processes", run: gfxShared},
		{name: "sprite", about: "helder.sprite's SpriteBatch on a GPU", run: sprite},
		{name: "gfx-web", about: "helder.gfx on WebGPU and WebGL2 in headless Chromium", run: gfxWeb},
		{name: "gfx-compute", about: "helder.gfx's compute tier, headless", run: gfxCompute},
		{name: "gfx-compute-web", about: "helder.gfx's compute tier in headless Chromium", run: gfxComputeWeb},
		{name: "gfx-soft", about: "helder.gfx on the CPU against golden images", run: gfxSoft}
	];

	static function gfxShader() {
		interp(cps(["src", "tests/gfx"]).concat(cps(GFX_EXAMPLES)), "ShaderCheck", [TOOL].concat(BLESS ? ["--bless"] : []));
	}

	static function gfxPrograms() {
		for (m in ["GfxCheck", "Triangle", "Cube", "Instances", "Targets", "Mips", "Formats"])
			native('bin/gfx/$GFX_TARGET/$m', gfxCp().concat(["-main", m]), GFX_TARGET);
	}

	static function gfx() {
		gfxPrograms();
		run("sh", ["tests/gfx/check.sh", 'bin/gfx/$GFX_TARGET']);
	}

	static function gfxShared() {
		native('bin/gfx-shared/$GFX_TARGET/SharedTextureCheck', cps(["src", "tests/gfx"]).concat(["-main", "SharedTextureCheck"]), GFX_TARGET);
		var exe = exePath('bin/gfx-shared/$GFX_TARGET/SharedTextureCheck', GFX_TARGET);
		// (a Mac's and Windows' own GPU always share; under Wine, or on Linux without a dma-buf exporter, skipped)
		var require = GFX_TARGET == HOST && (HOST.startsWith("macos-") || HOST.startsWith("windows-"));
		if (GFX_TARGET.startsWith("windows-") && !HOST.startsWith("windows-")) run("wine", [exe]) else run(exe, require ? ["--require"] : []);
	}

	static function sprite() {
		native('bin/sprite/$GFX_TARGET/SpriteFrameCheck', cps(["src", "tests/sprite"]).concat(["-main", "SpriteFrameCheck"]), GFX_TARGET);
		Sys.putEnv("LIBGL_ALWAYS_SOFTWARE", "1");
		run(exePath('bin/sprite/$GFX_TARGET/SpriteFrameCheck', GFX_TARGET), []);
	}

	static function gfxWeb() {
		wasm("bin/gfx/WebCheck.wasm", gfxCp().concat(["-main", "WebCheck"]));
		run(NODE, ["tests/gfx/web.mjs", "bin/gfx/WebCheck.wasm", "bin/gfx"]);
	}

	// (ComputeCheck, then helder.parallel's Gpu form: tests/parallel/GpuCheck,
	// and examples/cloth's against its CPU forms: ClothCheck)
	static function gfxCompute() {
		for (c in [
			{main: "ComputeCheck", dirs: ["tests/gfx"]},
			{main: "GpuCheck", dirs: ["tests/parallel"]},
			{main: "ClothCheck", dirs: ["tests/parallel", "examples/cloth"]}
		]) {
			native('bin/gfx-compute/$GFX_TARGET/${c.main}', cps(["src"].concat(c.dirs)).concat(["-main", c.main]), GFX_TARGET);
			var exe = exePath('bin/gfx-compute/$GFX_TARGET/${c.main}', GFX_TARGET);
			// (Mesa's llvmpipe and WARP: software; no Metal device on a Mac VM: exit 3, skipped)
			Sys.putEnv("LIBGL_ALWAYS_SOFTWARE", "1");
			Sys.putEnv("HXMC_GFX_SOFTWARE", "1");
			var p = GFX_TARGET.startsWith("windows-") && !HOST.startsWith("windows-") ? new Process("wine", [exe]) : new Process(exe, []);
			var r = drain(p);
			var code = p.exitCode();
			p.close();
			Sys.print(r.out + r.err);
			if (code == 3) Sys.println('gfx-compute: ${c.main} skipped (no device with compute)') else if (code != 0) throw new Failed('$exe: exit code $code');
		}
	}

	static function gfxComputeWeb() {
		wasm("bin/gfx-compute/ComputeCheck.wasm", cps(["src", "tests/gfx"]).concat(["-main", "ComputeCheck"]));
		run(NODE, ["tests/gfx/compute-web.mjs", "bin/gfx-compute/ComputeCheck.wasm"]);
		// (helder.parallel's Gpu form, its results awaited: Items.read)
		wasm("bin/gfx-compute/GpuWebCheck.wasm", cps(["src", "tests/parallel"]).concat(["-main", "GpuWebCheck"]));
		run(NODE, ["tests/parallel/browser.mjs", "bin/gfx-compute/GpuWebCheck.wasm"]);
	}

	// (helder.gfx's frames and helder.scene's drawn on the CPU against the GPUs'
	// goldens; on Linux static, so nothing of a GPU's can be loaded)
	static function gfxSoft() {
		var b = 'bin/gfx-soft/$HOST', soft = ["-D", "helder.soft", "-D", 'hxmc.target=$HOST'];
		pack();
		var builds = [
			{out: exePath('$b/SoftShaderCheck', HOST), args: cps(["src", "tests/gfx"]).concat(["-main", "SoftShaderCheck", "-D", "helder.soft.exact", "-D", "helder.soft.reference"]).concat(soft)},
			{out: exePath('$b/GfxCheck', HOST), args: gfxCp().concat(["-main", "GfxCheck", "-D", "helder.headless"]).concat(soft)},
			{out: exePath('$b/ComputeCheck', HOST), args: cps(["src", "tests/gfx"]).concat(["-main", "ComputeCheck", "-D", "helder.headless"]).concat(soft)},
			{out: exePath('$b/GpuCheck', HOST), args: cps(["src", "tests/parallel"]).concat(["-main", "GpuCheck", "-D", "helder.headless"]).concat(soft)},
			{out: exePath('$b/ClothCheck', HOST), args: cps(["src", "tests/parallel", "examples/cloth"]).concat(["-main", "ClothCheck", "-D", "helder.headless"]).concat(soft)},
			{out: exePath('$b/RenderCheck', HOST), args: sceneCp().concat(["-main", "RenderCheck"]).concat(soft)}
		];
		prebuild(builds);
		for (p in builds)
			hxmc(p.out, p.args);
		run(exePath('$b/SoftShaderCheck', HOST), []);
		run(exePath('$b/ComputeCheck', HOST), []);
		run(exePath('$b/GpuCheck', HOST), []);
		run(exePath('$b/ClothCheck', HOST), []);
		for (s in ["triangle", "cube", "instances", "targets", "msaa", "mips", "formats", "blend", "palette", "layers"])
			run(exePath('$b/GfxCheck', HOST), ["headless", s, 'tests/gfx/$s.png', '$b/$s.png']);
		run("sh", ["tests/3d/check.sh", b], ["SOFT" => "1"]);
	}
}
