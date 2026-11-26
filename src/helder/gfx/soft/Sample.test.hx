package helder.gfx.soft;

import helder.math.Vec3;
import helder.test.Test;
import hxmc.unsafe.LibC;
import hxmc.unsafe.Mem;

// A cube sampled on the CPU: filtered across its faces' edges (seamless),
// each face its own colour
function tests() {
	describe("Sample", () -> {
		#if (target.name == "hxmc")
		test("a cube's edge: both faces' texels", () -> @:hxmc.unsafe(gc) {
			var red = cube();
			// (on +X's edge with +Y: half +X's red, half +Y's green)
			var c = Sample.cubeAt(red, new Vec3(1, 1, 0), 0);
			assert(c.x > 0.4 && c.x < 0.6, 'red ${c.x}');
			assert(c.y > 0.4 && c.y < 0.6, 'green ${c.y}');
			// (the face's middle: its own colour alone)
			equals(Sample.cubeAt(red, new Vec3(1, 0, 0), 0).x, 1.0);
			SoftTexture.free(Mem.getPtr(red, Sample.TEXTURE));
			LibC.free(red);
		});
		#end
	});
}

#if (target.name == "hxmc")
// (a 2x2 cube, +X red, +Y green, the others blue, linear, its binding)
@:hxmc.unsafe(gc) function cube():hxmc.unsafe.Ptr {
	var t = SoftTexture.make({width: 2, height: 2, cube: true});
	for (face in 0...6) {
		var px = haxe.io.Bytes.alloc(16);
		for (i in 0...4)
			px.setInt32(4 * i, face == 0 ? 0xFF0000FF : face == 2 ? 0xFF00FF00 : 0xFFFF0000);
		SoftTexture.write(t, px, 0, 0, 0, 2, 2, 0, face);
	}
	var b = LibC.malloc(Sample.SIZE);
	Mem.setPtr(b, Sample.TEXTURE, t);
	Mem.setI32(b, Sample.FILTER, 1);
	Mem.setI32(b, Sample.MIP, -1);
	Mem.setI32(b, Sample.WRAP, 0);
	return b;
}
#end
