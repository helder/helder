package helder.scene.render;

import helder.gfx.shader.Mat4;
import helder.gfx.shader.Vec3;
import helder.scene.math.MathTools;
import helder.test.Test;

// ClusteredLights' cells on the CPU (Clusters, no device): each cell's list
// against brute force (every light tested against every cell, Clusters.
// reaches, the compute path's test), the same lights in the same order; a
// full cell keeps the first perCell; the lights' rows after the cells';
// assign allocating nothing, and 256 lights' time printed (natively and as
// wasm32-wasi).
function tests() {
	describe("Clusters", () -> {
		test("each cell lists the lights that reach it, as brute force does", () -> {
			var c = lensed(new Clusters(16, 9, 24, 64));
			var l = lights(120, 1);
			c.assign(VIEW, l.xs, l.ys, l.zs, l.rs, 120);
			equals(c.overflow, 0);
			var listed = 0, wrong = "";
			for (z in 0...c.slices)
				for (y in 0...c.tilesY)
					for (x in 0...c.tilesX) {
						var want = brute(c, x, y, z, l, 120);
						listed += want.length;
						var got = [for (k in 0...c.count(x, y, z)) c.light(x, y, z, k)];
						if (got.join(",") != want.join(",") && wrong == "") wrong = 'cell $x, $y, $z: [${got.join(",")}], not [${want.join(",")}]';
					}
			equals(wrong, "");
			// (most cells reach some light: the test is not empty)
			assert(listed > 500, '$listed lights listed');
		});
		test("a full cell keeps the first perCell, the others counted", () -> {
			var c = lensed(new Clusters(4, 3, 6, 4));
			var l = lights(60, 2);
			c.assign(VIEW, l.xs, l.ys, l.zs, l.rs, 60);
			var full = 0;
			for (z in 0...c.slices)
				for (y in 0...c.tilesY)
					for (x in 0...c.tilesX) {
						var want = brute(c, x, y, z, l, 60);
						if (want.length > 4) full++;
						equals([for (k in 0...c.count(x, y, z)) c.light(x, y, z, k)].join(","), want.slice(0, 4).join(","));
					}
			assert(full > 0 && c.overflow > 0, '$full full cells, ${c.overflow} left out');
		});
		test("the lights' rows after the cells'", () -> {
			var c = new Clusters(4, 3, 6, 4, 8);
			equals(c.lightRow, 18);
			equals(c.height, 26);
			// (a grid narrower than a light's 12 texels: the map as wide as one)
			equals(new Clusters(1, 1, 1, 2).width, 12);
		});
		test("assign allocates nothing; 256 lights' time", () -> {
			var c = lensed(new Clusters(16, 9, 24, 32));
			var l = lights(256, 3);
			c.assign(VIEW, l.xs, l.ys, l.zs, l.rs, 256);
			#if (target.name == "hxmc")
			var before = hxmc.GcStats.bytesAllocated();
			c.assign(VIEW, l.xs, l.ys, l.zs, l.rs, 256);
			equals(hxmc.GcStats.bytesAllocated() - before, 0.0);
			#end
			var t0 = haxe.Timer.stamp(), runs = 20;
			for (_ in 0...runs)
				c.assign(VIEW, l.xs, l.ys, l.zs, l.rs, 256);
			Sys.println('Clusters: 256 lights over 16x9x24 cells in ${Math.round((haxe.Timer.stamp() - t0) / runs * 1e6) / 1000} ms');
		});
	});
}

// (a camera at (0, 3, 8) looking at the origin, 60 degrees, 16:9, 0.1 to 60 m)
private final VIEW = MathTools.lookAt(new Vec3(0, 3, 8), new Vec3(0, 0, 0), new Vec3(0, 1, 0));

private function lensed(c:Clusters):Clusters {
	c.lens(Mat4.perspective(1.05, 16 / 9, 0.1, 60), 0.1, 60);
	return c;
}

// (n lights scattered in front of the camera and some behind it, ranges 0.5
// to 3 m: a linear congruential sequence from seed)
private function lights(n:Int, seed:Int):{xs:Array<Float>, ys:Array<Float>, zs:Array<Float>, rs:Array<Float>} {
	var s = seed * 7919;
	function next():Float {
		s = (s * 1103515245 + 12345) & 0x7FFFFFFF;
		return s / 0x7FFFFFFF;
	}
	var xs = [], ys = [], zs = [], rs = [];
	for (_ in 0...n) {
		xs.push(next() * 24 - 12);
		ys.push(next() * 4 - 0.5);
		zs.push(next() * 30 - 22);
		rs.push(0.5 + next() * 2.5);
	}
	return {xs: xs, ys: ys, zs: zs, rs: rs};
}

// (the lights that reach cell x, y, z, every one tested, in order)
private function brute(c:Clusters, x:Int, y:Int, z:Int, l:{xs:Array<Float>, ys:Array<Float>, zs:Array<Float>, rs:Array<Float>}, n:Int):Array<Int> {
	var out = [];
	for (k in 0...n) {
		var p = MathTools.transformPoint(VIEW, new Vec3(l.xs[k], l.ys[k], l.zs[k]));
		if (c.reaches(x, y, z, p.x, p.y, p.z, l.rs[k])) out.push(k);
	}
	return out;
}
