package helder.ui.draw;

import haxe.crypto.Md5;
import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import helder.canvas.Svg;
import helder.image.Deflate;
import helder.image.Image;
import helder.image.Inflate;
import helder.image.JpegEncoder;
import helder.image.PngEncoder;
import helder.text.FontFile;
import helder.text.SystemFonts;
import helder.ui.Drawing.ImageDrawing;
import helder.ui.draw.FrameStreams.FrameInput;
import helder.ui.draw.FrameWriter.Frame;
import helder.ui.draw.FrameWriter.FrameLoopData;
import helder.ui.draw.FrameWriter.FontRef;
import helder.ui.draw.FrameWriter.ImageRef;

// A set of frames as a file (the studio's: bin/studio/<project>/frames.hframes):
// each screen's frame (FrameWriter's) under its name and key, the fonts and
// images they draw stored once, by hash. Fonts by reference (the file they
// were read from, their face, a fingerprint of their file: a face whose file
// changed is not drawn), but those no file is behind (an app's own,
// SystemFonts.add's), stored; images as the file they were decoded from,
// else their pixels as a PNG; an SVG icon as its drawing (SvgData), a
// box's gradient as its data, each rendered again at its size.
//
// The file: "HFRM", its version, then chunks (a tag, a varint length, its
// bytes; one of a tag not known skipped): "BLOB" (an image's or a font's
// bytes, its hash first, then 1 when they are deflated) and one "BODY"
// (deflated: the font table, the screens, each its frame and its loop's:
// FrameLoop's deltas at its fps).
class FrameArchive {
	public static inline var VERSION = 3;

	final screens = new Map<String, Screen>();
	final order:Array<String> = [];
	final blobs = new Map<String, Bytes>();

	public function new() {}

	// the screens' names, in the order they were added
	public function names():Array<String>
		return order.copy();

	// a screen's key (what its frame was made from: the studio's sources' hash), null: none
	public function key(name:String):Null<String>
		return screens.get(name)?.key;

	// a screen's frame kept under another key (the files changed, not what it draws)
	public function rekey(name:String, key:String) {
		var s = screens.get(name);
		if (s != null) screens.set(name, {key: key, width: s.width, height: s.height, bytes: s.bytes, loop: s.loop, fonts: s.fonts, images: s.images});
	}

	public function size(name:String):Null<{width:Float, height:Float}> {
		var s = screens.get(name);
		return s == null ? null : {width: s.width, height: s.height};
	}

	public function add(name:String, key:String, width:Float, height:Float, frame:Frame) {
		for (f in frame.fonts)
			if (f.data != null && !blobs.exists(f.hash)) blobs.set(f.hash, f.data);
		for (i in frame.images)
			if (i.data != null && !blobs.exists(i.hash)) blobs.set(i.hash, i.data);
		if (!screens.exists(name)) order.push(name);
		screens.set(name, {
			key: key,
			width: width,
			height: height,
			bytes: frame.bytes,
			loop: frame.loop,
			fonts: [
				for (f in frame.fonts) {
					hash: f.hash,
					family: f.family,
					weight: f.weight,
					italic: f.italic,
					path: f.path,
					index: f.index,
					engine: f.engine,
					coords: f.coords,
					data: null
				}
			],
			images: [
				for (i in frame.images) {
					hash: i.hash,
					kind: i.kind,
					width: i.width,
					height: i.height,
					color: i.color,
					data: null
				}
			]
		});
	}

	// another archive's screen (a host's still) under key, its fonts' and images' bytes with it
	public function take(from:FrameArchive, name:String, key:String) {
		var s = from.screens.get(name);
		if (s == null) return;
		for (f in s.fonts)
			if (!blobs.exists(f.hash) && from.blobs.exists(f.hash)) blobs.set(f.hash, from.blobs.get(f.hash));
		for (i in s.images)
			if (!blobs.exists(i.hash) && from.blobs.exists(i.hash)) blobs.set(i.hash, from.blobs.get(i.hash));
		// (a still of a build whose loop was recorded with an earlier one: that loop kept)
		var was = screens.get(name), loop = s.loop ?? (was != null && was.key == key ? was.loop : null);
		if (!screens.exists(name)) order.push(name);
		screens.set(name, {key: key, width: s.width, height: s.height, bytes: s.bytes, loop: loop, fonts: s.fonts, images: s.images});
	}

	// the archive as another machine reads it (a share's: helder.run's Board):
	// each font it refers to by its file stored with it (at most maxFont
	// bytes each; a larger one, an emoji font's, left to the reader's match);
	// the keys let go (they name this machine's files)
	public function portable(maxFont = 16 * 1024 * 1024):FrameArchive {
		var out = new FrameArchive();
		for (name in order) {
			var s = screens.get(name);
			for (f in s.fonts) {
				if (out.blobs.exists(f.hash)) continue;
				var b = blobs.get(f.hash) ?? (f.path == null ? null : try sys.io.File.getBytes(f.path) catch (_:Dynamic) null);
				if (b != null && b.length <= maxFont) out.blobs.set(f.hash, b);
			}
			for (i in s.images)
				if (blobs.exists(i.hash)) out.blobs.set(i.hash, blobs.get(i.hash));
			out.order.push(name);
			out.screens.set(name, {
				key: "",
				width: s.width,
				height: s.height,
				bytes: s.bytes,
				loop: s.loop,
				fonts: [for (f in s.fonts) {hash: f.hash, family: f.family, weight: f.weight, italic: f.italic, path: null, index: f.index, engine: f.engine, coords: f.coords, data: null}],
				images: s.images
			});
		}
		return out;
	}

	public function remove(name:String) {
		screens.remove(name);
		order.remove(name);
	}

	// a screen's frame recorded into a list to draw; null when there is none,
	// or a font it draws is not here (its file gone or changed); passes: what
	// passes draw as data (FrameReader.read's)
	public function list(name:String, ?passes:Array<PassData>):Null<DisplayList> {
		var s = screens.get(name);
		if (s == null) return null;
		var fonts = [for (f in s.fonts) font(f)];
		if (fonts.contains(null)) return null;
		return FrameReader.read(s.bytes, cast fonts, k -> imageAt(s.images, k), passes);
	}

	// whether a screen has a loop stored
	public function looped(name:String):Bool
		return screens.get(name)?.loop != null;

	// a screen's loop: its fps and its frames recorded into lists; null when
	// it has none (one with a pass plays live) or a font it draws is not here
	// (passes: each frame's passes' data kept, as list's)
	public function loop(name:String, passes = false):Null<{fps:Int, lists:Array<DisplayList>, passes:Array<Array<PassData>>}> {
		var s = screens.get(name);
		if (s == null || s.loop == null) return null;
		var fonts = [for (f in s.fonts) font(f)];
		if (fonts.contains(null)) return null;
		var lists = [], datas = [];
		for (recs in FrameLoop.decode(s.loop.frames)) {
			var d = passes ? [] : null;
			lists.push(FrameReader.read(FrameStreams.of(recs), cast fonts, k -> imageAt(s.images, k), d));
			datas.push(d ?? []);
		}
		return {fps: s.loop.fps, lists: lists, passes: datas};
	}

	public function encode():Bytes {
		// (a font's bytes deflated: an image's are its file's, compressed already)
		var used = new Map<String, Bool>();
		for (s in screens) {
			for (f in s.fonts)
				used.set(f.hash, true);
			for (i in s.images)
				used.set(i.hash, i.kind == SVG || i.kind == GRADIENT);
		}
		var out = new BytesBuffer();
		out.addString("HFRM");
		out.addByte(VERSION);
		for (hash => b in blobs)
			if (used.exists(hash)) {
				var c = new BytesBuffer(), deflated = used.get(hash);
				str(c, hash);
				c.addByte(deflated ? 1 : 0);
				c.add(deflated ? Deflate.zlib(b) : b);
				chunk(out, "BLOB", c.getBytes());
			}
		var o = new FrameStreams();
		o.uint(order.length);
		for (name in order) {
			var s = screens.get(name);
			o.string(name);
			o.string(s.key);
			o.float(0, s.width);
			o.float(1, s.height);
			o.uint(s.fonts.length);
			for (f in s.fonts) {
				o.string(f.hash);
				o.string(f.family);
				o.uint(f.weight);
				o.bool(f.italic);
				o.string(f.path ?? "");
				o.uint(f.index);
				o.uint(f.engine);
				o.uint(f.coords == null ? 0 : f.coords.length + 1);
				if (f.coords != null)
					for (c in f.coords)
						o.float(2, c);
			}
			o.uint(s.images.length);
			for (i in s.images) {
				o.string(i.hash);
				o.uint(i.kind);
				o.uint(i.width);
				o.uint(i.height);
				o.color(i.color);
			}
			o.uint(s.bytes.length);
			o.ints.add(s.bytes);
			o.uint(s.loop == null ? 0 : s.loop.fps);
			if (s.loop != null) {
				o.uint(s.loop.frames.length);
				for (f in s.loop.frames) {
					o.uint(f.length);
					o.ints.add(f);
				}
			}
		}
		chunk(out, "BODY", Deflate.zlib(o.bytes()));
		return out.getBytes();
	}

	// (null: not a frames file, or one of another version: none to show)
	public static function decode(b:Bytes):Null<FrameArchive> {
		if (b.length < 5 || b.getString(0, 4) != "HFRM" || b.get(4) != VERSION) return null;
		var a = new FrameArchive(), p = 5;
		while (p + 4 < b.length) {
			var tag = b.getString(p, 4), n = 0, k = 1, c;
			p += 4;
			do {
				c = b.get(p++);
				n += (c & 127) * k;
				k *= 128;
			} while (c >= 128);
			var data = b.sub(p, n);
			p += n;
			switch tag {
				case "BLOB":
					var h = data.get(0), b = data.sub(2 + h, data.length - 2 - h);
					a.blobs.set(data.getString(1, h), data.get(1 + h) == 1 ? Inflate.all(b, 1 << 30) : b);
				case "BODY":
					a.body(Inflate.all(data, 1 << 30));
				case _:
			}
		}
		return a;
	}

	function body(b:Bytes) {
		var r = new FrameInput(b);
		for (_ in 0...Std.int(r.uint())) {
			var name = r.string(), key = r.string(), width = r.float(0), height = r.float(1);
			var fonts:Array<FontRef> = [
				for (_ in 0...Std.int(r.uint())) {
					var hash = r.string(), family = r.string(), weight = Std.int(r.uint()), italic = r.bool(), path = r.string();
					var index = Std.int(r.uint()), engine = Std.int(r.uint()), n = Std.int(r.uint());
					{
						hash: hash,
						family: family,
						weight: weight,
						italic: italic,
						path: path == "" ? null : path,
						index: index,
						engine: engine,
						coords: n == 0 ? null : [for (_ in 1...n) r.float(2)],
						data: null
					};
				}
			];
			var images:Array<ImageRef> = [
				for (_ in 0...Std.int(r.uint())) {
					var hash = r.string(), kind = Std.int(r.uint()), w = Std.int(r.uint()), h = Std.int(r.uint());
					{hash: hash, kind: kind, width: w, height: h, color: r.color(), data: null};
				}
			];
			var n = Std.int(r.uint());
			var bytes = r.raw(n), fps = Std.int(r.uint());
			var loop = fps == 0 ? null : {fps: fps, frames: [for (_ in 0...Std.int(r.uint())) r.raw(Std.int(r.uint()))]};
			order.push(name);
			screens.set(name, {key: key, width: width, height: height, bytes: bytes, loop: loop, fonts: fonts, images: images});
		}
	}

	// --- fonts ---

	static final hashes = new Map<Int, String>();
	static final faces = new Map<String, Null<FontFile>>();

	// a face by reference (FrameWriter's); its bytes only when no file is behind it
	@:access(helder.text.FontFile)
	public static function fontRef(f:FontFile):FontRef {
		var hash = hashes.get(f.id) ?? hash(f);
		return {
			hash: hash,
			family: f.family,
			weight: f.weight,
			italic: f.italic,
			path: f.path,
			index: f.faceIndex,
			engine: f.engine,
			coords: f.coords?.copy(),
			data: f.path == null ? f.data : null
		};
	}

	// the face again: from its file, else the system's of its name, else its
	// stored bytes; its hash checked
	@:access(helder.text.FontFile)
	function font(r:FontRef):Null<FontFile> {
		var key = r.hash + "#" + r.index + "@" + r.engine + ":" + r.coords;
		if (faces.exists(key)) return faces.get(key);
		var base = face(r);
		var f = base;
		if (base != null && (r.coords != null || base.engine != r.engine)) {
			f = base.instance([]);
			f.engine = r.engine;
			if (r.coords != null) {
				f.coords = r.coords.copy();
				f.weight = r.weight;
			}
		}
		faces.set(key, f);
		return f;
	}

	function face(r:FontRef):Null<FontFile> {
		function same(f:Null<FontFile>):Null<FontFile>
			return f != null && f.faceIndex == r.index && (hashes.get(f.id) ?? hash(f)) == r.hash ? f : null;
		var f = r.path == null ? null : same(SystemFonts.get().file(r.path, r.index));
		if (f != null) return f;
		var b = blobs.get(r.hash);
		if (b != null) return same(try FontFile.parse(b, r.index) catch (e:Dynamic) null);
		return same(SystemFonts.get().match(r.family, r.weight, r.italic));
	}

	// (a face's file told apart without reading all of it, an emoji font's
	// 190 MB: its length, its head table's checksum of the whole file, its
	// first 4 KB's md5)
	static function hash(f:FontFile):String {
		var head = f.table("head"), d = f.data;
		var sum = head == null || head.length < 12 ? 0 : head.getInt32(8);
		var h = d.length + "-" + StringTools.hex(sum, 8) + "-" + Md5.make(d.sub(0, d.length < 4096 ? d.length : 4096)).toHex();
		hashes.set(f.id, h);
		return h;
	}

	// --- images ---

	static final refs = new Map<String, ImageRef>();
	static final images = new Map<String, Null<Image>>();
	static final svgs = new haxe.ds.ObjectMap<Svg, {hash:String, data:Bytes}>();

	public static inline var FILE = 0;
	public static inline var PIXELS = 1;
	public static inline var SVG = 2;
	public static inline var GRADIENT = 3;

	// an image by its content (FrameWriter's): its drawing, else the file it
	// was decoded from, else its pixels; null bytes when they are not readable
	public static function imageRef(img:Image):ImageRef {
		var id = img.id + "@" + img.version;
		var r = refs.get(id);
		if (r != null) return r;
		var d:Null<ImageDrawing> = img.drawing;
		r = if (d != null && d.gradient != null) {
			var o = new FrameStreams();
			FrameWriter.gradient(o, d.gradient);
			o.float(0, d.scale ?? 1);
			var data = o.bytes();
			{hash: Md5.make(data).toHex(), kind: GRADIENT, width: img.width, height: img.height, color: 0, data: data};
		} else if (d != null && d.svg != null) {
			var s = svgs.get(d.svg);
			if (s == null) {
				var data = SvgData.write(d.svg);
				svgs.set(d.svg, s = {hash: Md5.make(data).toHex(), data: data});
			}
			{hash: s.hash, kind: SVG, width: img.width, height: img.height, color: d.color ?? 0, data: s.data};
		} else if (img.source != null) {
			{hash: Md5.make(img.source.bytes).toHex(), kind: FILE, width: img.width, height: img.height, color: 0, data: img.source.bytes};
		} else pixelsRef(img);
		refs.set(id, r);
		return r;
	}

	// an image by its pixels, not kept (a picture read back: drawn once);
	// lossy: a JPEG when opaque (a loop's pictures: a tenth of a PNG's bytes,
	// a third of its time)
	public static function pixelsRef(img:Image, lossy = false):ImageRef {
		var px = try img.pixels catch (e:Dynamic) null;
		if (px == null) return {hash: "", kind: PIXELS, width: img.width, height: img.height, color: 0, data: null};
		var jpeg = lossy && opaque(px);
		return {
			hash: Md5.make(px).toHex(),
			kind: PIXELS,
			width: img.width,
			height: img.height,
			color: 0,
			data: jpeg ? JpegEncoder.encode(px, img.width, img.height, LOOP_QUALITY) : PngEncoder.encode(px, img.width, img.height, false, lossy)
		};
	}

	public static inline var LOOP_QUALITY = 88;

	static function opaque(px:haxe.io.Bytes):Bool {
		var i = 3;
		while (i < px.length) {
			if (px.get(i) != 255) return false;
			i += 4;
		}
		return true;
	}

	// (an image decoded as a list draws it: a still's, not its loop's hundreds)
	function imageAt(refs:Array<ImageRef>, k:Int):Null<Image>
		return k < refs.length ? image(refs[k]) : null;

	function image(r:ImageRef):Null<Image> {
		var key = r.hash + "@" + r.width + "x" + r.height + ":" + r.color;
		if (images.exists(key)) return images.get(key);
		var b = blobs.get(r.hash);
		var img = b == null ? null : try switch r.kind {
			case SVG: SvgData.read(b).render(r.width, r.height, r.color);
			case GRADIENT:
				var input = new FrameInput(b), g = FrameReader.gradient(input);
				g.render(r.width, r.height, input.float(0));
			case _: Image.decode(b);
		} catch (e:Dynamic) null;
		images.set(key, img);
		return img;
	}

	static function chunk(out:BytesBuffer, tag:String, b:Bytes) {
		out.addString(tag);
		FrameStreams.varint(out, b.length);
		out.add(b);
	}

	static function str(out:BytesBuffer, s:String) {
		out.addByte(s.length);
		out.addString(s);
	}
}

private typedef Screen = {
	key:String,
	width:Float,
	height:Float,
	bytes:Bytes,
	loop:Null<FrameLoopData>,
	fonts:Array<FontRef>,
	images:Array<ImageRef>
}
