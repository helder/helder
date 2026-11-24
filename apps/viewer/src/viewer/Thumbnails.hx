package viewer;

import haxe.io.Bytes;
import helder.async.Async;
import helder.async.Task;
import helder.image.*;
import helder.jobs.Jobs;
#if (hxmc.target != "wasm32-wasi")
import helder.os.SystemImages;
import sys.io.File;
import sys.thread.Mutex;
#end

typedef ThumbRequest = {
	path:String,
	size:Float,
	mtime:Float,
	side:Int,
	owner:Int
}

private typedef ThumbWork = {
	request:ThumbRequest,
	ticket:Int,
	priority:Int,
	slot:Int,
	done:Null<Image>->Void
}

private typedef ThumbPixels = {
	width:Int,
	height:Int,
	rgba:Bytes
}

typedef ThumbResult = {
	width:Int,
	height:Int,
	pixels:Null<hxmc.Buffer>,
	cold:Bool
}

// Requests and callbacks belong to the caller's loop. A heap keeps the
// nearest requests first (ties in the order asked for); the jobs' pool has
// its own limit, so the viewer's prefetch can go on independently. On the
// web there is no cache on disk (Tiles keeps the last ones in memory): a
// file's bytes are read through the browser's files on the page, its
// thumbnail made from them on a worker (a photo's, a PNG's, a GIF's, a
// WebP's, a PDF's first page; no video's).
class Thumbnails {
	public static inline var SIDE = 256;
	static inline var MIN_CACHE_SIZE = 64 << 10;
	static inline var JPEG_PREFIX = 256 << 10;
	static inline var RAW_PREFIX = 512 << 10;
	static inline var RAW_LIMIT = 4 << 20;

	#if (hxmc.target == "wasm32-wasi")
	final files:WebFiles;
	final owner = 0;
	#else
	// (a job gets the cache by ID: the native workers share its mutex and
	// file handles; the job's argument itself is copied across by Jobs)
	static final owners = new Map<Int, ThumbCache>();
	static final ownerLock = new Mutex();
	static var nextOwner = 1;

	final cache:ThumbCache;
	final owner:Int;
	var flushTask:Null<Task<Void>>;
	#end
	final limit:Int;
	final pending:Array<ThumbWork> = [];
	final tickets = new Map<Int, ThumbWork>();
	var nextTicket = 1;
	var active = 0;
	var posted = false;
	var closed = false;

	// Source decode attempts, including ones that could not make a thumbnail.
	public var sourceDecodes(default, null) = 0;

	#if (hxmc.target == "wasm32-wasi")
	public function new(files:WebFiles) {
		this.files = files;
		limit = 2;
	}

	// what a file is asked for by: its path in the browser's files
	public function of(files:Files, path:String):Null<String>
		return path;
	#else
	public function new(?cache:ThumbCache, ?concurrency:Int) {
		this.cache = cache ?? new ThumbCache();
		var max = Std.int(Math.max(2, helder.jobs.Pool.Cores.count() >> 1));
		limit = concurrency == null ? max : Std.int(Math.min(max, Math.max(1, concurrency)));
		ownerLock.acquire();
		owner = nextOwner++;
		owners.set(owner, this.cache);
		ownerLock.release();
		if (!this.cache.readOnly) flushTask = Async.launch(_ -> {
			while (!closed) {
				Async.delay(5);
				Jobs.job(flushCache).run(owner);
			}
		});
	}

	// what a file is asked for by: its path on disk (none: no thumbnail)
	public function of(files:Files, path:String):Null<String>
		return files.localPath(path);
	#end

	public function request(path:String, size:Float, mtime:Float, side = SIDE, priority:Int, done:Null<Image>->Void):Int {
		var id = nextTicket++;
		if (closed) return id;
		var w = {
			request: {path: path, size: size, mtime: mtime, side: side > 0 ? side : SIDE, owner: owner},
			ticket: id, priority: priority, slot: pending.length, done: done
		};
		tickets.set(id, w);
		pending.push(w);
		up(w.slot);
		schedule();
		return id;
	}

	public function cancel(ticket:Int) {
		var w = tickets.get(ticket);
		if (w == null) return;
		tickets.remove(ticket);
		if (w.slot >= 0) remove(w.slot);
		// (a running decoder still counts until it returns; its pixels are
		// released there and its callback is skipped)
	}

	public function reprioritize(ticket:Int, priority:Int) {
		var w = tickets.get(ticket);
		if (w == null || w.slot < 0) return;
		var old = w.priority;
		w.priority = priority;
		if (priority < old) up(w.slot) else down(w.slot);
	}

	public function close() {
		if (closed) return;
		closed = true;
		pending.resize(0);
		tickets.clear();
		#if (hxmc.target != "wasm32-wasi")
		if (flushTask != null) flushTask.cancel();
		flushTask = null;
		ownerLock.acquire();
		owners.remove(owner);
		ownerLock.release();
		cache.close();
		#end
	}

	function schedule() {
		if (posted || closed || active >= limit || pending.length == 0) return;
		posted = true;
		Async.launch(_ -> pump());
	}

	function pump() {
		posted = false;
		while (!closed && active < limit && pending.length > 0) {
			var w = remove(0);
			active++;
			launch(w);
		}
	}

	function launch(w:ThumbWork) {
		#if (hxmc.target == "wasm32-wasi")
		var files = files;
		var job = Async.launch(_ -> {
			var b = try files.bytes(w.request.path) catch (_:Dynamic) null;
			b == null ? null : Decode.onPage(b) ? made({request: w.request, bytes: b}) : Jobs.job(made).run({request: w.request, bytes: b});
		});
		#else
		var job = Async.launch(_ -> Jobs.job(work).run(w.request));
		#end
		job.onCompletion((r, _) -> {
			active--;
			if (r != null && r.cold) sourceDecodes++;
			var wanted = tickets.remove(w.ticket);
			var pixels = r == null ? null : r.pixels;
			schedule();
			if (wanted) w.done(pixels == null ? null : Image.ofHeld(r.width, r.height, pixels, false));
			else if (pixels != null) pixels.close();
		});
	}

	static inline function before(a:ThumbWork, b:ThumbWork):Bool
		return a.priority < b.priority || (a.priority == b.priority && a.ticket < b.ticket);

	function swap(a:Int, b:Int) {
		var x = pending[a], y = pending[b];
		pending[a] = y;
		pending[b] = x;
		x.slot = b;
		y.slot = a;
	}

	function up(i:Int) {
		while (i > 0) {
			var parent = (i - 1) >> 1;
			if (!before(pending[i], pending[parent])) break;
			swap(i, parent);
			i = parent;
		}
	}

	function down(i:Int) {
		while (2 * i + 1 < pending.length) {
			var child = 2 * i + 1, right = child + 1;
			if (right < pending.length && before(pending[right], pending[child])) child = right;
			if (!before(pending[child], pending[i])) break;
			swap(i, child);
			i = child;
		}
	}

	function remove(i:Int):ThumbWork {
		var first = pending[i], last = pending.pop();
		first.slot = -1;
		if (i < pending.length) {
			pending[i] = last;
			last.slot = i;
			if (i > 0 && before(last, pending[(i - 1) >> 1])) up(i) else down(i);
		}
		return first;
	}

	#if (hxmc.target == "wasm32-wasi")
	// (the web's job: the file's bytes read already)
	static function made(input:{request:ThumbRequest, bytes:Bytes}):ThumbResult {
		var b = input.bytes, req = input.request, mem = ImageMemory.offHeapMemory();
		try {
			var d = source(req.path, b.length, req.side, mem, (at, n) -> b.sub(at, Std.int(Math.min(n, b.length - at))));
			if (d != null) {
				d = fit(d, req.side, mem);
				var pixels = mem.take(d.rgba);
				mem.free();
				return {width: d.width, height: d.height, pixels: pixels, cold: true};
			}
		} catch (_:Dynamic) {}
		mem.free();
		return {width: 0, height: 0, pixels: null, cold: true};
	}
	#else
	static function cacheOf(owner:Int):Null<ThumbCache> {
		ownerLock.acquire();
		var cache = owners.get(owner);
		ownerLock.release();
		return cache;
	}

	static function flushCache(owner:Int)
		cacheOf(owner)?.flush();

	static function work(req:ThumbRequest):ThumbResult {
		var cache = req.size >= MIN_CACHE_SIZE || !cheap(req.path) ? cacheOf(req.owner) : null;
		var key = cache == null ? haxe.Int64.ofInt(0) : ThumbCache.key(req.path, req.size, req.mtime, req.side);
		var hit = cache == null ? null : cache.get(key);
		if (hit != null && hit.bytes == null) return {width: 0, height: 0, pixels: null, cold: false};
		var mem = ImageMemory.offHeapMemory();
		var cold = true;
		try {
			var d = null;
			if (hit != null) {
				d = try jpeg(hit.bytes, req.side, mem) catch (_:ImageError) null;
				cold = d == null;
				if (cold) mem.free();
			}
			if (d == null) d = source(req.path, req.size, req.side, mem, (at, n) -> read(req.path, at, n));
			if (d != null) {
				d = fit(d, req.side, mem);
				if (cold && cache != null && !cache.readOnly) {
					var encoded = JpegEncoder.encode(d.rgba, d.width, d.height, 80);
					cache.put(key, d.width, d.height, encoded);
				}
				var pixels = mem.take(d.rgba);
				mem.free();
				return {width: d.width, height: d.height, pixels: pixels, cold: cold};
			}
		} catch (_:Dynamic) {}
		mem.free();
		if (cache != null) cache.putNone(key);
		return {width: 0, height: 0, pixels: null, cold: cold};
	}

	#end

	// (a small file of these decodes about as fast as the cache reads it)
	static function cheap(path:String):Bool {
		var dot = path.lastIndexOf(".");
		return dot >= 0 && ["jpg", "jpeg", "jfif", "png", "apng", "gif", "webp"].contains(path.substr(dot + 1).toLowerCase());
	}

	// (read(at, n): the file's bytes, from the disk or those read already)
	static function source(path:String, size:Float, side:Int, mem:ImageMemory, read:(at:Int, n:Int) -> Bytes):Null<ThumbPixels> {
		var dot = path.lastIndexOf("."), ext = dot < 0 ? "" : path.substr(dot + 1).toLowerCase();
		inline function whole():Bytes
			return read(0, Std.int(size));
		return switch ext {
			case "jpg" | "jpeg" | "jfif":
				var head = read(0, Std.int(Math.min(size, JPEG_PREFIX)));
				var original = JpegDecoder.size(head), wanted = original == null ? side : Std.int(Math.min(side, Math.max(original.width, original.height)));
				var d = embedded(head, wanted, mem);
				d == null ? jpeg(size <= head.length ? head : whole(), side, mem) : d;
			#if (hxmc.target != "wasm32-wasi")
			case "heic" | "heif" | "avif" | "tif" | "tiff": system(path, side, mem);
			case ext if (SystemImages.EXTENSIONS.contains(ext)):
				embedded(raw(path, size), side, mem) ?? system(path, side, mem);
			#end
			case "png" | "apng": PngDecoder.decode(whole(), mem);
			case "gif": GifDecoder.decode(whole());
			case "webp":
				var bytes = whole(), d = WebpDecoder.decode(bytes, mem);
				Exif.apply(d.rgba, d.width, d.height, Exif.orientation(bytes), mem);
			case "pdf":
				var d = PdfPages.render(null, whole(), 0, side);
				{width: d.pixelsWidth, height: d.pixelsHeight, rgba: d.rgba};
			case _:
				#if (hxmc.target == "wasm32-wasi")
				null;
				#else
				var img = FolderModel.MEDIA.contains(ext) ? Thumbs.poster(path, side) : null;
				img == null ? null : {width: img.width, height: img.height, rgba: img.pixels};
				#end
		}
	}

	#if (hxmc.target != "wasm32-wasi")
	// (a RAW's first part, then up to its farthest preview when that is further)
	static function raw(path:String, size:Float):Bytes {
		var head = read(path, 0, Std.int(Math.min(size, RAW_PREFIX)));
		var need = Std.int(Math.min(size, Math.min(Exif.previewsNeed(head), RAW_LIMIT)));
		if (need <= head.length) return head;
		var all = Bytes.alloc(need);
		all.blit(0, head, 0, head.length);
		all.blit(head.length, read(path, head.length, need - head.length), 0, need - head.length);
		return all;
	}

	// Every read of a file's bytes, so they can go through the viewer's
	// asynchronous file access later (the system decoders and the video's
	// reader open the file themselves). A PDF is read here too, so that
	// PdfPages does not keep it among the viewer's open documents.
	static function read(path:String, at:Int, n:Int):Bytes {
		var f = File.read(path, true);
		try {
			if (at > 0) f.seek(at, SeekBegin);
			var bytes = Bytes.alloc(n);
			f.readFullBytes(bytes, 0, n);
			f.close();
			return bytes;
		} catch (e:Dynamic) {
			f.close();
			throw e;
		}
	}

	#end

	static function jpeg(bytes:Bytes, side:Int, mem:ImageMemory):ThumbPixels {
		var size = JpegDecoder.size(bytes), long = size == null ? 0 : Std.int(Math.max(size.width, size.height));
		return JpegDecoder.decode(bytes, mem, JpegDecoder.scaleFor(long, long, side, side));
	}

	static function embedded(head:Bytes, side:Int, mem:ImageMemory):Null<ThumbPixels> {
		for (p in Exif.previews(head)) {
			if (Math.max(p.width, p.height) < side * 0.75) continue;
			var bytes = head.sub(p.offset, p.length);
			var d = try jpeg(bytes, side, mem) catch (_:ImageError) null;
			if (d == null) {
				mem.free();
				continue;
			}
			if (Exif.orientation(bytes) == 1) d = Exif.apply(d.rgba, d.width, d.height, Exif.orientation(head), mem);
			return fit(d, side, mem, true);
		}
		return null;
	}

	#if (hxmc.target != "wasm32-wasi")
	static function system(path:String, side:Int, mem:ImageMemory):ThumbPixels {
		var d = SystemImages.decode(path, side, true);
		var pixels = {width: d.pixelsWidth, height: d.pixelsHeight, rgba: d.rgba};
		return fit(pixels, Std.int(Math.min(side, Math.max(d.width, d.height))), mem, true);
	}
	#end

	static function fit(d:ThumbPixels, side:Int, mem:ImageMemory, enlarge = false):ThumbPixels {
		var long = Math.max(d.width, d.height);
		if (long == side || (!enlarge && long < side)) return d;
		var scale = side / long;
		var w = Std.int(Math.max(1, Math.round(d.width * scale))), h = Std.int(Math.max(1, Math.round(d.height * scale)));
		ImageLimits.check("Thumbnails", w, h, 4);
		return {width: w, height: h, rgba: Resize.area(d.rgba, d.width, d.height, w, h, mem)};
	}
}
