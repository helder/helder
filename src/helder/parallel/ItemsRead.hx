package helder.parallel;

#if !macro
import helder.gfx.Buffer;

// read(items)'s coroutine (Parallel.hx): an Items' values the CPU's,
// awaited. WebGPU's read back is asynchronous: started, polled on the
// loop's turns (a turn comes when it is done), taken into the Items' bytes;
// elsewhere a read back at once. A module of its own, typed only where a
// program awaits one: it has helder.async.
@:noCompletion @:hxmc.unsafe(gc)
class ItemsRead {
	@:coroutine public static function read(d:ItemsData):Void {
		if (d.state & ItemsData.CPU != 0) return;
		var r = GpuRunner.current;
		if (r == null) throw new haxe.Exception("Items: its values are a GPU's, and no Parallel.device");
		#if (hxmc.target == "wasm32-wasi")
		if (r.device.backend == WebGPU) {
			var b:Buffer = cast d.buffer;
			var h = helder.gfx.webgpu.WebGPU.read_start(b.id(), d.size);
			helder.async.http.web.Http.until(() -> helder.gfx.webgpu.WebGPU.read_state(h) != 0, () -> {});
			var ok = helder.gfx.webgpu.WebGPU.read_state(h) == 1;
			helder.gfx.webgpu.WebGPU.read_take(h, d.bytes(), d.size);
			if (!ok) throw new haxe.Exception("read(items): WebGPU's read back failed");
			d.state |= ItemsData.CPU;
			return;
		}
		#end
		r.fetch(d);
	}
}
#end
