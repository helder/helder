package helder.scene.render;

import haxe.io.Bytes;
import helder.gfx.*;
import helder.gfx.shader.Mat4;
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;
import helder.scene.World;
import helder.scene.math.MathTools;

// The point and spot lights' shadows, Shadows' tiles for them, opted in
// (shadows.local({atlas: 1024, maxLocal: 4}); a program that never asks
// links none of it, Little Skies' sun alone): the frame's local lights
// that cast (Light.castShadows), the most important first (the renderer's
// FrameLights), at most maxLocal of them, each given tiles of a square of
// the atlas `atlas` texels wide (made beside the sun's cascades when a
// local light first casts): a spot light one of its cone, a point light six
// (a cube's faces as six frusta: gfx has no cube textures), tileSize texels
// each (a point light's faces half that; light.shadow.size), halved, all of
// them, while they do not fit; the lights past the budget unshadowed that
// frame. Each tile's casters are the ones its frustum meets (their runs of
// one primitive, one instanced draw each); a tile whose light and casters
// stayed put (their signature: what they are and where) is kept from the
// frame before, not drawn again (cached; light.shadow.cached). Their
// filter: a 3x3, or a disc of 12 taps (radius); their bias in metres a
// metre from the light, their normal offset in the tile's texels, both
// growing with the distance as its texels do. Nothing is allocated a frame.
class LocalShadows implements RenderFeature.LocalShadowSource {
	// the local lights' budget: shadowed point and spot lights a frame
	public var maxLocal = 4;
	// a spot light's tile in texels (a point light's faces half of it), a
	// power of two (light.shadow.size: the light's own)
	public var tileSize = 512;
	// the depth offset (metres a metre from the light), the offset along the
	// surface's normal (texels of the tile), the filter's width (texels of
	// the tile; 0: the 3x3 filter), the strength (-1: Shadows.strength):
	// light.shadow's own fields over these
	public var bias = 0.004;
	public var normalBias = 2.0;
	public var radius = 0.0;
	public var strength = -1.0;
	// whether a tile is kept while its light and its casters stay put
	public var cached = true;
	// the square of the atlas, its side in texels
	public final atlas:Int;
	// the last frame's tiles drawn and kept, its shadowed lights
	public var tilesDrawn(default, null) = 0;
	public var tilesKept(default, null) = 0;
	public var lights(default, null) = 0;

	static inline var MAX_TILES = Shadows.MAX_TILES;

	// (this frame's tiles: their light (its row of FrameLights), face, place
	// and size, view-projection, filter; whether kept; the instance runs
	// each draws, tileRun..tileRun + tileRuns of the runs)
	var tileCount = 0;
	final tileLight:Array<Int> = Filled.ints(MAX_TILES, 0);
	final tileFace:Array<Int> = Filled.ints(MAX_TILES, 0);
	final tileX:Array<Int> = Filled.ints(MAX_TILES, 0);
	final tileY:Array<Int> = Filled.ints(MAX_TILES, 0);
	final tileS:Array<Int> = Filled.ints(MAX_TILES, 0);
	final tileViewProj:Array<Mat4> = Filled.mat4s(MAX_TILES);
	final tileParams:Array<Vec4> = Filled.vec4s(MAX_TILES);
	final tileKept:Array<Bool> = Filled.bools(MAX_TILES);
	final tileSig:Array<Float> = Filled.floats(MAX_TILES, 0.0);
	final tileRun:Array<Int> = Filled.ints(MAX_TILES, 0);
	final tileRuns:Array<Int> = Filled.ints(MAX_TILES, 0);
	// (the last frame's, by place: what each drew, from what light, to
	// keep a tile drawn the same again)
	var keptCount = 0;
	final keptLight:Array<Null<Light>> = Filled.lights(MAX_TILES);
	final keptFace:Array<Int> = Filled.ints(MAX_TILES, 0);
	final keptX:Array<Int> = Filled.ints(MAX_TILES, 0);
	final keptY:Array<Int> = Filled.ints(MAX_TILES, 0);
	final keptS:Array<Int> = Filled.ints(MAX_TILES, 0);
	final keptViewProj:Array<Mat4> = Filled.mat4s(MAX_TILES);
	final keptSig:Array<Float> = Filled.floats(MAX_TILES, 0.0);
	// (the runs: a primitive, its first instance's offset in the instance
	// buffer, its instances; the casters a tile sees, every tile's in seenAt)
	final runPrim:Array<Mesh.Primitive> = [];
	final runOffset:Array<Int> = [];
	final runSize:Array<Int> = [];
	var runCount = 0;
	final seen:Array<Int> = [];
	final seenAt:Array<Int> = [];
	final seenBase:Array<Int> = Filled.ints(MAX_TILES, 0);
	// (the lights asking, by their row: the tile size each gets)
	final askLight:Array<Int> = Filled.ints(MAX_TILES, 0);
	final askSize:Array<Int> = Filled.ints(MAX_TILES, 0);
	// (PbrLights' tiles: Shadows.MAX_TILES' matrices and two vectors)
	final tileBytes = Bytes.alloc(MAX_TILES * 96);

	// options: atlas (the square's side, 1024), maxLocal (4), tileSize (512)
	public function new(?options:LocalShadowsOptions) {
		atlas = options != null && options.atlas != null ? options.atlas : 1024;
		if (options != null && options.maxLocal != null) maxLocal = options.maxLocal;
		if (options != null && options.tileSize != null) tileSize = options.tileSize;
	}

	public function kept():Int
		return tilesKept;

	public function tiles():Bytes
		return tileBytes;

	public function forget()
		for (t in 0...keptCount)
			keptLight[t] = null;

	// the frame's casting local lights' tiles: the first maxLocal that ask
	// (in the frame's order), their sizes halved while they do not fit the
	// square, placed in rows; each light's first tile set in fl; each tile's
	// casters, and whether it is kept
	public function place(sh:Shadows, fl:FrameLights, world:World) {
		tileCount = 0;
		tilesKept = 0;
		tilesDrawn = 0;
		lights = 0;
		runCount = 0;
		var asks = 0, tiles = 0;
		for (k in 0...fl.count) {
			fl.setTile(k, -1);
			var light = fl.lights[k];
			if (!light.castShadows || light.area || atlas <= 0 || asks == maxLocal) continue;
			var faces = fl.isPoint(k) ? 6 : 1;
			if (tiles + faces > MAX_TILES) continue;
			var s = light.shadow != null && light.shadow.size != null && light.shadow.size > 0 ? light.shadow.size : faces == 6 ? tileSize >> 1 : tileSize;
			askLight[asks] = k;
			askSize[asks] = s;
			asks++;
			tiles += faces;
		}
		if (asks == 0) {
			keptCount = 0;
			writeTiles(sh);
			return;
		}
		// (the square made on the first local light: the atlas wider)
		var ox = sh.cascades * sh.size;
		if (sh.atlasWidth < ox + atlas) @:privateAccess sh.makeAtlas(ox + atlas, Std.int(Math.max(sh.size, atlas)));
		// (the sizes halved, all of them, while they cover more than the square)
		while (true) {
			var area = 0.0;
			for (a in 0...asks)
				area += askSize[a] * askSize[a] * (fl.isPoint(askLight[a]) ? 6 : 1);
			if (area <= atlas * atlas) break;
			var shrunk = false;
			for (a in 0...asks)
				if (askSize[a] > 64) {
					askSize[a] >>= 1;
					shrunk = true;
				}
			if (!shrunk) break;
		}
		// (rows, the largest tiles first, then the frame's order)
		for (a in 1...asks) {
			var l = askLight[a], s = askSize[a], j = a - 1;
			while (j >= 0 && askSize[j] < s) {
				askLight[j + 1] = askLight[j];
				askSize[j + 1] = askSize[j];
				j--;
			}
			askLight[j + 1] = l;
			askSize[j + 1] = s;
		}
		var x = 0, y = 0, row = 0;
		for (a in 0...asks) {
			var k = askLight[a], s = askSize[a], faces = fl.isPoint(k) ? 6 : 1;
			var first = tileCount;
			var fits = true;
			for (f in 0...faces) {
				if (x + s > atlas) {
					x = 0;
					y += row;
					row = 0;
				}
				if (y + s > atlas) {
					fits = false;
					break;
				}
				var t = tileCount++;
				tileLight[t] = k;
				tileFace[t] = faces == 6 ? f : -1;
				tileX[t] = ox + x;
				tileY[t] = y;
				tileS[t] = s;
				x += s;
				if (s > row) row = s;
			}
			if (!fits) {
				tileCount = first;
				continue;
			}
			fl.setTile(k, first);
			lights++;
			for (t in first...tileCount)
				frustumOf(sh, t, fl, k);
		}
		for (t in 0...tileCount) {
			cull(sh, t, world);
			var light = fl.lights[tileLight[t]];
			var keep = cached && (light.shadow == null || light.shadow.cached != false) && tileSig[t] == tileSig[t];
			if (keep) {
				keep = false;
				for (j in 0...keptCount)
					if (keptLight[j] == light && keptFace[j] == tileFace[t] && keptX[j] == tileX[t] && keptY[j] == tileY[t] && keptS[j] == tileS[t]
						&& keptSig[j] == tileSig[t] && MathTools.near(keptViewProj[j], tileViewProj[t], 0)) {
						keep = true;
						break;
					}
			}
			tileKept[t] = keep;
			if (keep) tilesKept++ else tilesDrawn++;
		}
		keptCount = tileCount;
		for (t in 0...tileCount) {
			keptLight[t] = fl.lights[tileLight[t]];
			keptFace[t] = tileFace[t];
			keptX[t] = tileX[t];
			keptY[t] = tileY[t];
			keptS[t] = tileS[t];
			keptViewProj[t] = tileViewProj[t];
			keptSig[t] = tileSig[t];
		}
		writeTiles(sh);
	}

	// (tile t's view-projection: a spot light's cone, a point light's face;
	// its filter in PbrLights' tileParams)
	function frustumOf(sh:Shadows, t:Int, fl:FrameLights, k:Int) {
		var light = fl.lights[k], node = fl.nodes[k], s = tileS[t];
		var p = new Vec3(fl.x(k), fl.y(k), fl.z(k)), range = fl.range(k);
		var near = Math.min(Math.max(range * 0.005, 0.01), 0.5);
		var fov = 0.0, dir = new Vec3(0, 0, -1), up = new Vec3(0, 1, 0);
		if (tileFace[t] < 0) {
			dir = MathTools.transformDir(node.worldMatrix(), new Vec3(0, 0, -1));
			// (the outer cone and a few texels more, for the filter's taps at its edge)
			fov = Math.min(2 * light.outerCone * (1 + 4 / s), 2.9);
			up = Math.abs(dir.y) > 0.99 * Math.sqrt(dir.x * dir.x + dir.y * dir.y + dir.z * dir.z) ? new Vec3(0, 0, 1) : new Vec3(0, 1, 0);
		} else {
			// (a quarter turn and a few texels: the faces overlap at their edges)
			fov = 2 * Math.atan(1 + 4 / s);
			var f = tileFace[t];
			dir = switch f {
				case 0: new Vec3(1, 0, 0);
				case 1: new Vec3(-1, 0, 0);
				case 2: new Vec3(0, 1, 0);
				case 3: new Vec3(0, -1, 0);
				case 4: new Vec3(0, 0, 1);
				case _: new Vec3(0, 0, -1);
			}
			up = f == 2 || f == 3 ? new Vec3(0, 0, 1) : new Vec3(0, 1, 0);
		}
		tileViewProj[t] = Mat4.perspective(fov, 1, near, range) * MathTools.lookAt(p, p + dir, up);
		var o = light.shadow;
		var b = o != null && o.bias != null ? o.bias : bias;
		var nb = o != null && o.normalBias != null ? o.normalBias : normalBias;
		var r = o != null && o.radius != null ? o.radius : radius;
		var st = o != null && o.strength != null ? o.strength : strength >= 0 ? strength : sh.strength;
		// (the normal offset in metres a metre from the light: texels of the tile's width there)
		tileParams[t] = new Vec4(st, b, nb * 2 * Math.tan(fov / 2) / s, r / s);
	}

	// (tile t's casters: those whose bounds its frustum meets, their runs
	// of one primitive, and their signature: what they are and where, the
	// same while nothing it holds moves; a skinned caster's never)
	@:access(helder.scene.render.Shadows)
	function cull(sh:Shadows, t:Int, world:World) {
		var vp = tileViewProj[t];
		var sig = 0.0;
		tileRun[t] = runCount;
		var seenCount = 0;
		for (i in 0...sh.count)
			if (Shadows.seesBox(vp, sh.casterBox, i)) {
				if (seenCount == seen.length) seen.push(i) else seen[seenCount] = i;
				seenCount++;
				var n = sh.casterNodes[i], m = n.worldMatrix();
				sig += (n.id() + 1) * 0.6180339 + sh.casterPrims[i].id * 0.3711 + m.c3.x * 1.3107 + m.c3.y * 1.7321 + m.c3.z * 2.1131 + m.c0.x * 0.5301
					+ m.c0.y * 0.4113 + m.c0.z * 0.2903 + m.c1.x * 0.6007 + m.c1.y * 0.7103 + m.c1.z * 0.3301 + m.c2.x * 0.4307 + m.c2.y * 0.5507 + m.c2.z * 0.9703;
			}
		// (runs of one primitive: the casters are sorted by it)
		var i = 0;
		while (i < seenCount) {
			var j = i + 1;
			while (j < seenCount && sh.casterPrims[seen[j]] == sh.casterPrims[seen[i]])
				j++;
			if (runCount == runPrim.length) {
				runPrim.push(null);
				runOffset.push(0);
				runSize.push(0);
			}
			runPrim[runCount] = sh.casterPrims[seen[i]];
			// (its first in the tile's seen; its offset in bytes set by layout)
			runOffset[runCount] = i;
			runSize[runCount] = j - i;
			runCount++;
			i = j;
		}
		tileRuns[t] = runCount - tileRun[t];
		// (the seen casters, kept for layout: in seenAt from the tile's base)
		var base = t > 0 ? seenBase[t - 1] + seenOf(t - 1) : 0;
		while (seenAt.length < base + seenCount)
			seenAt.push(0);
		for (k in 0...seenCount)
			seenAt[base + k] = seen[k];
		seenBase[t] = base;
		for (k in 0...sh.skinnedCount)
			if (Shadows.seesBox(vp, sh.skinnedBox, k)) sig = Math.NaN;
		var sets = world.store(InstancedMesh.KIND);
		for (k in 0...sets.length) {
			var n = sets.nodeAt(k), s = sets.valueAt(k);
			if (!n.shown() || !world.inTree(n) || s.count == 0 || !s.castShadows) continue;
			sig += (n.id() + 1) * 0.917 + s.version * 1.618 + s.count * 0.123;
		}
		tileSig[t] = sig;
	}

	// (the casters tile t sees: its runs' instances)
	function seenOf(t:Int):Int {
		var n = 0;
		for (r in tileRun[t]...tileRun[t] + tileRuns[t])
			n += runSize[r];
		return n;
	}

	public function instances():Int {
		var n = 0;
		for (t in 0...tileCount)
			if (!tileKept[t]) n += seenOf(t);
		return n;
	}

	// the casters' matrices of each tile drawn, into the shadows' instance
	// bytes from at (their runs' offsets set); returns the end
	@:access(helder.scene.render.Shadows)
	public function layout(sh:Shadows, at:Int):Int {
		var bytes = at;
		for (t in 0...tileCount) {
			if (tileKept[t]) continue;
			var base = seenBase[t];
			for (r in tileRun[t]...tileRun[t] + tileRuns[t]) {
				var first = runOffset[r];
				runOffset[r] = bytes;
				for (k in 0...runSize[r])
					bytes = sh.matrix(sh.casterNodes[seenAt[base + first + k]], bytes);
			}
		}
		return bytes;
	}

	// each tile not kept drawn (the atlas' pass begun; clear: the others kept)
	@:access(helder.scene.render.Shadows)
	public function draw(enc:Encoder, sh:Shadows, world:World, skins:Null<RenderFeature.SkinSource>, clear:Bool) {
		for (t in 0...tileCount) {
			if (tileKept[t]) continue;
			var vp = tileViewProj[t];
			sh.beginTile(enc, vp, tileX[t], tileY[t], tileS[t], clear);
			for (r in tileRun[t]...tileRun[t] + tileRuns[t]) {
				var p = runPrim[r];
				enc.setVertexBuffer(0, p.vertices);
				enc.setVertexBuffer(1, sh.instanceBuffer, runOffset[r]);
				enc.setIndexBuffer(p.indices, p.indexFormat);
				enc.drawIndexed(p.count, runSize[r]);
				sh.draws++;
			}
			sh.finishTile(enc, world, skins, vp, true);
		}
	}

	// (PbrLights' tiles: each tile's view-projection, its place in the atlas, its filter)
	function writeTiles(sh:Shadows) {
		var b = tileBytes;
		for (t in 0...MAX_TILES) {
			var on = t < tileCount;
			var m = on ? tileViewProj[t] : Mat4.identity();
			for (c in 0...4) {
				var col = MathTools.col(m, c);
				b.setFloat(t * 64 + c * 16, on ? col.x : 0);
				b.setFloat(t * 64 + c * 16 + 4, on ? col.y : 0);
				b.setFloat(t * 64 + c * 16 + 8, on ? col.z : 0);
				b.setFloat(t * 64 + c * 16 + 12, on ? col.w : 0);
			}
			var r = MAX_TILES * 64 + t * 16, q = MAX_TILES * 80 + t * 16;
			b.setFloat(r, on ? tileX[t] / sh.atlasWidth : 0);
			b.setFloat(r + 4, on ? tileY[t] / sh.atlasHeight : 0);
			b.setFloat(r + 8, on ? tileS[t] / sh.atlasWidth : 0);
			b.setFloat(r + 12, on ? tileS[t] / sh.atlasHeight : 0);
			var p = tileParams[t];
			b.setFloat(q, on ? p.x : 0);
			b.setFloat(q + 4, on ? p.y : 0);
			b.setFloat(q + 8, on ? p.z : 0);
			b.setFloat(q + 12, on ? p.w : 0);
		}
	}
}

// LocalShadows' options (shadows.local(options))
typedef LocalShadowsOptions = {
	// the local lights' square of the atlas: its side in texels (1024)
	?atlas:Int,
	// shadowed point and spot lights a frame (4)
	?maxLocal:Int,
	// a spot light's tile in texels (512; a point light's faces half)
	?tileSize:Int
}
