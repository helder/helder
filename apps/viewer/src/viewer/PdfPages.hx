package viewer;

import haxe.io.Bytes;
import helder.pdf.Document;
import helder.pdf.Pdf;
import helder.pdf.PdfLimits;
import helder.pdf.PdfSource;
import viewer.PageText;

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
//
// A file is read where its pages need it (helder.pdf's Pdf.openSource), not
// whole: one on disk through its handle (seeked), kept open while its
// document is; one read through Files (the web's) by through, its blocks
// fetched as they are needed; bytes read already as they are. A first
// page alone (a thumbnail's, the inspector's) is read so (first: a
// linearized file's from its start), its document not kept.
// a PDF's pages' sizes in points (turned as shown), its file's size, or why it cannot be read
typedef PdfSizes = {sizes:Array<{width:Float, height:Float}>, fileSize:Int, error:Null<String>};

class PdfPages {
	// the documents kept open
	public static inline var KEEP = 2;
	// pixels a point at 100%, and the largest side a page is drawn at
	public static inline var NOMINAL = 2.0;
	public static inline var MAX_SIDE = 4096;
	// (a side asked for that draws nothing: the page's text alone)
	public static inline var TEXT = -1;

	// (the viewer's limits: helder.pdf's defaults for untrusted files, the
	// decoded images and contents a document keeps at 48 MB)
	public static final limits = {
		var l = new PdfLimits();
		l.imageCache = 48 << 20;
		l;
	};

	static final lock = new sys.thread.Mutex();
	// (by path and stamp: content, so every screen's, a preview host's too)
	static var docs:Array<{path:String, stamp:String, doc:Document}> = [];

	// page index of the PDF at path (bytes: its contents, when read
	// already; source: a file read through Files, through's; else read here
	// where the page needs it unless the document is open; no path: bytes' or
	// source's document, not kept), drawn to side pixels on its larger side
	// (0: its nominal size); first: page 1 alone, not kept (its count all the
	// same); its text too (PageText), but a first page alone's (side TEXT:
	// that alone, no pixels). Throws PdfError (and ImageError's kinds through Decode), and
	// through's PdfMissing.
	public static function render(path:Null<String>, bytes:Null<Bytes>, index:Int, side:Int, first = false, ?source:PdfSource):{
		width:Int,
		height:Int,
		pixelsWidth:Int,
		pixelsHeight:Int,
		rgba:Null<Bytes>,
		pages:Int,
		fileSize:Int,
		text:Null<PageText>
	} {
		lock.acquire();
		var d:Null<{doc:Document, kept:Bool}> = null;
		try {
			d = document(path, bytes, first && index == 0, source);
			var doc = d.doc;
			if (index < 0 || index >= doc.pages.length) throw helder.pdf.PdfError.corrupt('no page ${index + 1} (of ${doc.count})');
			var pg = doc.pages[index], big = Math.max(pg.width, pg.height);
			var nominal = Math.min(NOMINAL, MAX_SIDE / big);
			// (a side asked for: that, a zoom's past the nominal too; else the nominal)
			var k = side > 0 ? Math.min(side / big, MAX_SIDE / big) : nominal;
			// (each page its own decompression budget: the document's total counts every page drawn since it opened)
			doc.decoded = 0;
			var b = side == TEXT ? null : Pdf.render(doc, index, k);
			// (the text pass a millisecond or two a page: content streams kept inflated, no image decoded)
			var text = first ? null : try PageTexts.of(Pdf.runs(pg)) catch (_:helder.pdf.PdfError) null;
			var out = {
				width: Std.int(Math.ceil(pg.width * nominal)),
				height: Std.int(Math.ceil(pg.height * nominal)),
				pixelsWidth: b == null ? 0 : b.width,
				pixelsHeight: b == null ? 0 : b.height,
				rgba: b == null ? null : b.straight(),
				pages: doc.count,
				fileSize: doc.size,
				text: text
			};
			if (!d.kept) doc.close();
			lock.release();
			return out;
		} catch (e:Dynamic) {
			if (d != null && !d.kept) d.doc.close();
			lock.release();
			throw e;
		}
	}

	// each page's size in points, as it is shown (turned), the file's size: the document opened and kept
	public static function sizes(path:String, ?bytes:Bytes, ?source:PdfSource):{sizes:Array<{width:Float, height:Float}>, fileSize:Int} {
		lock.acquire();
		try {
			var doc = document(path, bytes, false, source).doc;
			var out = {sizes: [for (p in doc.pages) {width: p.width, height: p.height}], fileSize: doc.size};
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

	// (the file's bytes read already, or its source: through's)
	public static function sizesIn(req:{path:String, bytes:Null<Bytes>, ?source:PdfSource}):PdfSizes {
		return try {
			var s = sizes(req.path, req.bytes, req.source);
			{sizes: s.sizes, fileSize: s.fileSize, error: null};
		} catch (e:helder.pdf.PdfError) {
			{sizes: [], fileSize: 0, error: e.kind == Encrypted ? "This PDF is protected by a password" : "A damaged PDF: " + e.message};
		} catch (m:PdfMissing) {
			// (a block not fetched yet: through's to fetch)
			throw m;
		} catch (e:Dynamic) {
			{sizes: [], fileSize: 0, error: "A damaged PDF: " + Std.string(e)};
		}
	}

	// the file read through files (the web's, a phone's documents), its
	// sizes here (the web: on the page, Decode.onPage, as much of it as they
	// need; a phone's: all of it, a job's threads not sharing the blocks)
	@:coroutine public static function read(files:Files, path:String):PdfSizes {
		#if (hxmc.target == "wasm32-wasi")
		return try through(files, path, true, src -> sizesIn({path: path, bytes: null, source: src})) catch (_:Dynamic) {
			sizes: [],
			fileSize: 0,
			error: "The PDF could not be read"
		};
		#else
		var b = try FileBytes.read(files, path) catch (_:Dynamic) null;
		return b == null ? {sizes: [], fileSize: 0, error: "The PDF could not be read"} : sizesIn({path: path, bytes: b});
		#end
	}

	// work on the PDF at path read through files (the web's): its blocks
	// fetched as it needs them (PdfFetched: the work done again once the
	// block it was missing is read; keep: the blocks kept for path's
	// document, kept too)
	@:coroutine public static function through<T>(files:Files, path:String, keep:Bool, work:PdfSource->T):T {
		var e = files.stat(path);
		if (e == null || e.kind == Folder) throw "No such file";
		var size = Std.int(e.size), src = keep ? fetched.get(path) : null;
		if (src == null || src.size != size) {
			src = new PdfFetched(size);
			if (keep) fetched.set(path, src);
		}
		var reader:Null<helder.media.ByteSource> = null;
		while (true) {
			var r = attempt(src, work);
			if (r.missing == null) {
				if (reader != null) reader.close();
				if (r.error != null) throw r.error;
				return r.value;
			}
			if (reader == null) reader = files.open(path);
			var m = r.missing, b = Bytes.alloc(m.length), got = 0, n = 0;
			while (got < m.length && (n = reader.read(m.index * PdfFetched.BLOCK + got, b, got, m.length - got)) > 0)
				got += n;
			if (got < m.length) {
				reader.close();
				throw "The PDF could not be read";
			}
			src.add(m.index, b);
		}
	}

	// (the files' blocks kept for their kept documents: through's)
	static final fetched = new Map<String, PdfFetched>();

	// (the work, or the block it needs first: caught here, outside the coroutine, which would throw
	// again what it catches)
	static function attempt<T>(src:PdfFetched, work:PdfSource->T):{value:Null<T>, missing:Null<PdfMissing>, error:Dynamic} {
		return try {value: work(src), missing: null, error: null} catch (m:PdfMissing) {
			value: null,
			missing: m,
			error: null
		} catch (e:Dynamic) {value: null, missing: null, error: e};
	}

	// how many pages the document at path has, when it is open (-1: not)
	public static function pagesOf(path:String):Int {
		lock.acquire();
		var s = stamp(path), n = -1;
		for (d in docs)
			if (d.path == path && d.stamp == s) n = d.doc.count;
		lock.release();
		return n;
	}

	// whether the file at path is one of the documents kept (then render needs no bytes)
	public static function isOpen(path:String):Bool
		return pagesOf(path) >= 0;

	// the documents let go (tests; memory)
	public static function clear() {
		lock.acquire();
		for (d in docs)
			drop(d);
		docs = [];
		lock.release();
	}

	// (under the lock: the document kept, else opened and kept first; no path, or the first page
	// alone of a document not kept: opened, not kept)
	static function document(path:Null<String>, bytes:Null<Bytes>, first:Bool, source:Null<PdfSource>):{doc:Document, kept:Bool} {
		if (path == null || first && !isKept(path)) {
			var doc = Pdf.openSource(sourceOf(path, bytes, source), first, "", limits);
			if (doc.count == 0) throw helder.pdf.PdfError.corrupt("no pages");
			return {doc: doc, kept: false};
		}
		var s = stamp(path);
		for (i in 0...docs.length)
			if (docs[i].path == path) {
				var d = docs[i];
				docs.splice(i, 1);
				if (d.stamp == s) {
					docs.unshift(d);
					return {doc: d.doc, kept: true};
				}
				drop(d);
				break;
			}
		var doc = Pdf.openSource(sourceOf(path, bytes, source), false, "", limits);
		if (doc.count == 0) throw helder.pdf.PdfError.corrupt("no pages");
		docs.unshift({path: path, stamp: s, doc: doc});
		while (docs.length > KEEP)
			drop(docs.pop());
		return {doc: doc, kept: true};
	}

	// (a document let go of: its file's handle, its blocks)
	static function drop(d:{path:String, stamp:String, doc:Document}) {
		d.doc.close();
		if ((fetched.get(d.path) : Null<PdfSource>) == d.doc.source) fetched.remove(d.path);
	}

	// (under the lock: whether path's document is kept, its file unchanged)
	static function isKept(path:String):Bool {
		var s = stamp(path);
		for (d in docs)
			if (d.path == path && d.stamp == s) return true;
		return false;
	}

	// (the file's bytes read already, a source given (through's), else the file on disk)
	static function sourceOf(path:Null<String>, bytes:Null<Bytes>, source:Null<PdfSource>):PdfSource {
		if (source != null) return source;
		if (bytes != null) return new PdfBytes(bytes);
		#if (hxmc.target == "wasm32-wasi")
		throw "helder.pdf: no file on disk here: " + path;
		#else
		return new DiskSource(path);
		#end
	}

	// (none on the web: its files do not change)
	static function stamp(p:String):String
		return #if (hxmc.target == "wasm32-wasi") "" #else try {
			var s = sys.FileSystem.stat(p);
			s.size + ":" + s.mtime.getTime();
		} catch (_:Dynamic) "" #end;
}

#if (hxmc.target != "wasm32-wasi")
// (a PDF on disk, read where its pages need: its handle kept while its document is)
private class DiskSource implements PdfSource {
	public var size(get, never):Int;

	final input:sys.io.FileInput;
	final length:Int;

	public function new(path:String) {
		input = sys.io.File.read(path, true);
		length = Std.int(sys.FileSystem.stat(path).size);
	}

	function get_size():Int
		return length;

	public function read(offset:Int, b:Bytes, pos:Int, len:Int):Int {
		if (offset < 0 || offset >= length || len <= 0) return 0;
		input.seek(offset, SeekBegin);
		var n = Std.int(Math.min(len, length - offset)), got = 0;
		while (got < n) {
			var k = try input.readBytes(b, pos + got, n - got) catch (_:haxe.io.Eof) 0;
			if (k <= 0) break;
			got += k;
		}
		return got;
	}

	public function close()
		input.close();
}
#end
