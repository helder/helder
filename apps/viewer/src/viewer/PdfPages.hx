package viewer;

import haxe.io.Bytes;
import helder.pdf.Document;
import helder.pdf.Pdf;
import helder.pdf.PdfLimits;

// A PDF's pages for the viewer, on the decode jobs' threads: the
// documents opened last kept (KEEP, the most recent first, each with
// helder.pdf's own cache of decoded images and page contents, its
// PdfLimits.imageCache), so that the next page decodes none of what the
// last one did; a document opened again when its file changed. One page
// is drawn at a time, under a lock: the pool's two jobs never share a
// document, and the pages' memory is one canvas at a time.
//
// A page's size, as a decode says it, is NOMINAL pixels a point (at most
// MAX_SIDE a side); it is drawn at the side asked for (the size it is shown
// at: PdfDoc's, the inspector's), at most MAX_SIDE; sizes gives every page's
// size in points without drawing any.
// a PDF's pages' sizes in points (turned as shown), its file's size, or why it cannot be read
typedef PdfSizes = {sizes:Array<{width:Float, height:Float}>, fileSize:Int, error:Null<String>};

class PdfPages {
	// the documents kept open
	public static inline var KEEP = 2;
	// pixels a point at 100%, and the largest side a page is drawn at
	public static inline var NOMINAL = 2.0;
	public static inline var MAX_SIDE = 4096;

	// (the viewer's limits: helder.pdf's defaults for untrusted files, the
	// decoded images and contents a document keeps at 48 MB)
	public static final limits = {
		var l = new PdfLimits();
		l.imageCache = 48 << 20;
		l;
	};

	static final lock = new sys.thread.Mutex();
	static var docs:Array<{path:String, stamp:String, doc:Document}> = [];

	// page index of the PDF at path (bytes: its contents, when read
	// already; else read here unless the document is open; no path: bytes'
	// document, not kept), drawn to side
	// pixels on its larger side (0: its nominal size). Throws PdfError
	// (and ImageError's kinds through Decode).
	public static function render(path:Null<String>, bytes:Null<Bytes>, index:Int, side:Int):{
		width:Int,
		height:Int,
		pixelsWidth:Int,
		pixelsHeight:Int,
		rgba:Bytes,
		pages:Int,
		fileSize:Int
	} {
		lock.acquire();
		try {
			var doc = document(path, bytes);
			if (index < 0 || index >= doc.pages.length) throw helder.pdf.PdfError.corrupt('no page ${index + 1} (of ${doc.pages.length})');
			var pg = doc.pages[index], big = Math.max(pg.width, pg.height);
			var nominal = Math.min(NOMINAL, MAX_SIDE / big);
			// (a side asked for: that, a zoom's past the nominal too; else the nominal)
			var k = side > 0 ? Math.min(side / big, MAX_SIDE / big) : nominal;
			// (each page its own decompression budget: the document's total counts every page drawn since it opened)
			doc.decoded = 0;
			var b = Pdf.render(doc, index, k);
			var out = {
				width: Std.int(Math.ceil(pg.width * nominal)),
				height: Std.int(Math.ceil(pg.height * nominal)),
				pixelsWidth: b.width,
				pixelsHeight: b.height,
				rgba: b.straight(),
				pages: doc.pages.length,
				fileSize: doc.data.length
			};
			lock.release();
			return out;
		} catch (e:Dynamic) {
			lock.release();
			throw e;
		}
	}

	// each page's size in points, as it is shown (turned), the file's size: the document opened and kept
	public static function sizes(path:String, ?bytes:Bytes):{sizes:Array<{width:Float, height:Float}>, fileSize:Int} {
		lock.acquire();
		try {
			var doc = document(path, bytes);
			var out = {sizes: [for (p in doc.pages) {width: p.width, height: p.height}], fileSize: doc.data.length};
			lock.release();
			return out;
		} catch (e:Dynamic) {
			lock.release();
			throw e;
		}
	}

	// (the job's: an error said, not thrown)
	public static function sizesOf(path:String):PdfSizes
		return sizesIn({path: path, bytes: null});

	// (the web's job: the file's bytes read already, through its Files)
	public static function sizesIn(req:{path:String, bytes:Null<Bytes>}):PdfSizes {
		return try {
			var s = sizes(req.path, req.bytes);
			{sizes: s.sizes, fileSize: s.fileSize, error: null};
		} catch (e:helder.pdf.PdfError) {
			{sizes: [], fileSize: 0, error: e.kind == Encrypted ? "This PDF is protected by a password" : "A damaged PDF: " + e.message};
		} catch (e:Dynamic) {
			{sizes: [], fileSize: 0, error: "A damaged PDF: " + Std.string(e)};
		}
	}

	#if (hxmc.target == "wasm32-wasi")
	// the web's: the file's bytes read through the browser's files, its sizes
	// on the page (Decode.onPage)
	@:coroutine public static function read(files:WebFiles, path:String):PdfSizes {
		var b = try files.bytes(path) catch (_:Dynamic) null;
		return b == null ? {sizes: [], fileSize: 0, error: "The PDF could not be read"} : sizesIn({path: path, bytes: b});
	}
	#end

	// how many pages the document at path has, when it is open (-1: not)
	public static function pagesOf(path:String):Int {
		lock.acquire();
		var s = stamp(path), n = -1;
		for (d in docs)
			if (d.path == path && d.stamp == s) n = d.doc.pages.length;
		lock.release();
		return n;
	}

	// whether the file at path is one of the documents kept (then render needs no bytes)
	public static function isOpen(path:String):Bool
		return pagesOf(path) >= 0;

	// the documents let go (tests; memory)
	public static function clear() {
		lock.acquire();
		docs = [];
		lock.release();
	}

	// (under the lock: the document kept, else opened and kept first; no path: opened, not kept)
	static function document(path:Null<String>, bytes:Null<Bytes>):Document {
		if (path == null) {
			var doc = Pdf.open(bytes, "", limits);
			if (doc.pages.length == 0) throw helder.pdf.PdfError.corrupt("no pages");
			return doc;
		}
		var s = stamp(path);
		for (i in 0...docs.length)
			if (docs[i].path == path) {
				var d = docs[i];
				docs.splice(i, 1);
				if (d.stamp == s) {
					docs.unshift(d);
					return d.doc;
				}
				break;
			}
		if (bytes == null) bytes = sys.io.File.getBytes(path);
		var doc = Pdf.open(bytes, "", limits);
		if (doc.pages.length == 0) throw helder.pdf.PdfError.corrupt("no pages");
		docs.unshift({path: path, stamp: s, doc: doc});
		if (docs.length > KEEP) docs.resize(KEEP);
		return doc;
	}

	static function stamp(p:String):String
		return try {
			var s = sys.FileSystem.stat(p);
			s.size + ":" + s.mtime.getTime();
		} catch (_:Dynamic) "";
}
