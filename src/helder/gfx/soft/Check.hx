package helder.gfx.soft;

import hxmc.I64;
import hxmc.unsafe.LibC;
import hxmc.unsafe.Mem;
import hxmc.unsafe.Ptr;

// A shader's SIMD form against its scalar reference (-D helder.soft.reference:
// Soft's soft_vs_ref and soft_fs_ref, the same stage lane by lane in
// helder.gfx.shader's scalar code), on the same random inputs, uniform
// blocks and textures: their outputs' bits and the lanes left must be equal
// (with -D helder.soft.exact, the lanes Haxe's doubles: tests/gfx/SoftShaderTest).
// Each shader of such a build registers its check (Soft: soft_check).
@:hxmc.unsafe(gc)
class Check {
	// (made at the first registration: the shaders' classes may be initialised before this one)
	public static var shaders(get, null):Array<{name:String, check:Int->Null<String>}>;

	static function get_shaders() {
		if (shaders == null) shaders = [];
		return shaders;
	}

	public static function register(name:String, check:Int->Null<String>):Bool {
		get_shaders().push({name: name, check: check});
		return true;
	}

	static inline var BUFFER = 4096;

	final ctx:Ptr;
	final input:Ptr;
	final simd:Ptr;
	final scalar:Ptr;
	final owned:Array<Ptr> = [];
	var seed:Int;

	public function new(seed:Int) {
		this.seed = seed * 7919 + 17;
		ctx = alloc(Abi.SIZE);
		input = alloc(BUFFER);
		simd = alloc(BUFFER);
		scalar = alloc(BUFFER);
	}

	function alloc(n:Int):Ptr {
		var p:Ptr = LibC.malloc((n : I64));
		Mem.zero(p, (n : I64));
		owned.push(p);
		return p;
	}

	public function free() {
		for (p in owned)
			LibC.free(p);
		owned.resize(0);
	}

	public function random():Float {
		seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
		return seed / 2147483648.0;
	}

	// a value of a float's range: -2 to 2, a quarter of them small fractions
	function float():Float {
		var r = random();
		return r < 0.25 ? (random() - 0.5) * 0.1 : (random() - 0.5) * 4;
	}

	// a uniform block at a slot: its words' kinds (0 a float, 1 an Int: 0 to 4)
	public function block(slot:Int, kinds:Array<Int>) {
		var p = alloc(4 * kinds.length + 16);
		for (i in 0...kinds.length)
			if (kinds[i] == 1) Mem.setI32(p, 4 * i, Std.int(random() * 5)) else Mem.setF32(p, 4 * i, float());
		Mem.setPtr(ctx, Abi.UNIFORMS + 8 * slot, p);
	}

	// a texture at a slot: 8x8 random RGBA8 texels of one level, nearest, repeating (a
	// cube's six faces, an array's four layers); dimension as STexture's
	public function texture(slot:Int, dimension:Int) {
		var layers = dimension == 1 ? 6 : dimension == 2 ? 4 : 1;
		var t = SoftTexture.make({width: 8, height: 8, cube: dimension == 1, layers: dimension == 2 ? 4 : null});
		owned.push(t);
		for (l in 0...layers) {
			var base = SoftTexture.at(t, 0, l);
			for (i in 0...64)
				Mem.setI32(base, 4 * i, Std.int(random() * 256) | (Std.int(random() * 256) << 8) | (Std.int(random() * 256) << 16) | (Std.int(random() * 256) << 24));
		}
		var b = alloc(Sample.SIZE);
		Mem.setPtr(b, Sample.TEXTURE, t);
		Mem.setI32(b, Sample.FILTER, 0);
		Mem.setI32(b, Sample.MIP, -1);
		Mem.setI32(b, Sample.WRAP, 0);
		Mem.setPtr(ctx, Abi.TEXTURES + 8 * slot, b);
	}

	// a stage's two forms on n bytes of random input (a fragment's position:
	// pixels, a depth, 1/w), their outputs' bytes compared
	public function stage(name:String, entry:I64, reference:I64, inBytes:Int, outBytes:Int, fragment:Bool):Null<String> {
		for (i in 0...inBytes >> 2)
			Mem.setF32(input, 4 * i, float());
		if (fragment)
			for (l in 0...4) {
				Mem.setF32(input, 4 * l, 100 * random());
				Mem.setF32(input, 16 + 4 * l, 100 * random());
				Mem.setF32(input, 32 + 4 * l, random());
				Mem.setF32(input, 48 + 4 * l, 0.1 + random());
			}
		Mem.setPtr(ctx, Abi.IN, input);
		Mem.setI32(ctx, Abi.MASK, 15);
		Mem.zero(simd, (outBytes : I64));
		Mem.zero(scalar, (outBytes : I64));
		Mem.setPtr(ctx, Abi.OUT, simd);
		var a = Entry.call(Ptr.ofI64(entry), ctx);
		Mem.setPtr(ctx, Abi.OUT, scalar);
		var b = Entry.call(Ptr.ofI64(reference), ctx);
		if (a != b) return '$name: lanes left ${a} (SIMD), ${b} (scalar)';
		for (i in 0...outBytes >> 2) {
			var x = Mem.getI32(simd, 4 * i), y = Mem.getI32(scalar, 4 * i);
			if (x == y) continue;
			// (lanes discarded: their colour is no one's)
			if (fragment && a & (1 << (i & 3)) == 0) continue;
			var fx:Float = Mem.getF32(simd, 4 * i), fy:Float = Mem.getF32(scalar, 4 * i);
			if (Math.isNaN(fx) && Math.isNaN(fy)) continue;
			return '$name: output component ${i >> 2}, lane ${i & 3}: $fx (SIMD), $fy (scalar)';
		}
		return null;
	}
}

@:hxmc.c @:hxmc.fast private extern class Entry {
	@:hxmc.indirect static function call(f:Ptr, c:Ptr):Int;
}
