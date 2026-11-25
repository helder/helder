import LitShader;
import haxe.io.Bytes;
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;
import BuiltinShader;
import InstancesShader;
import SlotsShader;
import TexturedShader;
import TriangleShader;
import PaletteShader;
import ComputeShaders;

// The shader definition's tests, on Eval (bun run test gfx-shader):
//
//   <tool> -cp src -cp examples -cp tests/gfx
//     --run ShaderCheck <tool> [--bless]
//
// - the math types and the shaders' functions run on the CPU (TriangleShader,
//   LitShader with Lighting's helpers): their values
// - the generated members: the vertex layout and bytes, the uniform blocks'
//   std140 layout and writers
// - the emitted source in all four languages (Eval: all of them), against
//   test/shader/<Class>.<vert|frag>.<glsl|wgsl|msl|hlsl> (--bless rewrites them)
// - the programs test/reject/*.hx the compiler must reject: each `// expect:
//   <text>` line of one is in the compiler's output (as hxmc/test/reject)
// - the tests' PNG files (Png.hx, as GfxCheck --bless writes them, in stored
//   blocks of 65535 bytes) read back by Png.decode, pixel for pixel
class ShaderCheck {
	static var failures = 0;
	static var checks = 0;

	static function main() {
		var args = Sys.args();
		var tool = args[0], bless = args.contains("--bless");
		var here = haxe.io.Path.directory(Sys.programPath());
		if (here == "") here = ".";
		math();
		shaders();
		layouts();
		compute();
		png();
		golden(here + "/shader", bless);
		if (tool != null && tool != "--bless") rejects(tool, here);
		Sys.println('ShaderCheck: $checks checks, ' + (failures == 0 ? "ok" : '$failures FAILED'));
		Sys.exit(failures == 0 ? 0 : 1);
	}

	static function check(what:String, ok:Bool, ?detail:String) {
		checks++;
		if (!ok) {
			failures++;
			Sys.println('ShaderCheck: FAIL: $what' + (detail != null ? ": " + detail : ""));
		}
	}

	static function near(what:String, got:Float, want:Float)
		check(what, Math.abs(got - want) < 1e-9, 'got $got, want $want');

	static function nearVec(what:String, got:Vec4, want:Array<Float>)
		for (i in 0...4)
			near(what + "." + "xyzw".charAt(i), [got.x, got.y, got.z, got.w][i], want[i]);

	// Png: encode (stored blocks) then decode, at sizes of one block and of
	// several full ones (InflateImpl's window: 32 KiB at once)
	static function png() {
		for (size in [[4, 3], [256, 192], [640, 480]]) {
			var w = size[0], h = size[1];
			var rgba = Bytes.alloc(w * h * 4);
			for (i in 0...rgba.length)
				rgba.set(i, (i * 31 + (i >> 9)) & 0xFF);
			var g = try Png.decode(Png.encode(rgba, w, h)) catch (e:Dynamic) {
				check('png ${w}x$h', false, Std.string(e));
				continue;
			}
			var same = g.width == w && g.height == h;
			for (p in 0...w * h)
				for (k in 0...3)
					if (same && g.rgba.get(4 * p + k) != rgba.get(4 * p + k)) same = false;
			check('png ${w}x$h', same, "other pixels read back");
		}
	}

	// the math types and ShaderMath as ordinary Haxe
	static function math() {
		var a = vec3(1, 2, 3), b = vec3(-2, 0.5, 4);
		near("dot", dot(a, b), -2 + 1 + 12);
		var c = cross(a, b);
		nearVec("cross", vec4(c, 0), [2 * 4 - 3 * 0.5, 3 * -2 - 1 * 4, 1 * 0.5 - 2 * -2, 0]);
		nearVec("swizzles", vec4(a.zyx, a.xy.yx.x), [3, 2, 1, 2]);
		nearVec("operators", vec4(2 * a - 1 + a / 2, 0), [1.5, 4, 6.5, 0]);
		near("length", length(normalize(b)), 1);
		near("mix", mix(a, b, 0.25).y, 2 + (0.5 - 2) * 0.25);
		near("smoothstep", smoothstep(0, 2, 0.5), 0.15625);
		near("clamp", clamp(a, 1.5, 2.5).x, 1.5);
		near("fract", fract(-1.25), 0.75);
		near("step", step(vec2(1, 3), vec2(2)).y, 0);
		// columns: (m * v) = c0 * v.x + c1 * v.y + ...; mat4(s) is s on the diagonal
		var m = mat4(vec4(1, 0, 0, 0), vec4(0, 2, 0, 0), vec4(0, 0, 3, 0), vec4(4, 5, 6, 1));
		nearVec("mat4 * vec4", m * vec4(1, 1, 1, 1), [5, 7, 9, 1]);
		nearVec("mat4 * mat4", (m * mat4(2)) * vec4(1, 0, 0, 1), [2 + 4 * 2, 5 * 2, 6 * 2, 2]);
		// the clip space: z from 0 at the near plane to w at the far one
		var proj = Mat4.perspective(Math.PI / 2, 2, 1, 10), n = proj * vec4(0, 0, -1, 1), f = proj * vec4(0, 0, -10, 1);
		near("perspective near", n.z / n.w, 0);
		near("perspective far", f.z / f.w, 1);
		nearVec("perspective, a corner", proj * vec4(2, 1, -1, 1), [1, 1, 0, 1]);
		var o = Mat4.orthographic(0, 4, 0, 2, 1, 3) * vec4(4, 0, -3, 1);
		nearVec("orthographic", o, [1, -1, 1, 1]);
		nearVec("rotations", Mat4.translation(1, 0, 0) * Mat4.rotationZ(Math.PI / 2) * Mat4.rotationY(Math.PI / 2) * vec4(0, 0, 1, 1), [1, 1, 0, 1]);
	}

	// the shaders' functions on the CPU
	static function shaders() {
		var o = TriangleShader.vertex({pos: vec2(0.6, -0.5), color: vec3(0, 0, 1)});
		nearVec("TriangleShader.vertex pos", o.pos, [0.6, -0.5, 0, 1]);
		nearVec("TriangleShader.fragment", TriangleShader.fragment(o), [0, 0, 1, 1]);
		var cam:Camera = {viewProj: mat4(2), eye: vec3(1, 0, 5), time: 0};
		var v = LitShader.vertex({pos: vec3(1, 0, 0), normal: vec3(0, 0, 1), uv: vec2(0.25, 0.75)}, {cam: cam});
		nearVec("LitShader.vertex clip", v.clip, [2 + Math.sin(3) * 0.05, 0, 0, 2]);
		near("LitShader.vertex uv", v.uv.x, 0.75);
		near("LitShader.vertex shade", v.shade, 1);
		near("Lighting.lambert", Lighting.lambert(vec3(0, 3, 0), vec3(1, 1, 0)), Math.sqrt(0.5));
		near("Lighting.posterize", Lighting.posterize(0.5, 4), 2 / 3);
		var i:LitVaryings = {normal: vec3(0, 0, 1), clip: vec4(0), uv: vec2(0.25, 0.75), shade: 0.5};
		var glow = 1 / 2 + 1 / 3 + 1 / 4 + 1 / 5, k = 0.1 + 2 / 3;
		nearVec("LitShader.fragment", LitShader.fragment(i, {m: {tint: vec4(1, 0.5, 0.25, 1), steps: 4}}),
			[k + glow * 0.01, 0.5 * k + glow * 0.01, 0.25 * k + glow * 0.01, 1]);
		// (the uv in the right half: the colour reversed; the checker's dark squares)
		var j:LitVaryings = {normal: vec3(0, 0, 1), clip: vec4(0), uv: vec2(0.7, 0.75), shade: 0.5};
		nearVec("LitShader.fragment, right half", LitShader.fragment(j, {m: {tint: vec4(1, 0.5, 0.25, 1), steps: 0}}),
			[0.25 * 0.6 * 0.5, 0.5 * 0.6 * 0.5, 0.6 * 0.5, 1]);
		// (a vector constant, atan2, arrays: Palette)
		var pal:PaletteBlock = {scale: vec4(1), colors: COLORS, turns: [mat4(0), mat4(1)]};
		var pv = PaletteShader.vertex({pos: vec2(0.5, -0.5), index: 2}, {palette: pal});
		nearVec("PaletteShader.vertex", pv.pos, [0.5, -0.5, 0, 1]);
		nearVec("PaletteShader.fragment", PaletteShader.fragment(pv, {palette: pal}), [0, 0, 0.25, 1]);
		near("atan2", atan2(1, 0), Math.PI / 2);
		// (a translation by pos.xyz, then halved)
		var b = BuiltinShader.vertex({pos: vec4(1, 2, 3, 1)});
		nearVec("BuiltinShader.vertex", b.pos, [1, 2, 3, 0.5]);
		var c = BuiltinShader.fragment(b);
		check("BuiltinShader.fragment", [c.x, c.y, c.z, c.w].filter(Math.isFinite).length == 4, Std.string([c.x, c.y, c.z, c.w]));
		// (textures on the CPU: the nearest texel, repeating; rows top to bottom)
		var texels = Bytes.alloc(2 * 2 * 4);
		for (i in 0...4) {
			texels.set(4 * i, 255);
			texels.set(4 * i + 1, [0, 64, 128, 255][i]);
			texels.set(4 * i + 3, 255);
		}
		var tex = new Texture2D(2, 2, texels);
		near("sample", sample(tex, vec2(0.75, 0.25)).y, 64 / 255);
		near("sample, repeating", sample(tex, vec2(-0.25, 1.75)).y, 255 / 255);
		var tv = TexturedShader.vertex({pos: vec2(0, 0), uv: vec2(0.25, 0.75)}, {height: tex});
		near("TexturedShader.vertex lift", tv.lift, 1);
		nearVec("TexturedShader.fragment", TexturedShader.fragment(tv, {fade: {amount: 0.5}, albedo: tex, height: tex}), [1, (0.5 + 128 / 255) / 2, 0, 1]);
	}

	// the generated layouts and writers
	static function layouts() {
		var l = TriangleShader.layout[0];
		check("TriangleShader.layout", l.stride == 20 && l.attributes.length == 2 && l.attributes[1].offset == 8 && l.attributes[1].format == Float3);
		var b = TriangleShader.vertexBytes([{pos: vec2(0, 0.6), color: vec3(1, 0, 0)}, {pos: vec2(-0.6, -0.5), color: vec3(0, 1, 0)}]);
		var want = [0.0, 0.6, 1, 0, 0, -0.6, -0.5, 0, 1, 0];
		check("TriangleShader.vertexBytes", b.length == 40 && [for (i in 0...10) b.getFloat(4 * i)].join(",") == [
			for (f in want) {
				var x = Bytes.alloc(4);
				x.setFloat(0, f);
				x.getFloat(0);
			}
		].join(","));
		var u = LitShader.uniforms;
		check("LitShader.uniforms", u.length == 2 && u[0].name == "Camera" && u[0].binding == 0 && u[0].size == 80 && u[1].name == "Material"
			&& u[1].size == 32, Std.string(u));
		var bytes = Bytes.alloc(96);
		LitShader.params.cam.write({viewProj: mat4(vec4(1, 2, 3, 4), vec4(5, 6, 7, 8), vec4(9, 10, 11, 12), vec4(13, 14, 15, 16)), eye: vec3(-1, -2, -3), time: 7}, bytes,
			16);
		check("LitShader.params.cam.write", [for (i in 0...20) bytes.getFloat(16 + 4 * i)].join(",") == "1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,-1,-2,-3,7");
		LitShader.params.m.write({tint: vec4(0.5), steps: 3}, bytes);
		check("LitShader.params.m.write", bytes.getFloat(12) == 0.5 && bytes.getInt32(16) == 3);
		// (arrays: 16 bytes a Vec4, 64 a Mat4; the elements given, zeros after)
		var pu = PaletteShader.uniforms[0];
		check("PaletteShader.uniforms", pu.size == 16 + 64 + 128, Std.string(pu.size));
		var pb = Bytes.alloc(pu.size);
		pb.fill(0, pu.size, 7);
		PaletteShader.params.palette.write({scale: vec4(2), colors: [vec4(1, 2, 3, 4)], turns: [mat4(1)]}, pb);
		check("PaletteShader.params.palette.write", [for (i in 0...8) pb.getFloat(16 + 4 * i)].join(",") == "1,2,3,4,0,0,0,0" && pb.getFloat(80) == 1
			&& pb.getFloat(100) == 1 && pb.getFloat(144) == 0 && pb.get(pu.size - 1) == 0);
		var t = TexturedShader.textures, tu = TexturedShader.uniforms;
		check("TexturedShader.textures", t.length == 2 && t[0].name == "height" && t[0].binding == 0 && t[1].name == "albedo" && t[1].binding == 2
			&& tu.length == 1 && tu[0].binding == 1, Std.string(t) + " " + Std.string(tu));
		// a slot object's variants (SlotsShader): the attributes, varyings and parameters each reads
		var sp = SlotsPlain.layout[0], st = SlotsTinted.layout[0];
		check("SlotsPlain.layout", sp.stride == 8 && sp.attributes.length == 1, Std.string(sp));
		check("SlotsTinted.layout", st.stride == 32 && st.attributes.length == 3 && st.attributes[2].offset == 24 && st.attributes[2].format == Float2,
			Std.string(st));
		check("SlotsPlain.textures", SlotsPlain.textures.length == 0 && SlotsTextured.textures.length == 1 && SlotsTextured.params.image.binding == 1,
			Std.string(SlotsTextured.textures));
		check("SlotsTinted.vertexBytes", SlotsTinted.vertexBytes([{pos: vec2(1, 2), tint: vec4(3), shift: vec2(4, 5)}]).getFloat(28) == 5);
		var tv = SlotsTinted.vertex({pos: vec2(1, 2), tint: vec4(0.5), shift: vec2(1, 1)}, {view: {scale: vec4(2)}});
		nearVec("SlotsTinted.vertex", tv.clip, [3, 5, 0, 1]);
		// (tinted, taps 3: the colour times the tint, times 1 + 2 + 3)
		nearVec("SlotsTinted.fragment", SlotsTinted.fragment(tv, {view: {scale: vec4(2)}}), [1 * 0.5 * 6, 2 * 0.5 * 6, 2 * 0.5 * 6, 0.5 * 6]);
		nearVec("SlotsPlain.fragment", SlotsPlain.fragment(tv, {view: {scale: vec4(2)}}), [1, 2, 2, 1]);
		var bs = TexturedShader.fragmentCode.bindings;
		check("TexturedShader.fragmentCode.bindings", bs.length == 3 && bs[0].name == "Fade_block" && bs[0].slot == 1 && bs[1].name == "tex_2" && bs[2].name == "tex_0", Std.string(bs));
	}

	// compute({size, main}): the stages on the CPU, the storage slots' std430 layouts, the bindings
	static function compute() {
		// (a scan step: in -> out)
		var src:Array<Int> = [1, 2, 3, 4, 5], dst:Array<Int> = [0, 0, 0, 0, 0];
		for (x in 0...8)
			Scan.main(ComputeInput.at(x, 0, 0, 64, 1, 1), {step: {offset: 2, count: 5}, src: src, dst: dst});
		check("Scan.main", dst.join(",") == "1,2,4,6,8", dst.join(","));
		var ps:Array<Particle> = [{pos: vec4(0, 0, 0, 1), vel: vec4(1, 2, 0, 0)}, {pos: vec4(5, 0, 0, 0), vel: vec4(1, 0, 0, 0)}];
		var kept:Array<Vec4> = [vec4(0), vec4(0)], args:Array<Int> = [6, 0, 0, 0];
		for (x in 0...2)
			Move.main(ComputeInput.at(x, 0, 0, 64, 1, 1), {step: {dt: 0.5, count: 2}, particles: ps, kept: kept, args: args});
		check("Move.main", args[1] == 1 && kept[0].x == 0.5 && kept[0].y == 1 && ps[1].pos.x == 5.5, args.join(",") + " " + kept[0].x + " " + ps[1].pos.x);
		var img = new StorageTexture(2, 2);
		for (y in 0...2)
			for (x in 0...2)
				Gradient.main(ComputeInput.at(x, y, 0, 8, 8, 1), {size: {width: 2, height: 2}, image: img});
		check("Gradient.main", img.texels.get(4 * 3) == 8 && img.texels.get(4 * 3 + 1) == 8 && img.texels.get(2) == 128, [for (i in 0...16) img.texels.get(i)].join(","));
		var i = ComputeInput.at(70, 9, 0, 64, 8, 1);
		check("ComputeInput.at", i.localX == 6 && i.groupX == 1 && i.localY == 1 && i.groupY == 1 && i.localIndex == 6 + 64 * 1, Std.string(i));
		// (std430: a struct of two Vec4s 32 bytes, Vec4s 16, Ints 4)
		check("Move.params strides", Move.params.particles.stride == 32 && Move.params.kept.stride == 16 && Move.params.args.stride == 4 && Move.params.particles.writable
			&& !Scan.params.src.writable);
		var b = Move.params.particles.bytesOf(ps);
		var back = Move.params.particles.load(b, 1);
		check("StorageSlot store, load", b.length == 64 && b.getFloat(32) == 5.5 && b.getFloat(48) == 1 && back.pos.x == 5.5 && back.vel.x == 1);
		check("Move.groups", Move.groups(64) == 1 && Move.groups(65) == 2 && Gradient.groups(17, 1) == 3);
		var bs = Move.code.bindings;
		// (slots in order; GL's storage bindings and D3D11's UAVs: the written buffers 0, 1, 2)
		check("Move.code.bindings", bs.length == 4 && bs[0].name == "MoveStep_block" && bs[1].kind == StorageWrite && bs[1].index == 0 && bs[3].index == 2
			&& Move.code.workgroupSize.join(",") == "64,1,1", Std.string(bs));
		var sb = Scan.code.bindings;
		check("Scan.code.bindings", sb[1].kind == Storage && sb[1].index == 1 && sb[2].kind == StorageWrite && sb[2].index == 0, Std.string(sb));
		check("Gradient.code", Gradient.code.workgroupSize.join(",") == "8,8,1" && Gradient.code.bindings[1].kind == StorageTexture, Std.string(Gradient.code.bindings));
		// (workgroup memory and subgroups on the CPU: an invocation alone, a
		// subgroup of one; the invocations in reverse, so that the first's
		// sum reads the others' parts)
		var values:Array<Float> = [for (i in 0...10) i + 1], out:Array<Float> = [0], part:Array<Float> = [for (_ in 0...256) 0];
		var x = 255;
		while (x >= 0)
			Sums.main(ComputeInput.at(x--, 0, 0, 256, 1, 1), {count: {n: 10}, values: values, out: out}, {part: part});
		check("Sums.main", out[0] == 55, Std.string(out));
		var i = ComputeInput.at(70, 0, 0, 64, 1, 1);
		check("ComputeInput.at's subgroups", i.subgroupLane == 0 && i.subgroupSize == 1 && i.subgroupIndex == 6 && i.subgroups == 64, Std.string(i));
		// (the subgroups' second form beside the first; cs_5_0's only that one)
		var e = Sums.emulated().program;
		check("Sums.emulated()", Sums.code.hlsl == null && e.hlsl != null && e.wgsl != Sums.code.wgsl && Prefix.code.emulated == null && Prefix.emulated().program == Prefix.code
			&& e.workgroupSize.join(",") == "256,1,1" && e.bindings == Sums.code.bindings);
	}

	// the emitted source against the golden files
	static function golden(dir:String, bless:Bool) {
		var codes:Array<{name:String, code:helder.gfx.ShaderCode}> = [
			{name: "TriangleShader.vert", code: TriangleShader.vertexCode},
			{name: "TriangleShader.frag", code: TriangleShader.fragmentCode},
			{name: "LitShader.vert", code: LitShader.vertexCode},
			{name: "LitShader.frag", code: LitShader.fragmentCode},
			{name: "BuiltinShader.vert", code: BuiltinShader.vertexCode},
			{name: "BuiltinShader.frag", code: BuiltinShader.fragmentCode},
			{name: "TexturedShader.vert", code: TexturedShader.vertexCode},
			{name: "TexturedShader.frag", code: TexturedShader.fragmentCode},
			{name: "InstancesShader.vert", code: InstancesShader.vertexCode},
			{name: "InstancesShader.frag", code: InstancesShader.fragmentCode},
			{name: "SlotsPlain.vert", code: SlotsPlain.vertexCode},
			{name: "SlotsPlain.frag", code: SlotsPlain.fragmentCode},
			{name: "SlotsTinted.vert", code: SlotsTinted.vertexCode},
			{name: "SlotsTinted.frag", code: SlotsTinted.fragmentCode},
			{name: "SlotsTextured.vert", code: SlotsTextured.vertexCode},
			{name: "SlotsTextured.frag", code: SlotsTextured.fragmentCode},
			{name: "PaletteShader.vert", code: PaletteShader.vertexCode},
			{name: "PaletteShader.frag", code: PaletteShader.fragmentCode},
			{name: "Scan.comp", code: Scan.code},
			{name: "Move.comp", code: Move.code},
			{name: "Gradient.comp", code: Gradient.code},
			{name: "Sums.comp", code: Sums.code},
			{name: "Sums.emulated.comp", code: Sums.emulated().program},
			{name: "Prefix.comp", code: Prefix.code},
			{name: "Lanes.comp", code: Lanes.code},
			{name: "Lanes.emulated.comp", code: Lanes.emulated().program}
		];
		for (c in codes)
			for (l in ["glsl", "wgsl", "msl", "hlsl"]) {
				var src:Null<String> = Reflect.field(c.code, l);
				var file = '$dir/${c.name}.$l';
				// (a language without this form: HLSL has no subgroups)
				if (src == null) {
					check('$file', !sys.FileSystem.exists(file), "a form the stage has not");
					continue;
				}
				if (bless) {
					sys.io.File.saveContent(file, src);
					continue;
				}
				var want = sys.FileSystem.exists(file) ? sys.io.File.getContent(file) : null;
				check('$file', src == want, want == null ? "missing (--bless writes it)" : "differs:\n" + src);
			}
		if (bless) Sys.println('ShaderCheck: blessed $dir');
	}

	// the programs the compiler must reject
	static function rejects(tool:String, here:String) {
		var dir = here + "/reject";
		var src = haxe.io.Path.normalize(here + "/../../src");
		var files = [for (f in sys.FileSystem.readDirectory(dir)) if (StringTools.endsWith(f, ".hx")) f];
		files.sort(Reflect.compare);
		for (f in files) {
			var expect = [
				for (l in sys.io.File.getContent('$dir/$f').split("\n"))
					if (StringTools.startsWith(l, "// expect: ")) StringTools.trim(l.substr(11))
			];
			var p = new sys.io.Process(tool, ["-D", "hxmc.markup-braces", "-cp", src, "-cp", dir, "-main", f.substr(0, f.length - 3), "--interp", "--no-output"]);
			var out = p.stdout.readAll().toString() + p.stderr.readAll().toString();
			var code = p.exitCode();
			p.close();
			var missing = [for (e in expect) if (out.indexOf(e) < 0) e];
			check('reject/$f', code != 0 && expect.length > 0 && missing.length == 0,
				code == 0 ? "compiled, but must be rejected" : "missing: " + missing.join("; ") + "\n" + out);
		}
	}
}
