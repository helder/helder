package helder.scene.render;

import haxe.io.Bytes;
import helder.gfx.*;
import helder.math.Mat4;
import helder.math.Vec3;
import helder.math.Vec4;
import helder.scene.Node;
import helder.scene.World;
import helder.scene.math.Aabb;
import helder.scene.math.MathTools;
import helder.scene.render.ShadowShader;
import helder.scene.render.ShadowInstancedShader;
import helder.scene.render.LocalShadows.LocalShadowsOptions;

// The shadow system, opted in (renderer.use(new Shadows(device))): one
// atlas (an R32F texture, each texel a depth from its light, and its depth
// buffer) holding, as tiles, the sun's cascades and, opted in, the point
// and spot lights' shadows, drawn before the frame's pass and read by the
// standard material.
//
//   the sun     the world's first directional light that casts
//               (Light.castShadows, a directional light's default; the
//               renderer's sun without lights): one cascade of size x size
//               fitted to the casters' bounds, or two (Shadows.cascaded,
//               whose fitting code a program without it does not link):
//               the first fitted to the camera's view up to split metres
//               (its bounding sphere, moved by whole texels: steady as the
//               camera moves), sharp near the camera, the second the whole
//               scene's, read beyond the first; a 3x3 percentage-closer
//               filter or a soft one (soft: a disc of taps, a blocker
//               search, sharper where the shadow meets its caster)
//   local       shadows.local({atlas, maxLocal, tileSize}): the point and
//               spot lights that cast, their tiles in a square of the atlas
//               beside the cascades (LocalShadows: a spot light's one, a
//               point light's six, a budget, kept while nothing moves); a
//               program that never asks links none of it
//
// The casters: every shown mesh whose material casts (Material.castShadows,
// InstancedMesh.castShadows), a primitive's in one instanced draw a tile
// (their matrices in an instance buffer written once for every tile), a
// local tile's culled by its frustum, each tile's draws kept to its
// rectangle (ShadowShader). Nothing is allocated a frame. A program that
// never makes a Shadows links none of this but the material's lookup of a
// 1x1 map that shadows nothing.
class Shadows implements RenderFeature implements RenderFeature.ShadowSource {
	public final device:Device;
	// a cascade's tile, in texels
	public final size:Int;
	// 1, or 2 (Shadows.cascaded)
	public var cascades(default, null) = 1;
	// how far from the camera the first of two cascades reaches (metres)
	public var split = 10.0;
	// the sun's depth offset against shadow acne (in the whole scene's map's
	// 0..1 depth; the first of two cascades', as many of its texels)
	public var bias = 0.004;
	// the shadows' strength, 0 (none) to 1 (no direct light at all)
	public var strength = 0.85;
	// the sun's soft filter (soft): the widest penumbra's radius in metres
	// (0: the 3x3 filter), its taps a point (8 for phones, 16, 32), and how
	// much the penumbra widens a metre from its caster (0: the radius
	// everywhere, no blocker search)
	public var softRadius = 0.0;
	public var softSamples = 16;
	public var softSpread = 0.0;
	// the point and spot lights' shadows (local: null without)
	public var locals(default, null):Null<LocalShadows> = null;
	// the atlas (made again, wider, when a local light first casts) and its size
	public var atlas(default, null):Texture;
	public var atlasWidth(default, null) = 0;
	public var atlasHeight(default, null) = 0;
	// the last frame's draws into the atlas (every tile's: a primitive's
	// casters one instanced draw a tile, a skinned caster one draw)
	public var draws(default, null) = 0;
	// the last frame's sun's view-projections (the first cascade's, the second's)
	public var viewProj(default, null):Mat4 = Mat4.identity();
	public var viewProjFar(default, null):Mat4 = Mat4.identity();

	var depth:Texture;
	final pipeline:Pipeline;
	final clearPipeline:Pipeline;
	final corners:Buffer;
	final casterBytes = Bytes.alloc(ShadowShader.uniforms[0].size);
	// (the block as written, kept: a struct literal per write would allocate)
	final casterBlock:ShadowCaster = {mvp: Mat4.identity(), rect: new Vec4(-1, -1, 1, 1)};
	final pass:PassDesc;
	// (the first of two cascades' bias in its depth)
	var nearBias = 0.004;
	// (the frame's casters, count of them in use, sorted by primitive, each
	// one's bounds in the world (six numbers); the skinned ones and their
	// meshes, drawn alone; the runs of one primitive)
	final casterNodes:Array<Node> = [];
	final casterPrims:Array<Mesh.Primitive> = [];
	final casterBox:Array<Float> = [];
	var count = 0;
	final skinned:Array<Node> = [];
	final skinnedMeshes:Array<Mesh> = [];
	final skinnedBox:Array<Float> = [];
	var skinnedCount = 0;
	final batchStart:Array<Int> = [];
	final batchSize:Array<Int> = [];
	var batchCount = 0;
	var instanceBytes = Bytes.alloc(64 * 64);
	var instanceBuffer:Buffer = Buffer.NONE;
	var instanceCapacity = 0;
	// (the last frame's maps' width and depth in metres: the first's, the second's)
	var nearWidth = 1.0;
	var nearRange = 1.0;
	var farWidth = 1.0;
	var farRange = 1.0;
	// (two cascades: the first's fitting, set by cascaded)
	var fit:Null<(Renderer.FrameInfo, Vec3, Vec3, Vec3, Float) -> Mat4>;
	// (whether the sun casts this frame)
	var sunCasts = true;
	// (the local lights' tiles, reached through what the renderer core
	// reaches: LocalShadows linked only by local)
	var localSource:Null<RenderFeature.LocalShadowSource> = null;

	// one cascade of size texels
	public function new(device:Device, size = 1024) {
		this.device = device;
		this.size = size;
		var d = ShadowInstancedShader.pipeline({cull: None, depthCompare: Less, depthWrite: true});
		d.colorFormat = R32F;
		d.depthFormat = Depth32F;
		d.layout = @:privateAccess Renderer.INSTANCED_LAYOUT;
		pipeline = device.createPipeline(d);
		var c = ShadowClearShader.pipeline({cull: None, depthCompare: Always, depthWrite: true});
		c.colorFormat = R32F;
		c.depthFormat = Depth32F;
		clearPipeline = device.createPipeline(c);
		var q = Bytes.alloc(6 * 8);
		var k = 0;
		for (v in [0.0, 0, 1, 0, 0, 1, 1, 0, 1, 1, 0, 1]) {
			q.setFloat(k, v);
			k += 4;
		}
		corners = device.createBuffer({size: q.length, usage: Vertex, data: q});
		pass = {colors: [{load: Clear, clear: new Vec4(1, 1, 1, 1)}], depth: {load: Clear}};
		atlas = cast 0;
		depth = cast 0;
		makeAtlas(size, size);
	}

	// two cascades, the first reaching split metres from the camera
	public static function cascaded(device:Device, size = 1024, split = 10.0):Shadows {
		var s = new Shadows(device, size);
		s.cascades = 2;
		s.split = split;
		s.fit = s.fitNear;
		s.makeAtlas(2 * size, size);
		return s;
	}

	// (the atlas at width x height, the tiles in it forgotten)
	function makeAtlas(width:Int, height:Int) {
		if (atlasWidth > 0) {
			device.destroyTexture(atlas);
			device.destroyTexture(depth);
		}
		atlasWidth = width;
		atlasHeight = height;
		atlas = device.createTexture({width: width, height: height, format: R32F, renderTarget: true});
		depth = device.createTexture({width: width, height: height, format: Depth32F});
		pass.colors[0].texture = atlas;
		pass.depth.texture = depth;
		if (localSource != null) localSource.forget();
	}

	// the point and spot lights' shadows on (returns the shadows): their
	// tiles in a square of the atlas atlas texels wide (1024), at most
	// maxLocal lights a frame (4), a spot light's tile tileSize texels (512;
	// a point light's faces half); the lights that cast, Light.castShadows
	public function local(?options:LocalShadowsOptions):Shadows {
		var l = new LocalShadows(options);
		locals = l;
		localSource = l;
		return this;
	}

	// the sun's soft filter on (returns the shadows): taps on a disc out to
	// radius metres, samples a point (8: phones; 16; 32), and with a spread
	// a blocker search first, the penumbra growing by spread a metre from
	// its caster up to the radius (contact hardening: PCSS); spread 0, the
	// radius everywhere
	public function soft(radius = 0.1, samples = 16, spread = 0.05):Shadows {
		softRadius = radius;
		softSamples = samples;
		softSpread = spread;
		return this;
	}

	public function attach(renderer:Renderer)
		@:privateAccess renderer.shadowSource = this;

	final frame = new RenderFeature.ShadowFrame();

	@:noCompletion public function shadowFrame():RenderFeature.ShadowFrame {
		frame.map = atlas;
		frame.viewProj = viewProj;
		var on = softRadius > 0 && softSamples > 0;
		var s = sunCasts ? strength : 0;
		frame.params = new Vec4(s, cascades == 2 ? nearBias : bias, 1 / size, on ? softRadius / nearWidth : 0);
		frame.viewProjFar = viewProjFar;
		frame.paramsFar = cascades == 2 ? new Vec4(s, bias, 1 / size, on ? softRadius / farWidth : 0) : frame.params;
		frame.soft = on ? new Vec4(softSamples, nearWidth / nearRange, farWidth / farRange, softSpread) : new Vec4(0, 0, 0, 0);
		frame.rect = new Vec4(0, 0, size / atlasWidth, size / atlasHeight);
		frame.rectFar = cascades == 2 ? new Vec4(size / atlasWidth, 0, size / atlasWidth, size / atlasHeight) : frame.rect;
		frame.atlas = new Vec4(1 / atlasWidth, 1 / atlasHeight, 0, 0);
		frame.tiles = localSource != null ? localSource.tiles() : null;
		frame.draws = draws;
		return frame;
	}

	// the atlas' pass: the sun's cascades (along -toLight) fitted to the
	// casters and the view, the frame's local lights' tiles (the
	// renderer's FrameLights, each one's first tile set there)
	@:noCompletion public function render(enc:Encoder, renderer:Renderer, toLight:Vec3, view:Renderer.FrameInfo) {
		var world = view.world;
		var skins = @:privateAccess renderer.skinSource;
		var meshes = world.store(MeshRenderer.KIND);
		// (the casters' bounds as numbers: an Aabb a caster would allocate)
		bx0 = by0 = bz0 = Math.POSITIVE_INFINITY;
		bx1 = by1 = bz1 = Math.NEGATIVE_INFINITY;
		count = 0;
		skinnedCount = 0;
		for (k in 0...meshes.length) {
			var n = meshes.nodeAt(k), mesh = meshes.valueAt(k);
			if (!n.shown() || !world.inTree(n) || !casts(mesh)) continue;
			var m = n.worldMatrix();
			box(mesh.bounds, m);
			grow();
			// (the casters: a skinned node drawn alone, else each casting primitive)
			if (mesh.primitives[0].skinned) {
				if (skinnedCount == skinned.length) {
					skinned.push(n);
					skinnedMeshes.push(mesh);
					for (_ in 0...6)
						skinnedBox.push(0);
				} else {
					skinned[skinnedCount] = n;
					skinnedMeshes[skinnedCount] = mesh;
				}
				keepBox(skinnedBox, skinnedCount);
				skinnedCount++;
				continue;
			}
			for (p in mesh.primitives) {
				if (!p.material.castShadows) continue;
				if (count == casterNodes.length) {
					casterNodes.push(n);
					casterPrims.push(p);
					for (_ in 0...6)
						casterBox.push(0);
				} else {
					casterNodes[count] = n;
					casterPrims[count] = p;
				}
				keepBox(casterBox, count);
				count++;
			}
		}
		sort();
		// (instanced sets: their bounds when the program gave them)
		var sets = world.store(InstancedMesh.KIND);
		for (k in 0...sets.length) {
			var n = sets.nodeAt(k), s = sets.valueAt(k);
			if (n.shown() && world.inTree(n) && s.count > 0 && s.castShadows && casts(s.mesh) && !s.bounds.isEmpty()) {
				var b = s.bounds;
				bx0 = Math.min(bx0, b.min.x);
				by0 = Math.min(by0, b.min.y);
				bz0 = Math.min(bz0, b.min.z);
				bx1 = Math.max(bx1, b.max.x);
				by1 = Math.max(by1, b.max.y);
				bz1 = Math.max(bz1, b.max.z);
			}
		}
		if (bx0 > bx1 || by0 > by1 || bz0 > bz1) {
			bx0 = by0 = bz0 = -1;
			bx1 = by1 = bz1 = 1;
		}
		var c = new Vec3((bx0 + bx1) * 0.5, (by0 + by1) * 0.5, (bz0 + bz1) * 0.5), e = new Vec3(bx1 - bx0, by1 - by0, bz1 - bz0);
		var r = Math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z) / 2 + 0.01;
		// (up: any direction not along the light's)
		var up = Math.abs(toLight.y) > 0.99 ? new Vec3(0, 0, 1) : new Vec3(0, 1, 0);
		var whole = Mat4.orthographic(-r, r, -r, r, r * 0.5, r * 3.5) * MathTools.lookAt(c + toLight * (2 * r), c, up);
		draws = 0;
		// (each map's width and depth in metres: the soft filter's radius in its uv, its slopes)
		farWidth = nearWidth = 2 * r;
		farRange = nearRange = 3 * r;
		sunCasts = sunCasting(world);
		if (fit == null || view.camera == null) viewProj = viewProjFar = whole else {
			viewProjFar = whole;
			viewProj = fit(view, toLight, up, c, r);
		}
		// (the local lights' tiles, which they keep, and what each draws)
		if (localSource != null) localSource.place(this, renderer.frameLights, world);
		// (the instance buffer: the sun's casters, then each local tile drawn's)
		layout();
		var keep = localSource != null && localSource.kept() > 0;
		pass.colors[0].load = keep ? Load : Clear;
		pass.depth.load = keep ? Load : Clear;
		enc.beginPass(pass);
		if (sunCasts) {
			sunTile(enc, world, skins, viewProj, 0, keep);
			if (cascades == 2) sunTile(enc, world, skins, viewProjFar, size, keep);
		}
		if (localSource != null) localSource.draw(enc, this, world, skins, keep);
		enc.endPass();
	}

	// (whether the frame's sun casts: the world's first directional light's
	// castShadows; the renderer's sun's in a world without lights; none in
	// a world of other lights alone, which has no sun)
	static function sunCasting(world:World):Bool {
		var lights = world.store(Light.KIND);
		for (k in 0...lights.length) {
			var n = lights.nodeAt(k), l = lights.valueAt(k);
			if (l.kind == Directional && n.shown() && world.inTree(n)) return l.castShadows;
		}
		return lights.length == 0;
	}

	// the first cascade: the bounding sphere of the camera's view from its
	// near plane to split, as deep towards the light as the scene (its
	// sphere: centre c, radius r)
	function fitNear(view:Renderer.FrameInfo, toLight:Vec3, up:Vec3, c:Vec3, r:Float):Mat4 {
		var cam = view.camera, inv = MathTools.inverse(view.viewProj);
		var f = Math.min(Math.max((split - cam.near) / (cam.far - cam.near), 0), 1);
		// (the eight corners as numbers, kept: an array of Vec3s would box them)
		for (k in 0...4) {
			var x = (k & 1) == 0 ? -1.0 : 1.0, y = (k & 2) == 0 ? -1.0 : 1.0;
			var a = MathTools.transformPoint(inv, new Vec3(x, y, 0)), b = MathTools.transformPoint(inv, new Vec3(x, y, 1));
			// (along the corner's edge: linear in the view's depth)
			var q = a + (b - a) * f;
			cornerX[2 * k] = a.x;
			cornerY[2 * k] = a.y;
			cornerZ[2 * k] = a.z;
			cornerX[2 * k + 1] = q.x;
			cornerY[2 * k + 1] = q.y;
			cornerZ[2 * k + 1] = q.z;
		}
		var sx = 0.0, sy = 0.0, sz = 0.0;
		for (k in 0...8) {
			sx += cornerX[k];
			sy += cornerY[k];
			sz += cornerZ[k];
		}
		var centre = new Vec3(sx / 8, sy / 8, sz / 8);
		var radius = 0.0;
		for (k in 0...8) {
			var dx = cornerX[k] - centre.x, dy = cornerY[k] - centre.y, dz = cornerZ[k] - centre.z;
			radius = Math.max(radius, Math.sqrt(dx * dx + dy * dy + dz * dz));
		}
		radius += 0.01;
		// (the centre moved by whole texels in the light's view: shadows do not crawl)
		var lightView = MathTools.lookAt(new Vec3(0, 0, 0), toLight * -1, up);
		var lc = MathTools.transformPoint(lightView, centre), texel = 2 * radius / size;
		lc = new Vec3(Math.floor(lc.x / texel) * texel, Math.floor(lc.y / texel) * texel, lc.z);
		var snapped = MathTools.transformPoint(MathTools.inverse(lightView), lc);
		// (back towards the light past every caster: the scene's sphere)
		var toCentre = c - snapped, back = Math.sqrt(toCentre.x * toCentre.x + toCentre.y * toCentre.y + toCentre.z * toCentre.z) + r;
		// (the bias: as many of this map's texels as the whole map's, in its depth)
		nearBias = bias * (3 * r / (back + radius + r)) * (radius / r);
		nearWidth = 2 * radius;
		nearRange = back + radius + r - 0.01;
		return Mat4.orthographic(-radius, radius, -radius, radius, 0.01, back + radius + r) * MathTools.lookAt(snapped + toLight * back, snapped, up);
	}

	// the local lights' tiles a frame at most (the frame's lights' texture's tile rows)
	public static inline var MAX_TILES = 12;

	// whether a frustum (vp) meets a caster's bounds in the world (boxes: six numbers each)
	@:allow(helder.scene.render) static function seesBox(vp:Mat4, boxes:Array<Float>, i:Int):Bool {
		var o = i * 6;
		var o0 = 0, o1 = 0, o2 = 0, o3 = 0, o4 = 0, o5 = 0;
		for (k in 0...8) {
			var c = vp * new Vec4((k & 1) == 0 ? boxes[o] : boxes[o + 3], (k & 2) == 0 ? boxes[o + 1] : boxes[o + 4], (k & 4) == 0 ? boxes[o + 2] : boxes[o + 5], 1);
			if (c.x < -c.w) o0++;
			if (c.x > c.w) o1++;
			if (c.y < -c.w) o2++;
			if (c.y > c.w) o3++;
			if (c.z < 0) o4++;
			if (c.z > c.w) o5++;
		}
		return o0 < 8 && o1 < 8 && o2 < 8 && o3 < 8 && o4 < 8 && o5 < 8;
	}

	// ---- the casters and their draws

	// (a mesh's box through its node's matrix: Aabb.transform's, Arvo's, as
	// numbers, into tx0..tz1)
	var tx0 = 0.0;
	var ty0 = 0.0;
	var tz0 = 0.0;
	var tx1 = 0.0;
	var ty1 = 0.0;
	var tz1 = 0.0;

	function box(b:Aabb, m:Mat4) {
		if (b.isEmpty()) {
			tx0 = ty0 = tz0 = Math.POSITIVE_INFINITY;
			tx1 = ty1 = tz1 = Math.NEGATIVE_INFINITY;
			return;
		}
		var cx = (b.min.x + b.max.x) * 0.5, cy = (b.min.y + b.max.y) * 0.5, cz = (b.min.z + b.max.z) * 0.5;
		var hx = (b.max.x - b.min.x) * 0.5, hy = (b.max.y - b.min.y) * 0.5, hz = (b.max.z - b.min.z) * 0.5;
		var tc = m * new Vec4(cx, cy, cz, 1);
		var ex = Math.abs(m.c0.x) * hx + Math.abs(m.c1.x) * hy + Math.abs(m.c2.x) * hz;
		var ey = Math.abs(m.c0.y) * hx + Math.abs(m.c1.y) * hy + Math.abs(m.c2.y) * hz;
		var ez = Math.abs(m.c0.z) * hx + Math.abs(m.c1.z) * hy + Math.abs(m.c2.z) * hz;
		tx0 = tc.x - ex;
		ty0 = tc.y - ey;
		tz0 = tc.z - ez;
		tx1 = tc.x + ex;
		ty1 = tc.y + ey;
		tz1 = tc.z + ez;
	}

	// (the casters' bounds grown by the last box)
	var bx0 = 0.0;
	var by0 = 0.0;
	var bz0 = 0.0;
	var bx1 = 0.0;
	var by1 = 0.0;
	var bz1 = 0.0;

	inline function grow() {
		if (tx0 > tx1) return;
		bx0 = Math.min(bx0, tx0);
		by0 = Math.min(by0, ty0);
		bz0 = Math.min(bz0, tz0);
		bx1 = Math.max(bx1, tx1);
		by1 = Math.max(by1, ty1);
		bz1 = Math.max(bz1, tz1);
	}

	inline function keepBox(boxes:Array<Float>, i:Int) {
		boxes[i * 6] = tx0;
		boxes[i * 6 + 1] = ty0;
		boxes[i * 6 + 2] = tz0;
		boxes[i * 6 + 3] = tx1;
		boxes[i * 6 + 4] = ty1;
		boxes[i * 6 + 5] = tz1;
	}

	final cornerX:Array<Float> = Filled.floats(8, 0.0);
	final cornerY:Array<Float> = Filled.floats(8, 0.0);
	final cornerZ:Array<Float> = Filled.floats(8, 0.0);

	static function casts(m:Mesh):Bool {
		for (p in m.primitives)
			if (p.material.castShadows) return true;
		return false;
	}

	// the casters sorted by primitive (insertion sort: a scene's order
	// changes little from frame to frame), their boxes with them; cut into
	// the sun's runs of one primitive
	function sort() {
		for (i in 1...count) {
			var n = casterNodes[i], p = casterPrims[i], j = i - 1;
			var b0 = casterBox[i * 6], b1 = casterBox[i * 6 + 1], b2 = casterBox[i * 6 + 2], b3 = casterBox[i * 6 + 3], b4 = casterBox[i * 6 + 4],
				b5 = casterBox[i * 6 + 5];
			while (j >= 0 && casterPrims[j].id > p.id) {
				casterNodes[j + 1] = casterNodes[j];
				casterPrims[j + 1] = casterPrims[j];
				for (f in 0...6)
					casterBox[(j + 1) * 6 + f] = casterBox[j * 6 + f];
				j--;
			}
			casterNodes[j + 1] = n;
			casterPrims[j + 1] = p;
			casterBox[(j + 1) * 6] = b0;
			casterBox[(j + 1) * 6 + 1] = b1;
			casterBox[(j + 1) * 6 + 2] = b2;
			casterBox[(j + 1) * 6 + 3] = b3;
			casterBox[(j + 1) * 6 + 4] = b4;
			casterBox[(j + 1) * 6 + 5] = b5;
		}
		batchCount = 0;
		var i = 0;
		while (i < count) {
			var j = i + 1;
			while (j < count && casterPrims[j] == casterPrims[i])
				j++;
			if (batchCount == batchStart.length) {
				batchStart.push(0);
				batchSize.push(0);
			}
			batchStart[batchCount] = i;
			batchSize[batchCount] = j - i;
			batchCount++;
			i = j;
		}
	}

	// the instance buffer: every caster's matrix (the sun's runs), then the
	// casters of each local tile drawn (LocalShadows.layout), written before
	// the pass
	function layout() {
		var total = count + (localSource != null ? localSource.instances() : 0);
		if (total * 64 > instanceBytes.length) instanceBytes = Bytes.alloc(Std.int(Math.max(instanceBytes.length * 2, total * 64)));
		var bytes = 0;
		for (k in 0...count)
			bytes = matrix(casterNodes[k], bytes);
		if (localSource != null) bytes = localSource.layout(this, bytes);
		if (bytes > 0) {
			if (bytes > instanceCapacity) {
				if (instanceCapacity > 0) device.destroyBuffer(instanceBuffer);
				instanceCapacity = instanceBytes.length;
				instanceBuffer = device.createBuffer({size: instanceCapacity, usage: Vertex});
			}
			device.writeBuffer(instanceBuffer, 0, instanceBytes, 0, bytes);
		}
	}

	function matrix(n:Node, bytes:Int):Int {
		var m = n.worldMatrix();
		for (c in 0...4) {
			var col = MathTools.col(m, c);
			instanceBytes.setFloat(bytes, col.x);
			instanceBytes.setFloat(bytes + 4, col.y);
			instanceBytes.setFloat(bytes + 8, col.z);
			instanceBytes.setFloat(bytes + 12, c == 3 ? 1 : 0);
			bytes += 16;
		}
		return bytes;
	}

	// a cascade's tile (at x, size texels) drawn from the sun's view-projection: every caster
	function sunTile(enc:Encoder, world:World, skins:Null<RenderFeature.SkinSource>, vp:Mat4, x:Int, clear:Bool) {
		beginTile(enc, vp, x, 0, size, clear);
		for (b in 0...batchCount) {
			var p = casterPrims[batchStart[b]];
			enc.setVertexBuffer(0, p.vertices);
			enc.setVertexBuffer(1, instanceBuffer, batchStart[b] * 64);
			enc.setIndexBuffer(p.indices, p.indexFormat);
			enc.drawIndexed(p.count, batchSize[b]);
			draws++;
		}
		finishTile(enc, world, skins, vp, false);
	}

	// a tile of the atlas (x, y, s: its texels) begun from a light's
	// view-projection: cleared first when other tiles are kept, the
	// casters' pipeline and block bound (the light's view mapped into the
	// tile, its rectangle the casters' draws are kept to)
	@:allow(helder.scene.render) function beginTile(enc:Encoder, vp:Mat4, x:Int, y:Int, s:Int, clear:Bool) {
		// (the tile in the atlas' clip space: its rectangle, and the light's
		// view mapped into it; y up, the atlas' first row its top)
		var x0 = 2 * x / atlasWidth - 1, x1 = 2 * (x + s) / atlasWidth - 1;
		var y1 = 1 - 2 * y / atlasHeight, y0 = 1 - 2 * (y + s) / atlasHeight;
		var into = new Mat4(new Vec4(s / atlasWidth, 0, 0, 0), new Vec4(0, s / atlasHeight, 0, 0), new Vec4(0, 0, 1, 0), new Vec4((x0 + x1) / 2, (y0 + y1) / 2, 0, 1));
		tileMvp = into * vp;
		casterBlock.rect = new Vec4(x0, y0, x1, y1);
		casterBlock.mvp = tileMvp;
		ShadowShader.params.caster.write(casterBlock, casterBytes);
		if (clear) {
			enc.setPipeline(clearPipeline);
			enc.setUniforms(ShadowClearShader.uniforms[0].binding, casterBytes);
			enc.setVertexBuffer(0, corners);
			enc.draw(6);
		}
		enc.setPipeline(pipeline);
		enc.setUniforms(ShadowInstancedShader.uniforms[0].binding, casterBytes);
	}

	// (the tile begun's view mapped into it)
	var tileMvp:Mat4 = Mat4.identity();

	// the tile begun finished: the instanced sets and the skinned casters
	// (culled: those its frustum meets)
	@:allow(helder.scene.render) function finishTile(enc:Encoder, world:World, skins:Null<RenderFeature.SkinSource>, vp:Mat4, culled:Bool) {
		drawSets(enc, world, vp);
		// (a skinned mesh: drawn by the skinning's shadow pipeline, its joints bound)
		if (skins != null && skinnedCount > 0) {
			var bound = false;
			for (k in 0...skinnedCount) {
				if (culled && !seesBox(vp, skinnedBox, k)) continue;
				var slots = skins.shadowSlots();
				if (!bound) {
					enc.setPipeline(skins.shadowPipeline());
					slots = skins.shadowSlots();
					bound = true;
				}
				var n = skinned[k];
				casterBlock.mvp = tileMvp * n.worldMatrix();
				ShadowShader.params.caster.write(casterBlock, casterBytes);
				enc.setUniforms(slots[0], casterBytes);
				skins.bind(enc, slots, n);
				for (p in skinnedMeshes[k].primitives) {
					if (!p.material.castShadows) continue;
					enc.setVertexBuffer(0, p.vertices);
					enc.setIndexBuffer(p.indices, p.indexFormat);
					enc.drawIndexed(p.count);
					draws++;
				}
			}
		}
	}

	// the instanced sets that cast and that the frustum vp meets (by their
	// bounds, when given), each primitive one instanced draw (the casters'
	// pipeline and block bound)
	function drawSets(enc:Encoder, world:World, vp:Mat4) {
		var sets = world.store(InstancedMesh.KIND);
		for (k in 0...sets.length) {
			var n = sets.nodeAt(k), s = sets.valueAt(k);
			if (!n.shown() || !world.inTree(n) || s.count == 0 || !s.castShadows || s.buffer == Buffer.NONE) continue;
			if (!s.bounds.isEmpty() && !@:privateAccess Renderer.visibleBox(vp, s.bounds)) continue;
			for (p in s.mesh.primitives) {
				if (!p.material.castShadows || p.skinned) continue;
				enc.setVertexBuffer(0, p.vertices);
				enc.setVertexBuffer(1, s.buffer);
				enc.setIndexBuffer(p.indices, p.indexFormat);
				enc.drawIndexed(p.count, s.count);
				draws++;
			}
		}
	}

	public function dispose() {
		if (instanceCapacity > 0) device.destroyBuffer(instanceBuffer);
		instanceCapacity = 0;
		device.destroyTexture(atlas);
		device.destroyTexture(depth);
		device.destroyBuffer(corners);
		atlasWidth = 0;
	}
}
