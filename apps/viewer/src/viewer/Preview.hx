package viewer;

import haxe.io.Bytes;
import helder.async.Async;
import helder.image.Image;
import helder.image.Resize;

// what the inspector shows of a file: its picture (null: none, a glyph
// instead), and what was learnt opening it (0: not known); a Markdown
// document's parsed (Explorer's preview of one)
typedef Shown = {image:Null<Image>, width:Int, height:Int, pages:Int, duration:Float, format:String, error:Null<String>, ?markdown:MarkdownDoc};

// The inspector's preview of the selected file: an image or a PDF's
// first page decoded through Decode's path at SIDE pixels, then halved to
// fit the preview's box twice over (on helder.jobs' pool, so the window
// never waits); a video's keyframe at a tenth of it (Thumbs) and its
// duration; an audio file's duration. One request at a time: the next
// selection's stops the last. (The thumbnails' pipeline takes this over
// once it lands: request is where it plugs in.)
class Preview {
	public static inline var SIDE = 512;
	// (the box is 272 by 220 points: twice that in pixels at most)
	static inline var FIT = 640;

	#if (hxmc.target != "wasm32-wasi")
	// done(shown) on the loop; the function returned stops it
	public static function request(path:String, done:Shown->Void):Void->Void {
		var stopped = false;
		if (FolderModel.isMedia(path)) {
			media(() -> new helder.media.FileSource(path), s -> if (!stopped) done(s));
			return () -> stopped = true;
		}
		// (a job that could not run: no preview, the glyph stays)
		Async.launch(_ -> helder.jobs.Jobs.job(decode).run(path)).onCompletion((r, _) -> if (!stopped && r != null) done(shown(r)));
		return () -> stopped = true;
	}
	#end

	// the file read through files (the web's, a phone's documents), decoded on a worker
	public static function read(files:Files, path:String, done:Shown->Void):Void->Void {
		var stopped = false;
		if (FolderModel.isMedia(path)) {
			media(() -> files.open(path), s -> if (!stopped) done(s));
			return () -> stopped = true;
		}
		Async.launch(_ -> {
			var b = try FileBytes.read(files, path) catch (_:Dynamic) null;
			b == null ? null : Decode.onPage(b) ? decodeBytes({path: path, bytes: b}) : helder.jobs.Jobs.job(decodeBytes).run({path: path, bytes: b});
		}).onCompletion((r, _) -> if (!stopped && r != null) done(shown(r)));
		return () -> stopped = true;
	}

	#if (hxmc.target != "wasm32-wasi")
	// at once, on this thread (tests and stories)
	public static function now(path:String, done:Shown->Void):Void->Void {
		done(shown(decode(path)));
		return () -> {};
	}

	// (on the pool: the decode, its pixels copied out, fitted)
	static function decode(path:String):{width:Int, height:Int, pw:Int, ph:Int, rgba:Null<Bytes>, pages:Int, format:String, error:Null<String>} {
		return try fitted(Decode.file({path: path, side: SIDE})) catch (e:Dynamic) failed(e);
	}
	#end

	// (the web's: the bytes read already)
	static function decodeBytes(req:{path:String, bytes:Bytes}):{width:Int, height:Int, pw:Int, ph:Int, rgba:Null<Bytes>, pages:Int, format:String, error:Null<String>} {
		return try fitted(Decode.of({path: req.path, bytes: req.bytes, side: SIDE})) catch (e:Dynamic) failed(e);
	}

	static function failed(e:Dynamic):{width:Int, height:Int, pw:Int, ph:Int, rgba:Null<Bytes>, pages:Int, format:String, error:Null<String>}
		return {width: 0, height: 0, pw: 0, ph: 0, rgba: null, pages: 0, format: "", error: "The preview failed: " + Std.string(e)};

	static function fitted(d:Decode.Decoded):{width:Int, height:Int, pw:Int, ph:Int, rgba:Null<Bytes>, pages:Int, format:String, error:Null<String>} {
		if (d.error != null || d.frames.length == 0) {
			Decode.release(d);
			return {width: d.width, height: d.height, pw: 0, ph: 0, rgba: null, pages: d.pages, format: d.format, error: d.error};
		}
		var px = d.frames[0].pixels, rgba = Bytes.alloc(d.pixelsWidth * d.pixelsHeight * 4);
		px.blitToBytes(0, rgba, 0, rgba.length);
		Decode.release(d);
		var fit = Resize.toFit(rgba, d.pixelsWidth, d.pixelsHeight, FIT, FIT);
		return {width: d.width, height: d.height, pw: fit.width, ph: fit.height, rgba: fit.rgba, pages: d.pages, format: d.format, error: null};
	}

	static function shown(r:{width:Int, height:Int, pw:Int, ph:Int, rgba:Null<Bytes>, pages:Int, format:String, error:Null<String>}):Shown
		return {
			image: r.rgba == null ? null : new Image(r.pw, r.ph, r.rgba),
			width: r.width,
			height: r.height,
			pages: r.pages,
			duration: 0,
			format: r.format,
			error: r.error
		};

	// (a video's or an audio file's: its duration and size from its header, a video's keyframe)
	static function media(open:Void->helder.media.ByteSource, done:Shown->Void) {
		Async.launch(_ -> {
			var m = try helder.media.Media.open(open()) catch (_:Dynamic) null;
			if (m == null) {
				done({image: null, width: 0, height: 0, pages: 0, duration: 0, format: "", error: "Not a video or audio file this viewer reads"});
				return;
			}
			var v = Lambda.find(m.tracks, t -> t.kind == Video), duration = m.duration;
			m.close();
			var s:Shown = {image: null, width: v == null ? 0 : v.width, height: v == null ? 0 : v.height, pages: 0, duration: duration, format: "", error: null};
			if (v == null) {
				done(s);
				return;
			}
			var thumbs = new Thumbs(open);
			thumbs.at(Math.min(2, duration * 0.1), img -> {
				thumbs.close();
				s.image = img;
				done(s);
			});
		});
	}
}
