package helder.pdf;

import haxe.io.Bytes;
import helder.pdf.PdfValue;
import helder.pdf.PdfSource;
import helder.async.Errors;

// A PDF file read (after leanpdf's core: its xref, reader and recovery):
// the cross-reference table or stream at startxref and those it chains to
// (/Prev, a hybrid file's /XRefStm; each offset once: no loops), objects
// read where it says, those in object streams through their stream; a
// file whose xref is missing or wrong rebuilt from its "n g obj" headers.
// Read through a PdfSource: the tail, then each object at its offset when
// it is needed (in blocks, PdfLimits.readBlock, readCache of them kept), so
// a page is drawn having read what it needs; only a rebuilt file is read
// whole. Its first page alone (first): a linearized file's from the file's
// start (its /Linearized dictionary, the first page's xref; the rest of its
// xref only once an object is not there), another's by the page tree's
// first leaf, the count its root's /Count.
// Encrypted files open with the standard handler (Crypto: the empty user
// password unless another is given) and their strings and streams are
// decrypted as objects are read. The page tree is walked once, each page
// with what it inherits; every bound is PdfLimits'.
class Document {
	public final source:PdfSource;
	// the file's bytes
	public final size:Int;
	public final limits:PdfLimits;
	// (decoded images, for pages drawn again: PdfLimits.imageCache)
	public final images:ImageCache;
	public var trailer(default, null):PdfDict;
	public var pages(default, null):Array<Page> = [];
	// the document's pages: pages.length, or a linearized file's /N when only its first is read
	public var count(default, null) = 0;
	public var repaired(default, null) = false;
	// (why the xref was not taken: a repaired file's)
	public var repairReason(default, null) = "";
	// the bytes read from the source so far (blocks: PdfLimits.readBlock)
	public var bytesRead(default, null) = 0.0;

	// object number: its offset (type 1) or its object stream's number and index (type 2: -(stream+1), index)
	final offsets = new Map<Int, Int>();
	final inStream = new Map<Int, Int>();
	final cache = new Map<Int, PdfValue>();
	final loading = new Map<Int, Bool>();
	var cached = 0;
	var crypto:Null<Decryptor> = null;
	var encryptRef = -1;
	// (what the document's streams have decoded so far: maxDecoded's budget)
	public var decoded = 0;
	// (a Bytes' file: parsed in place, nothing read)
	final whole:Null<Bytes>;
	// (the blocks read, the most recently used last)
	final blocks = new Map<Int, Bytes>();
	final order:Array<Int> = [];
	// (a linearized file's first page read: where the rest of its xref is, read once an object is
	// not in the first page's; -1: none, or read)
	var rest = -1;

	// (decryption: Crypto.open, or null where none is linked: Pdf.openPlain; first: a linearized
	// file's first page alone where it can, Pdf.openSource's)
	public function new(source:PdfSource, password = "", ?limits:PdfLimits, ?decryption:(enc:PdfDict, id:Bytes, password:String) -> Null<Decryptor>,
			first = false) {
		this.source = source;
		this.limits = limits ?? PdfLimits.DEFAULT;
		size = source.size;
		whole = Std.isOfType(source, PdfBytes) ? (cast source : PdfBytes).bytes : null;
		images = new ImageCache(this.limits.imageCache);
		if (size < 8) throw PdfError.corrupt("not a PDF: too short");
		if (first && firstPage(password, decryption)) return;
		try {
			readXref();
		} catch (e:PdfError) {
			if (e.kind == TooLarge) throw Errors.kept(e);
			repairReason = e.message;
			recover();
		}
		if (trailer == null || !trailer.has("Root")) recover();
		decrypt(password, decryption);
		if (!first || !firstLeaf()) {
			readPages();
			count = pages.length;
		}
	}

	// the source let go of (a file's handle)
	public function close() {
		source.close();
		blocks.clear();
		order.resize(0);
	}

	function decrypt(password:String, decryption:Null<(enc:PdfDict, id:Bytes, password:String) -> Null<Decryptor>>) {
		var enc = trailer.get("Encrypt");
		if (enc == PNull) return;
		switch enc {
			case PRef(n, _): encryptRef = n;
			case _:
		}
		var d = Values.dict(resolve(enc));
		if (d == null) return;
		var ids = Values.arr(resolve(trailer.get("ID")));
		var id = ids != null && ids.length > 0 ? Values.str(resolve(ids[0])) : null;
		if (decryption == null) throw new PdfError(Encrypted, "encrypted, and no decryption linked (Pdf.openPlain): Pdf.open decrypts");
		crypto = decryption(d, id ?? Bytes.alloc(0), password);
		if (crypto == null) throw new PdfError(Encrypted, "the password does not open it");
		// (what was read before the key was known: read again)
		for (k in cache.keys())
			if (k != encryptRef) cache.remove(k);
	}

	// ---- the file's bytes

	// the bytes at [o, o + n), fewer at the file's end: the source's blocks, kept
	function bytes(o:Int, n:Int):Bytes {
		if (o < 0) o = 0;
		if (n > size - o) n = size - o;
		if (n <= 0) return Bytes.alloc(0);
		if (whole != null) return whole.sub(o, n);
		var out = Bytes.alloc(n), k = limits.readBlock, done = 0;
		while (done < n) {
			var at = o + done, i = Std.int(at / k), b = block(i), from = at - i * k;
			var m = Std.int(Math.min(n - done, b.length - from));
			if (m <= 0) break;
			out.blit(done, b, from, m);
			done += m;
		}
		return done == n ? out : out.sub(0, done);
	}

	function block(i:Int):Bytes {
		var b = blocks.get(i);
		if (b != null) {
			order.remove(i);
			order.push(i);
			return b;
		}
		var k = limits.readBlock, len = Std.int(Math.min(k, size - i * k));
		b = Bytes.alloc(len);
		var got = 0;
		while (got < len) {
			var r = source.read(i * k + got, b, got, len - got);
			if (r <= 0) break;
			got += r;
		}
		bytesRead += got;
		if (got < len) b = b.sub(0, got);
		blocks.set(i, b);
		order.push(i);
		while (order.length > 1 && order.length * k > limits.readCache)
			blocks.remove(order.shift());
		return b;
	}

	// a window of the file from o, at least n bytes where there are (a Bytes' file: all of it): its
	// bytes and the offset they start at
	function window(o:Int, n:Int):{b:Bytes, base:Int} {
		if (whole != null) return {b: whole, base: 0};
		return {b: bytes(o, n), base: o};
	}

	// what f parses from a window at o, the window larger until it does (to the file's end)
	function parsed<T>(o:Int, f:(b:Bytes, base:Int, last:Bool) -> T):T {
		var n = 4096;
		while (true) {
			var w = window(o, n), last = w.base + w.b.length >= size;
			try {
				return f(w.b, w.base, last);
			} catch (e:PdfError) {
				if (last || e.kind == TooLarge) throw Errors.kept(e);
			}
			n *= 4;
		}
	}

	// ---- the cross-reference

	function readXref() {
		// (the last startxref, by its bytes: the tail is binary)
		var tail = Std.int(Math.min(size, 4096)), w = window(size - tail, tail), t = w.b, base = w.base;
		var at = -1, key = Bytes.ofString("startxref"), i = size - key.length;
		var stop = size - tail;
		while (i >= stop && at < 0) {
			var ok = true;
			for (k in 0...key.length)
				if (t.get(i - base + k) != key.get(k)) {
					ok = false;
					break;
				}
			if (ok) at = i;
			i--;
		}
		if (at < 0) throw PdfError.corrupt("no startxref");
		var p = new Parser(t, at + 9 - base);
		p.skip();
		chain(Std.int(p.number()), true);
	}

	// the xref at off and those it chains to (/XRefStm, /Prev); its trailer the document's (top)
	function chain(off:Int, top:Bool) {
		var seen = new Map<Int, Bool>();
		var first = true;
		var queue = [off];
		while (queue.length > 0) {
			var o = queue.shift();
			if (seen.exists(o) || o < 0 || o >= size) {
				if (first && top) throw PdfError.corrupt("startxref past the file");
				continue;
			}
			seen.set(o, true);
			var t = xrefAt(o);
			if (first && top) trailer = t;
			first = false;
			var stm = Values.int(t.get("XRefStm"), -1);
			if (stm >= 0) queue.unshift(stm);
			var prev = Values.int(t.get("Prev"), -1);
			if (prev >= 0) queue.push(prev);
		}
	}

	// a table or an xref stream at o: its trailer; its entries added where none is yet (the newest first)
	function xrefAt(o:Int):PdfDict {
		var table = parsed(o, (b, base, last) -> {
			var p = new Parser(b, o - base, null, limits.maxNesting);
			p.skip();
			if (!(p.pos + 4 <= b.length && b.getString(p.pos, 4) == "xref")) return null;
			p.pos += 4;
			// (the entries: added once the whole table parsed, a window too short tried again)
			var found:Array<{n:Int, off:Int}> = [];
			while (true) {
				p.skip();
				if (p.pos + 7 <= b.length && b.getString(p.pos, 7) == "trailer") {
					p.pos += 7;
					var t = Values.dict(p.next());
					if (t == null) throw PdfError.corrupt("a trailer that is no dictionary");
					return {trailer: t, found: found};
				}
				var before = p.pos;
				var start = Std.int(p.number());
				p.skip();
				var count = Std.int(p.number());
				if (p.pos == before) throw PdfError.corrupt("an xref table that does not parse");
				if (count < 0 || count > limits.maxObjects) throw PdfError.tooLarge("an xref section of " + count + " entries");
				for (i in 0...count) {
					p.skip();
					if (p.pos >= b.length) break;
					var off = Std.int(p.number());
					p.skip();
					p.number();
					p.skip();
					var kind = p.at(p.pos);
					p.pos++;
					if (kind == "n".code) found.push({n: start + i, off: off}) else if (kind == "f".code) found.push({n: start + i, off: -1});
				}
				if (p.pos >= b.length) throw PdfError.corrupt("an xref table without a trailer");
			}
			return null;
		});
		if (table != null) {
			for (e in table.found)
				if (!offsets.exists(e.n) && !inStream.exists(e.n)) offsets.set(e.n, e.off);
			return table.trailer;
		}
		// an xref stream
		var v = objectAt(o, -1);
		var d:PdfDict, raw:Bytes;
		switch v {
			case PStream(dd, r):
				d = dd;
				raw = r;
			case _:
				throw PdfError.corrupt("startxref at no xref");
		}
		if (Values.name(d.get("Type")) != "XRef") throw PdfError.corrupt("startxref at no xref");
		var bytes = Filters.decode(raw, d, limits.maxStream, null).data;
		var w = Values.nums(d.get("W"));
		if (w == null || w.length < 3) throw PdfError.corrupt("an xref stream without /W");
		var w0 = Std.int(w[0]), w1 = Std.int(w[1]), w2 = Std.int(w[2]), row = w0 + w1 + w2;
		if (w0 < 0 || w1 < 0 || w2 < 0 || row <= 0 || row > 32) throw PdfError.corrupt("an xref stream's /W");
		var size = Values.int(d.get("Size"));
		var index = Values.nums(d.get("Index")) ?? [0, size];
		var at = 0;
		inline function field(width:Int, def:Int):Int {
			if (width == 0) return def;
			var v = 0;
			for (k in 0...width)
				v = v * 256 + (at + k < bytes.length ? bytes.get(at + k) : 0);
			at += width;
			return v;
		}
		var k = 0;
		while (k + 1 < index.length) {
			var start = Std.int(index[k]), count = Std.int(index[k + 1]);
			if (count < 0 || count > limits.maxObjects) throw PdfError.tooLarge("an xref stream of " + count + " entries");
			for (i in 0...count) {
				if (at + row > bytes.length) break;
				var t = field(w0, 1), a = field(w1, 0), b = field(w2, 0), n = start + i;
				if (offsets.exists(n) || inStream.exists(n)) continue;
				if (t == 1) offsets.set(n, a) else if (t == 2) inStream.set(n, a * 65536 + b) else if (t == 0) offsets.set(n, -1);
			}
			k += 2;
		}
		return d;
	}

	// ---- a linearized file's first page

	// (its /Linearized dictionary in the first KB, /L the file's length: the
	// first page's xref after it, page /O, /N pages; the rest of the file's
	// xref (its trailer's /Prev) read only once an object is not in it.
	// false, anything amiss: the whole file's path, from nothing kept)
	function firstPage(password:String, decryption:Null<(enc:PdfDict, id:Bytes, password:String) -> Null<Decryptor>>):Bool {
		var b = window(0, 1024).b, end = Std.int(Math.min(1024, size)), at = -1, key = Bytes.ofString("/Linearized");
		for (i in 0...end - key.length) {
			var ok = true;
			for (k in 0...key.length)
				if (b.get(i + k) != key.get(k)) {
					ok = false;
					break;
				}
			if (ok) {
				at = i;
				break;
			}
		}
		if (at < 0) return false;
		try {
			// (its object's start: back over "obj", the generation and the number)
			var j = at;
			while (j > 3 && !(b.get(j - 3) == "o".code && b.get(j - 2) == "b".code && b.get(j - 1) == "j".code))
				j--;
			if (j <= 3) return false;
			j -= 4;
			for (_ in 0...2) {
				while (j > 0 && Parser.isWhite(b.get(j)))
					j--;
				while (j > 0 && b.get(j - 1) >= "0".code && b.get(j - 1) <= "9".code)
					j--;
				if (j > 0) j--;
			}
			var o = j == 0 ? 0 : j + 1;
			var head = parsed(o, (b, base, last) -> {
				var p = new Parser(b, o - base, null, limits.maxNesting);
				p.next();
				p.next();
				p.next();
				if (p.keyword != "obj") throw PdfError.corrupt("no /Linearized object");
				var lin = Values.dict(p.next());
				p.next();
				if (p.keyword != "endobj") throw PdfError.corrupt("a /Linearized object not ended");
				if (!last && p.pos + 16 > b.length) throw PdfError.corrupt("a window too short");
				return {lin: lin, after: base + p.pos};
			});
			var lin = head.lin;
			if (lin == null || Values.int(lin.get("L"), -1) != size) return false;
			var page = Values.int(lin.get("O"), -1), n = Values.int(lin.get("N"), -1);
			if (page <= 0 || n <= 0 || n > limits.maxPages) return false;
			var w = window(head.after, 64), p = new Parser(w.b, head.after - w.base);
			p.skip();
			trailer = xrefAt(w.base + p.pos);
			if (!trailer.has("Root")) throw PdfError.corrupt("a first page's trailer without /Root");
			rest = Values.int(trailer.get("Prev"), -1);
			decrypt(password, decryption);
			var d = Values.dict(object(page));
			if (d == null || Values.name(d.get("Type")) != "Page") throw PdfError.corrupt("/O no page");
			// (what it inherits, up its /Parent chain where it says no resources or box of its own)
			var inh = {resources: d.get("Resources"), media: d.get("MediaBox"), crop: d.get("CropBox"), rotate: d.get("Rotate")}, up = d, depth = 0;
			while ((inh.resources == PNull || inh.media == PNull) && depth++ < 64) {
				up = Values.dict(resolve(up.get("Parent")));
				if (up == null) break;
				if (inh.resources == PNull) inh.resources = up.get("Resources");
				if (inh.media == PNull) inh.media = up.get("MediaBox");
				if (inh.crop == PNull) inh.crop = up.get("CropBox");
				if (inh.rotate == PNull) inh.rotate = up.get("Rotate");
			}
			pages = [new Page(this, d, inh.resources, inh.media, inh.crop, Values.int(resolve(inh.rotate)))];
			count = n;
			return true;
		} catch (e:PdfError) {
			if (e.kind == TooLarge || e.kind == Encrypted) throw Errors.kept(e);
			offsets.clear();
			inStream.clear();
			cache.clear();
			objectStreams.clear();
			trailer = null;
			crypto = null;
			encryptRef = -1;
			pages = [];
			cached = 0;
			decoded = 0;
			rest = -1;
			return false;
		}
	}

	// every "n g obj" in the file: a damaged file's objects, the last of each number kept (the whole file read)
	function recover() {
		repaired = true;
		offsets.clear();
		inStream.clear();
		cache.clear();
		var s = whole ?? bytes(0, size), n = s.length, i = 0;
		trailer = null;
		var root:Null<PdfValue> = null;
		while (i < n - 4) {
			var c = s.get(i);
			if (c == "o".code && s.get(i + 1) == "b".code && s.get(i + 2) == "j".code) {
				// (back over the generation and the number)
				var j = i - 1;
				while (j > 0 && Parser.isWhite(s.get(j)))
					j--;
				var ge = j;
				while (j > 0 && s.get(j) >= "0".code && s.get(j) <= "9".code)
					j--;
				if (j < ge) {
					while (j > 0 && Parser.isWhite(s.get(j)))
						j--;
					var ne = j;
					while (j >= 0 && s.get(j) >= "0".code && s.get(j) <= "9".code)
						j--;
					if (j < ne) {
						var num = Std.parseInt(s.getString(j + 1, ne - j));
						if (num != null && num > 0 && num <= limits.maxObjects) offsets.set(num, j + 1);
					}
				}
			} else if (c == "t".code && i + 7 < n && s.getString(i, 7) == "trailer") {
				var p = new Parser(s, i + 7, null, limits.maxNesting);
				try {
					var t = Values.dict(p.next());
					if (t != null && t.has("Root")) trailer = t;
				} catch (_:PdfError) {}
			}
			i++;
		}
		if (trailer == null) {
			// (no trailer: an xref stream's dictionary, or the catalog itself)
			for (num => off in offsets) {
				var v = try objectAt(off, num) catch (_:PdfError) PNull;
				var d = Values.dict(v);
				if (d == null) continue;
				if (d.has("Root")) {
					trailer = d;
					break;
				}
				if (Values.name(d.get("Type")) == "Catalog") root = PRef(num, 0);
			}
			if (trailer == null && root != null) {
				trailer = new PdfDict();
				trailer.set("Root", root);
			}
		}
		if (trailer == null) throw PdfError.corrupt("no trailer and no catalog");
	}

	// ---- objects

	// v itself, or the object it refers to
	public function resolve(v:PdfValue):PdfValue {
		if (v == null) return PNull;
		var depth = 0;
		while (true)
			switch v {
				case PRef(n, _):
					if (++depth > 32) return PNull;
					v = object(n);
				case _:
					return v;
			}
	}

	public function object(n:Int):PdfValue {
		var c = cache.get(n);
		if (c != null) return c;
		if (loading.exists(n)) return PNull;
		if (rest >= 0 && !offsets.exists(n) && !inStream.exists(n)) {
			var r = rest;
			rest = -1;
			try chain(r, false) catch (e:PdfError) if (e.kind == TooLarge) throw Errors.kept(e);
		}
		loading.set(n, true);
		var v = PNull;
		try {
			if (inStream.exists(n)) {
				var e = inStream.get(n);
				v = fromObjectStream(Std.int(e / 65536), e % 65536, n);
			} else if (offsets.exists(n) && offsets.get(n) >= 0) {
				v = objectAt(offsets.get(n), n);
				if (crypto != null && n != encryptRef) v = decryptAll(v, n, 0);
			}
		} catch (e:PdfError) {
			loading.remove(n);
			if (e.kind == TooLarge) throw Errors.kept(e);
			v = PNull;
		} catch (e:PdfMissing) {
			// (a block not fetched yet: read again once it is, nothing kept of this one)
			loading.remove(n);
			throw e;
		}
		loading.remove(n);
		if (++cached > limits.maxObjects) throw PdfError.tooLarge("past " + limits.maxObjects + " objects");
		cache.set(n, v);
		return v;
	}

	// "n g obj value [stream ... endstream]" at o (want: the number it must be, -1 any)
	function objectAt(o:Int, want:Int):PdfValue {
		var head = parsed(o, (b, base, last) -> {
			var p = new Parser(b, o - base, null, limits.maxNesting);
			p.next();
			p.next();
			p.next();
			if (p.keyword != "obj") throw PdfError.corrupt("no object at " + o);
			var v = p.next();
			// (a value that ends near the window's end may go on past it: a larger one; "stream" after a dictionary too)
			if (!last && p.pos + 16 > b.length) throw PdfError.corrupt("a window too short");
			var s = -1;
			switch v {
				case PDict(_):
					p.skip();
					if (p.pos + 6 <= b.length && b.getString(p.pos, 6) == "stream") {
						s = p.pos + 6;
						if (s < b.length && b.get(s) == 13) s++;
						if (s < b.length && b.get(s) == 10) s++;
						s += base;
					}
				case _:
			}
			return {v: v, s: s};
		});
		var v = head.v;
		if (v == null) return PNull;
		if (head.s < 0) return v;
		var d = Values.dict(v), s = head.s, len = -1;
		switch d.get("Length") {
			case PNum(x): len = Std.int(x);
			case PRef(rn, _): if (rn != want) len = Values.int(object(rn), -1);
			case _:
		}
		// (a length that does not end at endstream: the stream to its endstream)
		if (len < 0 || s + len > size || !endsAt(s + len)) {
			var e = find("endstream", s);
			if (e < 0) e = size;
			len = e - s;
			var tail = bytes(Std.int(Math.max(s, e - 64)), e - Std.int(Math.max(s, e - 64))), k = tail.length;
			while (len > 0 && k > 0 && Parser.isWhite(tail.get(k - 1))) {
				len--;
				k--;
			}
		}
		if (len > limits.maxStream) throw PdfError.tooLarge("a stream of " + len + " bytes");
		return PStream(d, bytes(s, len));
	}

	function endsAt(p:Int):Bool {
		var b = bytes(p, 64), q = 0;
		while (q < b.length && Parser.isWhite(b.get(q)))
			q++;
		return q + 9 <= b.length && b.getString(q, 9) == "endstream";
	}

	// the first `what` at or after from (-1: none), read a block at a time
	function find(what:String, from:Int):Int {
		var w = Bytes.ofString(what), n = w.length, step = Std.int(Math.max(limits.readBlock, 4096));
		var at = from;
		while (at + n <= size) {
			var b = bytes(at, step + n - 1);
			var i = 0;
			while (i + n <= b.length) {
				if (b.get(i) == w.get(0)) {
					var ok = true;
					for (k in 1...n)
						if (b.get(i + k) != w.get(k)) {
							ok = false;
							break;
						}
					if (ok) return at + i;
				}
				i++;
			}
			at += step;
		}
		return -1;
	}

	final objectStreams = new Map<Int, {data:Bytes, first:Int, offsets:Map<Int, Int>}>();

	function fromObjectStream(stream:Int, index:Int, n:Int):PdfValue {
		var os = objectStreams.get(stream);
		if (os == null) {
			var v = object(stream);
			switch v {
				case PStream(d, _):
					var bytes = this.stream(v);
					var count = Values.int(d.get("N")), first = Values.int(d.get("First"));
					if (count < 0 || count > limits.maxObjects || first < 0) throw PdfError.corrupt("an object stream's /N or /First");
					var p = new Parser(bytes, 0, Std.int(Math.min(first, bytes.length)));
					var map = new Map<Int, Int>();
					for (_ in 0...count) {
						var on = Values.int(p.next() ?? PNull, -1), off = Values.int(p.next() ?? PNull, -1);
						if (on < 0) break;
						if (!map.exists(on)) map.set(on, off);
					}
					os = {data: bytes, first: first, offsets: map};
					objectStreams.set(stream, os);
				case _:
					return PNull;
			}
		}
		var off = os.offsets.get(n);
		if (off == null) return PNull;
		var p = new Parser(os.data, os.first + off, null, limits.maxNesting);
		return p.next() ?? PNull;
	}

	function decryptAll(v:PdfValue, n:Int, depth:Int):PdfValue {
		if (depth > limits.maxNesting) return v;
		return switch v {
			case PStr(b): PStr(crypto.decrypt(b, n, 0, false));
			case PArray(a): PArray([for (x in a) decryptAll(x, n, depth + 1)]);
			case PDict(d):
				for (k => x in d.map)
					d.map.set(k, decryptAll(x, n, depth + 1));
				PDict(d);
			case PStream(d, data):
				for (k => x in d.map)
					d.map.set(k, decryptAll(x, n, depth + 1));
				var t = Values.name(d.get("Type"));
				PStream(d, t == "XRef" ? data : crypto.decrypt(data, n, 0, true));
			case _: v;
		}
	}

	// a stream's bytes decoded by its filters (stopAt: one left for the caller); within the budgets
	public function stream(v:PdfValue, ?stopAt:Array<String>):Bytes
		return streamWith(v, stopAt).data;

	public function streamWith(v:PdfValue, ?stopAt:Array<String>):{data:Bytes, rest:Null<String>, parms:Null<PdfDict>} {
		v = resolve(v);
		switch v {
			case PStream(d, raw):
				var left = limits.maxDecoded - decoded;
				if (left <= 0) throw PdfError.tooLarge("the document's streams past " + limits.maxDecoded + " bytes decoded");
				var r = Filters.decode(raw, d, Std.int(Math.min(limits.maxStream, left)), this, stopAt);
				decoded += r.data.length;
				return r;
			case _:
				return {data: Bytes.alloc(0), rest: null, parms: null};
		}
	}

	// ---- pages

	// (the page tree's first leaf alone, the count its root's /Count: a file's first page without
	// reading every page's dictionary; false, a tree that does not say: every page then)
	function firstLeaf():Bool {
		var root = Values.dict(resolve(trailer.get("Root")));
		if (root == null) return false;
		var node = Values.dict(resolve(root.get("Pages")));
		if (node == null) return false;
		var n = Values.int(node.get("Count"), -1);
		if (n <= 0 || n > limits.maxPages) return false;
		var inh = {resources: PNull, media: PNull, crop: PNull, rotate: PNull}, depth = 0;
		while (depth++ < 64) {
			if (node.has("Resources")) inh.resources = node.get("Resources");
			if (node.has("MediaBox")) inh.media = node.get("MediaBox");
			if (node.has("CropBox")) inh.crop = node.get("CropBox");
			if (node.has("Rotate")) inh.rotate = node.get("Rotate");
			var kids = Values.arr(resolve(node.get("Kids")));
			if (kids == null || Values.name(node.get("Type")) == "Page") {
				pages = [new Page(this, node, inh.resources, inh.media, inh.crop, Values.int(resolve(inh.rotate)))];
				count = n;
				return true;
			}
			// (the first kid with a page in it)
			var next:Null<PdfDict> = null;
			for (k in kids) {
				var d = Values.dict(resolve(k));
				if (d != null && (Values.name(d.get("Type")) == "Page" || Values.int(d.get("Count"), 1) > 0)) {
					next = d;
					break;
				}
			}
			if (next == null) return false;
			node = next;
		}
		return false;
	}

	function readPages() {
		var root = Values.dict(resolve(trailer.get("Root")));
		if (root == null) throw PdfError.corrupt("no catalog");
		var seen = new Map<Int, Bool>();
		function walk(v:PdfValue, inherited:{resources:PdfValue, media:PdfValue, crop:PdfValue, rotate:PdfValue}, depth:Int) {
			if (depth > 64) throw PdfError.corrupt("a page tree past 64 levels");
			switch v {
				case PRef(n, _):
					if (seen.exists(n)) return;
					seen.set(n, true);
				case _:
			}
			var d = Values.dict(resolve(v));
			if (d == null) return;
			var inh = {
				resources: d.has("Resources") ? d.get("Resources") : inherited.resources,
				media: d.has("MediaBox") ? d.get("MediaBox") : inherited.media,
				crop: d.has("CropBox") ? d.get("CropBox") : inherited.crop,
				rotate: d.has("Rotate") ? d.get("Rotate") : inherited.rotate
			};
			var kids = Values.arr(resolve(d.get("Kids")));
			var type = Values.name(d.get("Type"));
			if (kids != null && type != "Page") {
				for (k in kids)
					walk(k, inh, depth + 1);
			} else {
				if (pages.length >= limits.maxPages) throw PdfError.tooLarge("past " + limits.maxPages + " pages");
				pages.push(new Page(this, d, inh.resources, inh.media, inh.crop, Values.int(resolve(inh.rotate))));
			}
		}
		walk(root.get("Pages"), {resources: PNull, media: PNull, crop: PNull, rotate: PNull}, 0);
	}
}

// A page: its dictionary and what it inherits; its box in points
class Page {
	public final doc:Document;
	public final dict:PdfDict;
	public final resources:Null<PdfDict>;
	public final box:Array<Float>;
	public final rotate:Int;

	public function new(doc:Document, dict:PdfDict, resources:PdfValue, media:PdfValue, crop:PdfValue, rotate:Int) {
		this.doc = doc;
		this.dict = dict;
		this.resources = Values.dict(doc.resolve(resources));
		var m = Values.nums(doc.resolve(media)), c = Values.nums(doc.resolve(crop));
		var b = c != null && c.length == 4 ? c : m != null && m.length == 4 ? m : [0.0, 0, 612, 792];
		box = [Math.min(b[0], b[2]), Math.min(b[1], b[3]), Math.max(b[0], b[2]), Math.max(b[1], b[3])];
		var r = rotate % 360;
		if (r < 0) r += 360;
		this.rotate = Std.int(r / 90) * 90;
	}

	// its size in points, rotated as shown
	public var width(get, never):Float;
	public var height(get, never):Float;

	function get_width()
		return rotate % 180 == 0 ? box[2] - box[0] : box[3] - box[1];

	function get_height()
		return rotate % 180 == 0 ? box[3] - box[1] : box[2] - box[0];

	// the page's content streams, one after another
	static var nextId = 0;
	final id = nextId++;

	// (kept in the document's cache, Document.images, beside the decoded images: a page drawn again
	// is not inflated again)
	public function contents():Bytes {
		var key = "contents " + id;
		var kept:Null<Bytes> = doc.images.get(key);
		if (kept != null) return kept;
		var b = readContents();
		doc.images.put(key, b, b.length);
		return b;
	}

	function readContents():Bytes {
		var v = doc.resolve(dict.get("Contents"));
		var parts = switch v {
			case PArray(a): a;
			case PNull: [];
			case _: [v];
		}
		var b = new haxe.io.BytesBuffer();
		for (part in parts) {
			b.add(doc.stream(part));
			b.addByte(10);
		}
		return b.getBytes();
	}
}

// A security handler's decryption of a string or stream (Crypto: the standard handler's)
interface Decryptor {
	function decrypt(data:Bytes, num:Int, gen:Int, stream:Bool):Bytes;
}

// A document's decoded images by key (an image XObject's reference and the size it is shown at) and
// its pages' decoded content streams, bounded by bytes together, the least recently used let go of
// first (its release called: a browser image's)
class ImageCache {
	final budget:Int;
	final entries = new Map<String, {value:Dynamic, bytes:Int, used:Int, release:Null<() -> Void>}>();
	var total = 0;
	var tick = 0;

	public function new(budget:Int)
		this.budget = budget;

	public function get(key:String):Null<Dynamic> {
		var e = entries.get(key);
		if (e == null) return null;
		e.used = ++tick;
		return e.value;
	}

	public function put(key:String, value:Dynamic, bytes:Int, ?release:() -> Void) {
		if (bytes > budget) {
			if (release != null) release();
			return;
		}
		remove(key);
		while (total + bytes > budget) {
			var oldest:Null<String> = null, at = 0x7fffffff;
			for (k => e in entries)
				if (e.used < at) {
					at = e.used;
					oldest = k;
				}
			if (oldest == null) break;
			remove(oldest);
		}
		entries.set(key, {value: value, bytes: bytes, used: ++tick, release: release});
		total += bytes;
	}

	public function remove(key:String) {
		var e = entries.get(key);
		if (e == null) return;
		entries.remove(key);
		total -= e.bytes;
		if (e.release != null) e.release();
	}

	// every image let go of
	public function clear()
		for (k in [for (k in entries.keys()) k])
			remove(k);

	public var bytes(get, never):Int;

	function get_bytes()
		return total;
}
