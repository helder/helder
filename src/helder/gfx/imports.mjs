// The JavaScript side of helder.gfx in the browser, loaded by
// src/helder/os/browser.mjs with src/helder/os/imports.mjs: the imports of the
// module "hxmc_gfx" for the WebGPU back end (src/helder/gfx/webgpu/WebGPU.hx)
// and of the module "hxmc_gl" for the GL back end on WebGL2
// (src/helder/gfx/gl/GL.hx, WebGL.hx). The adapter and the device are
// requested before the module starts; without them (no navigator.gpu, no
// adapter, or run's option gfx: 'webgl2') ready() is 0 and Device.create
// takes WebGL2, or throws without it. GPU objects, and GL's object names,
// live in the loader's handle table; the enums are helder.gfx's, GL's are
// GL's own.
//
// host.gfx.release() destroys the device and loses the WebGL contexts (a page
// done with the program); a device or context lost otherwise goes to run's
// option onError when given.
//
// Swapped out (hxmc dev, host.dispose(): src/helder/os/browser.mjs), the
// instance's GPU objects are released (what the program left too, counted:
// host.gfx.left), but the device and the canvases' contexts stay as they
// are, configured, showing the last frame: run's option gpu ({adapter,
// device}) gives the next instance the same device, and a canvas configured
// alike is not configured again (which would clear it). A WebGL2 context
// stays too (the same one for the next instance's getContext), its state
// set back to WebGL's defaults.
//
// host.gfx.backend is the API a device was created on ('webgpu', 'webgl2';
// null: none yet). Reading a frame back on WebGPU waits for the GPU, which a
// browser does asynchronously only: host.gfx.readPixels() resolves to
// {width, height, data} (RGBA8, rows top to bottom) of a headless target as
// it is now, or of a canvas's next frame (copied before it is presented);
// on WebGL2 the same, read synchronously (Device.readPixels works there too).
//
// run's option antialias (true: 4 samples a pixel) multisamples a canvas's
// frames: on WebGPU a multisampled colour and depth texture resolved into
// the canvas's, the frame's pipelines made for them; on WebGL2 the
// context's antialias. Render targets and headless targets stay single-
// sampled, and readPixels reads what is shown (resolved).
//
// The compute tier: a compute pass in the frame's encoder (or one of its
// own, submitted at compute_end, its uniforms written first); its bind
// group (uniform blocks at dynamic offsets, textures, samplers, storage
// buffers read-only-storage or storage, storage textures write-only) made
// once per set of resources, set at a dispatch after a change. A storage
// buffer is also a vertex and index buffer (BufferUsage.Storage), an
// indirect one a storage buffer. host.gfx.readBuffer(handle, offset, size)
// resolves to a buffer's bytes (a Uint8Array) once the frames writing it
// are done.
//
// WebGPU's textures: their TextureFormat's GPU format; a pipeline is made
// for its bind group layout reading every texture as filterable, and again
// (once, at the first draw binding one) for R32F or depth textures at some
// slots, read unfilterable; generate_mips draws each level from the one
// before (MIPS).

const FORMATS = ['float32', 'float32x2', 'float32x3', 'float32x4', 'unorm8x4']; // VertexFormat
const TOPOLOGIES = ['triangle-list', 'triangle-strip', 'line-list', 'point-list']; // Topology
const CULLS = ['none', 'front', 'back']; // Cull
const LOADS = ['clear', 'load', 'clear']; // LoadOp (DontCare: clear)
const COMPARES = ['never', 'less', 'equal', 'less-equal', 'greater', 'not-equal', 'greater-equal', 'always']; // Compare
const INDEX = ['uint16', 'uint32']; // IndexFormat
const WRAPS = ['repeat', 'clamp-to-edge', 'mirror-repeat']; // Wrap
// Blend: Opaque, Alpha, Additive, Premultiplied, Multiply
const BLENDS = [
	undefined,
	{ color: { srcFactor: 'src-alpha', dstFactor: 'one-minus-src-alpha' }, alpha: { srcFactor: 'one', dstFactor: 'one-minus-src-alpha' } },
	{ color: { srcFactor: 'one', dstFactor: 'one' }, alpha: { srcFactor: 'one', dstFactor: 'one' } },
	{ color: { srcFactor: 'one', dstFactor: 'one-minus-src-alpha' }, alpha: { srcFactor: 'one', dstFactor: 'one-minus-src-alpha' } },
	{ color: { srcFactor: 'dst', dstFactor: 'zero' }, alpha: { srcFactor: 'zero', dstFactor: 'one' } },
];
const INFO_LOG_LENGTH = 0x8b84; // (GL's, not WebGL's)
const RING = 256 * 1024; // the uniform ring (Encoder.UNIFORM_RING)
const UNIFORM = 0, TEXTURE = 1, STORAGE = 2, STORAGE_WRITE = 3, STORAGE_TEXTURE = 4; // BindingKind
// TextureFormat: WebGPU's, bytes a texel; R32F and the depth formats are unfilterable from R32F on
const TEXTURE_FORMATS = ['rgba8unorm', 'rgba8unorm-srgb', 'r8unorm', 'rg8unorm', 'rgba16float', 'r32float', 'depth16unorm', 'depth32float', 'bc1-rgba-unorm',
	'bc3-rgba-unorm', 'astc-4x4-unorm', 'rgba32float'];
// (compressed: a 4x4 block's bytes)
const TEXEL = [4, 4, 1, 2, 8, 4, 2, 4, 8, 16, 16, 16];
const R32F = 5, DEPTH16 = 6, BC1 = 8, RGBA32F = 11;
const compressed = (format) => format >= BC1 && format < RGBA32F;
// a texture's views' dimension (WebGPU's), by its dimension: 2D, a cube, a 2D array
const DIMENSIONS = ['2d', 'cube', '2d-array'];
// the compressed formats' features, asked for with the device where the adapter has them (TextureFormat: from BC1)
const FEATURES = ['texture-compression-bc', 'texture-compression-bc', 'texture-compression-astc'];
// generateMips: a level drawn from the one before, sampled at its texels' centres
const MIPS = `@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var smp: sampler;
struct V { @builtin(position) pos: vec4f, @location(0) uv: vec2f }
@vertex fn vs(@builtin(vertex_index) i: u32) -> V {
	let uv = vec2f(f32((i << 1u) & 2u), f32(i & 2u));
	return V(vec4f(uv * vec2f(2, -2) + vec2f(-1, 1), 0, 1), uv);
}
@fragment fn fs(v: V) -> @location(0) vec4f { return textureSampleLevel(src, smp, v.uv, 0.0); }`;

// texels (or a compressed level's blocks: rows of 4x4 blocks, the level's
// size rounded up to them, WebGPU's physical size) into a texture's level
function writeTextureData(device, host, t, x, y, w, h, level, data, layer = 0) {
	if (t.compressed) {
		const bw = (w + 3) >> 2, bh = (h + 3) >> 2;
		device.queue.writeTexture({ texture: t.texture, mipLevel: level }, host.bytes(data, bw * bh * t.texel), { bytesPerRow: bw * t.texel, rowsPerImage: bh }, [bw * 4, bh * 4]);
	} else device.queue.writeTexture({ texture: t.texture, mipLevel: level, origin: [x, y, layer] }, host.bytes(data, w * h * t.texel), { bytesPerRow: w * t.texel }, [w, h]);
}

// (a canvas's WebGPU configuration, kept across instances: hxmc dev)
const configured = new WeakMap();

export default async function (host) {
	let adapter = null, device = null;
	try {
		if (host.options.gpu) ({ adapter, device } = host.options.gpu);
		else {
			adapter = host.options.gfx !== 'webgl2' && navigator.gpu && (await navigator.gpu.requestAdapter());
			device = adapter ? await adapter.requestDevice({ requiredFeatures: [...new Set(FEATURES)].filter((f) => adapter.features.has(f)) }) : null;
		}
	} catch (e) {
		console.error('helder.gfx: no WebGPU device:', e);
	}
	if (device) device.addEventListener('uncapturederror', (e) => console.error('helder.gfx: WebGPU:', e.error.message));
	// (a device or context lost, but by release: run's option onError)
	let released = false;
	const lost = (what) => !released && !host.disposed && host.options.onError && host.options.onError(new Error(what));
	if (device) device.lost.then((info) => lost('the WebGPU device was lost' + (info.message ? ': ' + info.message : '')));
	const contexts = [];
	const { handles } = host;
	const write = (t, x, y, w, h, level, data, layer) => writeTextureData(device, host, t, x, y, w, h, level, data, layer);
	// a pipeline's vertex buffers and resources, as pipeline_buffer,
	// pipeline_attribute and pipeline_binding give them
	let layout = [], resources = [];
	// the frame
	let encoder = null, texture = null, frameTarget = null, frameView = null, pass = null;
	// (what was released while the encoder's commands were not submitted: destroyed after)
	const doomed = [];
	const destroy = (o) => {
		o?.destroy?.();
		o?.texture?.destroy();
		// (a target's depth and multisampled textures; a texture's depth is whether it is one)
		o?.depth?.destroy?.();
		o?.msaa?.destroy?.();
	};
	const submitted = () => {
		for (const o of doomed.splice(0)) destroy(o);
	};
	// generateMips: its pipeline per format, its sampler
	const mipPipelines = new Map();
	let mipSampler = null;
	// the uniform ring: the frame's blocks, copied at set_uniforms and written
	// to the GPU buffer before the frame's submit (which the queue orders
	// after the previous frames' reads); each slot's offset, for the bind group
	const ring = device ? { buffer: device.createBuffer({ size: RING, usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST }), staging: new Uint8Array(RING), used: 0 } : null;
	const offsets = new Uint32Array(16);
	// each slot's texture and sampler (handles)
	const textures = new Int32Array(16), samplers = new Int32Array(16);
	// the pipeline set (its bind group layout and groups), and whether its bind group needs setting
	let pipe = null, dirty = false;
	// (the pass's occlusion query set, a query open in it, the sets the frame wrote)
	let passQueries = null, queryOpen = false, frameQueries = [];
	const attachment = { view: null, loadOp: 'clear', storeOp: 'store', clearValue: { r: 0, g: 0, b: 0, a: 1 } };
	const depthAttachment = { view: null, depthLoadOp: 'clear', depthStoreOp: 'store', depthClearValue: 1 };
	const passDesc = { colorAttachments: [attachment], depthStencilAttachment: depthAttachment };
	let captures = [];

	// records a copy of a texture into a buffer; then, once the encoder is
	// submitted, the result resolves to its pixels as RGBA8, rows top to bottom
	function copy(enc, tex, format) {
		const w = tex.width, h = tex.height, row = Math.ceil(w * 4 / 256) * 256;
		const buf = device.createBuffer({ size: row * h, usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.MAP_READ });
		enc.copyTextureToBuffer({ texture: tex }, { buffer: buf, bytesPerRow: row }, [w, h]);
		return async () => {
			await buf.mapAsync(GPUMapMode.READ);
			const src = new Uint8Array(buf.getMappedRange()), data = new Uint8Array(w * h * 4);
			const bgra = format.startsWith('bgra');
			for (let y = 0; y < h; y++)
				for (let x = 0; x < w; x++) {
					const s = y * row + 4 * x, d = 4 * (y * w + x);
					data[d] = src[s + (bgra ? 2 : 0)];
					data[d + 1] = src[s + 1];
					data[d + 2] = src[s + (bgra ? 0 : 2)];
					data[d + 3] = src[s + 3];
				}
			buf.destroy();
			return { width: w, height: h, data };
		};
	}

	// helder_image: images the browser decodes (helder.image.WebImages), each
	// {file, premultiply, state, width, height, bitmap, decoding}; decoded
	// again from the file when its bitmap was closed and it is uploaded
	const images = { get: (h) => handles.get(h) };
	function decodeImage(im) {
		im.decoding = createImageBitmap(new Blob([im.file]), { premultiplyAlpha: im.premultiply ? 'premultiply' : 'none', colorSpaceConversion: 'none' }).then(
			(b) => { im.bitmap = b; im.width = b.width; im.height = b.height; im.state = 1; im.decoding = null; host.wake?.(0); return b; },
			(e) => { im.state = -1; im.decoding = null; host.wake?.(0); return null; });
		return im.decoding;
	}
	// up(bitmap) with the image decoded: now when it is, else once it is
	// (nothing for one the browser cannot read); release: the image freed after
	function fill(image, release, up) {
		const im = images.get(image);
		const done = (b) => {
			if (b) up(b);
			if (release) {
				im.bitmap?.close();
				handles.remove(image);
			}
		};
		if (im.bitmap) done(im.bitmap);
		else (im.decoding ?? decodeImage(im)).then(done);
	}
	const helder_image = {
		decode(fetch, p, length, premultiply) {
			let file;
			if (fetch) {
				file = handles.get(fetch).body;
				handles.remove(fetch);
			} else file = host.bytes(p, length).slice();
			const im = { file, premultiply: !!premultiply, state: 0, width: 0, height: 0, bitmap: null, decoding: null };
			decodeImage(im);
			return handles.add(im);
		},
		state: (h) => images.get(h).state,
		width: (h) => images.get(h).width,
		height: (h) => images.get(h).height,
		file_length: (h) => images.get(h).file.length,
		// (into a span: its address and length; no more than the length)
		file_take: (h, p, n) => host.bytes(p, Math.min(n, images.get(h).file.length)).set(images.get(h).file.subarray(0, n)),
		close(h) {
			const im = images.get(h);
			im.bitmap?.close();
			im.bitmap = null;
		},
		free(h) {
			images.get(h).bitmap?.close();
			handles.remove(h);
		},
	};

	host.gfx = {
		adapter,
		device,
		backend: null,
		// the GPU's memory given back: the device destroyed, the WebGL contexts lost
		release() {
			released = true;
			if (device) device.destroy();
			for (const g of contexts) g.getExtension('WEBGL_lose_context')?.loseContext();
			contexts.length = 0;
		},
		readPixels() {
			if (current) {
				if (current.offscreen) return Promise.resolve(read(current));
				return new Promise((resolve, reject) => current.captures.push({ resolve, reject }));
			}
			if (frameTarget && frameTarget.texture) {
				const enc = device.createCommandEncoder();
				const pixels = copy(enc, frameTarget.texture, frameTarget.format);
				device.queue.submit([enc.finish()]);
				return pixels();
			}
			return new Promise((resolve, reject) => captures.push({ resolve, reject }));
		},
		// a buffer's bytes (its handle: Buffer.id(); WebGPU): size bytes from
		// offset (by default all of it), once the work submitted before is done
		readBuffer(h, offset = 0, size) {
			const b = handles.get(h);
			size ??= b.size - offset;
			const n = Math.ceil(size / 4) * 4, read = device.createBuffer({ size: n, usage: GPUBufferUsage.COPY_DST | GPUBufferUsage.MAP_READ });
			const enc = device.createCommandEncoder();
			enc.copyBufferToBuffer(b, offset, read, 0, n);
			device.queue.submit([enc.finish()]);
			return read.mapAsync(GPUMapMode.READ).then(() => {
				const data = new Uint8Array(read.getMappedRange()).slice(0, size);
				read.destroy();
				return data;
			});
		},
		// a render target's pixels (its handle; WebGPU), as readPixels: once the frames drawing it are submitted
		readTexture(h) {
			const t = handles.get(h), enc = device.createCommandEncoder();
			const pixels = copy(enc, t.texture, t.texture.format);
			device.queue.submit([enc.finish()]);
			return pixels();
		},
	};

	// the current pipeline's bind group, with the slots' uniform offsets (a
	// group per set of textures, made once)
	let serials = 0;

	function bind() {
		if (!dirty) return;
		dirty = false;
		// (an unfilterable texture bound: the pipeline made for those slots)
		let mask = 0;
		for (const t of pipe.textures) if (handles.get(textures[t.slot])?.unfilterable) mask |= 1 << t.slot;
		const c = pipe.variants.get(mask) ?? variant(pipe, mask);
		if (c !== pipe.active) {
			pipe.active = c;
			pass.setPipeline(c.pipeline);
		}
		if (!c.bgl) return;
		// (by the objects' serials, not their handles: a released texture's handle is given again to the next one)
		let key = '';
		for (const t of c.textures) key += handles.get(textures[t.slot]).serial + ':' + samplers[t.slot] + ',';
		let group = c.groups.get(key);
		if (!group) {
			const entries = c.uniforms.map((u) => ({ binding: u.slot, resource: { buffer: ring.buffer, size: u.size } }));
			for (const t of c.textures) {
				entries.push({ binding: t.slot, resource: handles.get(textures[t.slot]).view }, { binding: 16 + t.slot, resource: handles.get(samplers[t.slot]) });
			}
			group = device.createBindGroup({ layout: c.bgl, entries });
			c.groups.set(key, group);
		}
		for (let i = 0; i < c.uniforms.length; i++) c.offsets[i] = offsets[c.uniforms[i].slot];
		pass.setBindGroup(0, group, c.offsets);
	}

	// a pipeline's bind group layout: uniform blocks at dynamic offsets, a
	// texture at its slot and its sampler at 16 + slot (in mask: an
	// unfilterable texture and a non-filtering sampler)
	function bindGroupLayout(resources, mask) {
		const visibility = GPUShaderStage.VERTEX | GPUShaderStage.FRAGMENT;
		const entries = [];
		for (const r of resources)
			if (r.kind === UNIFORM) entries.push({ binding: r.slot, visibility, buffer: { type: 'uniform', hasDynamicOffset: true, minBindingSize: r.size } });
			else {
				const plain = (mask & (1 << r.slot)) === 0;
				entries.push({ binding: r.slot, visibility, texture: { sampleType: plain ? 'float' : 'unfilterable-float', viewDimension: DIMENSIONS[r.size] } }, { binding: 16 + r.slot, visibility, sampler: { type: plain ? 'filtering' : 'non-filtering' } });
			}
		return entries.length ? device.createBindGroupLayout({ entries }) : null;
	}

	// the compute pass: its encoder its own (none in a frame), its pipeline,
	// each slot's storage buffer or texture (handles), whether its bind group needs setting
	let own = false, cpipe = null, cdirty = false;
	const storages = new Int32Array(16);
	// (a buffer's serial, for the bind groups' keys: a released buffer's handle is given again)
	const bufferSerials = new WeakMap();
	const serialOf = (o) => {
		let s = o.serial ?? bufferSerials.get(o);
		if (s === undefined) bufferSerials.set(o, (s = ++serials));
		return s;
	};

	// the compute pipeline's bind group (its variant for the unfilterable textures bound)
	function bindCompute() {
		if (!cdirty) return;
		cdirty = false;
		let mask = 0;
		for (const t of cpipe.textures) if (handles.get(textures[t.slot])?.unfilterable) mask |= 1 << t.slot;
		const c = cpipe.variants.get(mask) ?? computeVariant(cpipe, mask);
		if (c !== cpipe.active) {
			cpipe.active = c;
			pass.setPipeline(c.pipeline);
		}
		if (!c.bgl) return;
		let key = '';
		for (const t of c.textures) key += handles.get(textures[t.slot]).serial + ':' + samplers[t.slot] + ',';
		for (const s of c.storage) key += serialOf(handles.get(storages[s.slot])) + ';';
		let group = c.groups.get(key);
		if (!group) {
			const entries = c.uniforms.map((u) => ({ binding: u.slot, resource: { buffer: ring.buffer, size: u.size } }));
			for (const t of c.textures) entries.push({ binding: t.slot, resource: handles.get(textures[t.slot]).view }, { binding: 16 + t.slot, resource: handles.get(samplers[t.slot]) });
			for (const s of c.storage) {
				const o = handles.get(storages[s.slot]);
				entries.push({ binding: s.slot, resource: s.kind === STORAGE_TEXTURE ? o.view : { buffer: o } });
			}
			group = device.createBindGroup({ layout: c.bgl, entries });
			c.groups.set(key, group);
		}
		for (let i = 0; i < c.uniforms.length; i++) c.offsets[i] = offsets[c.uniforms[i].slot];
		pass.setBindGroup(0, group, c.offsets);
	}

	// a compute pipeline's variant for unfilterable textures at the slots of mask
	function computeVariant(p, mask) {
		const visibility = GPUShaderStage.COMPUTE, entries = [];
		for (const r of p.resources)
			if (r.kind === UNIFORM) entries.push({ binding: r.slot, visibility, buffer: { type: 'uniform', hasDynamicOffset: true, minBindingSize: r.size } });
			else if (r.kind === TEXTURE) {
				const plain = (mask & (1 << r.slot)) === 0;
				entries.push({ binding: r.slot, visibility, texture: { sampleType: plain ? 'float' : 'unfilterable-float', viewDimension: DIMENSIONS[r.size] } }, { binding: 16 + r.slot, visibility, sampler: { type: plain ? 'filtering' : 'non-filtering' } });
			} else if (r.kind === STORAGE_TEXTURE) entries.push({ binding: r.slot, visibility, storageTexture: { access: 'write-only', format: TEXTURE_FORMATS[r.size], viewDimension: '2d' } });
			else entries.push({ binding: r.slot, visibility, buffer: { type: r.kind === STORAGE ? 'read-only-storage' : 'storage' } });
		const bgl = entries.length ? device.createBindGroupLayout({ entries }) : null;
		const v = { ...p.base, pipeline: device.createComputePipeline({ ...p.desc, layout: bgl ? device.createPipelineLayout({ bindGroupLayouts: [bgl] }) : 'auto' }), bgl, groups: new Map() };
		p.variants.set(mask, v);
		return v;
	}

	// the pipeline p for unfilterable textures at the slots of mask, made
	// when first drawn with them (each a whole compile: seconds of a
	// software GPU's, SwiftShader's, for a large fragment stage, and a
	// pipeline whose textures are never all filterable never needs mask 0's)
	function variant(p, mask) {
		const bgl = bindGroupLayout(p.resources, mask);
		const v = { ...p.base, pipeline: device.createRenderPipeline({ ...p.desc, layout: bgl ? device.createPipelineLayout({ bindGroupLayouts: [bgl] }) : 'auto' }), bgl, groups: new Map() };
		p.variants.set(mask, v);
		return v;
	}

	const hxmc_gfx = {
		ready: () => (device ? 1 : 0),
		target_canvas(canvas, antialias) {
			host.gfx.backend = 'webgpu';
			const context = handles.get(canvas).getContext('webgpu');
			const format = navigator.gpu.getPreferredCanvasFormat();
			// (COPY_SRC: readPixels; configured alike by an earlier instance: as it is, its last frame shown)
			const c = configured.get(context);
			if (!c || c.device !== device || c.format !== format) {
				context.configure({ device, format, usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.COPY_SRC, alphaMode: 'opaque' });
				configured.set(context, { device, format });
			}
			return handles.add({ context, format, samples: host.options.antialias ?? antialias ? 4 : 1 });
		},
		target_texture(width, height) {
			host.gfx.backend = 'webgpu';
			const format = 'rgba8unorm';
			const texture = device.createTexture({ size: [width, height], format, usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.COPY_SRC });
			return handles.add({ texture, format });
		},
		buffer(size, usage, data, length) {
			// (BufferUsage: a storage buffer is a vertex and index buffer too; read back: COPY_SRC)
			const u = [GPUBufferUsage.VERTEX, GPUBufferUsage.INDEX, GPUBufferUsage.UNIFORM, GPUBufferUsage.STORAGE | GPUBufferUsage.VERTEX | GPUBufferUsage.INDEX | GPUBufferUsage.COPY_SRC,
				GPUBufferUsage.STORAGE | GPUBufferUsage.INDIRECT | GPUBufferUsage.COPY_SRC][usage];
			const b = device.createBuffer({ size: Math.ceil(size / 4) * 4, usage: u | GPUBufferUsage.COPY_DST });
			if (length > 0) {
				// (writeBuffer: a multiple of 4 bytes)
				const bytes = new Uint8Array(Math.ceil(length / 4) * 4);
				bytes.set(host.bytes(data, length));
				device.queue.writeBuffer(b, 0, bytes);
			}
			return handles.add(b);
		},
		write_buffer: (b, offset, data, size) => device.queue.writeBuffer(handles.get(b), offset, host.bytes(data, size)),
		texture(width, height, format, levels, target, samples, storage, layers, dimension, data) {
			// (a mip chain's levels are drawn by generate_mips; a multisampled one is only drawn into, then resolved)
			// (RGBA8's a render attachment too: copyExternalImageToTexture's, texture_image)
			const usage = samples > 1 ? GPUTextureUsage.RENDER_ATTACHMENT
				: GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.COPY_DST | (target ? GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.COPY_SRC : (levels > 1 && format < R32F) || format < 2 ? GPUTextureUsage.RENDER_ATTACHMENT : 0);
			const label = samples > 1 ? 'helder multisampled target' : target ? 'helder render target' : 'helder texture';
			const texture = device.createTexture({ label, size: [width, height, layers], format: TEXTURE_FORMATS[format], mipLevelCount: levels, sampleCount: samples, usage: usage | (storage ? GPUTextureUsage.STORAGE_BINDING : 0) });
			// (a cube's or a 2D array's target: a view a layer)
			const targets = target && dimension ? Array.from({ length: layers }, (_, l) => texture.createView({ dimension: '2d', baseArrayLayer: l, arrayLayerCount: 1, mipLevelCount: 1 })) : null;
			const t = { serial: ++serials, texture, view: texture.createView({ dimension: DIMENSIONS[dimension] }), target: targets ? targets[0] : target ? texture.createView({ mipLevelCount: 1 }) : null, targets, layers, texel: TEXEL[format],
				unfilterable: format === R32F || format === DEPTH16 || format === DEPTH16 + 1 || format === RGBA32F, depth: format === DEPTH16 || format === DEPTH16 + 1, compressed: compressed(format) };
			if (data) for (let l = 0; l < layers; l++) write(t, 0, 0, width, height, 0, data + l * width * height * t.texel, l);
			return handles.add(t);
		},
		write_texture: (h, x, y, w, height, level, layer, data) => write(handles.get(h), x, y, w, height, level, data, layer),
		// 1: the device samples the TextureFormat (the compressed ones: their features)
		max_texture: () => (device ? device.limits.maxTextureDimension2D : 8192),
		supports: (format) => (!compressed(format) || (device && device.features.has(FEATURES[format - BC1])) ? 1 : 0),
		generate_mips(h) {
			const t = handles.get(h), { texture } = t;
			let pipeline = mipPipelines.get(texture.format);
			if (!pipeline) {
				const module = device.createShaderModule({ code: MIPS });
				pipeline = device.createRenderPipeline({ layout: 'auto', vertex: { module, entryPoint: 'vs' }, fragment: { module, entryPoint: 'fs', targets: [{ format: texture.format }] } });
				mipPipelines.set(texture.format, pipeline);
				mipSampler ??= device.createSampler({ magFilter: 'linear', minFilter: 'linear' });
			}
			// (each level's view and the bind group reading the one before, made once)
			if (!t.mips) {
				// (each layer's levels: a cube's faces, a 2D array's layers)
				t.mips = [];
				for (let l = 0; l < texture.depthOrArrayLayers; l++) {
					const views = [];
					for (let i = 0; i < texture.mipLevelCount; i++) views.push(texture.createView({ dimension: '2d', baseMipLevel: i, mipLevelCount: 1, baseArrayLayer: l, arrayLayerCount: 1 }));
					t.mips.push(...views.slice(1).map((view, i) => ({
						attachments: [{ view, loadOp: 'clear', storeOp: 'store', clearValue: { r: 0, g: 0, b: 0, a: 0 } }],
						group: device.createBindGroup({ layout: pipeline.getBindGroupLayout(0), entries: [{ binding: 0, resource: views[i] }, { binding: 1, resource: mipSampler }] }),
					})));
				}
			}
			const enc = encoder ?? device.createCommandEncoder();
			for (const m of t.mips) {
				const p = enc.beginRenderPass({ colorAttachments: m.attachments });
				p.setPipeline(pipeline);
				p.setBindGroup(0, m.group);
				p.draw(3);
				p.end();
			}
			if (!encoder) device.queue.submit([enc.finish()]);
		},
		texture_image(h, image, release) {
			const t = handles.get(h);
			fill(image, release, (bitmap) => {
				if (handles.get(h) !== t) return;
				device.queue.copyExternalImageToTexture({ source: bitmap }, { texture: t.texture, premultipliedAlpha: images.get(image).premultiply }, [bitmap.width, bitmap.height]);
				if (t.texture.mipLevelCount > 1) hxmc_gfx.generate_mips(h);
			});
		},
		sampler(filter, mip, wrap) {
			const f = filter ? 'linear' : 'nearest', w = WRAPS[wrap];
			return handles.add(device.createSampler({ magFilter: f, minFilter: f, mipmapFilter: mip === 2 ? 'linear' : 'nearest', lodMaxClamp: mip ? 32 : 0, addressModeU: w, addressModeV: w }));
		},
		shader(code) {
			const module = device.createShaderModule({ code: host.string(code) });
			module.getCompilationInfo().then((info) => {
				for (const m of info.messages) if (m.type === 'error') console.error(`helder.gfx: WGSL ${m.lineNum}:${m.linePos}: ${m.message}`);
			});
			return handles.add(module);
		},
		pipeline_begin() {
			layout = [];
			resources = [];
		},
		pipeline_buffer(stride, instance) {
			layout.push({ arrayStride: stride, stepMode: instance ? 'instance' : 'vertex', attributes: [] });
		},
		pipeline_attribute(location, format, offset) {
			layout[layout.length - 1].attributes.push({ shaderLocation: location, format: FORMATS[format], offset });
		},
		pipeline_binding(slot, kind, size) {
			resources.push({ slot, kind, size });
		},
		compute_pipeline_end(shader) {
			const uniforms = resources.filter((r) => r.kind === UNIFORM).sort((a, b) => a.slot - b.slot);
			const desc = { compute: { module: handles.get(shader), entryPoint: 'main' } };
			const base = { uniforms, textures: resources.filter((r) => r.kind === TEXTURE), storage: resources.filter((r) => r.kind >= STORAGE), offsets: new Uint32Array(uniforms.length) };
			const p = { ...base, base, desc, resources, variants: new Map(), active: null, compute: true };
			computeVariant(p, 0);
			p.pipeline = p.variants.get(0).pipeline;
			return handles.add(p);
		},
		compute_begin() {
			own = !encoder;
			if (own) encoder = device.createCommandEncoder();
			pass = encoder.beginComputePass();
			cpipe = null;
		},
		set_compute_pipeline(p) {
			cpipe = handles.get(p);
			cpipe.active = null;
			cdirty = true;
		},
		set_storage(slot, b) {
			storages[slot] = b;
			cdirty = true;
		},
		set_storage_texture(slot, t) {
			storages[slot] = t;
			cdirty = true;
		},
		dispatch(x, y, z) {
			bindCompute();
			pass.dispatchWorkgroups(x, y, z);
		},
		dispatch_indirect(b, offset) {
			bindCompute();
			pass.dispatchWorkgroupsIndirect(handles.get(b), offset);
		},
		compute_end() {
			pass.end();
			pass = null;
			if (own) {
				if (ring.used) device.queue.writeBuffer(ring.buffer, 0, ring.staging, 0, Math.ceil(ring.used / 4) * 4);
				ring.used = 0;
				device.queue.submit([encoder.finish()]);
				encoder = null;
				own = false;
				submitted();
			}
		},
		draw_indirect(b, offset) {
			bind();
			pass.drawIndirect(handles.get(b), offset);
		},
		draw_indexed_indirect(b, offset) {
			bind();
			pass.drawIndexedIndirect(handles.get(b), offset);
		},
		pipeline_end(vertex, fragment, target, topology, cull, blend, depthCompare, depthWrite, colorFormat, depthFormat, samples) {
			const uniforms = resources.filter((r) => r.kind === UNIFORM).sort((a, b) => a.slot - b.slot);
			const bgl = bindGroupLayout(resources, 0);
			const desc = {
				vertex: { module: handles.get(vertex), entryPoint: 'main', buffers: layout },
				fragment: { module: handles.get(fragment), entryPoint: 'main', targets: [{ format: colorFormat < 0 ? handles.get(target).format : TEXTURE_FORMATS[colorFormat], blend: BLENDS[blend] }] },
				depthStencil: depthFormat < 0 ? undefined : { format: TEXTURE_FORMATS[depthFormat], depthWriteEnabled: !!depthWrite, depthCompare: COMPARES[depthCompare] },
				// (GL's front faces)
				primitive: { topology: TOPOLOGIES[topology], cullMode: CULLS[cull], frontFace: 'ccw' },
				// (the frame's: its samples; a render target's, the pipeline's)
				multisample: { count: colorFormat < 0 ? handles.get(target).samples ?? 1 : samples },
			};
			// (base: what its variants share; each variant made when first drawn, variant())
			const base = { uniforms, textures: resources.filter((r) => r.kind === TEXTURE), offsets: new Uint32Array(uniforms.length) };
			const p = { ...base, bgl, groups: new Map(), base, desc, resources, variants: new Map(), active: null };
			return handles.add(p);
		},
		frame_begin(target) {
			const t = handles.get(target);
			texture = t.texture ?? t.context.getCurrentTexture();
			if (texture.width === 0 || texture.height === 0) return 0;
			frameTarget = t;
			frameView = texture.createView();
			// (the depth buffer, of the target's size and samples; multisampled,
			// the colour texture resolved into the target's)
			if (!t.depth || t.depth.width !== texture.width || t.depth.height !== texture.height) {
				const size = [texture.width, texture.height], sampleCount = t.samples ?? 1, usage = GPUTextureUsage.RENDER_ATTACHMENT;
				t.depth?.destroy();
				t.msaa?.destroy();
				t.depth = device.createTexture({ label: 'helder frame depth', size, format: 'depth32float', sampleCount, usage });
				t.depthView = t.depth.createView();
				t.msaa = sampleCount > 1 ? device.createTexture({ label: 'helder frame (multisampled)', size, format: t.format, sampleCount, usage }) : null;
				t.msaaView = t.msaa?.createView();
			}
			depthAttachment.view = t.depthView;
			encoder = device.createCommandEncoder();
			return 1;
		},
		// (occlusion queries: a query set, its resolve buffer and a buffer it
		// is read back through; the queries a frame wrote resolved at its
		// end, read once mapped, while one read is on its way the next
		// frames' answers let go)
		query_set(count) {
			const q = {
				set: device.createQuerySet({ type: 'occlusion', count }),
				resolve: device.createBuffer({ label: 'helder queries', size: count * 8, usage: GPUBufferUsage.QUERY_RESOLVE | GPUBufferUsage.COPY_SRC }),
				read: device.createBuffer({ label: 'helder queries (read)', size: count * 8, usage: GPUBufferUsage.MAP_READ | GPUBufferUsage.COPY_DST }),
				count, results: new Int32Array(count).fill(-1), written: new Uint8Array(count), reading: null,
				destroy() {
					this.set.destroy();
					this.resolve.destroy();
					this.read.destroy();
				},
			};
			return handles.add(q);
		},
		query_result: (h, k) => handles.get(h)?.results[k] ?? -1,
		reset_query(h, k) {
			const q = handles.get(h);
			if (!q) return;
			q.results[k] = -1;
			if (q.reading) q.reading[k] = 0;
		},
		begin_query(k) {
			if (!passQueries || k < 0 || k >= passQueries.count) return;
			pass.beginOcclusionQuery(k);
			passQueries.written[k] = 1;
			queryOpen = true;
		},
		end_query() {
			if (!queryOpen) return;
			pass.endOcclusionQuery();
			queryOpen = false;
			if (!frameQueries.includes(passQueries)) frameQueries.push(passQueries);
		},
		pass_begin(color, resolve, load, r, g, b, a, depthTexture, depthLoad, depth, queries, layer) {
			passQueries = queries ? handles.get(queries) : null;
			passDesc.occlusionQuerySet = passQueries ? passQueries.set : undefined;
			// (a render target: its first level, and its depth texture or none;
			// multisampled, resolved into resolve's at the end)
			const t = color ? handles.get(color) : null, d = depthTexture ? handles.get(depthTexture) : null;
			attachment.view = t ? (t.targets ? t.targets[layer] : t.target) : frameTarget.msaaView ?? frameView;
			attachment.resolveTarget = t ? (resolve ? handles.get(resolve).target : undefined) : frameTarget.msaa ? frameView : undefined;
			attachment.loadOp = LOADS[load];
			depthAttachment.view = t ? d?.target : frameTarget.depthView;
			passDesc.depthStencilAttachment = depthAttachment.view ? depthAttachment : undefined;
			depthAttachment.depthLoadOp = LOADS[depthLoad];
			depthAttachment.depthClearValue = depth;
			const c = attachment.clearValue;
			c.r = r;
			c.g = g;
			c.b = b;
			c.a = a;
			pass = encoder.beginRenderPass(passDesc);
			const size = t ? t.texture : texture;
			pass.setViewport(0, 0, size.width, size.height, 0, 1);
		},
		set_pipeline(p) {
			pipe = handles.get(p);
			// (its variant set by the first draw: bind)
			pipe.active = null;
			dirty = true;
		},
		set_vertex_buffer: (slot, b, offset) => pass.setVertexBuffer(slot, handles.get(b), offset),
		set_texture(slot, t, s) {
			textures[slot] = t;
			samplers[slot] = s;
			dirty = cdirty = true;
		},
		set_uniforms(slot, offset, data, size) {
			ring.staging.set(host.bytes(data, size), offset);
			ring.used = Math.max(ring.used, offset + size);
			offsets[slot] = offset;
			dirty = cdirty = true;
		},
		set_index_buffer: (b, format, offset) => pass.setIndexBuffer(handles.get(b), INDEX[format], offset),
		draw(vertices, instances, first) {
			bind();
			pass.draw(vertices, instances, first, 0);
		},
		draw_indexed(count, instances, first, baseVertex) {
			bind();
			pass.drawIndexed(count, instances, first, baseVertex, 0);
		},
		pass_end() {
			pass.end();
			pass = null;
		},
		frame_end() {
			// (a readPixels waiting for a canvas's frame)
			const waiting = captures;
			captures = [];
			const pixels = waiting.length ? copy(encoder, texture, frameTarget.format) : null;
			if (ring.used) device.queue.writeBuffer(ring.buffer, 0, ring.staging, 0, Math.ceil(ring.used / 4) * 4);
			ring.used = 0;
			// (the queries the frame wrote, resolved and copied where they are read back)
			const reads = [];
			for (const q of frameQueries) {
				if (!q.reading) {
					encoder.resolveQuerySet(q.set, 0, q.count, q.resolve, 0);
					encoder.copyBufferToBuffer(q.resolve, 0, q.read, 0, q.count * 8);
					q.reading = q.written.slice();
					reads.push(q);
				}
				q.written.fill(0);
			}
			frameQueries = [];
			device.queue.submit([encoder.finish()]);
			for (const q of reads)
				q.read.mapAsync(GPUMapMode.READ).then(() => {
					const v = new BigUint64Array(q.read.getMappedRange());
					for (let k = 0; k < q.count; k++) if (q.reading[k]) q.results[k] = v[k] > 0n ? 1 : 0;
					q.read.unmap();
					q.reading = null;
				}, () => { q.reading = null; });
			pixels?.().then((px) => waiting.forEach((w) => w.resolve(px)), (e) => waiting.forEach((w) => w.reject(e)));
			encoder = null;
			submitted();
			attachment.view = attachment.resolveTarget = frameView = null;
			depthAttachment.view = null;
			texture = null;
		},
		release(h) {
			const o = handles.get(h);
			// (commands recorded and not yet submitted may use it, a frame's or a
			// compute pass's: destroyed after their submit, which WebGPU lets
			// finish with it; destroyed now, the submit failed: "used in submit
			// while destroyed", a buffer grown in the middle of a frame)
			if (encoder) doomed.push(o);
			else destroy(o);
			// (swapped out: the canvas stays configured, its last frame shown)
			if (o?.context && !host.swapping) {
				o.context.unconfigure();
				configured.delete(o.context);
			}
			handles.remove(h);
		},
	};

	// (hxmc dev: swapped out; what the program did not release, released and counted)
	host.onDispose?.(() => {
		// (what waited on a submit that will not come)
		submitted();
		let left = 0;
		const glObject = typeof WebGLObject === 'function' ? WebGLObject : null;
		for (const g of contexts) resetGL(g);
		for (let h = 1; h < handles.size(); h++) {
			const o = handles.get(h);
			if (!o) continue;
			if (typeof GPUBuffer === 'function' && (o instanceof GPUBuffer || o instanceof GPUTexture)) {
				o.destroy();
				left++;
			} else if (o.texture instanceof Object && typeof o.texture.destroy === 'function') {
				o.texture.destroy();
				o.depth?.destroy?.();
				o.msaa?.destroy?.();
				left++;
			} else if (o.context && typeof GPUCanvasContext === 'function' && o.context instanceof GPUCanvasContext) {
				o.depth?.destroy?.();
				o.msaa?.destroy?.();
				left++;
			} else if (glObject && o instanceof glObject && gl) {
				const d = o instanceof WebGLBuffer ? 'deleteBuffer' : o instanceof WebGLTexture ? 'deleteTexture' : o instanceof WebGLProgram ? 'deleteProgram'
					: o instanceof WebGLShader ? 'deleteShader' : o instanceof WebGLFramebuffer ? 'deleteFramebuffer' : o instanceof WebGLVertexArrayObject ? 'deleteVertexArray'
					: o instanceof WebGLSampler ? 'deleteSampler' : o instanceof WebGLRenderbuffer ? 'deleteRenderbuffer' : null;
				if (d) {
					gl[d](o);
					left++;
				}
			}
		}
		ring?.buffer.destroy();
		host.gfx.left = left;
		if (left > 0) console.warn(`helder.gfx: ${left} GPU objects left by the build swapped out, released`);
	});

	// a context's state as WebGL's defaults: what the next instance finds
	function resetGL(g) {
		if (g.isContextLost()) return;
		g.bindFramebuffer(g.FRAMEBUFFER, null);
		g.bindBuffer(g.ARRAY_BUFFER, null);
		g.bindBuffer(g.ELEMENT_ARRAY_BUFFER, null);
		g.bindBuffer(g.UNIFORM_BUFFER, null);
		g.bindVertexArray(null);
		g.useProgram(null);
		const units = g.getParameter(g.MAX_COMBINED_TEXTURE_IMAGE_UNITS);
		for (let i = 0; i < Math.min(units, 32); i++) {
			g.activeTexture(g.TEXTURE0 + i);
			g.bindTexture(g.TEXTURE_2D, null);
			g.bindSampler(i, null);
		}
		g.activeTexture(g.TEXTURE0);
		for (const cap of [g.BLEND, g.CULL_FACE, g.DEPTH_TEST, g.SCISSOR_TEST, g.STENCIL_TEST, g.POLYGON_OFFSET_FILL]) g.disable(cap);
		g.blendFunc(g.ONE, g.ZERO);
		g.blendEquation(g.FUNC_ADD);
		g.depthFunc(g.LESS);
		g.depthMask(true);
		g.colorMask(true, true, true, true);
		g.clearColor(0, 0, 0, 0);
		g.clearDepth(1);
		g.cullFace(g.BACK);
		g.frontFace(g.CCW);
		g.pixelStorei(g.UNPACK_ALIGNMENT, 4);
		g.pixelStorei(g.PACK_ALIGNMENT, 4);
		g.viewport(0, 0, g.drawingBufferWidth, g.drawingBufferHeight);
	}

	// WebGL2: the current context ({gl, canvas, offscreen, captures}: the
	// readPixels waiting for its next frame)
	let current = null, gl = null;
	const view = () => new DataView(host.memory().buffer);
	const get = (h) => handles.get(h);

	// the drawing buffer as RGBA8, rows top to bottom
	function read(c) {
		const g = c.gl, w = g.drawingBufferWidth, h = g.drawingBufferHeight;
		const src = new Uint8Array(w * h * 4), data = new Uint8Array(w * h * 4);
		g.pixelStorei(g.PACK_ALIGNMENT, 1);
		g.readPixels(0, 0, w, h, g.RGBA, g.UNSIGNED_BYTE, src);
		for (let y = 0; y < h; y++) data.set(src.subarray((h - 1 - y) * w * 4, (h - y) * w * 4), y * w * 4);
		return { width: w, height: h, data };
	}
	// GL's glGen*: n new objects, their handles into p
	function gen(n, p, make) {
		const v = view();
		for (let i = 0; i < n; i++) v.setInt32(p + 4 * i, handles.add(make()), true);
	}
	function del(n, p, f) {
		const v = view();
		for (let i = 0; i < n; i++) {
			const h = v.getInt32(p + 4 * i, true);
			if (h) {
				f(get(h));
				handles.remove(h);
			}
		}
	}
	// glGet*iv: INFO_LOG_LENGTH, which WebGL lacks, from the log itself
	function iv(o, pname, p, param, log) {
		const x = pname === INFO_LOG_LENGTH ? new TextEncoder().encode(log(o)).length + 1 : param(o, pname);
		view().setInt32(p, typeof x === 'boolean' ? (x ? 1 : 0) : x, true);
	}
	// glGet*InfoLog: at most size - 1 bytes and a NUL
	function infoLog(text, size, length, p) {
		const b = new TextEncoder().encode(text).subarray(0, Math.max(0, size - 1));
		host.bytes(p, b.length + 1).set([...b, 0]);
		if (length) view().setInt32(length, b.length, true);
	}

	const hxmc_gl = {
		context(canvas, width, height, antialias) {
			const offscreen = canvas === 0;
			const c = offscreen ? (typeof OffscreenCanvas === 'function' ? new OffscreenCanvas(width, height) : Object.assign(document.createElement('canvas'), { width, height })) : handles.get(canvas);
			// (a canvas: presented after each frame's task, read back at swap;
			// offscreen: nothing presents it, read back at any time)
			const g = c.getContext('webgl2', { antialias: !offscreen && !!(host.options.antialias ?? antialias), alpha: false, depth: true, preserveDrawingBuffer: offscreen });
			if (!g) return 0;
			// (RGBA16F and R32F render targets; RGBA16F alone where only half
			// floats are: some phones' WebGL2)
			if (!g.getExtension('EXT_color_buffer_float')) g.getExtension('EXT_color_buffer_half_float');
			contexts.push(g);
			if (!offscreen) c.addEventListener('webglcontextlost', () => lost('the WebGL2 context was lost'));
			host.gfx.backend = 'webgl2';
			return handles.add({ gl: g, canvas: c, offscreen, captures: [] });
		},
		make_current(h) {
			current = get(h);
			gl = current.gl;
		},
		swap(h) {
			const c = get(h), waiting = c.captures;
			if (!waiting.length) return;
			c.captures = [];
			try {
				const px = read(c);
				waiting.forEach((w) => w.resolve(px));
			} catch (e) {
				waiting.forEach((w) => w.reject(e));
			}
		},
		release(h) {
			const c = get(h);
			// (swapped out: a canvas's context stays, its last frame shown, for the next instance)
			if (!(host.swapping && !c.offscreen)) c.gl.getExtension('WEBGL_lose_context')?.loseContext();
			else contexts.splice(contexts.indexOf(c.gl), 1), resetGL(c.gl);
			if (current === c) current = gl = null;
			handles.remove(h);
		},
		extension: (h, name) => (get(h).gl.getExtension(host.string(name)) ? 1 : 0),
		glGetError: () => gl.getError(),
		glEnable: (cap) => gl.enable(cap),
		glDisable: (cap) => gl.disable(cap),
		glCullFace: (mode) => gl.cullFace(mode),
		glFrontFace: (mode) => gl.frontFace(mode),
		glViewport: (x, y, w, h) => gl.viewport(x, y, w, h),
		glClearColor: (r, g, b, a) => gl.clearColor(r, g, b, a),
		glClear: (mask) => gl.clear(mask),
		glGenBuffers: (n, p) => gen(n, p, () => gl.createBuffer()),
		glDeleteBuffers: (n, p) => del(n, p, (b) => gl.deleteBuffer(b)),
		glDeleteTextures: (n, p) => del(n, p, (t) => gl.deleteTexture(t)),
		glBindBuffer: (target, b) => gl.bindBuffer(target, get(b)),
		// (GLsizeiptr, GLintptr: Int64, a BigInt)
		glBufferData(target, size, data, usage) {
			if (data) gl.bufferData(target, host.bytes(data, Number(size)), usage);
			else gl.bufferData(target, Number(size), usage);
		},
		glBufferSubData: (target, offset, size, data) => gl.bufferSubData(target, Number(offset), host.bytes(data, Number(size))),
		glCreateShader: (type) => handles.add(gl.createShader(type)),
		// (strings: hxmc's Ptr, 8 bytes each; lengths: none, or one each, < 0 for a C string)
		glShaderSource(s, count, strings, lengths) {
			const v = view();
			let src = '';
			for (let i = 0; i < count; i++) {
				const p = v.getUint32(strings + 8 * i, true), n = lengths ? v.getInt32(lengths + 4 * i, true) : -1;
				src += n < 0 ? host.string(p) : new TextDecoder().decode(host.bytes(p, n));
			}
			gl.shaderSource(get(s), src);
		},
		glCompileShader: (s) => gl.compileShader(get(s)),
		glGetShaderiv: (s, pname, p) => iv(get(s), pname, p, (o, k) => gl.getShaderParameter(o, k), (o) => gl.getShaderInfoLog(o)),
		glGetShaderInfoLog: (s, size, length, p) => infoLog(gl.getShaderInfoLog(get(s)), size, length, p),
		glDeleteShader(s) {
			gl.deleteShader(get(s));
			handles.remove(s);
		},
		glCreateProgram: () => handles.add(gl.createProgram()),
		glAttachShader: (p, s) => gl.attachShader(get(p), get(s)),
		glLinkProgram: (p) => gl.linkProgram(get(p)),
		glGetProgramiv: (o, pname, p) => iv(get(o), pname, p, (x, k) => gl.getProgramParameter(x, k), (x) => gl.getProgramInfoLog(x)),
		glGetProgramInfoLog: (o, size, length, p) => infoLog(gl.getProgramInfoLog(get(o)), size, length, p),
		glUseProgram: (p) => gl.useProgram(get(p)),
		glDeleteProgram(p) {
			gl.deleteProgram(get(p));
			handles.remove(p);
		},
		glGenVertexArrays: (n, p) => gen(n, p, () => gl.createVertexArray()),
		glBindVertexArray: (a) => gl.bindVertexArray(get(a)),
		glEnableVertexAttribArray: (i) => gl.enableVertexAttribArray(i),
		glDisableVertexAttribArray: (i) => gl.disableVertexAttribArray(i),
		glVertexAttribPointer: (i, size, type, normalized, stride, offset) => gl.vertexAttribPointer(i, size, type, !!normalized, stride, offset),
		glVertexAttribDivisor: (i, divisor) => gl.vertexAttribDivisor(i, divisor),
		glDrawArrays: (mode, first, count) => gl.drawArrays(mode, first, count),
		glDrawArraysInstanced: (mode, first, count, instances) => gl.drawArraysInstanced(mode, first, count, instances),
		// (offset: a byte offset into the index buffer)
		glDrawElements: (mode, count, type, offset) => gl.drawElements(mode, count, type, offset),
		glDrawElementsInstanced: (mode, count, type, offset, instances) => gl.drawElementsInstanced(mode, count, type, offset, instances),
		glGetIntegerv: (pname, p) => view().setInt32(p, gl.getParameter(pname), true),
		glBindBufferRange: (target, index, b, offset, size) => gl.bindBufferRange(target, index, get(b), Number(offset), Number(size)),
		glGetUniformBlockIndex: (p, name) => gl.getUniformBlockIndex(get(p), host.string(name)) | 0,
		glUniformBlockBinding: (p, index, binding) => gl.uniformBlockBinding(get(p), index >>> 0, binding),
		// (a location: a handle, -1 none; each lookup a new one, as a program's are looked up once)
		glGetUniformLocation(p, name) {
			const l = gl.getUniformLocation(get(p), host.string(name));
			return l ? handles.add(l) : -1;
		},
		glUniform1i: (l, x) => gl.uniform1i(get(l), x),
		glUniform1f: (l, x) => gl.uniform1f(get(l), x),
		glUniform2f: (l, x, y) => gl.uniform2f(get(l), x, y),
		glBlendFuncSeparate: (a, b, c, d) => gl.blendFuncSeparate(a, b, c, d),
		glBlendEquation: (mode) => gl.blendEquation(mode),
		glDepthFunc: (f) => gl.depthFunc(f),
		glDepthMask: (flag) => gl.depthMask(!!flag),
		glClearDepthf: (d) => gl.clearDepth(d),
		glGenTextures: (n, p) => gen(n, p, () => gl.createTexture()),
		glBindTexture: (target, t) => gl.bindTexture(target, get(t)),
		glActiveTexture: (unit) => gl.activeTexture(unit),
		glTexStorage2D: (target, levels, internal, w, h) => gl.texStorage2D(target, levels, internal, w, h),
		// (pixels: w * h texels of the memory, in the view WebGL wants for the type, copied for floats: their address may be unaligned)
		glTexSubImage2D(target, level, x, y, w, h, format, type, p) {
			const n = w * h * (format === gl.RED ? 1 : format === gl.RG ? 2 : 4), size = type === gl.FLOAT ? 4 : type === gl.HALF_FLOAT ? 2 : 1;
			const b = host.bytes(p, n * size);
			gl.texSubImage2D(target, level, x, y, w, h, format, type, size === 1 ? b : new (size === 4 ? Float32Array : Uint16Array)(b.slice().buffer));
		},
		glTexStorage3D: (target, levels, internal, w, h, d) => gl.texStorage3D(target, levels, internal, w, h, d),
		glTexSubImage3D(target, level, x, y, z, w, h, d, format, type, p) {
			const n = w * h * d * (format === gl.RED ? 1 : format === gl.RG ? 2 : 4), size = type === gl.FLOAT ? 4 : type === gl.HALF_FLOAT ? 2 : 1;
			const b = host.bytes(p, n * size);
			gl.texSubImage3D(target, level, x, y, z, w, h, d, format, type, size === 1 ? b : new (size === 4 ? Float32Array : Uint16Array)(b.slice().buffer));
		},
		glFramebufferTextureLayer: (target, attachment, t, level, layer) => gl.framebufferTextureLayer(target, attachment, get(t), level, layer),
		glGenerateMipmap: (target) => gl.generateMipmap(target),
		glCompressedTexSubImage2D: (target, level, x, y, w, h, format, size, p) => gl.compressedTexSubImage2D(target, level, x, y, w, h, format, host.bytes(p, size)),
		texture_image(texture, image, levels, release) {
			const g = gl, t = get(texture);
			fill(image, release, (bitmap) => {
				if (get(texture) !== t || g.isContextLost()) return;
				// (unit 0's binding kept: the back end's units[0])
				const unit = g.getParameter(g.ACTIVE_TEXTURE);
				g.activeTexture(g.TEXTURE0);
				const was = g.getParameter(g.TEXTURE_BINDING_2D), align = g.getParameter(g.UNPACK_ALIGNMENT);
				g.bindTexture(g.TEXTURE_2D, t);
				g.pixelStorei(g.UNPACK_ALIGNMENT, 4);
				g.texSubImage2D(g.TEXTURE_2D, 0, 0, 0, g.RGBA, g.UNSIGNED_BYTE, bitmap);
				if (levels > 1) g.generateMipmap(g.TEXTURE_2D);
				g.pixelStorei(g.UNPACK_ALIGNMENT, align);
				g.bindTexture(g.TEXTURE_2D, was);
				g.activeTexture(unit);
			});
		},
		glGenFramebuffers: (n, p) => gen(n, p, () => gl.createFramebuffer()),
		glDeleteFramebuffers: (n, p) => del(n, p, (f) => gl.deleteFramebuffer(f)),
		glBindFramebuffer: (target, f) => gl.bindFramebuffer(target, get(f)),
		glFramebufferTexture2D: (target, attachment, textarget, t, level) => gl.framebufferTexture2D(target, attachment, textarget, get(t), level),
		glCheckFramebufferStatus: (target) => gl.checkFramebufferStatus(target),
		glGenRenderbuffers: (n, p) => gen(n, p, () => gl.createRenderbuffer()),
		glDeleteRenderbuffers: (n, p) => del(n, p, (r) => gl.deleteRenderbuffer(r)),
		glBindRenderbuffer: (target, r) => gl.bindRenderbuffer(target, get(r)),
		glRenderbufferStorageMultisample: (target, samples, internal, w, h) => gl.renderbufferStorageMultisample(target, samples, internal, w, h),
		glFramebufferRenderbuffer: (target, attachment, rbTarget, r) => gl.framebufferRenderbuffer(target, attachment, rbTarget, get(r)),
		glBlitFramebuffer: (x0, y0, x1, y1, dx0, dy0, dx1, dy1, mask, filter) => gl.blitFramebuffer(x0, y0, x1, y1, dx0, dy0, dx1, dy1, mask, filter),
		glGenSamplers: (n, p) => gen(n, p, () => gl.createSampler()),
		glDeleteSamplers: (n, p) => del(n, p, (s) => gl.deleteSampler(s)),
		glDeleteVertexArrays: (n, p) => del(n, p, (a) => gl.deleteVertexArray(a)),
		glSamplerParameteri: (s, pname, param) => gl.samplerParameteri(get(s), pname, param),
		glBindSampler: (unit, s) => gl.bindSampler(unit, get(s)),
		glPixelStorei: (pname, param) => gl.pixelStorei(pname, param),
		// (pixels: the memory from p on, which WebGL fills as far as it needs)
		glReadPixels: (x, y, w, h, format, type, p) => gl.readPixels(x, y, w, h, format, type, new Uint8Array(host.memory().buffer, p)),
		glFinish: () => gl.finish(),
		glFlush: () => gl.flush(),
		// (occlusion queries: a result is not available in the task that ended it, WebGL2's rule)
		glGenQueries: (n, p) => gen(n, p, () => gl.createQuery()),
		glDeleteQueries: (n, p) => del(n, p, (q) => gl.deleteQuery(q)),
		glBeginQuery: (target, q) => gl.beginQuery(target, get(q)),
		glEndQuery: (target) => gl.endQuery(target),
		glGetQueryObjectuiv: (q, pname, p) => view().setInt32(p, Number(gl.getQueryParameter(get(q), pname)) | 0, true),
		// (GL ES 3.1's: none on WebGL2, whose device has no compute; never called)
		...Object.fromEntries(['glMapBufferRange', 'glUnmapBuffer', 'glDispatchCompute', 'glDispatchComputeIndirect', 'glMemoryBarrier', 'glBindBufferBase', 'glBindImageTexture',
			'glDrawArraysIndirect', 'glDrawElementsIndirect'].map((n) => [n, () => { throw new Error('helder.gfx: ' + n + ': WebGL2 has no compute'); }])),
	};
	return { hxmc_gfx, hxmc_gl, helder_image };
}
