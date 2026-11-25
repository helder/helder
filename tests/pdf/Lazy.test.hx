package pdf;

import haxe.io.Bytes;
import helder.pdf.Document;
import helder.pdf.Pdf;
import helder.pdf.PdfLimits;
import helder.pdf.PdfSource;
import helder.test.Gen;
import helder.test.Test;

// helder.pdf read lazily (Pdf.openSource), natively and on wasm32-wasi in
// the test lane: the corpus (tests/pdf/corpus) the same whole and lazily
// (pages, their text, page 1's pixels); page 1 of a large file and of a
// linearized one read from a small share of it (a counting source, small
// blocks); a linearized file updated since falling back; a fetched
// source's PdfMissing; and, as a property, any order of pages the same
// lazily as whole. The large files are made here (make: a page's content
// padded; linearized: the first page's section first, its xref, the rest's
// at the end).
function tests() {
	describe("PDF, read lazily", () -> {
		function small(block = 1024, cache = 4 << 20):PdfLimits {
			var l = new PdfLimits();
			l.readBlock = block;
			l.readCache = cache;
			return l;
		}
		function pixels(doc:Document, i:Int):Bytes
			return Pdf.render(doc, i, 0.25).straight();
		test("the corpus: the same pages, text and pixels whole and lazily", () -> {
			var dir = "tests/pdf/corpus";
			var names = [for (f in sys.FileSystem.readDirectory(dir)) if (StringTools.endsWith(f, ".pdf")) f];
			names.sort(Reflect.compare);
			for (f in names) {
				var b = sys.io.File.getBytes('$dir/$f');
				var whole = Pdf.open(b), lazy = Pdf.openSource(new Counting(b), false, "", small(4096));
				equals('$f ${lazy.pages.length} ${lazy.count} ${lazy.repaired}', '$f ${whole.pages.length} ${whole.pages.length} ${whole.repaired}');
				for (i in [0, whole.pages.length - 1]) {
					equals('$f $i ${lazy.pages[i].width}x${lazy.pages[i].height} ${lazy.pages[i].rotate}',
						'$f $i ${whole.pages[i].width}x${whole.pages[i].height} ${whole.pages[i].rotate}');
					equals(Pdf.text(lazy.pages[i]), Pdf.text(whole.pages[i]));
				}
				assert(pixels(lazy, 0).compare(pixels(whole, 0)) == 0, '$f: page 1 drawn otherwise');
				// (its first page alone: the same page, the same count)
				var first = Pdf.openSource(new Counting(b), true, "", small(4096));
				equals('$f ${first.count} ${Pdf.text(first.pages[0])}', '$f ${whole.pages.length} ${Pdf.text(whole.pages[0])}');
			}
		});
		test("page 1 of a large file: its tail and its objects, not the file", () -> {
			var b = make(120, 32768, false), c = new Counting(b);
			var doc = Pdf.openSource(c, true, "", small());
			equals(doc.count, 120);
			equals(Pdf.text(doc.pages[0]), Pdf.text(Pdf.open(b).pages[0]));
			assert(pixels(doc, 0).compare(pixels(Pdf.open(b), 0)) == 0, "page 1 drawn otherwise");
			assert(c.total < b.length / 20, 'read ${c.total} of ${b.length}');
			// (every page's size: their dictionaries read, still not their contents)
			var c2 = new Counting(b), all = Pdf.openSource(c2, false, "", small());
			equals(all.pages.length, 120);
			assert(c2.total < b.length / 4, 'every page: read ${c2.total} of ${b.length}');
		});
		test("a linearized file's first page: its first section alone", () -> {
			var b = make(120, 32768, true), c = new Counting(b);
			var e = entry(b, "E"), doc = Pdf.openSource(c, true, "", small());
			equals([doc.count, doc.pages.length], [120, 1]);
			equals(Pdf.text(doc.pages[0]), Pdf.text(Pdf.open(b).pages[0]));
			assert(pixels(doc, 0).compare(pixels(Pdf.open(b), 0)) == 0, "page 1 drawn otherwise");
			// (its first /E bytes, in blocks of 1 KB: and the block holding /E)
			assert(c.total <= e + 1024, 'read ${c.total}, /E $e');
			assert(c.maxEnd <= e + 1024, 'read to ${c.maxEnd}, /E $e');
			// (the whole file's path: every page, the same)
			var all = Pdf.openSource(new Counting(b), false, "", small());
			equals(all.pages.length, 120);
			equals(Pdf.text(all.pages[119]), Pdf.text(Pdf.open(b).pages[119]));
			assert(Pdf.text(all.pages[119]).indexOf("Page 120") >= 0, Pdf.text(all.pages[119]));
		});
		test("a linearized file updated since (/L not its length): read as any other", () -> {
			var b = make(12, 2048, true), more = Bytes.ofString("\n% an update appended\n");
			var u = Bytes.alloc(b.length + more.length);
			u.blit(0, b, 0, b.length);
			u.blit(b.length, more, 0, more.length);
			var doc = Pdf.openSource(new Counting(u), true, "", small());
			equals([doc.count, doc.pages.length], [12, 1]);
			equals(Pdf.text(doc.pages[0]), Pdf.text(Pdf.open(u).pages[0]));
		});
		test("a fetched source: each block missing fetched, the work done again", () -> {
			for (linear in [false, true]) {
				var b = make(30, 8192, linear), src = new PdfFetched(b.length), fetched = 0;
				function fetch(m:PdfMissing) {
					src.add(m.index, b.sub(m.index * PdfFetched.BLOCK, m.length));
					fetched++;
				}
				var doc:Null<Document> = null;
				while (doc == null)
					try doc = Pdf.openSource(src, true) catch (m:PdfMissing) fetch(m);
				var text:Null<String> = null;
				while (text == null)
					try text = Pdf.text(doc.pages[0]) catch (m:PdfMissing) fetch(m);
				equals('$linear $text ${doc.count}', '$linear ${Pdf.text(Pdf.open(b).pages[0])} 30');
				assert(fetched > 0 && fetched < Math.ceil(b.length / PdfFetched.BLOCK), '$linear: $fetched blocks of ${Math.ceil(b.length / PdfFetched.BLOCK)}');
			}
		});
		test("any order of pages: the same lazily as whole (a cache of two blocks)", () -> {
			var b = make(24, 4096, false), whole = Pdf.open(b);
			var texts = [for (p in whole.pages) Pdf.text(p)];
			property(array(int(0, 23)), order -> {
				var lazy = Pdf.openSource(new Counting(b), false, "", small(1024, 2048));
				for (i in order) {
					equals(Pdf.text(lazy.pages[i]), texts[i]);
					equals(keys(lazy.pages[i].dict), keys(whole.pages[i].dict));
				}
			});
		});
	});
}

// (a source over bytes that counts what is read: bytes, and the farthest)
private class Counting implements PdfSource {
	public var total(default, null) = 0;
	public var maxEnd(default, null) = 0;
	public var size(get, never):Int;

	final bytes:Bytes;

	public function new(bytes:Bytes)
		this.bytes = bytes;

	function get_size():Int
		return bytes.length;

	public function read(offset:Int, b:Bytes, pos:Int, len:Int):Int {
		var n = Std.int(Math.max(0, Math.min(len, bytes.length - offset)));
		b.blit(pos, bytes, offset, n);
		total += n;
		if (offset + n > maxEnd) maxEnd = offset + n;
		return n;
	}

	public function close() {}
}

private function keys(d:helder.pdf.PdfValue.PdfDict):Array<String> {
	var k = [for (k in d.map.keys()) k];
	k.sort(Reflect.compare);
	return k;
}

// a /Linearized dictionary's entry (its /E, /L ...) in b's first KB
private function entry(b:Bytes, key:String):Int {
	var head = b.getString(0, Std.int(Math.min(1024, b.length)));
	var r = new EReg("/" + key + " (\\d+)", "");
	return r.match(head) ? Std.parseInt(r.matched(1)) : -1;
}

// a PDF of n pages ("Page i" in Helvetica, a grey square), each page's content
// padded by comments to pad bytes; linearized: the first page's section first
// (its /Linearized dictionary, its xref, the catalog, the page tree, the font,
// page 1), the others after, their xref at the end
private function make(n:Int, pad:Int, linearized:Bool):Bytes {
	inline function num(v:Int):String
		return StringTools.lpad(Std.string(v), "0", 10);
	function content(i:Int):String {
		var s = 'BT /F1 24 Tf 72 700 Td (Page ${i + 1}) Tj ET\n0.5 g 72 72 100 100 re f\n';
		var line = "% " + StringTools.lpad("", "x", 77) + "\n";
		while (s.length + line.length <= pad)
			s += line;
		return s;
	}
	// (objects: 1 the /Linearized dictionary (linearized only), 2 the catalog, 3 the pages, 4 the
	// font, then page i: 5 + 2i, its content 6 + 2i)
	var page = i -> 5 + 2 * i, total = 5 + 2 * n;
	var bodies = new Map<Int, String>();
	bodies.set(2, "<< /Type /Catalog /Pages 3 0 R >>");
	bodies.set(3, "<< /Type /Pages /Count " + n + " /Kids [" + [for (i in 0...n) '${page(i)} 0 R'].join(" ") + "] >>");
	bodies.set(4, "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>");
	for (i in 0...n) {
		bodies.set(page(i), '<< /Type /Page /Parent 3 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents ${page(i) + 1} 0 R >>');
		var c = content(i);
		bodies.set(page(i) + 1, '<< /Length ${c.length} >>\nstream\n${c}endstream');
	}
	inline function obj(k:Int):String
		return '$k 0 obj\n${bodies.get(k)}\nendobj\n';
	function table(from:Int, count:Int, at:Map<Int, Int>, withFree:Bool):String {
		var s = new StringBuf();
		s.add("xref\n");
		if (withFree) s.add("0 1\n0000000000 65535 f \n");
		s.add('$from $count\n');
		for (k in from...from + count)
			s.add(StringTools.lpad(Std.string(at.get(k)), "0", 10) + " 00000 n \n");
		return s.toString();
	}
	var at = new Map<Int, Int>(), out = new StringBuf(), length = 0;
	inline function add(s:String) {
		out.add(s);
		length += s.length;
	}
	var header = "%PDF-1.7\n%made by Lazy.test.hx\n";
	if (!linearized) {
		add(header);
		for (k in 2...total) {
			at.set(k, length);
			add(obj(k));
		}
		var x = length;
		add("xref\n0 1\n0000000000 65535 f \n" + table(2, total - 2, at, false).substr(5));
		add('trailer\n<< /Size $total /Root 2 0 R >>\nstartxref\n$x\n%%EOF\n');
		return Bytes.ofString(out.toString());
	}
	// (two passes: the fixed-width numbers (/L, /E, /T, the xrefs' offsets) known the second time)
	var first = [2, 3, 4, page(0), page(0) + 1], rest = [for (k in page(1)...total) k];
	var known = {l: 0, e: 0, t: 0, firstXref: 0};
	for (pass in 0...2) {
		out = new StringBuf();
		length = 0;
		add(header);
		at.set(1, length);
		add('1 0 obj\n<< /Linearized 1 /L ${num(known.l)} /H [0 0] /O ${page(0)} /E ${num(known.e)} /N $n /T ${num(known.t)} >>\nendobj\n');
		known.firstXref = length;
		var fx = new StringBuf();
		fx.add("xref\n0 1\n0000000000 65535 f \n1 6\n");
		for (k in [1, 2, 3, 4, page(0), page(0) + 1])
			fx.add(StringTools.lpad(Std.string(at.get(k) ?? 0), "0", 10) + " 00000 n \n");
		add(fx.toString());
		add('trailer\n<< /Size $total /Root 2 0 R /Prev ${num(known.t)} >>\nstartxref\n0\n%%EOF\n');
		for (k in first) {
			at.set(k, length);
			add(obj(k));
		}
		known.e = length;
		for (k in rest) {
			at.set(k, length);
			add(obj(k));
		}
		known.t = length;
		add(table(rest[0], rest.length, at, false));
		add('trailer\n<< /Size $total /Root 2 0 R >>\nstartxref\n${known.firstXref}\n%%EOF\n');
		known.l = length;
	}
	return Bytes.ofString(out.toString());
}
