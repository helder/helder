package helder.gfx;

import haxe.io.Bytes;

// Commands executed in order on the back end (Impl): inline on the
// program's thread (Device's synchronous mode: headless runs, goldens,
// tests), or on the render thread (RenderThread). Device's handles are
// its own, given on the program's thread; the back end's are made here,
// the tables mapping one to the other. Executing allocates nothing but a
// creation's data and a pass's boxed fields.
@:noCompletion @:hxmc.unsafe(gc)
final class Replay {
	public final impl:Impl;
	public final buffers:Array<Int> = [0];
	public final textures:Array<Int> = [0];
	public final samplers:Array<Int> = [0];
	public final shaders:Array<Int> = [0];
	public final pipelines:Array<Int> = [0];
	public final computes:Array<Int> = [0];
	public final queries:Array<Int> = [0];
	// the last beginFrame's answer; whether a frame of the device's is open
	// (begun, not ended: the compositor's frames wait for its end)
	public var began(default, null) = false;
	public var framing(default, null) = false;
	// (the render thread's: the first command that threw, rethrown to the program at its next wait)
	public var error:Null<haxe.Exception> = null;
	// after each frame's present returned, where it ran (latency measured:
	// tests/ui/RenderThreadCheck)
	public var onEndFrame:Null<Void->Void> = null;

	var scratch = Bytes.alloc(4096);
	final color:ColorTarget = {load: Clear};
	final depth:DepthTarget = {load: Clear};
	final pass:PassDesc;
	final rects:Array<Int> = [];

	public function new(impl:Impl) {
		this.impl = impl;
		pass = {colors: [color]};
	}

	public static inline function at(t:Array<Int>, id:Int):Int
		return id <= 0 || id >= t.length ? 0 : t[id];

	// the back end's id of what was made last with no id of the device's
	// (synchronous: the device's handles are the back end's own, as the
	// browser's page reads buffers and textures by them)
	public var made(default, null) = 0;

	// v, made for the device's id (0: none, v its own)
	public function make(t:Array<Int>, id:Int, v:Int):Int {
		if (id == 0) {
			made = v;
			put(t, v, v);
		} else
			put(t, id, v);
		return v;
	}

	public static function put(t:Array<Int>, id:Int, v:Int) {
		while (t.length <= id)
			t.push(0);
		t[id] = v;
	}

	// here: what throws ends it there (the caller drops the rest), as the
	// call itself would have; otherwise each command that throws is
	// skipped, the first error kept
	public function run(c:Commands, here:Bool) {
		if (here) {
			while (c.more())
				step(c);
			return;
		}
		while (c.more()) {
			var start = c.cursor();
			try {
				while (c.more()) {
					start = c.cursor();
					step(c);
				}
			} catch (e:haxe.Exception) {
				if (error == null) error = e;
				c.seek(start + c.sizeAt(start));
			}
		}
	}

	inline function bytes(c:Commands):Int {
		var n = c.next();
		if (scratch.length < n) scratch = Bytes.alloc(n + (n >> 1));
		c.copy(scratch, n);
		return n;
	}

	// (a creation's data: its own, the back end may keep it)
	inline function owned(c:Commands):Bytes {
		var n = c.next();
		var b = Bytes.alloc(n);
		c.copy(b, n);
		return b;
	}

	static inline function opt(v:Int):Null<Int>
		return v == NONE ? null : v;

	function step(c:Commands) {
		var op = c.next();
		c.next();
		switch op {
			case CALL:
				c.objects[c.next()](this);
			case BEGIN_FRAME:
				began = framing = impl.beginFrame();
			case END_FRAME:
				began = framing = false;
				impl.endFrame();
				if (onEndFrame != null) onEndFrame();
			case DAMAGED:
				var n = c.next();
				if (n < 0) impl.damaged(null) else {
					rects.resize(n);
					for (i in 0...n)
						rects[i] = c.next();
					impl.damaged(rects);
				}
			case FRAME_INTO:
				impl.frameInto(at(textures, c.next()));
			case BEGIN_PASS:
				var flags = c.next();
				color.load = cast c.next();
				if (flags & 1 != 0) {
					var r = c.nextFloat(), g = c.nextFloat(), b = c.nextFloat();
					ColorTarget.ClearValue.set(color, r, g, b, c.nextFloat());
				} else
					color.clear = null;
				var t = c.next(), r = c.next(), layer = c.next();
				color.texture = t == 0 ? null : new Texture(at(textures, t));
				color.resolve = r == 0 ? null : new Texture(at(textures, r));
				color.layer = opt(layer);
				if (flags & 2 != 0) {
					depth.load = cast c.next();
					depth.clear = flags & 4 != 0 ? c.nextFloat() : null;
					var d = c.next();
					depth.texture = d == 0 ? null : new Texture(at(textures, d));
					pass.depth = depth;
				} else
					pass.depth = null;
				var q = c.next();
				pass.queries = q == 0 ? null : new QuerySet(at(queries, q));
				impl.beginPass(pass);
			case SET_PIPELINE:
				impl.setPipeline(at(pipelines, c.next()));
			case SET_VERTEX_BUFFER:
				var slot = c.next(), b = c.next();
				impl.setVertexBuffer(slot, at(buffers, b), c.next());
			case SET_INDEX_BUFFER:
				var b = c.next(), format:IndexFormat = cast c.next();
				impl.setIndexBuffer(at(buffers, b), format, c.next());
			case SET_UNIFORMS:
				var slot = c.next(), n = bytes(c);
				impl.setUniforms(slot, scratch, 0, n);
			case SET_TEXTURE:
				var slot = c.next(), t = c.next();
				impl.setTexture(slot, at(textures, t), at(samplers, c.next()));
			case DRAW:
				var v = c.next(), i = c.next();
				impl.draw(v, i, c.next());
			case DRAW_INDEXED:
				var n = c.next(), i = c.next(), f = c.next();
				impl.drawIndexed(n, i, f, c.next());
			case END_PASS:
				impl.endPass();
			case BEGIN_QUERY:
				impl.beginQuery(c.next());
			case END_QUERY:
				impl.endQuery();
			case BEGIN_COMPUTE:
				impl.beginCompute();
			case SET_COMPUTE_PIPELINE:
				impl.setComputePipeline(at(computes, c.next()));
			case SET_STORAGE:
				var slot = c.next();
				impl.setStorage(slot, at(buffers, c.next()));
			case SET_STORAGE_TEXTURE:
				var slot = c.next();
				impl.setStorageTexture(slot, at(textures, c.next()));
			case DISPATCH:
				var x = c.next(), y = c.next();
				impl.dispatch(x, y, c.next());
			case DISPATCH_INDIRECT:
				var b = c.next();
				impl.dispatchIndirect(at(buffers, b), c.next());
			case END_COMPUTE:
				impl.endCompute();
			case DRAW_INDIRECT:
				var b = c.next();
				impl.drawIndirect(at(buffers, b), c.next());
			case DRAW_INDEXED_INDIRECT:
				var b = c.next();
				impl.drawIndexedIndirect(at(buffers, b), c.next());
			case CREATE_BUFFER:
				var id = c.next(), size = c.next(), usage:BufferUsage = cast c.next();
				var data = c.next() != 0 ? owned(c) : null;
				make(buffers, id, impl.createBuffer({size: size, usage: usage, data: data}));
			case WRITE_BUFFER:
				var b = c.next(), offset = c.next(), n = bytes(c);
				impl.writeBuffer(at(buffers, b), offset, scratch, 0, n);
			case CREATE_TEXTURE:
				var id = c.next(), w = c.next(), h = c.next(), format = c.next(), levels = c.next(), flags = c.next(), samples = c.next(),
					layers = c.next();
				var data = flags & 8 != 0 ? owned(c) : null;
				var d:TextureDesc = {
					width: w,
					height: h,
					format: format == NONE ? null : cast format,
					mipLevels: opt(levels),
					renderTarget: flags & 1 != 0,
					samples: opt(samples),
					storage: flags & 2 != 0,
					layers: opt(layers),
					cube: flags & 4 != 0,
					data: data
				};
				make(textures, id, impl.createTexture(d));
			case WRITE_TEXTURE:
				var t = c.next(), x = c.next(), y = c.next(), w = c.next(), h = c.next(), level = c.next(), layer = c.next(), n = bytes(c);
				impl.writeTexture(at(textures, t), scratch, x, y, w, h, 0, level, layer);
			case WRITE_TEXTURE_IMAGE:
				var t = c.next(), image = c.next();
				impl.writeTextureImage(at(textures, t), image, c.next() != 0);
			case GENERATE_MIPS:
				impl.generateMips(at(textures, c.next()));
			case DESTROY_BUFFER:
				var id = c.next();
				impl.destroyBuffer(at(buffers, id));
				put(buffers, id, 0);
			case DESTROY_TEXTURE:
				var id = c.next();
				impl.destroyTexture(at(textures, id));
				put(textures, id, 0);
			case CREATE_SAMPLER:
				var id = c.next(), f = c.next(), m = c.next(), w = c.next();
				make(samplers, id, impl.createSampler({
					filter: f == NONE ? null : cast f,
					mipFilter: m == NONE ? null : cast m,
					wrap: w == NONE ? null : cast w
				}));
			case CREATE_QUERIES:
				var id = c.next();
				make(queries, id, impl.createQueries(c.next()));
			case DESTROY_QUERIES:
				var id = c.next();
				impl.destroyQueries(at(queries, id));
				put(queries, id, 0);
			case RESET_QUERY:
				var q = c.next();
				impl.resetQuery(at(queries, q), c.next());
			case op:
				throw "helder.gfx: Replay: no command " + op;
		}
	}

	// (an absent optional Int)
	public static inline var NONE = -0x7FFFFFFF;

	public static inline var CALL = 1;
	public static inline var BEGIN_FRAME = 2;
	public static inline var END_FRAME = 3;
	public static inline var DAMAGED = 4;
	public static inline var FRAME_INTO = 5;
	public static inline var BEGIN_PASS = 6;
	public static inline var SET_PIPELINE = 7;
	public static inline var SET_VERTEX_BUFFER = 8;
	public static inline var SET_INDEX_BUFFER = 9;
	public static inline var SET_UNIFORMS = 10;
	public static inline var SET_TEXTURE = 11;
	public static inline var DRAW = 12;
	public static inline var DRAW_INDEXED = 13;
	public static inline var END_PASS = 14;
	public static inline var BEGIN_QUERY = 15;
	public static inline var END_QUERY = 16;
	public static inline var BEGIN_COMPUTE = 17;
	public static inline var SET_COMPUTE_PIPELINE = 18;
	public static inline var SET_STORAGE = 19;
	public static inline var SET_STORAGE_TEXTURE = 20;
	public static inline var DISPATCH = 21;
	public static inline var DISPATCH_INDIRECT = 22;
	public static inline var END_COMPUTE = 23;
	public static inline var DRAW_INDIRECT = 24;
	public static inline var DRAW_INDEXED_INDIRECT = 25;
	public static inline var CREATE_BUFFER = 26;
	public static inline var WRITE_BUFFER = 27;
	public static inline var CREATE_TEXTURE = 28;
	public static inline var WRITE_TEXTURE = 29;
	public static inline var WRITE_TEXTURE_IMAGE = 30;
	public static inline var GENERATE_MIPS = 31;
	public static inline var DESTROY_BUFFER = 32;
	public static inline var DESTROY_TEXTURE = 33;
	public static inline var CREATE_SAMPLER = 34;
	public static inline var CREATE_QUERIES = 35;
	public static inline var DESTROY_QUERIES = 36;
	public static inline var RESET_QUERY = 37;
}
