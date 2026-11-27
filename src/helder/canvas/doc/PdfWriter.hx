package helder.canvas.doc;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import helder.canvas.ColorGlyphs;
import helder.canvas.Gradient;
import helder.canvas.doc.Recorder;
import helder.canvas.doc.PdfFonts;
import helder.text.FontFile;

// A Document as a PDF (1.7): a page a recording, its calls as vectors.
// Paths as PDF's (m, l, c, h; f, f*, S; W n for clips, q and Q for saves),
// colours with their opacity and blend mode in an ExtGState, linear and
// radial gradients as axial and radial shadings (their stops a stitching
// function, their alpha a luminosity soft mask), images as image
// XObjects with their alpha as a soft mask, layers as transparency groups.
// What PDF cannot say (conic gradients, patterns, a gradient's reflect or
// repeat, erasing) is drawn on the CPU into an image of its own (the page's
// size, at `fallbackScale`). Streams Flate-compressed (helder.image's
// zlib).
//
// Text recorded as text (Recorder's Text ops, from GlyphText) is PDF text:
// each face one embedded subset font for the document (PdfFonts), each
// glyph placed where the layout put it (Tm, TJ), filled (Tr 0: a colour, or
// a linear or radial gradient as a pattern) or stroked (Tr 1, the pen in
// the painter's units, as a path's). What text cannot show as drawn is
// drawn apart and its text made invisible (Tr 3), so that copy and search
// still find it: a paint PDF's text cannot have (a pattern, a conic
// gradient, an unbounded operator: its outlines, then the CPU's), colour
// glyphs (COLR's layers as fills, CBDT's and sbix's bitmaps as images).
// Text in a layer with a filter (a shadow's copy) is outlines alone, so each
// character is found once. Characters ToUnicode cannot say glyph by glyph
// (a cluster of several glyphs, a glyph shown before for other characters,
// a right-to-left run in visual order) are an ActualText span of them in
// their logical order. Links, anchors, bookmarks, page labels and the
// document's information are Document's.
class PdfWriter {
	public var fallbackScale = 2.0;

	final objects:Array<Null<Bytes>> = [null];
	var resources:Resources;
	// (the page's resources' object: its forms' too)
	var resourcesId = 0;
	final fonts:PdfFonts;

	public function new() {
		fonts = new PdfFonts(this);
	}

	public static function write(doc:Document):Bytes
		return new PdfWriter().document(doc);

	@:allow(helder.canvas.doc)
	function reserve():Int {
		objects.push(null);
		return objects.length - 1;
	}

	@:allow(helder.canvas.doc)
	function set(id:Int, s:String)
		objects[id] = Bytes.ofString(s);

	@:allow(helder.canvas.doc)
	function stream(id:Int, dict:String, data:Bytes, compress = true) {
		var body = compress ? helder.image.Deflate.zlib(data) : data;
		var b = new BytesBuffer();
		b.addString('<< $dict${compress ? " /Filter /FlateDecode" : ""} /Length ${body.length} >>\nstream\n');
		b.addBytes(body, 0, body.length);
		b.addString("\nendstream");
		objects[id] = b.getBytes();
	}

	@:allow(helder.canvas.doc)
	function add(s:String):Int {
		var id = reserve();
		set(id, s);
		return id;
	}

	public function document(doc:Document):Bytes {
		var pagesId = reserve();
		var kids = [for (_ in doc.pages) reserve()];
		for (i in 0...doc.pages.length)
			page(doc, i, kids[i], pagesId);
		set(pagesId, '<< /Type /Pages /Kids [${[for (k in kids) '$k 0 R'].join(" ")}] /Count ${kids.length} >>');
		fonts.write();
		var cat = new StringBuf();
		cat.add('<< /Type /Catalog /Pages $pagesId 0 R');
		var outline = outlines(doc, kids);
		if (outline > 0) cat.add(' /Outlines $outline 0 R /PageMode /UseOutlines');
		var dests = names(doc, kids);
		if (dests != "") cat.add(' /Names << /Dests << /Names [$dests] >> >>');
		var labels = pageLabels(doc);
		if (labels != "") cat.add(' /PageLabels << /Nums [$labels] >>');
		if (doc.lang != null) cat.add(' /Lang ${textString(doc.lang)}');
		var meta = reserve();
		stream(meta, "/Type /Metadata /Subtype /XML", xmp(doc), false);
		cat.add(' /Metadata $meta 0 R >>');
		var catalog = add(cat.toString());
		var info = add(infoDict(doc));
		var out = new BytesBuffer();
		// (the header, then a comment of bytes past ASCII: a binary file)
		var head = Bytes.ofHex("255044462d312e370a25e2e3cfd30a");
		out.addBytes(head, 0, head.length);
		var offsets = [0];
		var pos = head.length;
		for (i in 1...objects.length) {
			offsets.push(pos);
			var s = Bytes.ofString('$i 0 obj\n');
			out.addBytes(s, 0, s.length);
			var o = objects[i];
			out.addBytes(o, 0, o.length);
			var e = Bytes.ofString("\nendobj\n");
			out.addBytes(e, 0, e.length);
			pos += s.length + o.length + e.length;
		}
		var xref = new StringBuf();
		xref.add('xref\n0 ${objects.length}\n0000000000 65535 f \n');
		for (i in 1...objects.length)
			xref.add(StringTools.lpad(Std.string(offsets[i]), "0", 10) + " 00000 n \n");
		xref.add('trailer\n<< /Size ${objects.length} /Root $catalog 0 R /Info $info 0 R >>\nstartxref\n$pos\n%%EOF\n');
		out.addString(xref.toString());
		return out.getBytes();
	}

	function page(doc:Document, index:Int, id:Int, parent:Int) {
		var r = doc.pages[index];
		resources = new Resources();
		resourcesId = reserve();
		var content = new StringBuf();
		// (canvas units: y down from the top left)
		content.add('1 0 0 -1 0 ${r.height} cm\n');
		body(r, 0, r.ops.length, content, true);
		var cid = reserve();
		stream(cid, "", Bytes.ofString(content.toString()));
		set(resourcesId, resources.dict());
		var annots = [];
		for (l in doc.links)
			if (l.page == index) {
				var rect = '[${num(l.x)} ${num(r.height - l.y - l.h)} ${num(l.x + l.w)} ${num(r.height - l.y)}]';
				var target = l.uri != null ? '/A << /S /URI /URI ${byteString(l.uri)} >>' : '/Dest ${textString(l.name)}';
				annots.push(add('<< /Type /Annot /Subtype /Link /Rect $rect /Border [0 0 0] /F 4 $target >>'));
			}
		var a = annots.length > 0 ? ' /Annots [${[for (x in annots) '$x 0 R'].join(" ")}]' : "";
		set(id, '<< /Type /Page /Parent $parent 0 R /MediaBox [0 0 ${r.width} ${r.height}] /Resources $resourcesId 0 R /Contents $cid 0 R$a'
			+ ' /Group << /S /Transparency /CS /DeviceRGB >> >>');
	}

	// a place on a page as a destination (y its top, in the page's units; x null: the reader's)
	function dest(doc:Document, kids:Array<Int>, page:Int, x:Null<Float>, y:Float):String
		return '[${kids[page]} 0 R /XYZ ${x == null ? "null" : num(x)} ${num(doc.pages[page].height - y)} null]';

	// the named destinations' tree: one leaf, its names in the order of their strings' bytes
	function names(doc:Document, kids:Array<Int>):String {
		var byName = new Map<String, String>();
		for (a in doc.anchors)
			if (a.page >= 0 && a.page < kids.length) byName.set(a.name, dest(doc, kids, a.page, a.x, a.y));
		var list = [for (k in byName.keys()) k];
		list.sort((a, b) -> {
			var x = stringBytes(a), y = stringBytes(b);
			for (i in 0...(x.length < y.length ? x.length : y.length))
				if (x[i] != y[i]) return x[i] - y[i];
			return x.length - y.length;
		});
		return [for (k in list) '${textString(k)} ${byName.get(k)}'].join(" ");
	}

	// (a text string's bytes as textString writes it)
	static function stringBytes(s:String):Array<Int> {
		var out = [], ascii = true;
		for (i in 0...s.length) {
			var c = StringTools.fastCodeAt(s, i);
			if (c < 32 || c > 126) ascii = false;
		}
		if (ascii) return [for (i in 0...s.length) StringTools.fastCodeAt(s, i)];
		out.push(0xFE);
		out.push(0xFF);
		for (i in 0...s.length) {
			var c = StringTools.fastCodeAt(s, i);
			out.push(c >> 8);
			out.push(c & 255);
		}
		return out;
	}

	// the bookmarks as the outline's items, each one's parent the last shallower one before it (0: none)
	function outlines(doc:Document, kids:Array<Int>):Int {
		var list = [for (b in doc.bookmarks) if (b.page >= 0 && b.page < kids.length) b];
		if (list.length == 0) return 0;
		var root = reserve();
		var ids = [for (_ in list) reserve()];
		var children:Array<Array<Int>> = [for (_ in list) []], top = [], stack:Array<Int> = [];
		for (i in 0...list.length) {
			while (stack.length > 0 && list[stack[stack.length - 1]].level >= list[i].level)
				stack.pop();
			if (stack.length == 0) top.push(i) else children[stack[stack.length - 1]].push(i);
			stack.push(i);
		}
		function count(i:Int):Int {
			var n = 0;
			for (c in children[i])
				n += 1 + count(c);
			return n;
		}
		function items(of:Array<Int>, up:Int) {
			for (k in 0...of.length) {
				var i = of[k], b = new StringBuf();
				b.add('<< /Title ${textString(list[i].title)} /Parent $up 0 R /Dest ${dest(doc, kids, list[i].page, null, list[i].y)}');
				if (k > 0) b.add(' /Prev ${ids[of[k - 1]]} 0 R');
				if (k + 1 < of.length) b.add(' /Next ${ids[of[k + 1]]} 0 R');
				var c = children[i];
				if (c.length > 0) b.add(' /First ${ids[c[0]]} 0 R /Last ${ids[c[c.length - 1]]} 0 R /Count ${count(i)}');
				b.add(" >>");
				set(ids[i], b.toString());
				items(c, ids[i]);
			}
		}
		items(top, root);
		set(root, '<< /Type /Outlines /First ${ids[top[0]]} 0 R /Last ${ids[top[top.length - 1]]} 0 R /Count ${list.length} >>');
		return root;
	}

	function pageLabels(doc:Document):String {
		var list = [for (l in doc.labels) if (l.page >= 0 && l.page < doc.pages.length) l];
		if (list.length == 0) return "";
		list.sort((a, b) -> a.page - b.page);
		var b = new StringBuf();
		// (the first range starts at the first page: numbers as usual before the first label)
		if (list[0].page != 0) b.add("0 << /S /D >> ");
		for (l in list) {
			var s = switch l.style {
				case "decimal": "D";
				case "lower-roman": "r";
				case "upper-roman": "R";
				case "lower-alpha": "a";
				case "upper-alpha": "A";
				case _: null;
			}
			b.add('${l.page} <<${s == null ? "" : ' /S /$s'}${l.prefix != "" ? ' /P ${textString(l.prefix)}' : ""}${l.start != 1 ? ' /St ${l.start}' : ""} >> ');
		}
		return StringTools.trim(b.toString());
	}

	function infoDict(doc:Document):String {
		var b = new StringBuf();
		b.add("<<");
		for (e in [
			["Title", doc.title],
			["Author", doc.author],
			["Subject", doc.subject],
			["Keywords", doc.keywords],
			["Creator", doc.creator],
			["Producer", doc.producer]
		])
			if (e[1] != null) b.add(' /${e[0]} ${textString(e[1])}');
		if (doc.created != null) b.add(' /CreationDate (${pdfDate(doc.created)})');
		if (doc.modified != null) b.add(' /ModDate (${pdfDate(doc.modified)})');
		b.add(" >>");
		return b.toString();
	}

	static function two(v:Int):String
		return StringTools.lpad(Std.string(v), "0", 2);

	static function pdfDate(d:Date):String
		return 'D:${d.getUTCFullYear()}${two(d.getUTCMonth() + 1)}${two(d.getUTCDate())}${two(d.getUTCHours())}${two(d.getUTCMinutes())}${two(d.getUTCSeconds())}Z';

	static function isoDate(d:Date):String
		return '${d.getUTCFullYear()}-${two(d.getUTCMonth() + 1)}-${two(d.getUTCDate())}T${two(d.getUTCHours())}:${two(d.getUTCMinutes())}:${two(d.getUTCSeconds())}Z';

	// the information again as XMP (Dublin Core's, XMP's and PDF's schemas)
	function xmp(doc:Document):Bytes {
		var esc = s -> StringTools.htmlEscape(s, true);
		var b = new StringBuf();
		b.add('<?xpacket begin="\u{FEFF}" id="W5M0MpCehiHzreSzNTczkc9d"?>\n<x:xmpmeta xmlns:x="adobe:ns:meta/">\n');
		b.add('<rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">\n<rdf:Description rdf:about=""');
		b.add(' xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:xmp="http://ns.adobe.com/xap/1.0/" xmlns:pdf="http://ns.adobe.com/pdf/1.3/">\n');
		b.add("<dc:format>application/pdf</dc:format>\n");
		if (doc.title != null) b.add('<dc:title><rdf:Alt><rdf:li xml:lang="x-default">${esc(doc.title)}</rdf:li></rdf:Alt></dc:title>\n');
		if (doc.author != null) b.add('<dc:creator><rdf:Seq><rdf:li>${esc(doc.author)}</rdf:li></rdf:Seq></dc:creator>\n');
		if (doc.subject != null) b.add('<dc:description><rdf:Alt><rdf:li xml:lang="x-default">${esc(doc.subject)}</rdf:li></rdf:Alt></dc:description>\n');
		if (doc.keywords != null) {
			b.add("<dc:subject><rdf:Bag>");
			for (k in doc.keywords.split(","))
				if (StringTools.trim(k) != "") b.add('<rdf:li>${esc(StringTools.trim(k))}</rdf:li>');
			b.add('</rdf:Bag></dc:subject>\n<pdf:Keywords>${esc(doc.keywords)}</pdf:Keywords>\n');
		}
		if (doc.lang != null) b.add('<dc:language><rdf:Bag><rdf:li>${esc(doc.lang)}</rdf:li></rdf:Bag></dc:language>\n');
		if (doc.producer != null) b.add('<pdf:Producer>${esc(doc.producer)}</pdf:Producer>\n');
		if (doc.creator != null) b.add('<xmp:CreatorTool>${esc(doc.creator)}</xmp:CreatorTool>\n');
		if (doc.created != null) b.add('<xmp:CreateDate>${isoDate(doc.created)}</xmp:CreateDate>\n');
		if (doc.modified != null) b.add('<xmp:ModifyDate>${isoDate(doc.modified)}</xmp:ModifyDate>\n');
		b.add('</rdf:Description>\n</rdf:RDF>\n</x:xmpmeta>\n<?xpacket end="w"?>');
		return Bytes.ofString(b.toString(), UTF8);
	}

	// a text string: printable ASCII as it is, else UTF-16BE after its byte order mark
	static function textString(s:String):String {
		var ascii = true;
		for (i in 0...s.length) {
			var c = StringTools.fastCodeAt(s, i);
			if (c < 32 || c > 126) ascii = false;
		}
		if (ascii) return byteString(s);
		var b = new StringBuf();
		b.add("<FEFF");
		for (i in 0...s.length)
			b.add(StringTools.hex(StringTools.fastCodeAt(s, i), 4));
		b.add(">");
		return b.toString();
	}

	// a string of bytes (a URI's UTF-8) as a literal, its parentheses and backslashes escaped
	static function byteString(s:String):String {
		var bytes = Bytes.ofString(s, UTF8), b = new StringBuf();
		b.add("(");
		for (i in 0...bytes.length) {
			var c = bytes.get(i);
			if (c == "(".code || c == ")".code || c == "\\".code) {
				b.addChar("\\".code);
				b.addChar(c);
			} else if (c < 32 || c > 126) {
				b.addChar("\\".code);
				for (k in [6, 3, 0])
					b.addChar("0".code + ((c >> k) & 7));
			} else b.addChar(c);
		}
		b.add(")");
		return b.toString();
	}

	// ops from..to into content; a layer's ops into a group of their own (asText: text as text, not in a
	// layer with a filter, a shadow's copy)
	function body(r:Recorder, from:Int, to:Int, out:StringBuf, asText:Bool) {
		var i = from;
		while (i < to) {
			var o = r.ops[i];
			switch o.kind {
				case Save:
					out.add("q\n");
				case Restore:
					out.add("Q\n");
				case Layer:
					// (its ops up to its restore: a transparency group drawn with its alpha and blend)
					var depth = 0, j = i + 1;
					while (j < to) {
						var k = r.ops[j].kind;
						if (k == Save || k == Layer) depth++;
						if (k == Restore) {
							if (depth == 0) break;
							depth--;
						}
						j++;
					}
					var inner = new StringBuf();
					body(r, i + 1, j, inner, asText && o.filter == null);
					var fid = reserve();
					stream(fid, '/Type /XObject /Subtype /Form /BBox [0 0 ${r.width} ${r.height}] /Group << /S /Transparency /CS /DeviceRGB >> /Resources $resourcesId 0 R', Bytes.ofString(inner.toString()));
					resources.forms.push(fid);
					var gs = resources.state(o.alpha, o.alpha, o.blend);
					// (the group in the canvas's units, as the page's content around it)
					out.add('q /$gs gs /Fm$fid Do Q\n');
					i = j;
				case Clip:
					path(o.path, o.matrix, out);
					out.add(o.evenOdd ? "W* n\n" : "W n\n");
				case Fill | StrokePath:
					paintOp(r, o, out);
				case Text:
					if (asText) {
						i = text(r, i, to, out);
						continue;
					}
					paintOp(r, o.outlined(), out);
				case Clear:
					if (((o.color >>> 24) & 255) > 0) {
						out.add('q ${rgb(o.color)} rg /${resources.state(((o.color >>> 24) & 255) / 255, 1, null)} gs 0 0 ${r.width} ${r.height} re f Q\n');
					}
				case ClearRect | Pixels:
					fallback(r, o, out);
				case Image:
					image(o, out);
			}
			i++;
		}
	}

	// (a number as PDF writes one: at most four decimals, never an exponent)
	static function num(v:Float):String {
		var n = Math.fround(v * 10000);
		if (n == 0 || !Math.isFinite(n)) return "0";
		var neg = n < 0;
		if (neg) n = -n;
		var whole = Math.ffloor(n / 10000), frac = Std.int(n - whole * 10000);
		var s = whole < 2147483647 ? Std.string(Std.int(whole)) : Std.string(whole);
		if (frac > 0) {
			var f = StringTools.lpad(Std.string(frac), "0", 4);
			while (StringTools.endsWith(f, "0"))
				f = f.substr(0, f.length - 1);
			s += "." + f;
		}
		return neg ? "-" + s : s;
	}

	static function rgb(c:Int):String
		return '${num(((c >> 16) & 255) / 255)} ${num(((c >> 8) & 255) / 255)} ${num((c & 255) / 255)}';

	// a path through m into canvas units
	static function path(p:Path, m:Matrix, out:StringBuf) {
		var pts = p.points, pi = 0;
		inline function pt(k:Int)
			out.add(num(m.mapX(pts[k], pts[k + 1])) + " " + num(m.mapY(pts[k], pts[k + 1])) + " ");
		var lx = 0.0, ly = 0.0;
		for (i in 0...p.verbCount)
			switch p.verbs[i] {
				case Path.MOVE:
					pt(pi);
					out.add("m\n");
					lx = pts[pi];
					ly = pts[pi + 1];
					pi += 2;
				case Path.LINE:
					pt(pi);
					out.add("l\n");
					lx = pts[pi];
					ly = pts[pi + 1];
					pi += 2;
				case Path.QUAD:
					// (as a cubic: its control points two thirds of the way to the quadratic's)
					var cx = pts[pi], cy = pts[pi + 1], x = pts[pi + 2], y = pts[pi + 3];
					var c1x = lx + 2 / 3 * (cx - lx), c1y = ly + 2 / 3 * (cy - ly), c2x = x + 2 / 3 * (cx - x), c2y = y + 2 / 3 * (cy - y);
					out.add('${num(m.mapX(c1x, c1y))} ${num(m.mapY(c1x, c1y))} ${num(m.mapX(c2x, c2y))} ${num(m.mapY(c2x, c2y))} ');
					pt(pi + 2);
					out.add("c\n");
					lx = x;
					ly = y;
					pi += 4;
				case Path.CUBIC:
					pt(pi);
					pt(pi + 2);
					pt(pi + 4);
					out.add("c\n");
					lx = pts[pi + 4];
					ly = pts[pi + 5];
					pi += 6;
				case _:
					out.add("h\n");
			}
	}

	// whether a paint is one PDF has: a colour, a linear or radial gradient padded, a bounded blend mode
	static function plainPaint(p:Paint):Bool {
		var s = p.shader;
		var plain = s == null || ((Std.isOfType(s, LinearGradient) || Std.isOfType(s, RadialGradient)) && (cast s : Gradient).spread == Gradient.PAD);
		return plain && !(p.blend != null && p.blend.unbounded);
	}

	// a paint as the graphics state's: its opacity and blend mode, its colour or pattern, to fill or stroke with
	function setPaint(r:Recorder, p:Paint, m:Matrix, stroke:Bool, out:StringBuf) {
		var s = p.shader;
		var alpha = p.alpha * (s == null ? ((p.color >>> 24) & 255) / 255 : 1);
		var smask = s != null ? gradientMask(r, cast s, m) : -1;
		var gs = resources.state(alpha, alpha, p.blend, smask);
		out.add('/$gs gs\n');
		if (s == null) out.add('${rgb(p.color)} ${stroke ? "RG" : "rg"}\n') else {
			var pat = shadingPattern(r, cast s, m);
			out.add('/Pattern ${stroke ? "CS" : "cs"} /P$pat ${stroke ? "SCN" : "scn"}\n');
		}
	}

	static function pen(st:Stroke, out:StringBuf) {
		out.add('${num(st.width)} w ${st.cap.kind} J ${st.join.kind} j ${num(st.miterLimit)} M\n');
		if (st.dash != null && st.dash.valid()) out.add('[${[for (d in st.dash.intervals) num(d)].join(" ")}] ${num(st.dash.offset)} d\n');
	}

	static function cm(m:Matrix):String
		return '${num(m.a)} ${num(m.b)} ${num(m.c)} ${num(m.d)} ${num(m.e)} ${num(m.f)} cm\n';

	function paintOp(r:Recorder, o:Op, out:StringBuf) {
		var stroke = o.kind == StrokePath;
		if (!plainPaint(o.paint)) {
			fallback(r, o, out);
			return;
		}
		out.add("q\n");
		setPaint(r, o.paint, o.matrix, stroke, out);
		if (stroke) {
			// (a stroke in its own units: the transform made the PDF's, the pen with it)
			out.add(cm(o.matrix));
			pen(o.stroke, out);
			path(o.path, Matrix.IDENTITY, out);
			out.add("S\nQ\n");
		} else {
			path(o.path, o.matrix, out);
			out.add(o.evenOdd ? "f*\nQ\n" : "f\nQ\n");
		}
	}

	// ---- text

	// consecutive Text ops of one text, their characters apart (a layout's lines, its runs of faces): its
	// glyphs in the order drawn, cut where all the glyphs before show characters before all those after;
	// a piece of one glyph whose characters ToUnicode can say is shown as it is, the others are each an
	// ActualText span of their characters in order (the next op after them returned)
	function text(r:Recorder, from:Int, to:Int, out:StringBuf):Int {
		var s = r.ops[from].run.text;
		var j = from;
		var hulls:Array<Array<Int>> = [];
		while (j < to && r.ops[j].kind == Text && r.ops[j].run.text == s) {
			var run = r.ops[j].run, lo = 0x7FFFFFFF, hi = -1;
			for (k in 0...run.count) {
				if (run.starts[k] < lo) lo = run.starts[k];
				if (run.ends[k] > hi) hi = run.ends[k];
			}
			var apart = true;
			for (h in hulls)
				if (lo < h[1] && h[0] < hi) apart = false;
			if (!apart && hulls.length > 0) break;
			hulls.push([lo, hi]);
			j++;
		}
		var ops:Array<Int> = [], idx:Array<Int> = [];
		for (k in from...j)
			for (g in 0...r.ops[k].run.count) {
				ops.push(k);
				idx.push(g);
			}
		var n = ops.length;
		inline function runOf(q:Int):ShapedRun
			return r.ops[ops[q]].run;
		var after = [for (_ in 0...n + 1) 0x7FFFFFFF];
		var q = n - 1;
		while (q >= 0) {
			var st = runOf(q).starts[idx[q]];
			after[q] = st < after[q + 1] ? st : after[q + 1];
			q--;
		}
		// (the pieces: glyphs a to b, characters lo to hi)
		var cuts:Array<{a:Int, b:Int, lo:Int, hi:Int}> = [];
		var a = 0, lo = 0x7FFFFFFF, hi = -1;
		for (q in 0...n) {
			var run = runOf(q), g = idx[q];
			if (run.starts[g] < lo) lo = run.starts[g];
			if (run.ends[g] > hi) hi = run.ends[g];
			if (hi > after[q + 1]) continue;
			cuts.push({a: a, b: q + 1, lo: lo, hi: hi});
			a = q + 1;
			lo = 0x7FFFFFFF;
			hi = -1;
		}
		var pieces:Array<{a:Int, b:Int, actual:Null<String>}> = [];
		for (i in 0...cuts.length) {
			var p = cuts[i], hi = p.hi;
			// (the default ignorable characters after it, which no glyph shows: a joiner, a selector)
			var limit = i + 1 < cuts.length ? cuts[i + 1].lo : s.length;
			while (hi < limit) {
				var c = StringTools.fastCodeAt(s, hi), len = 1;
				if (c >= 0xD800 && c < 0xDC00 && hi + 1 < s.length) {
					c = 0x10000 + ((c - 0xD800) << 10) + (StringTools.fastCodeAt(s, hi + 1) - 0xDC00);
					len = 2;
				}
				if (!ignorable(c)) break;
				hi += len;
			}
			var t = hi > p.lo ? s.substring(p.lo, hi) : "";
			var actual:Null<String> = t;
			if (p.b - p.a == 1) {
				var run = runOf(p.a);
				if (fonts.get(run.face).map(run.ids[idx[p.a]], t)) actual = null;
			} else {
				// (where a glyph has its characters to itself, its ToUnicode says them too: for readers without ActualText)
				var shared = new Map<Int, Int>();
				for (x in p.a...p.b) {
					var st = runOf(x).starts[idx[x]];
					shared.set(st, (shared.get(st) ?? 0) + 1);
				}
				for (x in p.a...p.b) {
					var rx = runOf(x), gx = idx[x], f = fonts.get(rx.face);
					if (shared.get(rx.starts[gx]) == 1 && !f.mapped(rx.ids[gx]) && rx.ends[gx] > rx.starts[gx]) f.map(rx.ids[gx], s.substring(rx.starts[gx], rx.ends[gx]));
				}
			}
			pieces.push({a: p.a, b: p.b, actual: actual});
		}
		var k = 0;
		while (k < pieces.length) {
			var p = pieces[k], b = p.b;
			if (p.actual == null)
				while (k + 1 < pieces.length && pieces[k + 1].actual == null)
					b = pieces[++k].b;
			if (p.actual != null) out.add('/Span << /ActualText ${textString(p.actual)} >> BDC\n');
			var q = p.a;
			while (q < b) {
				var e = q;
				while (e < b && ops[e] == ops[q])
					e++;
				textPart(r, r.ops[ops[q]], idx[q], idx[e - 1] + 1, out);
				q = e;
			}
			if (p.actual != null) out.add("EMC\n");
			k++;
		}
		return j;
	}

	// (Unicode's default ignorable code points: drawn as nothing)
	static function ignorable(c:Int):Bool
		return c == 0xAD || c == 0x34F || c == 0x61C || c == 0x115F || c == 0x1160 || c == 0x17B4 || c == 0x17B5 || (c >= 0x180B && c <= 0x180F)
			|| (c >= 0x200B && c <= 0x200F) || (c >= 0x202A && c <= 0x202E) || (c >= 0x2060 && c <= 0x206F) || c == 0x3164 || (c >= 0xFE00 && c <= 0xFE0F)
			|| c == 0xFEFF || c == 0xFFA0 || (c >= 0xFFF0 && c <= 0xFFF8) || (c >= 0x1BCA0 && c <= 0x1BCA3) || (c >= 0x1D173 && c <= 0x1D17A)
			|| (c >= 0xE0000 && c <= 0xE0FFF);

	// whether text shows a glyph as it is drawn (not a colour one)
	static function colourGlyph(face:FontFile, g:Int, size:Float):Bool
		return face.bitmapsOnly || ColorGlyphs.has(face, g, size);

	// glyphs a to b of a Text op as a text object
	function textPart(r:Recorder, o:Op, a:Int, b:Int, out:StringBuf) {
		var run = o.run, face = run.face, f = fonts.get(face);
		if (resources.fonts.indexOf(f) < 0) resources.fonts.push(f);
		var stroke = o.stroke != null, visible = plainPaint(o.paint);
		var size = run.size, sx = size * run.scaleX;
		var colour = [for (k in a...b) colourGlyph(face, run.ids[k], size)];
		if (!visible) {
			// (a paint text cannot have: the outlines, drawn as a path is)
			var part = new ShapedRun(face, size);
			part.scaleX = run.scaleX;
			part.skew = run.skew;
			for (k in a...b)
				part.push(run.ids[k], run.xs[k], run.ys[k], run.starts[k], run.ends[k]);
			var g = new Glyphs();
			g.addRun(part);
			var p = new Op(stroke ? StrokePath : Fill, o.matrix);
			p.path = g.path;
			p.paint = o.paint;
			p.stroke = o.stroke;
			paintOp(r, p, out);
		} else
			for (k in a...b)
				if (colour[k - a]) colourGlyphDrawn(r, o, k, out);
		out.add("q\n" + cm(o.matrix));
		if (visible) {
			setPaint(r, o.paint, o.matrix, stroke, out);
			if (stroke) pen(o.stroke, out);
		}
		out.add('BT\n/${f.name} 1 Tf\n');
		var mode = -1, open = false, px = 0.0, py = 0.0;
		for (k in a...b) {
			var want = !visible || colour[k - a] ? 3 : stroke ? 1 : 0;
			if (want != mode) {
				if (open) out.add("] TJ\n");
				open = false;
				out.add('$want Tr\n');
				mode = want;
			}
			var x = run.xs[k], y = run.ys[k], g = run.ids[k];
			if (open && Math.abs(y - py) < 1e-4) {
				// (the pen moved from the advance's end to where the layout put the glyph)
				var adj = (px - x) * 1000 / sx;
				if (Math.abs(adj) >= 0.01) out.add(num(adj) + " ");
			} else {
				if (open) out.add("] TJ\n");
				out.add('${num(sx)} 0 ${num(run.skew * sx)} ${num(-size)} ${num(x)} ${num(y)} Tm\n[');
				open = true;
			}
			out.add("<" + StringTools.hex(f.code(g), 4) + ">");
			// (the width a reader advances by: W's, whole thousandths)
			px = x + Math.round(f.width(g)) * sx / 1000;
			py = y;
		}
		if (open) out.add("] TJ\n");
		out.add("ET\nQ\n");
	}

	// a colour glyph as it looks: drawn by ColorGlyphs into a recording of its
	// own, written as the page's ops are (COLR's paints as paths, clips,
	// transparency groups with their blend modes, linear and radial gradients
	// as shadings; what PDF cannot say, a conic gradient, an image), a
	// bitmap's PNG as an image
	function colourGlyphDrawn(r:Recorder, o:Op, k:Int, out:StringBuf) {
		var run = o.run, sub = new Recorder(r.width, r.height);
		var m = o.matrix;
		sub.setTransform(m.a, m.b, m.c, m.d, m.e, m.f);
		ColorGlyphs.draw(sub, run.face, run.ids[k], run.size, run.xs[k], run.ys[k], run.scaleX, run.skew, run.palette, o.paint.color, o.paint.alpha);
		body(sub, 0, sub.ops.length, out, false);
	}

	// ---- gradients and images

	// a gradient's shading: an axial or radial one over its stops (a stitching function of linear ones)
	function shading(g:Gradient, alpha:Bool):Int {
		var n = g.stopCount;
		var fns = [], bounds = [], encode = [];
		inline function c(i:Int):String {
			var col = g.stopColor(i);
			return alpha ? num(((col >>> 24) & 255) / 255) : rgb(col);
		}
		if (n == 1) fns.push(add('<< /FunctionType 2 /Domain [0 1] /C0 [${c(0)}] /C1 [${c(0)}] /N 1 >>'));
		for (i in 0...n - 1) {
			fns.push(add('<< /FunctionType 2 /Domain [0 1] /C0 [${c(i)}] /C1 [${c(i + 1)}] /N 1 >>'));
			if (i > 0) bounds.push(num(g.stopOffset(i)));
			encode.push("0 1");
		}
		var fn = fns.length == 1 ? fns[0] : add('<< /FunctionType 3 /Domain [${num(g.stopOffset(0))} ${num(g.stopOffset(n - 1))}] /Functions [${[for (f in fns) '$f 0 R'].join(" ")}] /Bounds [${bounds.join(" ")}] /Encode [${encode.join(" ")}] >>');
		var cs = alpha ? "/DeviceGray" : "/DeviceRGB";
		if (Std.isOfType(g, LinearGradient)) {
			var l:LinearGradient = cast g;
			return add('<< /ShadingType 2 /ColorSpace $cs /Coords [${num(l.x0)} ${num(l.y0)} ${num(l.x1)} ${num(l.y1)}] /Domain [${num(g.stopOffset(0))} ${num(g.stopOffset(n - 1))}] /Function $fn 0 R /Extend [true true] >>');
		}
		var rg:RadialGradient = cast g;
		return add('<< /ShadingType 3 /ColorSpace $cs /Coords [${num(rg.x0)} ${num(rg.y0)} ${num(rg.r0)} ${num(rg.x1)} ${num(rg.y1)} ${num(rg.r1)}] /Domain [${num(g.stopOffset(0))} ${num(g.stopOffset(n - 1))}] /Function $fn 0 R /Extend [true true] >>');
	}

	// (the gradient's space in the page's: the flip, the transform, its own matrix)
	static function patternMatrix(r:Recorder, g:Gradient, m:Matrix, flip = true):String {
		var t = (flip ? new Matrix(1, 0, 0, -1, 0, r.height) : new Matrix()).multiply(m).multiply(g.matrix);
		return '[${num(t.a)} ${num(t.b)} ${num(t.c)} ${num(t.d)} ${num(t.e)} ${num(t.f)}]';
	}

	function shadingPattern(r:Recorder, g:Gradient, m:Matrix):Int {
		var sh = shading(g, false);
		var id = add('<< /Type /Pattern /PatternType 2 /Shading $sh 0 R /Matrix ${patternMatrix(r, g, m)} >>');
		resources.patterns.push(id);
		return id;
	}

	// a gradient whose stops are not all opaque: its alpha as a luminosity soft mask (-1: none needed)
	function gradientMask(r:Recorder, g:Gradient, m:Matrix):Int {
		var opaque = true;
		for (i in 0...g.stopCount)
			if (((g.stopColor(i) >>> 24) & 255) < 255) opaque = false;
		if (opaque) return -1;
		var sh = shading(g, true);
		// (inside the mask's group the page's flip is already the space: its default)
		var pat = add('<< /Type /Pattern /PatternType 2 /Shading $sh 0 R /Matrix ${patternMatrix(r, g, m, false)} >>');
		var form = reserve();
		stream(form, '/Type /XObject /Subtype /Form /BBox [0 0 ${r.width} ${r.height}] /Group << /S /Transparency /CS /DeviceGray >> /Resources << /Pattern << /P$pat $pat 0 R >> >>',
			Bytes.ofString('/Pattern cs /P$pat scn 0 0 ${r.width} ${r.height} re f'));
		return add('<< /Type /Mask /S /Luminosity /G $form 0 R >>');
	}

	// a bitmap as an image XObject (premultiplied undone: RGB, its alpha a soft mask)
	function imageObject(b:Bitmap, smooth:Bool):Int {
		var n = b.width * b.height, rgbBytes = Bytes.alloc(n * 3), a = Bytes.alloc(n), straight = b.straight(), hasAlpha = false;
		for (i in 0...n) {
			rgbBytes.set(i * 3, straight.get(i * 4));
			rgbBytes.set(i * 3 + 1, straight.get(i * 4 + 1));
			rgbBytes.set(i * 3 + 2, straight.get(i * 4 + 2));
			a.set(i, straight.get(i * 4 + 3));
			if (straight.get(i * 4 + 3) < 255) hasAlpha = true;
		}
		var smask = -1;
		if (hasAlpha) {
			smask = reserve();
			stream(smask, '/Type /XObject /Subtype /Image /Width ${b.width} /Height ${b.height} /ColorSpace /DeviceGray /BitsPerComponent 8', a);
		}
		var id = reserve();
		stream(id, '/Type /XObject /Subtype /Image /Width ${b.width} /Height ${b.height} /ColorSpace /DeviceRGB /BitsPerComponent 8${smooth ? " /Interpolate true" : ""}${smask >= 0 ? ' /SMask $smask 0 R' : ""}', rgbBytes);
		resources.images.push(id);
		return id;
	}

	function image(o:Op, out:StringBuf) {
		var r = o.rect, img = o.image;
		// (the source rectangle cut out of the bitmap, whole pixels)
		var sx = Std.int(Math.max(0, Math.floor(r[0]))), sy = Std.int(Math.max(0, Math.floor(r[1])));
		var sw = Std.int(Math.min(img.width - sx, Math.ceil(r[0] + r[2]) - sx)), sh = Std.int(Math.min(img.height - sy, Math.ceil(r[1] + r[3]) - sy));
		if (sw <= 0 || sh <= 0) return;
		var cut = img;
		if (sx != 0 || sy != 0 || sw != img.width || sh != img.height) {
			cut = new Bitmap(sw, sh);
			for (j in 0...sh)
				cut.pixels.blit(j * sw * 4, img.pixels, ((sy + j) * img.width + sx) * 4, sw * 4);
		}
		var id = imageObject(cut, o.smooth);
		var kx = r[6] / r[2], ky = r[7] / r[3];
		var dx = r[4] + (sx - r[0]) * kx, dy = r[5] + (sy - r[1]) * ky, dw = sw * kx, dh = sh * ky;
		var m = o.matrix.clone().multiply(new Matrix(dw, 0, 0, -dh, dx, dy + dh));
		var gs = resources.state(o.paint.alpha, o.paint.alpha, o.paint.blend);
		out.add('q /$gs gs ${num(m.a)} ${num(m.b)} ${num(m.c)} ${num(m.d)} ${num(m.e)} ${num(m.f)} cm /Im$id Do Q\n');
	}

	// one call PDF cannot say drawn on the CPU, placed as an image
	function fallback(r:Recorder, o:Op, out:StringBuf) {
		var k = fallbackScale, w = Std.int(Math.ceil(r.width * k)), h = Std.int(Math.ceil(r.height * k));
		var c = new Canvas(w, h);
		c.scale(k, k);
		var m = o.matrix;
		c.transform(m.a, m.b, m.c, m.d, m.e, m.f);
		switch o.kind {
			case Fill:
				var p = new Paint().copyFrom(o.paint);
				p.blend = null;
				c.fill(o.path, p, o.evenOdd);
			case StrokePath:
				var p = new Paint().copyFrom(o.paint);
				p.blend = null;
				c.stroke(o.path, o.stroke, p);
			case ClearRect:
				// (erasing: the page's white over it)
				c.fillRect(o.rect[0], o.rect[1], o.rect[2], o.rect[3], Paint.solid(0xFFFFFFFF));
			case Pixels:
				c.resetTransform();
				c.scale(k, k);
				c.drawImage(o.image, 0, 0, o.image.width, o.image.height, o.rect[0], o.rect[1], o.image.width, o.image.height, new Paint(), false);
			case _:
		}
		var id = imageObject(c.bitmap, true);
		var gs = resources.state(1, 1, o.paint == null ? null : o.paint.blend);
		out.add('q /$gs gs ${r.width} 0 0 -${r.height} 0 ${r.height} cm /Im$id Do Q\n');
	}
}

// A page's resources as they are used
private class Resources {
	public final fonts:Array<EmbeddedFont> = [];
	public final states:Array<String> = [];
	public final patterns:Array<Int> = [];
	public final images:Array<Int> = [];
	public final forms:Array<Int> = [];

	public function new() {}

	// an ExtGState of these opacities and blend mode: its name
	public function state(fill:Float, stroke:Float, blend:Null<Blend.Blender>, smask = -1):String {
		var bm = blend == null ? "Normal" : switch blend.code {
			case 0: "Multiply";
			case 1: "Screen";
			case 2: "Overlay";
			case 3: "Darken";
			case 4: "Lighten";
			case 5: "ColorDodge";
			case 6: "ColorBurn";
			case 7: "HardLight";
			case 8: "SoftLight";
			case 9: "Difference";
			case 10: "Exclusion";
			case 11: "Hue";
			case 12: "Saturation";
			case 13: "Color";
			case 14: "Luminosity";
			case _: "Normal";
		}
		var s = '<< /Type /ExtGState /ca ${fill > 1 ? 1 : fill} /CA ${stroke > 1 ? 1 : stroke} /BM /$bm${smask >= 0 ? ' /SMask $smask 0 R' : ""} >>';
		var i = states.indexOf(s);
		if (i < 0) {
			states.push(s);
			i = states.length - 1;
		}
		return "GS" + i;
	}

	public function dict():String {
		var b = new StringBuf();
		b.add("<< /Font << ");
		for (f in fonts)
			b.add('/${f.name} ${f.id} 0 R ');
		b.add(">> /ExtGState << ");
		for (i in 0...states.length)
			b.add('/GS$i ${states[i]} ');
		b.add(">> /Pattern << ");
		for (p in patterns)
			b.add('/P$p $p 0 R ');
		b.add(">> /XObject << ");
		for (p in images)
			b.add('/Im$p $p 0 R ');
		for (p in forms)
			b.add('/Fm$p $p 0 R ');
		b.add(">> >>");
		return b.toString();
	}
}
