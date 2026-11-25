package helder.gfx.soft;

import helder.gfx.shader.Vec4;

import haxe.io.Bytes;
import helder.os.Blit;
import helder.os.Surface;
import hxmc.I64;
import hxmc.unsafe.BytesPtr;
import hxmc.unsafe.LibC;
import hxmc.unsafe.Mem;
import hxmc.unsafe.Ptr;

// helder.gfx on the CPU (Backend.Soft, -D helder.soft): the device's API
// over memory outside the collector's heap, the shaders' CPU forms
// (helder.gfx.shader.Soft: each stage over 4 lanes, a quad of pixels a
// call) shading it. A draw runs its vertex stage at once, 4 vertices a
// call, clips its triangles in clip space (near and far, and a guard band
// that keeps their fixed point exact), sets them up (fixed point, 8 bits
// under the pixel; the planes of their depth, 1/w and varyings) and bins
// them into the pass's 32x32 tiles; the pass's end shades its tiles in
// parallel (helder.jobs.Parallel: HELDER_SOFT_THREADS caps the threads,
// 1 none beside the caller's), each in the order its triangles came
// (Raster), then resolves a multisampled target. Uniform blocks are copied
// when set and textures bound by their records, so later changes do not
// reach draws already made. A window's frame is shown by the system's own
// path (helder.os.Blit), where it changed. Compute stages run on the
// calling thread, 4 invocations a call (their CPU form's lanes). No shared
// textures.
@:hxmc.unsafe(gc)
class SoftBackend {
	public final backend = Backend.Soft;
	public var width(default, null) = 0;
	public var height(default, null) = 0;

	static final BLACK = new Vec4(0, 0, 0, 1);

	final surface:Surface;
	final threads:Int;
	// resources by id (from 1)
	final buffers:Array<Ptr> = [];
	final bufferSizes:Array<Int> = [];
	final textures:Array<Ptr> = [];
	final samplers:Array<Int> = [];
	final shaders:Array<Null<{entry:Ptr, varyings:Int, stage:Stage, size:Array<Int>, workgroup:Int, frame:Int}>> = [];
	final pipelines:Array<SoftPipeline> = [];
	final queries:Array<Ptr> = [];
	final queryCounts:Array<Int> = [];
	// the frame's targets (or frameInto's texture)
	var frameColor = Ptr.nil();
	var frameDepth = Ptr.nil();
	var frameTarget = 0;
	var damage:Null<Array<Int>> = null;
	final damageRects:Array<Int> = [];
	// what is bound
	var pipeline:Null<SoftPipeline> = null;
	final vertexBuffers:Array<Ptr> = [for (_ in 0...8) Ptr.nil()];
	final vertexSizes:Array<Int> = [for (_ in 0...8) 0];
	var indexBuffer = Ptr.nil();
	var indexSize = 0;
	var indexOffset = 0;
	var index32 = false;
	final bound:Ptr;
	final boundSizes = [for (_ in 0...16) 0];
	var passQueries = 0;
	var query = Ptr.nil();
	// the pass
	final pass:Ptr;
	final memory = new Chunks();
	var inPass = false;
	var bins = Ptr.nil();
	var binsSize = 0;
	var resolveFrom = Ptr.nil();
	var resolveTo = Ptr.nil();
	// the vertex stage's lanes and its vertices
	final vin:Ptr;
	final vout:Ptr;
	var verts = Ptr.nil();
	var vertsSize = 0;
	final clip:Ptr;
	// the compute tier's: pipelines, the one set, its context, ids and storage bindings
	final computes:Array<{entry:Ptr, size:Array<Int>, workgroup:Int, frame:Int}> = [];
	var computing:Null<{entry:Ptr, size:Array<Int>, workgroup:Int, frame:Int}> = null;
	final cctx:Ptr;
	final cin:Ptr;
	// (a workgroup's memory, its calls' frames: grown to the largest pipeline's)
	var shared = Ptr.nil();
	var sharedSize = 0;
	final storage:Ptr;

	public function new(surface:Surface, antialias:Bool) {
		this.surface = surface;
		var env = Sys.getEnv("HELDER_SOFT_THREADS"), n = env == null ? -1 : Std.parseInt(env);
		threads = n == null ? -1 : n - 1;
		bound = LibC.malloc(256);
		LibC.memset(bound, 0, 256);
		pass = LibC.malloc(Raster.PASS);
		LibC.memset(pass, 0, Raster.PASS);
		vin = LibC.malloc(16 * 64);
		vout = LibC.malloc(64 + 16 * Abi.MAX_VARYINGS);
		clip = LibC.malloc(2 * 16 * 4 * (4 + Abi.MAX_VARYINGS) + 3 * 4 * (4 + Abi.MAX_VARYINGS));
		cctx = LibC.malloc(Abi.COMPUTE_SIZE);
		LibC.memset(cctx, 0, Abi.COMPUTE_SIZE);
		cin = LibC.malloc(16 * 14);
		storage = LibC.malloc(Buffers.SIZE * 16);
		LibC.memset(storage, 0, Buffers.SIZE * 16);
		resize(surface.width, surface.height);
	}

	function resize(w:Int, h:Int) {
		if (w == width && h == height && !frameColor.isNull()) return;
		if (!frameColor.isNull()) {
			SoftTexture.free(frameColor);
			SoftTexture.free(frameDepth);
		}
		width = w > 0 ? w : 1;
		height = h > 0 ? h : 1;
		frameColor = SoftTexture.make({width: width, height: height, renderTarget: true});
		frameDepth = SoftTexture.make({width: width, height: height, format: Depth32F});
	}

	// ---- resources

	static function put<T>(a:Array<T>, v:T):Int {
		for (i in 0...a.length)
			if (a[i] == null) {
				a[i] = v;
				return i + 1;
			}
		a.push(v);
		return a.length;
	}

	public function createBuffer(d:BufferDesc):Int {
		var size = d.size, data = d.data;
		var p:Ptr = LibC.malloc(((size > 0 ? size : 16) : I64));
		if (p.isNull()) throw "helder.gfx: out of memory for a buffer of " + size + " bytes";
		LibC.memset(p, 0, (size : I64));
		if (data != null) copy(p, data, 0, size);
		var id = putPtr(buffers, p);
		while (bufferSizes.length < id)
			bufferSizes.push(0);
		bufferSizes[id - 1] = d.size;
		return id;
	}

	static function putPtr(a:Array<Ptr>, v:Ptr):Int {
		for (i in 0...a.length)
			if (a[i].isNull()) {
				a[i] = v;
				return i + 1;
			}
		a.push(v);
		return a.length;
	}

	// (n bytes of b from pos to p)
	static function copy(p:Ptr, b:Bytes, pos:Int, n:Int)
		LibC.memcpy(p, BytesPtr.of(b, pos, n), (n : I64));

	inline function buffer(id:Int):Ptr
		return id <= 0 || id > buffers.length ? Ptr.nil() : buffers[id - 1];

	public function writeBuffer(id:Int, offset:Int, data:Bytes, dataOffset:Int, size:Int) {
		var p = buffer(id);
		if (p.isNull()) throw "helder.gfx: writeBuffer: no buffer " + id;
		if (offset + size > bufferSizes[id - 1]) throw "helder.gfx: writeBuffer: past the buffer's end";
		copy(p.add(offset), data, dataOffset, size);
	}

	public function readBuffer(id:Int, offset:Int, dst:Bytes, dstOffset:Int, size:Int) {
		var p = buffer(id);
		if (p.isNull()) throw "helder.gfx: readBuffer: no buffer " + id;
		BytesPtr.copyIn(dst, dstOffset, p.add(offset), size);
	}

	public function destroyBuffer(id:Int) {
		var p = buffer(id);
		if (p.isNull()) return;
		LibC.free(p);
		buffers[id - 1] = Ptr.nil();
	}

	public function createTexture(d:TextureDesc):Int {
		TextureInfo.of(d);
		var r = SoftTexture.make(d);
		if (d.data != null) {
			var format:TextureFormat = d.format == null ? RGBA8 : d.format, layers = Mem.getI32(r, SoftTexture.LAYERS);
			var n = format.levelBytes(d.width, d.height);
			for (l in 0...layers)
				if ((l + 1) * n <= d.data.length) SoftTexture.write(r, d.data, l * n, 0, 0, d.width, d.height, 0, l);
		}
		return putPtr(textures, r);
	}

	inline function texture(id:Int):Ptr
		return id <= 0 || id > textures.length ? Ptr.nil() : textures[id - 1];

	public function writeTexture(id:Int, data:Bytes, x:Int, y:Int, w:Int, h:Int, dataOffset:Int, level:Int, layer:Int) {
		var r = texture(id);
		if (r.isNull()) throw "helder.gfx: writeTexture: no texture " + id;
		if (w < 0) w = SoftTexture.width(r, level);
		if (h < 0) h = SoftTexture.height(r, level);
		SoftTexture.write(r, data, dataOffset, x, y, w, h, level, layer);
	}

	public function supports(f:TextureFormat):Bool
		return true;

	public function maxTextureSize():Int
		return 16384;

	public function generateMips(id:Int) {
		var r = texture(id);
		if (!r.isNull()) SoftTexture.mips(r);
	}

	public function destroyTexture(id:Int) {
		var r = texture(id);
		if (r.isNull()) return;
		SoftTexture.free(r);
		textures[id - 1] = Ptr.nil();
	}

	public function createSampler(d:SamplerDesc):Int {
		var filter = d.filter == null || d.filter == Linear ? 1 : 0, mip = d.mipFilter == null ? 0 : d.mipFilter == Linear ? 2 : 1;
		var wrap = d.wrap == null ? 0 : (cast d.wrap : Int);
		samplers.push(filter | (mip << 4) | (wrap << 8));
		return samplers.length;
	}

	public function createShader(d:ShaderDesc):Int {
		var s = d.code.soft;
		shaders.push(s == null ? null : {
			entry: Ptr.ofI64(s.entry),
			varyings: s.varyings,
			stage: d.stage,
			size: d.code.workgroupSize,
			workgroup: s.workgroup ?? 0,
			frame: s.frame ?? 0
		});
		return shaders.length;
	}

	public function createPipeline(d:PipelineDesc):Int {
		var vs = d.vertex == null ? null : shaders[d.vertex.id() - 1], fs = d.fragment == null ? null : shaders[d.fragment.id() - 1];
		if (vs != null && vs.varyings > Abi.MAX_VARYINGS) throw "helder.gfx: a shader of more than " + Abi.MAX_VARYINGS + " varying components";
		pipelines.push(new SoftPipeline(vs == null ? Ptr.nil() : vs.entry, fs == null ? Ptr.nil() : fs.entry, vs == null ? 0 : vs.varyings, d));
		return pipelines.length;
	}

	// ---- queries

	public function createQueries(count:Int):Int {
		var p:Ptr = LibC.malloc(4 * count);
		for (k in 0...count)
			Mem.setI32(p, 4 * k, -1);
		queryCounts.push(count);
		return putPtr(queries, p);
	}

	public function destroyQueries(id:Int) {
		if (id <= 0 || id > queries.length || queries[id - 1].isNull()) return;
		LibC.free(queries[id - 1]);
		queries[id - 1] = Ptr.nil();
	}

	public function queryResult(id:Int, k:Int):Int {
		if (id <= 0 || id > queries.length || queries[id - 1].isNull() || k < 0 || k >= queryCounts[id - 1]) return -1;
		return Mem.getI32(queries[id - 1], 4 * k);
	}

	public function resetQuery(id:Int, k:Int)
		if (id > 0 && id <= queries.length && !queries[id - 1].isNull() && k >= 0 && k < queryCounts[id - 1]) Mem.setI32(queries[id - 1], 4 * k, -1);

	public function beginQuery(k:Int) {
		var q = passQueries <= 0 || passQueries > queries.length ? Ptr.nil() : queries[passQueries - 1];
		if (q.isNull() || k < 0 || k >= queryCounts[passQueries - 1]) return;
		query = q.add(4 * k);
		// (its answer once the pass's tiles ran: 0 unless a sample passed)
		Mem.setI32(query, 0, 0);
	}

	public function endQuery()
		query = Ptr.nil();

	// ---- frames and passes

	public function beginFrame():Bool {
		if (frameTarget != 0) {
			var r = texture(frameTarget);
			width = Mem.getI32(r, SoftTexture.WIDTH);
			height = Mem.getI32(r, SoftTexture.HEIGHT);
			return true;
		}
		resize(surface.width, surface.height);
		return true;
	}

	public function frameInto(id:Int) {
		frameTarget = id;
		if (id == 0) {
			width = Mem.getI32(frameColor, SoftTexture.WIDTH);
			height = Mem.getI32(frameColor, SoftTexture.HEIGHT);
		}
	}

	public function beginPass(p:PassDesc) {
		if (inPass) endPass();
		passQueries = p.queries == null ? 0 : p.queries.id();
		var c = p.colors[0], d = p.depth;
		var target = c.texture != null ? texture(c.texture.id()) : frameTarget != 0 ? texture(frameTarget) : frameColor;
		if (target.isNull()) throw "helder.gfx: beginPass: no such texture";
		var depth = c.texture == null && frameTarget == 0 ? frameDepth : d != null && d.texture != null ? texture(d.texture.id()) : Ptr.nil();
		var layer = c.layer == null ? 0 : c.layer, w = Mem.getI32(target, SoftTexture.WIDTH), h = Mem.getI32(target, SoftTexture.HEIGHT);
		var samples = Mem.getI32(target, SoftTexture.SAMPLES);
		if (!depth.isNull() && (Mem.getI32(depth, SoftTexture.WIDTH) != w || Mem.getI32(depth, SoftTexture.HEIGHT) != h))
			throw "helder.gfx: beginPass: the depth texture is not of the colour target's size";
		var color = SoftTexture.at(target, 0, layer);
		Mem.setPtr(pass, Raster.COLOR, color);
		Mem.setPtr(pass, Raster.DEPTH, depth.isNull() ? Ptr.nil() : SoftTexture.at(depth, 0, 0));
		Mem.setI32(pass, Raster.W, w);
		Mem.setI32(pass, Raster.H, h);
		var tx = (w + Raster.TILE - 1) >> Raster.SHIFT, ty = (h + Raster.TILE - 1) >> Raster.SHIFT;
		Mem.setI32(pass, Raster.TILES_X, tx);
		Mem.setI32(pass, Raster.TILES_Y, ty);
		Mem.setI32(pass, Raster.KIND, Mem.getI32(target, SoftTexture.KIND));
		Mem.setI32(pass, Raster.FORMAT, Mem.getI32(target, SoftTexture.FORMAT));
		Mem.setI32(pass, Raster.SAMPLES, samples);
		Mem.setI32(pass, Raster.DEPTH16, !depth.isNull() && Mem.getI32(depth, SoftTexture.FORMAT) == (cast TextureFormat.Depth16 : Int) ? 1 : 0);
		Mem.setPtr(pass, Raster.TABLE, Formats.srgb());
		var n = tx * ty * Raster.BIN;
		if (binsSize < n) {
			LibC.free(bins);
			bins = LibC.malloc(n);
			binsSize = n;
		}
		LibC.memset(bins, 0, n);
		Mem.setPtr(pass, Raster.BINS, bins);
		rebase();
		resolveFrom = samples > 1 && c.resolve != null ? target : Ptr.nil();
		resolveTo = c.resolve == null ? Ptr.nil() : texture(c.resolve.id());
		// the clears
		// the clears: the tiles' first work (all of them run at the pass's end)
		var clears = 0;
		if (c.load != Load) {
			clearTexel(target, c.clear ?? BLACK);
			clears |= 1;
		}
		if (!depth.isNull() && d != null && d.load != Load) {
			var z:Float = d.clear == null ? 1 : d.clear;
			if (Mem.getI32(depth, SoftTexture.FORMAT) == (cast TextureFormat.Depth16 : Int)) z = Math.fround(z * 65535) / 65535;
			Mem.setF32(pass, Raster.CLEAR_DEPTH, z);
			clears |= 2;
		}
		Mem.setI32(pass, Raster.CLEAR, clears);
		pipeline = null;
		inPass = true;
	}

	// (a clear colour as the target stores it, into the pass's record)
	function clearTexel(r:Ptr, k:Vec4) {
		var kind = Mem.getI32(r, SoftTexture.KIND), format:TextureFormat = cast Mem.getI32(r, SoftTexture.FORMAT), p = pass.add(Raster.CLEAR_TEXEL);
		inline function c01(v:Float):Float
			return v < 0 ? 0 : v > 1 ? 1 : v;
		if (kind == SoftTexture.U8) {
			var t = Formats.srgb(), srgb = format == RGBA8Srgb;
			inline function code(v:Float, color:Bool):Int
				return srgb && color ? Formats.srgbCode(t, c01(v)) : Std.int(c01(v) * 255 + 0.5);
			var g = format == R8 ? 0.0 : k.y, b = format == R8 || format == RG8 ? 0.0 : k.z, a = format == R8 || format == RG8 ? 1.0 : k.w;
			Mem.setI32(p, 0, code(k.x, true) | (code(g, true) << 8) | (code(b, true) << 16) | (code(a, false) << 24));
		} else if (kind == SoftTexture.F4) {
			var half = format == RGBA16F;
			inline function v(x:Float):Float
				return half ? Formats.roundHalf(x) : x;
			Mem.setF32(p, 0, v(k.x));
			Mem.setF32(p, 4, v(k.y));
			Mem.setF32(p, 8, v(k.z));
			Mem.setF32(p, 12, v(k.w));
		} else
			Mem.setF32(p, 0, k.x);
	}

	public function setPipeline(id:Int)
		pipeline = id <= 0 || id > pipelines.length ? null : pipelines[id - 1];

	public function setVertexBuffer(slot:Int, id:Int, offset:Int) {
		if (slot < 0 || slot >= 8) return;
		var p = buffer(id);
		vertexBuffers[slot] = p.isNull() ? p : p.add(offset);
		vertexSizes[slot] = p.isNull() ? 0 : bufferSizes[id - 1] - offset;
	}

	public function setIndexBuffer(id:Int, format:IndexFormat, offset:Int) {
		indexBuffer = buffer(id);
		indexSize = indexBuffer.isNull() ? 0 : bufferSizes[id - 1];
		indexOffset = offset;
		index32 = format == UInt32;
	}

	// (a copy: the draws made before the pass's end read the bytes as they were)
	public function setUniforms(slot:Int, data:Bytes, offset:Int, size:Int) {
		if (slot < 0 || slot >= 16) return;
		var p = memory.alloc(size > 0 ? size : 16);
		copy(p, data, offset, size);
		Mem.setPtr(bound, 8 * slot, p);
		boundSizes[slot] = size;
	}

	public function setTexture(slot:Int, texture:Int, sampler:Int) {
		if (slot < 0 || slot >= 16) return;
		var b = memory.alloc(Sample.SIZE), s = sampler <= 0 || sampler > samplers.length ? 1 : samplers[sampler - 1];
		Mem.setPtr(b, Sample.TEXTURE, this.texture(texture));
		Mem.setI32(b, Sample.FILTER, s & 15);
		Mem.setI32(b, Sample.MIP, ((s >> 4) & 15) - 1);
		Mem.setI32(b, Sample.WRAP, (s >> 8) & 15);
		Mem.setPtr(bound, 128 + 8 * slot, b);
	}

	// the draw's record: its fragment stage, state and bindings as they are now
	function drawRecord(p:SoftPipeline):Ptr {
		var d = memory.alloc(Raster.DRAW);
		Mem.setPtr(d, Raster.D_FS, p.fs);
		Mem.setI32(d, Raster.D_N, p.varyings);
		Mem.setI32(d, Raster.D_BLEND, p.blend);
		Mem.setI32(d, Raster.D_COMPARE, p.compare);
		Mem.setI32(d, Raster.D_WRITE, p.write ? 1 : 0);
		Mem.setPtr(d, Raster.D_QUERY, query);
		LibC.memcpy(d.add(Raster.D_BINDINGS), bound, 256);
		return d;
	}

	public function draw(vertices:Int, instances:Int, first:Int)
		run(vertices, instances, first, 0, false, 0);

	public function drawIndexed(count:Int, instances:Int, first:Int, baseVertex:Int)
		run(count, instances, first, baseVertex, true, 0);

	public function drawIndirect(id:Int, offset:Int) {
		var p = buffer(id);
		if (p.isNull()) return;
		run(Mem.getI32(p, offset), Mem.getI32(p, offset + 4), Mem.getI32(p, offset + 8), 0, false, Mem.getI32(p, offset + 12));
	}

	public function drawIndexedIndirect(id:Int, offset:Int) {
		var p = buffer(id);
		if (p.isNull()) return;
		run(Mem.getI32(p, offset), Mem.getI32(p, offset + 4), Mem.getI32(p, offset + 8), Mem.getI32(p, offset + 12), true, Mem.getI32(p, offset + 16));
	}

	inline function indexAt(i:Int):Int {
		var at = indexOffset + (index32 ? 4 : 2) * i;
		return at + (index32 ? 4 : 2) > indexSize ? 0 : index32 ? Mem.getI32(indexBuffer, at) : Mem.getU16(indexBuffer, at);
	}

	function run(count:Int, instances:Int, first:Int, baseVertex:Int, indexed:Bool, firstInstance:Int) {
		var p = pipeline;
		if (!inPass || p == null || p.vs.isNull() || p.fs.isNull() || count <= 0 || instances <= 0) return;
		if (indexed && indexBuffer.isNull()) return;
		var lo = first, hi = first + count - 1;
		if (indexed) {
			lo = 0x7FFFFFFF;
			hi = -1;
			for (i in first...first + count) {
				var v = indexAt(i) + baseVertex;
				if (v < lo) lo = v;
				if (v > hi) hi = v;
			}
		}
		var d = drawRecord(p), stride = 4 + p.varyings, n = hi - lo + 1;
		if (vertsSize < n * stride * 4) {
			LibC.free(verts);
			vertsSize = n * stride * 4 + 4096;
			verts = LibC.malloc(vertsSize);
		}
		for (inst in firstInstance...firstInstance + instances) {
			shade(p, lo, n, inst);
			inline function vertex(i:Int):Ptr
				return verts.add(4 * stride * ((indexed ? indexAt(i) + baseVertex : i) - lo));
			switch p.topology {
				case TriangleStrip:
					for (t in 0...count - 2) {
						var i = first + t;
						if (t & 1 == 0) triangle(d, p, vertex(i), vertex(i + 1), vertex(i + 2)) else triangle(d, p, vertex(i + 1), vertex(i), vertex(i + 2));
					}
				case Lines:
					var t = 0;
					while (t + 1 < count) {
						line(d, p, vertex(first + t), vertex(first + t + 1));
						t += 2;
					}
				case Points:
					for (t in 0...count)
						line(d, p, vertex(first + t), vertex(first + t));
				case _:
					var t = 0;
					while (t + 2 < count) {
						triangle(d, p, vertex(first + t), vertex(first + t + 1), vertex(first + t + 2));
						t += 3;
					}
			}
			// (a pass of many triangles: its tiles shaded now, the memory let go)
			if (memory.used > 256 * 1024 * 1024) flush();
		}
	}

	// the vertex stage of vertices lo ... lo + n - 1 of an instance into verts, 4 a call
	function shade(p:SoftPipeline, lo:Int, n:Int, instance:Int) {
		var stride = 4 + p.varyings, c = Mem.stack(Abi.SIZE);
		LibC.memcpy(c.add(Abi.UNIFORMS), bound, 256);
		Mem.setPtr(c, Abi.IN, vin);
		Mem.setPtr(c, Abi.OUT, vout);
		var v = 0;
		while (v < n) {
			var lanes = n - v < 4 ? n - v : 4;
			for (a in p.attributes) {
				var slot = a.slot, buf = vertexBuffers[slot], size = vertexSizes[slot], st = p.strides[slot];
				var at = vin.add(64 * a.location);
				for (l in 0...4) {
					var index = p.instanced[slot] ? instance : lo + v + (l < lanes ? l : 0);
					var o = index * st + a.offset;
					for (k in 0...4) {
						var x = k == 3 ? 1.0 : 0.0;
						if (k < a.components && !buf.isNull() && o + 4 * k + (a.bytes ? 1 : 4) <= size)
							x = a.bytes ? Mem.getU8(buf, o + k) / 255 : (Mem.getF32(buf, o + 4 * k) : Float);
						Mem.setF32(at, 16 * k + 4 * l, x);
					}
				}
			}
			Mem.setI32(c, Abi.MASK, (1 << lanes) - 1);
			Raster.Fragment.call(p.vs, c);
			for (l in 0...lanes) {
				var o = verts.add(4 * stride * (v + l));
				for (k in 0...stride)
					Mem.setF32(o, 4 * k, Mem.getF32(vout, 16 * k + 4 * l));
			}
			v += 4;
		}
	}

	// ---- clipping and triangle setup

	// (the clip space's planes a vertex is inside of: near, far, and the guard band's four)
	inline function outcode(v:Ptr, g:Float):Int {
		var x:Float = Mem.getF32(v, 0), y:Float = Mem.getF32(v, 4), z:Float = Mem.getF32(v, 8), w:Float = Mem.getF32(v, 12);
		return (z < 0 ? 1 : 0) | (z > w ? 2 : 0) | (x > g * w ? 4 : 0) | (x < -g * w ? 8 : 0) | (y > g * w ? 16 : 0) | (y < -g * w ? 32 : 0)
			| (w <= 1e-30 ? 64 : 0);
	}

	// (the guard band: past it, triangles are clipped so that their fixed point stays within 2^15 pixels)
	inline function guard():Float {
		var w = Mem.getI32(pass, Raster.W), h = Mem.getI32(pass, Raster.H), m = w > h ? w : h;
		return (16384.0 - m) / m;
	}

	inline function plane(v:Ptr, k:Int, g:Float):Float {
		var x:Float = Mem.getF32(v, 0), y:Float = Mem.getF32(v, 4), z:Float = Mem.getF32(v, 8), w:Float = Mem.getF32(v, 12);
		return switch k {
			case 0: z;
			case 1: w - z;
			case 2: g * w - x;
			case 3: g * w + x;
			case 4: g * w - y;
			case 5: g * w + y;
			case _: w - 1e-30;
		}
	}

	function triangle(d:Ptr, p:SoftPipeline, a:Ptr, b:Ptr, c:Ptr) {
		var g = guard();
		var oa = outcode(a, g), ob = outcode(b, g), oc = outcode(c, g);
		if (oa & ob & oc != 0) return;
		if (oa | ob | oc == 0) {
			setup(d, p, a, b, c);
			return;
		}
		// (Sutherland-Hodgman over the planes crossed, then a fan)
		var stride = 4 + p.varyings, size = 4 * stride;
		var src = clip, dst = clip.add(16 * size), n = 3;
		LibC.memcpy(src, a, size);
		LibC.memcpy(src.add(size), b, size);
		LibC.memcpy(src.add(2 * size), c, size);
		var crossed = oa | ob | oc;
		for (k in 0...7) {
			if (crossed & (1 << k) == 0) continue;
			var m = 0;
			for (i in 0...n) {
				var u = src.add(size * i), v = src.add(size * ((i + 1) % n));
				var du = plane(u, k, g), dv = plane(v, k, g);
				if (du >= 0) {
					LibC.memcpy(dst.add(size * m++), u, size);
				}
				if ((du >= 0) != (dv >= 0) && m < 16) {
					var t = du / (du - dv), o = dst.add(size * m++);
					for (j in 0...stride) {
						var x:Float = Mem.getF32(u, 4 * j);
						Mem.setF32(o, 4 * j, x + ((Mem.getF32(v, 4 * j) : Float) - x) * t);
					}
				}
			}
			n = m;
			var t = src;
			src = dst;
			dst = t;
			if (n < 3) return;
		}
		for (i in 1...n - 1)
			setup(d, p, src, src.add(size * i), src.add(size * (i + 1)));
	}

	// a line (or a point: a == b) as a quad of a pixel's width in the target
	function line(d:Ptr, p:SoftPipeline, a:Ptr, b:Ptr) {
		var w = Mem.getI32(pass, Raster.W), h = Mem.getI32(pass, Raster.H);
		var aw:Float = Mem.getF32(a, 12), bw:Float = Mem.getF32(b, 12);
		if (aw <= 0 || bw <= 0) return;
		var ax = (Mem.getF32(a, 0) : Float) / aw * w * 0.5, ay = (Mem.getF32(a, 4) : Float) / aw * h * 0.5;
		var bx = (Mem.getF32(b, 0) : Float) / bw * w * 0.5, by = (Mem.getF32(b, 4) : Float) / bw * h * 0.5;
		var dx = bx - ax, dy = by - ay, l = Math.sqrt(dx * dx + dy * dy);
		var nx = 0.0, ny = 0.5, tx = 0.0, ty = 0.0;
		if (l > 1e-9) {
			nx = -dy / l * 0.5;
			ny = dx / l * 0.5;
		} else {
			nx = 0.5;
			ny = 0;
			tx = 0;
			ty = 0.5;
		}
		var stride = 4 + p.varyings, size = 4 * stride, q = clip.add(32 * size);
		inline function corner(i:Int, v:Ptr, vw:Float, sx:Float, sy:Float) {
			var o = q.add(size * i);
			LibC.memcpy(o, v, size);
			Mem.setF32(o, 0, (Mem.getF32(v, 0) : Float) + sx / (w * 0.5) * vw);
			Mem.setF32(o, 4, (Mem.getF32(v, 4) : Float) + sy / (h * 0.5) * vw);
		}
		corner(0, a, aw, nx - tx, ny - ty);
		corner(1, a, aw, -nx - tx, -ny - ty);
		corner(2, b, bw, nx + tx, ny + ty);
		corner(3, b, bw, -nx + tx, -ny + ty);
		var cull = p.cull;
		p.cull = 0;
		triangle(d, p, q, q.add(size), q.add(2 * size));
		triangle(d, p, q.add(size), q.add(3 * size), q.add(2 * size));
		p.cull = cull;
	}

	function setup(d:Ptr, p:SoftPipeline, a:Ptr, b:Ptr, c:Ptr) {
		var w = Mem.getI32(pass, Raster.W), h = Mem.getI32(pass, Raster.H);
		inline function iw(v:Ptr):Float
			return 1 / (Mem.getF32(v, 12) : Float);
		inline function sx(v:Ptr):Float
			return Math.fround(((Mem.getF32(v, 0) : Float) * iw(v) + 1) * 0.5 * w * 256);
		inline function sy(v:Ptr):Float
			return Math.fround((1 - (Mem.getF32(v, 4) : Float) * iw(v)) * 0.5 * h * 256);
		var x0 = sx(a), y0 = sy(a), x1 = sx(b), y1 = sy(b), x2 = sx(c), y2 = sy(c);
		var area = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0);
		if (area == 0) return;
		// (counter-clockwise in clip space, y up: negative here, y down)
		var front = area < 0;
		if ((p.cull == 2 && !front) || (p.cull == 1 && front)) return;
		if (area < 0) {
			var t = b;
			b = c;
			c = t;
			var tx = x1, ty = y1;
			x1 = x2;
			y1 = y2;
			x2 = tx;
			y2 = ty;
			area = -area;
		}
		var minX = Math.min(x0, Math.min(x1, x2)), maxX = Math.max(x0, Math.max(x1, x2)), minY = Math.min(y0, Math.min(y1, y2)), maxY = Math.max(y0, Math.max(y1, y2));
		var px0 = Std.int(Math.max(0, Math.floor(minX / 256))), py0 = Std.int(Math.max(0, Math.floor(minY / 256)));
		var px1 = Std.int(Math.min(w, Math.floor(maxX / 256) + 1)), py1 = Std.int(Math.min(h, Math.floor(maxY / 256) + 1));
		if (px0 >= px1 || py0 >= py1) return;
		var n = p.varyings, t = memory.alloc(Raster.T_V + 12 * n);
		Mem.setPtr(t, Raster.T_DRAW, d);
		// the edges opposite each vertex: e0 (1 to 2), e1 (2 to 0), e2 (0 to 1);
		// a pixel on an edge is covered only on a top or left one (C less 1 on the others)
		inline function edge(k:Int, xi:Float, yi:Float, xj:Float, yj:Float) {
			var A = yi - yj, B = xj - xi, C = -(A * xi + B * yi);
			var topLeft = (yj == yi && xj > xi) || yj < yi;
			Mem.setF64(t, Raster.T_EDGES + 24 * k, A);
			Mem.setF64(t, Raster.T_EDGES + 24 * k + 8, B);
			Mem.setF64(t, Raster.T_EDGES + 24 * k + 16, topLeft ? C : C - 1);
		}
		edge(0, x1, y1, x2, y2);
		edge(1, x2, y2, x0, y0);
		edge(2, x0, y0, x1, y1);
		var A1 = y2 - y0, B1 = x0 - x2, C1 = -(A1 * x2 + B1 * y2);
		var A2 = y0 - y1, B2 = x1 - x0, C2 = -(A2 * x0 + B2 * y0);
		Mem.setI32(t, Raster.T_X0, px0);
		Mem.setI32(t, Raster.T_Y0, py0);
		Mem.setI32(t, Raster.T_X1, px1);
		Mem.setI32(t, Raster.T_Y1, py1);
		// (the barycentrics' planes over the pixels from px0, py0: lambda1, lambda2)
		var X = 256.0 * px0 + 128, Y = 256.0 * py0 + 128;
		var a1 = 256 * A1 / area, b1 = 256 * B1 / area, c1 = (A1 * X + B1 * Y + C1) / area;
		var a2 = 256 * A2 / area, b2 = 256 * B2 / area, c2 = (A2 * X + B2 * Y + C2) / area;
		inline function plane(at:Int, f0:Float, f1:Float, f2:Float) {
			var d1 = f1 - f0, d2 = f2 - f0;
			Mem.setF32(t, at, d1 * a1 + d2 * a2);
			Mem.setF32(t, at + 4, d1 * b1 + d2 * b2);
			Mem.setF32(t, at + 8, f0 + d1 * c1 + d2 * c2);
		}
		var wa = iw(a), wb = iw(b), wc = iw(c);
		plane(Raster.T_Z, (Mem.getF32(a, 8) : Float) * wa, (Mem.getF32(b, 8) : Float) * wb, (Mem.getF32(c, 8) : Float) * wc);
		plane(Raster.T_W, wa, wb, wc);
		for (k in 0...n)
			plane(Raster.T_V + 12 * k, (Mem.getF32(a, 16 + 4 * k) : Float) * wa, (Mem.getF32(b, 16 + 4 * k) : Float) * wb, (Mem.getF32(c, 16 + 4 * k) : Float) * wc);
		// into the tiles its pixels' bounds meet
		var tx = Mem.getI32(pass, Raster.TILES_X);
		for (ty in (py0 >> Raster.SHIFT)...((py1 - 1) >> Raster.SHIFT) + 1)
			for (tx0 in (px0 >> Raster.SHIFT)...((px1 - 1) >> Raster.SHIFT) + 1)
				bin(bins.add(Raster.BIN * (ty * tx + tx0)), t);
	}

	function bin(b:Ptr, t:Ptr) {
		var last = Mem.getPtr(b, Raster.LAST), count = Mem.getI32(b, Raster.COUNT);
		if (last.isNull() || count == Raster.ENTRIES) {
			var c = memory.alloc(Raster.CHUNK);
			Mem.setPtr(c, 0, Ptr.nil());
			if (last.isNull()) Mem.setPtr(b, Raster.FIRST, c) else Mem.setPtr(last, 0, c);
			Mem.setPtr(b, Raster.LAST, c);
			last = c;
			count = 0;
		}
		Mem.setPtr(last, 8 + 8 * count, t);
		Mem.setI32(b, Raster.COUNT, count + 1);
	}

	// the pass's tiles shaded, their bins emptied
	function flush() {
		var n = Mem.getI32(pass, Raster.TILES_X) * Mem.getI32(pass, Raster.TILES_Y);
		helder.jobs.Parallel.run(TileCall.address(), pass, n, threads);
		LibC.memset(bins, 0, n * Raster.BIN);
		Mem.setI32(pass, Raster.CLEAR, 0);
		rebase();
	}

	// the pass's memory let go, the blocks and bindings bound copied into it again
	function rebase() {
		var keep = LibC.malloc(256);
		LibC.memcpy(keep, bound, 256);
		var most = 16;
		for (k in boundSizes)
			if (k > most) most = k;
		var blocks = LibC.malloc(16 * most);
		for (s in 0...16) {
			var u = Mem.getPtr(keep, 8 * s);
			if (!u.isNull()) LibC.memcpy(blocks.add(most * s), u, (boundSizes[s] : I64));
		}
		memory.reset();
		for (s in 0...16) {
			var u = Mem.getPtr(keep, 8 * s);
			if (u.isNull()) continue;
			var p = memory.alloc(boundSizes[s] > 0 ? boundSizes[s] : 16);
			LibC.memcpy(p, blocks.add(most * s), (boundSizes[s] : I64));
			Mem.setPtr(bound, 8 * s, p);
		}
		LibC.free(blocks);
		var samplers = LibC.malloc(16 * Sample.SIZE);
		for (s in 0...16) {
			var b = Mem.getPtr(keep, 128 + 8 * s);
			if (!b.isNull()) LibC.memcpy(samplers.add(Sample.SIZE * s), b, Sample.SIZE);
		}
		for (s in 0...16) {
			if (Mem.getPtr(keep, 128 + 8 * s).isNull()) continue;
			var p = memory.alloc(Sample.SIZE);
			LibC.memcpy(p, samplers.add(Sample.SIZE * s), Sample.SIZE);
			Mem.setPtr(bound, 128 + 8 * s, p);
		}
		LibC.free(samplers);
		LibC.free(keep);
	}

	public function endPass() {
		if (!inPass) return;
		inPass = false;
		var n = Mem.getI32(pass, Raster.TILES_X) * Mem.getI32(pass, Raster.TILES_Y);
		helder.jobs.Parallel.run(TileCall.address(), pass, n, threads);
		if (!resolveFrom.isNull() && !resolveTo.isNull()) resolve(resolveFrom, resolveTo);
		resolveFrom = resolveTo = Ptr.nil();
		passQueries = 0;
		query = Ptr.nil();
	}

	// a multisampled target's samples averaged into its resolve texture
	function resolve(from:Ptr, to:Ptr) {
		var w = Mem.getI32(from, SoftTexture.WIDTH), h = Mem.getI32(from, SoftTexture.HEIGHT), s = Mem.getI32(from, SoftTexture.SAMPLES);
		var kind = Mem.getI32(from, SoftTexture.KIND), srgb = Mem.getI32(from, SoftTexture.SRGB) != 0, t = Formats.srgb();
		var src = SoftTexture.at(from, 0, 0), dst = SoftTexture.at(to, 0, 0);
		var half = Mem.getI32(from, SoftTexture.FORMAT) == (cast TextureFormat.RGBA16F : Int);
		for (i in 0...w * h) {
			if (kind == SoftTexture.U8) {
				var out = 0;
				for (c in 0...4) {
					var sum = 0.0;
					for (k in 0...s) {
						var b = Mem.getU8(src, 4 * (s * i + k) + c);
						sum += srgb && c < 3 ? (Mem.getF32(t, 4 * b) : Float) : b / 255;
					}
					var avg = sum / s;
					out |= (srgb && c < 3 ? Formats.srgbCode(t, avg) : Std.int(avg * 255 + 0.5)) << (8 * c);
				}
				Mem.setI32(dst, 4 * i, out);
			} else {
				var n = kind == SoftTexture.F4 ? 4 : 1;
				for (c in 0...n) {
					var sum = 0.0;
					for (k in 0...s)
						sum += Mem.getF32(src, 4 * (n * (s * i + k) + c));
					var avg = sum / s;
					Mem.setF32(dst, 4 * (n * i + c), half ? Formats.roundHalf(avg) : avg);
				}
			}
		}
	}

	public function endFrame() {
		if (inPass) endPass();
		// (a window's frame shown by the system's own path: helder.os.Blit;
		// none headless, nor in a static Linux build, which has no windows)
		#if !(helder.headless || (helder.os == "linux" && hxmc.libc != "glibc"))
		if (frameTarget == 0 && surface.kind != Headless) Blit.present(surface, SoftTexture.at(frameColor, 0, 0), width, height, damage);
		#end
		damage = null;
	}

	// the frame's rectangles that changed (x0, y0, x1, y1 each), the ones shown; null: all of it
	public function damaged(rects:Null<Array<Int>>) {
		damage = null;
		if (rects == null) return;
		// (kept, not copied: a frame allocates nothing)
		damageRects.resize(0);
		for (r in rects)
			damageRects.push(r);
		damage = damageRects;
	}

	public function readPixels(dst:Bytes) {
		var r = frameTarget != 0 ? texture(frameTarget) : frameColor;
		var size = 4 * Mem.getI32(r, SoftTexture.WIDTH) * Mem.getI32(r, SoftTexture.HEIGHT);
		if (dst.length < size) throw "helder.gfx: readPixels: " + size + " bytes needed";
		SoftTexture.read(r, 0, 0, dst, 0);
	}

	// a texture's record (the soft canvas's: helder.ui.draw.soft, a <Scene>'s pixels read where they are)
	public function textureRecord(id:Int):Ptr
		return texture(id);

	// ---- the compute tier: a dispatch's invocations 4 a call (the
	// stage's lanes), workgroup by workgroup, on this thread (its atomics'
	// order the same on every machine); storage buffers and textures by slot

	public function has(f:Feature):Bool
		return true;

	public function createComputePipeline(shader:Int):Int {
		var s = shader <= 0 || shader > shaders.length ? null : shaders[shader - 1];
		if (s == null) throw "helder.gfx: createComputePipeline: a shader without its CPU form";
		var size = s.size == null ? [1, 1, 1] : [for (k in 0...3) k < s.size.length ? s.size[k] : 1];
		computes.push({entry: s.entry, size: size, workgroup: s.workgroup, frame: s.frame});
		return computes.length;
	}

	public function beginCompute()
		if (inPass) endPass();

	public function setComputePipeline(id:Int)
		computing = id <= 0 || id > computes.length ? null : computes[id - 1];

	public function setStorage(slot:Int, id:Int) {
		if (slot < 0 || slot >= 16) return;
		var b = storage.add(Buffers.SIZE * slot), p = buffer(id);
		Mem.setPtr(b, Buffers.DATA, p);
		Mem.setI32(b, Buffers.BYTES, p.isNull() ? 0 : bufferSizes[id - 1]);
		Mem.setPtr(cctx, Abi.STORAGE + 8 * slot, p.isNull() ? Ptr.nil() : b);
	}

	public function setStorageTexture(slot:Int, id:Int)
		if (slot >= 0 && slot < 16) Mem.setPtr(cctx, Abi.IMAGES + 8 * slot, texture(id));

	// (a workgroup's memory zeroed at its start; with barriers its phases
	// each over the workgroup's calls before the next, the call returning
	// the next phase, -1 the end, each call's frame its own)
	public function dispatch(x:Int, y:Int, z:Int) {
		var c = computing;
		if (c == null || x <= 0 || y <= 0 || z <= 0) return;
		LibC.memcpy(cctx.add(Abi.UNIFORMS), bound, 256);
		Mem.setPtr(cctx, Abi.IN, cin);
		var sx = c.size[0], sy = c.size[1], sz = c.size[2], n = sx * sy * sz, calls = (n + 3) >> 2;
		var need = c.workgroup + calls * c.frame;
		if (need > sharedSize) {
			if (!shared.isNull()) LibC.free(shared);
			shared = LibC.malloc(need);
			sharedSize = need;
		}
		var frames = shared.add(c.workgroup);
		Mem.setPtr(cctx, Abi.WORKGROUP, shared);
		for (gz in 0...z)
			for (gy in 0...y)
				for (gx in 0...x) {
					if (c.workgroup > 0) LibC.memset(shared, 0, c.workgroup);
					var phase = 0;
					while (phase >= 0) {
						var next = -1, k = 0;
						while (k < n) {
							var lanes = n - k < 4 ? n - k : 4;
							for (l in 0...4) {
								// (a lane past the workgroup: the last one's ids, masked out)
								var i = k + (l < lanes ? l : lanes - 1), lx = i % sx, ly = Std.int(i / sx) % sy, lz = Std.int(i / (sx * sy));
								// (ComputeInput's fields in order: x, y, z, localX, localY, localZ, localIndex,
								// groupX, groupY, groupZ, subgroupLane, subgroupSize, subgroupIndex, subgroups)
								inline function set(f:Int, v:Int)
									Mem.setI32(cin, 16 * f + 4 * l, v);
								set(0, gx * sx + lx);
								set(1, gy * sy + ly);
								set(2, gz * sz + lz);
								set(3, lx);
								set(4, ly);
								set(5, lz);
								set(6, i);
								set(7, gx);
								set(8, gy);
								set(9, gz);
								set(10, i & 3);
								set(11, 4);
								set(12, k >> 2);
								set(13, calls);
							}
							Mem.setI32(cctx, Abi.MASK, (1 << lanes) - 1);
							Mem.setPtr(cctx, Abi.FRAME, frames.add((k >> 2) * c.frame));
							Mem.setI32(cctx, Abi.PHASE, phase);
							next = Raster.Fragment.call(c.entry, cctx);
							k += 4;
						}
						phase = next;
					}
				}
	}

	public function dispatchIndirect(id:Int, offset:Int) {
		var p = buffer(id);
		if (!p.isNull()) dispatch(Mem.getI32(p, offset), Mem.getI32(p, offset + 4), Mem.getI32(p, offset + 8));
	}

	public function endCompute() {}

	// ---- shared textures: none

	public function sharing():Null<String>
		return null;

	public function createShared(w:Int, h:Int):Null<{id:Int, handle:String}>
		return null;

	public function openShared(handle:String, w:Int, h:Int):Int
		return 0;

	public function detach() {}

	public function presented():Bool
		return false;

	public function dispose() {
		if (!shared.isNull()) LibC.free(shared);
		shared = Ptr.nil();
		sharedSize = 0;
		for (b in buffers)
			if (!b.isNull()) LibC.free(b);
		for (t in textures)
			if (!t.isNull()) SoftTexture.free(t);
		for (q in queries)
			if (!q.isNull()) LibC.free(q);
		buffers.resize(0);
		textures.resize(0);
		queries.resize(0);
		if (!frameColor.isNull()) {
			SoftTexture.free(frameColor);
			SoftTexture.free(frameDepth);
			frameColor = frameDepth = Ptr.nil();
		}
		memory.free();
	}
}

// (Raster.tile's address)
@:hxmc.unsafe(gc)
private class TileCall {
	static var addr = Ptr.nil();

	public static function address():Ptr {
		if (addr.isNull()) addr = hxmc.unsafe.Callback.addr(Raster.tile);
		return addr;
	}
}

// a pipeline's state as the CPU back end draws it
class SoftPipeline {
	public final vs:Ptr;
	public final fs:Ptr;
	public final varyings:Int;
	public final attributes:Array<{location:Int, slot:Int, offset:Int, components:Int, bytes:Bool}> = [];
	public final strides:Array<Int> = [for (_ in 0...8) 0];
	public final instanced:Array<Bool> = [for (_ in 0...8) false];
	public final topology:Topology;
	// 0 none, 1 front, 2 back
	public var cull:Int;
	public final blend:Int;
	public final compare:Int;
	public final write:Bool;

	public function new(vs:Ptr, fs:Ptr, varyings:Int, d:PipelineDesc) {
		this.vs = vs;
		this.fs = fs;
		this.varyings = varyings;
		for (slot in 0...d.layout.length) {
			var l = d.layout[slot];
			if (slot >= 8) break;
			strides[slot] = l.stride;
			instanced[slot] = l.step == Instance;
			for (a in l.attributes)
				if (a.location < 16)
					attributes.push({
						location: a.location,
						slot: slot,
						offset: a.offset,
						components: switch a.format {
							case Float1: 1;
							case Float2: 2;
							case Float3: 3;
							case _: 4;
						},
						bytes: a.format == UByte4Norm
					});
		}
		topology = d.topology == null ? Triangles : d.topology;
		cull = d.cull == null ? 0 : switch d.cull {
			case Front: 1;
			case Back: 2;
			case _: 0;
		}
		blend = d.blend == null ? 0 : cast d.blend;
		compare = d.depthCompare == null ? 7 : cast d.depthCompare;
		write = d.depthWrite == true;
	}
}
