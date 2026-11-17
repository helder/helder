package helder.image;

#if (target.name == "hxmc")
import haxe.io.Bytes;
import helder.jobs.Job;
import helder.jobs.JobError;
import helder.jobs.Jobs;
import hxmc.Buffer;
import hxmc.ReadOnlySpan;
import hxmc.Span;
import hxmc.unsafe.UInt8;

// Images decoded as GC-free jobs (helder.jobs: natively on a pool's thread
// in a safe region, in a browser on a worker), so that a large one leaves
// the frames alone: a PNG by PngCore, the decoder PngDecoder runs on the
// calling thread; a JPEG, a GIF and a WebP by Image.decode on the calling
// thread, for now. The rest of helder.image depends on nothing; this
// module on helder.jobs.
//
//   var image = ImageJobs.decode(bytes);                  // in a coroutine
//   var p = ImageJobs.pixels(file);                       // file: an hxmc.Buffer; {width, height, rgba: a Buffer to upload and close}
class ImageJobs {
	// the PNG job: its input the file, its output the RGBA8 pixels (the
	// size: the header's, PngCore.info)
	@:hxmc.kernel @:hxmc.callback public static function png(job:Job):Int {
		var input = job.input(), info:Span<UInt8> = Span.stack(PngCore.INFO);
		var e = PngCore.info(input, info);
		if (e != 0) return e;
		var w = info.getI32(PngCore.WIDTH), h = info.getI32(PngCore.HEIGHT);
		var len = PngCore.bufferLength(info, w, h), out = job.output(len);
		if (out.length < len) return PngCore.ERR_MEMORY;
		e = PngCore.decode(input, info, out);
		if (e != 0) return e;
		job.truncate(w * h * 4);
		return 0;
	}

	// an image file decoded off the loop's thread: a PNG as a job (PngCore),
	// on iOS and Android 11 and later any other format the system reads by
	// the system (SystemDecoder, a job's), elsewhere the rest by Image.decode; the pixels off the heap,
	// the image's (freed once uploaded: decoded again from the file if drawn
	// again; on WebAssembly, which frees no native memory, kept for good as
	// a Bytes: keep)
	@:coroutine public static function decode(bytes:Bytes):Image {
		#if (hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64" || hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
		if (!Image.isPng(bytes) && SystemDecoder.available()) {
			var file = new Buffer(bytes.length);
			file.blitFromBytes(0, bytes, 0, bytes.length);
			var d = try Jobs.job(ImageJobs.system).run(file) catch (j:JobError) throw ImageError.corrupt(j.message);
			var image = Image.ofHeld(d.width, d.height, d.pixels, true);
			@:privateAccess image.source = {bytes: bytes, type: Image.typeOf(bytes)};
			return image;
		}
		#end
		if (!Image.isPng(bytes)) return Image.decode(bytes);
		var file = new Buffer(bytes.length);
		file.blitFromBytes(0, bytes, 0, bytes.length);
		var p = try pixels(file) catch (j:JobError) throw PngCore.error(j.code, Bytes.alloc(PngCore.INFO));
		var image = #if (hxmc.target == "wasm32-wasi") new Image(p.width, p.height, keep(p.rgba)) #else Image.ofHeld(p.width, p.height, p.rgba, false) #end;
		@:privateAccess image.source = {bytes: bytes, type: "png"};
		return image;
	}

	#if (hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64" || hxmc.target == "android-arm64" || hxmc.target == "android-x86_64")
	// the system's decode as a job (a GC job: its decoding and drawing in a
	// safe region, so collections never wait for it)
	@:hxmc.unsafe(gc) static function system(file:Buffer):{width:Int, height:Int, pixels:Buffer} {
		var io = file.detach();
		var d = try SystemDecoder.decode(io.ptr, io.length) catch (e:Dynamic) {
			io.free();
			throw e;
		}
		io.free();
		return {width: d.width, height: d.height, pixels: Buffer.adopt(d.pixels)};
	}
	#end

	// a PNG file's pixels (the file moved into the job): RGBA8, rows top to
	// bottom, straight alpha, in a Buffer the caller closes; its header's
	// errors and ImageLimits' thrown here (ImageError), the data's as a
	// JobError (PngCore's code, PngDecoder's message; decode: an ImageError)
	@:coroutine public static function pixels(file:Buffer):{width:Int, height:Int, rgba:Buffer} {
		var info = Bytes.alloc(PngCore.INFO);
		var e = PngCore.info(ReadOnlySpan.ofBuffer(file), Span.ofBytes(info));
		var w = info.getInt32(PngCore.WIDTH), h = info.getInt32(PngCore.HEIGHT);
		if (e == 0) try ImageLimits.check("PngDecoder", w, h, 0, PngCore.bufferLength(ReadOnlySpan.ofBytes(info), w, h)) catch (x:ImageError) {
			file.close();
			throw x;
		}
		if (e != 0) {
			file.close();
			throw PngCore.error(e, info);
		}
		var rgba = try Jobs.job(ImageJobs.png).run(file) catch (j:JobError) {
			throw new JobError(j.code, PngCore.message(j.code, Bytes.alloc(PngCore.INFO)));
		}
		return {width: w, height: h, rgba: rgba};
	}

	// pixels kept for good as a Bytes over their memory (not copied; the
	// Buffer closed): an Image's, which no collector frees
	@:hxmc.unsafe(gc) public static function keep(rgba:Buffer):Bytes
		return rgba.detach().view();
}
#end
