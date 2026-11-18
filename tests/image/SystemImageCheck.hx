import haxe.io.Bytes;
import helder.asset.Asset;
import helder.async.Async;
import helder.image.Image;
import helder.image.ImageJobs;

// helder.image's system decoders (SystemDecoder: iOS's ImageIO, Android's
// AImageDecoder; CI's ios-simulator and android jobs: tests/pack/ios.sh,
// android.sh): helder's cases decoded on the loop's thread (Image.decode,
// its pixels when read) and as a job (ImageJobs.decode), against the
// pixels png-cases.mjs, jpeg-cases.mjs and webp-cases.mjs wrote, compared
// premultiplied (what is uploaded): PNGs (helder's decoder) and lossless
// WebP but for the premultiplication's rounding (Android's: a level), JPEG and lossy WebP within a decoder's rounding on average
// (the system's chroma upsampling is not libjpeg's: a sharp colour edge of
// a 4:2:0 file's differs most); then a hundred photos through the
// pipeline, their pixels never on the collected heap nor kept. Lines end
// with "images: ... ok" or FAILED.
//   helder run tests/image/SystemImageCheck.hx --target ios -d <simulator>
//   helder run tests/image/SystemImageCheck.hx --target android
class SystemImageCheck {
	static var failed = 0;
	static var checks = 0;

	static function main() {
		Async.main(_ -> {
			var cases = [
				{file: Asset.bytes("png/rgba8.png"), want: Asset.bytes("png/rgba8.rgba"), lossy: false},
				{file: Asset.bytes("png/rgba8-interlaced.png"), want: Asset.bytes("png/rgba8-interlaced.rgba"), lossy: false},
				{file: Asset.bytes("png/rgba16.png"), want: Asset.bytes("png/rgba16.rgba"), lossy: false},
				{file: Asset.bytes("png/greya8.png"), want: Asset.bytes("png/greya8.rgba"), lossy: false},
				{file: Asset.bytes("png/grey16.png"), want: Asset.bytes("png/grey16.rgba"), lossy: false},
				{file: Asset.bytes("png/palette4.png"), want: Asset.bytes("png/palette4.rgba"), lossy: false},
				{file: Asset.bytes("png/rgb8-key.png"), want: Asset.bytes("png/rgb8-key.rgba"), lossy: false},
				{file: Asset.bytes("jpeg/q75-420.jpg"), want: Asset.bytes("jpeg/q75-420.rgba"), lossy: true},
				{file: Asset.bytes("jpeg/q90-444.jpg"), want: Asset.bytes("jpeg/q90-444.rgba"), lossy: true},
				{file: Asset.bytes("jpeg/progressive-420.jpg"), want: Asset.bytes("jpeg/progressive-420.rgba"), lossy: true},
				{file: Asset.bytes("jpeg/grey.jpg"), want: Asset.bytes("jpeg/grey.rgba"), lossy: true},
				{file: Asset.bytes("jpeg/restart.jpg"), want: Asset.bytes("jpeg/restart.rgba"), lossy: true},
				{file: Asset.bytes("jpeg/orient6.jpg"), want: Asset.bytes("jpeg/orient6.rgba"), lossy: true},
				{file: Asset.bytes("webp/lossless-alpha.webp"), want: Asset.bytes("webp/lossless-alpha.rgba"), lossy: false},
				{file: Asset.bytes("webp/lossy-q90.webp"), want: Asset.bytes("webp/lossy-q90.rgba"), lossy: true},
			];
			for (c in cases) {
				var file = c.file.load(), want = c.want.load(), name = c.file.key;
				var image = Image.decode(file);
				compare('$name, read', image.width, image.height, image.pixels, want, c.lossy);
				var job = ImageJobs.decode(file);
				job.premultiplied(pre -> compare('$name, a job\'s, premultiplied', job.width, job.height, pre, want, c.lossy, true));
				job.uploaded();
				check('$name: dropped once uploaded', !job.hasPixels);
				compare('$name, a job\'s, decoded again', job.width, job.height, job.pixels, want, c.lossy);
			}
			budget();
			var e = try {
				Image.decode(Bytes.ofString("not an image")).pixels;
				null;
			} catch (e:helder.image.ImageError) e;
			check("not an image: an ImageError", e != null);
			Sys.println(failed == 0 ? 'images: $checks checks ok' : 'images: $failed of $checks checks FAILED');
		});
	}

	// a hundred photos of 1024x1024 decoded as jobs, uploaded and dropped, as a
	// shop's list scrolls: their pixels (400 MB in all) never on the
	// collected heap, nor kept after (the process's footprint as it was)
	@:coroutine static function budget() {
		var n = 1024, px = Bytes.alloc(n * n * 4);
		for (i in 0...n * n) {
			px.set(4 * i, i % n & 255);
			px.set(4 * i + 1, Std.int(i / n) & 255);
			px.set(4 * i + 2, (i * 7) & 255);
			px.set(4 * i + 3, 255);
		}
		var photo = helder.image.JpegEncoder.encode(px, n, n, 80);
		px = null;
		var heap = hxmc.GcStats.bytesAllocated(), footprint = Footprint.now();
		for (i in 0...100) {
			var image = ImageJobs.decode(photo);
			image.premultiplied(_ -> {});
			image.uploaded();
		}
		var mb = (b:Float) -> Math.round(b / 1048576);
		var allocated = hxmc.GcStats.bytesAllocated() - heap, grew = Footprint.now() - footprint;
		check("a hundred photos: their pixels off the heap", allocated < 16 * 1048576, '${mb(allocated)} MB allocated');
		check("a hundred photos: their pixels freed", grew < 32 * 1048576, 'the footprint ${mb(grew)} MB larger');
	}

	static function check(what:String, ok:Bool, ?detail:String) {
		checks++;
		if (!ok) {
			failed++;
			Sys.println('images: FAIL: $what' + (detail == null ? "" : ": " + detail));
		}
	}

	// (compared premultiplied: a straight colour under a low alpha is a guess either way)
	static function compare(what:String, w:Int, h:Int, got:Bytes, want:Bytes, lossy:Bool, pre = false) {
		if (got.length != want.length) return check(what, false, '${w}x$h: ${got.length} bytes, not ${want.length}');
		var a = pre ? got : premultiply(got), b = premultiply(want), max = 0, at = 0, sum = 0.0;
		for (i in 0...a.length) {
			var d = a.get(i) - b.get(i);
			if (d < 0) d = -d;
			sum += d;
			if (d > max) {
				max = d;
				at = i >> 2;
			}
		}
		var px = (b:Bytes, k:Int) -> [for (c in 0...4) b.get(4 * k + c)].join(",");
		var mean = sum / a.length;
		check(what, lossy ? mean <= 2.5 : max <= 1, 'off by $max (mean ${Math.round(mean * 100) / 100}), pixel ${at % w},${Std.int(at / w)}: ${px(a, at)}, not ${px(b, at)}');
	}

	static function premultiply(px:Bytes):Bytes {
		var out = Bytes.alloc(px.length);
		for (k in 0...px.length >> 2) {
			var al = px.get(4 * k + 3);
			for (c in 0...3)
				out.set(4 * k + c, Std.int((px.get(4 * k + c) * al + 127) / 255));
			out.set(4 * k + 3, al);
		}
		return out;
	}
}

// (the process's memory as the system counts it: Apple's phys_footprint,
// what iOS ends an app for, rusage_info_v2's after its uuid and seven
// counters; Linux's and Android's resident set)
@:hxmc.c private extern class Rusage {
	static function getpid():Int;
	static function proc_pid_rusage(pid:Int, flavor:Int, buffer:hxmc.unsafe.Ptr):Int;
}

private class Footprint {
	@:hxmc.unsafe(gc) public static function now():Float {
		if (hxmc.Platform.os() == 1) {
			var buf = hxmc.unsafe.IoBuffer.alloc(256);
			Rusage.proc_pid_rusage(Rusage.getpid(), 2, buf.ptr);
			var f:Float = cast hxmc.unsafe.Mem.getI64(buf.ptr, 72);
			buf.free();
			return f;
		}
		return Std.parseFloat(sys.io.File.getContent("/proc/self/statm").split(" ")[1]) * 4096;
	}
}
