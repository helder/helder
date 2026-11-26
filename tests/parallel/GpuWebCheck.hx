import helder.async.Async;
import helder.gfx.Device;
import helder.os.App;
import helder.os.Window;
import helder.parallel.Items;
import helder.parallel.On;
import helder.parallel.Parallel;

// helder.parallel's Gpu form on WebGPU in headless Chromium (the
// gfx-compute-web lane, tests/parallel/browser.mjs): a dispatch's results
// read back by awaiting read(items) (WebGPU reads back asynchronously
// only: items[i] before it throws), against the Simd form; "GpuWebCheck:
// done <failures>" ends it.
class GpuWebCheck {
	static var failed = 0;

	static function check(what:String, ok:Bool, detail = "") {
		Sys.println('GpuWebCheck: ${ok ? "ok" : "FAIL"}: $what' + (detail == "" ? "" : ' ($detail)'));
		if (!ok) failed++;
	}

	static function main() {
		var window = new Window({title: "GpuWebCheck", width: 64, height: 64});
		var device = Device.create(window.surface);
		Async.launch(_ -> {
			if (!device.has(Compute)) {
				Sys.println('GpuWebCheck: no compute (${device.backend})');
				Sys.println("GpuWebCheck: done 0");
				App.quit();
				return;
			}
			Parallel.device = device;
			var n = 3001, a = new Items<Float>(n);
			for (i in 0...n)
				a[i] = Math.sin(i) * 100;
			var g = new Items<Float>(n), c = new Items<Float>(n);
			each(n, i -> g[i] = Math.sqrt(Math.abs(a[i])) * 3 + a[(i + 1) % n], Gpu);
			each(n, i -> c[i] = Math.sqrt(Math.abs(a[i])) * 3 + a[(i + 1) % n], Simd);
			var thrown = try {
				g[0];
				false;
			} catch (_:haxe.Exception) true;
			check("items[i] before read(): thrown", thrown);
			read(g);
			var worst = 0.0;
			for (i in 0...n)
				worst = Math.max(worst, Math.abs(g[i] - c[i]) / Math.max(1, Math.abs(c[i])));
			check("each on the GPU, read back", worst <= 1e-5, 'at most $worst apart');
			each(n, i -> g[i] += 1);
			read(g);
			check("Auto on the GPU where it is", Math.abs(g[7] - c[7] - 1) <= 1e-4, '${g[7]} and ${c[7]}');
			Sys.println('GpuWebCheck: done $failed');
			App.quit();
		});
		App.run(() -> {}, e -> switch e.kind {
			case Close: window.close();
			case _:
		});
	}
}
