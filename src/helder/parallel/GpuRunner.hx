package helder.parallel;

#if !macro
import haxe.io.Bytes;
import helder.gfx.Buffer;
import helder.gfx.Device;
import hxmc.unsafe.BytesPtr;
import hxmc.unsafe.Mem;
import hxmc.unsafe.Ptr;

// helder.parallel's side of the GPU: a site's Gpu form dispatched
// (GpuForm), Items' buffers made, uploaded and read back, each only when
// the other side reads. Reached from Parallel.device's setter and
// Items.buffer(device) alone (the dispatches and Items call it through
// Parallel's hooks), so a program without a GPU has none of helder.gfx.
//
// A dispatch is a compute pass outside a frame (Device.computeEncoder: its
// work before the next frame's passes, or between a frame's passes):
// ceil(n / 64) workgroups of 64, 65535 a row (the stage's index is x plus
// y times a row's). Items' buffers are storage buffers, vertex and
// instance buffers too (BufferUsage.Storage), of their padded size. Where
// the device shares its buffers' memory with the CPU (Metal, the CPU back
// end: Device.memory) an Items' bytes become the buffer's: no copies, a
// read after a dispatch waits for it. Elsewhere a copy each way through a
// scratch block. WebGPU reads back asynchronously only: items[i] there
// throws until read(items) is awaited (ItemsRead).
@:noCompletion @:hxmc.unsafe(gc)
class GpuRunner {
	public static var current(default, null):Null<GpuRunner> = null;

	public final device:Device;
	// (tests: the stages' emulated subgroups where the device has its own)
	@:noCompletion public static var emulate = false;
	// whether it dispatches (Device.has(Compute)): without, Items' buffers are vertex buffers, uploaded
	public final compute:Bool;

	var scratch = Bytes.alloc(64);
	final none = Bytes.alloc(0);
	// (buffers of Items collected: destroyed at the next dispatch, on its thread)
	final dropped:Array<Buffer> = [];

	function new(device:Device) {
		this.device = device;
		compute = device.has(Compute);
	}

	// (Parallel.device's setter: its runner, dispatching where the device has compute)
	public static function use(d:Null<Device>):Bool {
		current = d == null ? null : new GpuRunner(d);
		var r = current;
		Parallel.hooks(r == null || !r.compute ? null : r.dispatch, r == null || !r.compute ? null : r.reduce, r == null ? null : r.fetch, r == null ? null : r.release);
		return r != null && r.compute;
	}

	static function runner(d:Device):GpuRunner {
		if (current == null || current.device != d) Parallel.device = d;
		return current;
	}

	// Items.buffer(device): its buffer, its values there, drawn from
	public static function drawn(d:ItemsData, device:Device):Buffer {
		var r = runner(device);
		r.upload(d);
		d.drawn = true;
		return cast d.buffer;
	}

	// (the CPU's values on the GPU: the buffer made, or written where stale)
	function upload(d:ItemsData) {
		drop();
		if (d.device != null && d.device != device) throw new haxe.Exception("Items: its buffer is another device's");
		if (d.buffer == null) {
			d.cpu();
			var b = copy(d);
			var buf = device.createBuffer({size: d.size == 0 ? 16 : d.size, usage: compute ? Storage : Vertex, data: b});
			d.buffer = buf;
			d.device = device;
			var shared = device.memory(buf);
			if (!shared.isNull()) d.adopt(shared);
			d.state = ItemsData.CPU | ItemsData.GPU;
			return;
		}
		if (d.state & ItemsData.GPU != 0) return;
		if (d.size > 0) device.writeBuffer(cast d.buffer, 0, copy(d), 0, d.size);
		d.state |= ItemsData.GPU;
	}

	// (the CPU's bytes in a block the size of the buffer: scratch, grown)
	function copy(d:ItemsData):Bytes {
		var n = d.size == 0 ? 16 : d.size;
		if (scratch.length < n) scratch = Bytes.alloc(n + (n >> 2));
		if (d.size > 0) BytesPtr.copyIn(scratch, 0, d.bytes(), d.size);
		return scratch.length == n ? scratch : scratch.sub(0, n);
	}

	// (the GPU's values on the CPU: waited for where shared, else read back)
	@:allow(helder.parallel) function fetch(d:ItemsData) {
		if (d.buffer == null) {
			d.state |= ItemsData.CPU;
			return;
		}
		if (device.backend == WebGPU) throw new haxe.Exception("Items: its values are the GPU's, and WebGPU reads back asynchronously: await items.read() in a coroutine first");
		var buf:Buffer = cast d.buffer;
		if (d.shared) device.readBuffer(buf, 0, none, 0, 0) else if (d.size > 0) {
			if (scratch.length < d.size) scratch = Bytes.alloc(d.size + (d.size >> 2));
			device.readBuffer(buf, 0, scratch, 0, d.size);
			hxmc.unsafe.LibC.memcpy(d.bytes(), BytesPtr.of(scratch, 0, d.size), d.size);
		}
		d.state |= ItemsData.CPU;
	}

	// (an Items disposed: its buffer destroyed, at the next dispatch where it is collected)
	function release(d:ItemsData, now:Bool) {
		var b:Buffer = cast d.buffer;
		d.buffer = null;
		if (now) device.destroyBuffer(b) else dropped.push(b);
	}

	function drop()
		while (dropped.length > 0)
			device.destroyBuffer(dropped.pop());

	// (the form's pipeline on this device, made once)
	function pipeline(form:GpuForm):Any {
		if (form.device != device || form.emulated != emulate) {
			form.pipeline = device.createComputePipeline({program: emulate ? helder.gfx.ShaderCode.emulatedForm(form.code) : form.code});
			form.device = device;
			form.emulated = emulate;
		}
		return form.pipeline;
	}

	// (the context's captured values into the form's uniform block, the count n)
	function block(form:GpuForm, n:Int, ctx:Ptr):Bytes {
		var b = form.bytes;
		for (k in 0...form.kinds.length) {
			var o = form.to[k], c = form.from[k];
			switch form.kinds[k] {
				case GpuForm.KINT | GpuForm.KBOOL: b.setInt32(o, Mem.getI32(ctx, c));
				case GpuForm.KFLOAT: b.setFloat(o, Mem.getF64(ctx, c));
				case GpuForm.KMAT:
					for (col in 0...4)
						for (row in 0...4)
							b.setFloat(o + 16 * col + 4 * row, Mem.getF64(ctx, c + 32 * col + 8 * row));
				case kind:
					for (j in 0...kind - GpuForm.KVEC)
						b.setFloat(o + 4 * j, Mem.getF64(ctx, c + 8 * j));
			}
		}
		b.setInt32(form.count, n);
		return b;
	}

	// (groups workgroups of form, 65535 a row, over buffers by its slots, in the pass begun)
	function run(enc:helder.gfx.Encoder, form:GpuForm, b:Bytes, groups:Int, buffers:Array<Buffer>) {
		enc.setComputePipeline(cast pipeline(form));
		enc.setUniforms(form.binding, b);
		for (k in 0...buffers.length)
			enc.setStorage(form.slots[k], buffers[k]);
		enc.dispatch(groups > 65535 ? 65535 : groups, Std.int((groups + 65534) / 65535));
	}

	final bound:Array<Buffer> = [];

	// a site's Gpu form over n items: the context's captured values into its
	// uniform block, the Items' buffers bound, the workgroups dispatched
	function dispatch(form:GpuForm, n:Int, ctx:Ptr, items:Array<ItemsData>) {
		var b = block(form, n, ctx);
		for (d in items)
			upload(d);
		var enc = device.computeEncoder();
		enc.beginCompute();
		run(enc, form, b, Std.int((n + 63) / 64), buffers(items));
		enc.endCompute();
		wrote(form, items);
	}

	function buffers(items:Array<ItemsData>):Array<Buffer> {
		bound.resize(0);
		for (d in items)
			bound.push(cast d.buffer);
		return bound;
	}

	function wrote(form:GpuForm, items:Array<ItemsData>)
		for (k in 0...items.length)
			if (form.writes[k]) {
				items[k].state = ItemsData.GPU;
				items[k].byGpu = true;
			}

	// (the partials' buffers, two in turn: grown, never shrunk)
	final parts:Array<Null<Buffer>> = [null, null];
	final sizes = [0, 0];
	final value = Bytes.alloc(16);

	function part(k:Int, bytes:Int):Buffer {
		if (sizes[k] < bytes) {
			if (parts[k] != null) device.destroyBuffer(parts[k]);
			sizes[k] = bytes + (bytes >> 2);
			parts[k] = device.createBuffer({size: sizes[k], usage: Storage});
		}
		return parts[k];
	}

	// a reduction's Gpu form over n items: each workgroup's partial (of
	// SPAN items), those reduced by form.next until one is left, in one
	// compute pass (a dispatch sees what the ones before wrote), read back
	// (waited for) into the context where its identity was
	function reduce(form:GpuForm, n:Int, ctx:Ptr, items:Array<ItemsData>) {
		if (device.backend == WebGPU) throw new haxe.Exception("helder.parallel: a reduction's Gpu form reads its value back, and WebGPU reads back asynchronously: await read(items) in a coroutine and reduce on the CPU");
		var b = block(form, n, ctx);
		for (d in items)
			upload(d);
		inline function groups(n:Int):Int
			return Std.int((n + SPAN - 1) / SPAN);
		// (a row's last workgroups past the count write partials too: room for them)
		inline function room(g:Int):Int
			return (g > 65535 ? Std.int((g + 65534) / 65535) * 65535 : g) * form.stride;
		var m = groups(n), at = 0;
		var bs = buffers(items);
		bs.push(part(0, room(m)));
		var enc = device.computeEncoder();
		enc.beginCompute();
		run(enc, form, b, m, bs);
		var next = form.next;
		while (m > 1) {
			var g = groups(m);
			var src = parts[at], dst = part(1 - at, room(g));
			b.setInt32(form.count, m);
			bound.resize(0);
			bound.push(src);
			bound.push(dst);
			run(enc, next, b, g, bound);
			at = 1 - at;
			m = g;
		}
		enc.endCompute();
		wrote(form, items);
		device.readBuffer(parts[at], 0, value, 0, form.stride);
		var o = form.from[form.from.length - 1];
		switch form.value {
			case GpuForm.KINT: Mem.setI32(ctx, o, value.getInt32(0));
			case kind:
				for (j in 0...(kind == GpuForm.KFLOAT ? 1 : kind - GpuForm.KVEC))
					Mem.setF64(ctx, o + 8 * j, value.getFloat(4 * j));
		}
	}

	// (a reduction workgroup's items: ParallelMacro's SPAN)
	static inline var SPAN = 2048;
}
#end
