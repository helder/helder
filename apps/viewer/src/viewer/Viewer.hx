package viewer;

import helder.image.AnimatedImage;
import helder.view.graph.Graph;
import helder.view.graph.Signal;
import viewer.Decode.Decoded;
import viewer.PdfPages.PdfSizes;
import viewer.ViewerActions;

using StringTools;

enum abstract ViewState(String) to String {
	var Empty = "empty";
	var Loading = "loading";
	var Shown = "shown";
	var Failed = "failed";
}

// The full-size viewer without its window: the folder's files (the
// browser's list), the decodes, the camera, and what the window shows as
// signals (its title, the state and its message, the status line), driven
// by keys, the wheel and the pointer the shell passes on. Headless in
// tests (a decode of its own, no GPU).
class Viewer {
	public final folder = new FolderModel();
	public final cache:DecodeCache;
	public final camera = new ViewCamera();

	public final title = Graph.signal("Viewer");
	public final state = Graph.signal(Empty);
	public final message = Graph.signal("No image open");
	public final detail = Graph.signal("");
	public final status = Graph.signal("");
	public final statusOn = Graph.signal(false);
	public final fullscreen = Graph.signal(false);
	// a change the image view draws (a new image, frame or camera)
	public final version = Graph.signal(0);
	// a PDF's page shown (from 0) and its pages (1: an image's, or not known
	// yet); as signals for the window (its key context, the go to page card)
	public var page(default, null) = 0;
	public var pages(default, null) = 1;
	public final pageSignal = Graph.signal(0);
	public final pagesSignal = Graph.signal(1);
	// go to page: its card open, the number typed
	public final gotoOpen = Graph.signal(false);
	public final gotoText = Graph.signal("");
	// the about card
	public final aboutOpen = Graph.signal(false);
	// the video or audio file shown (its path; "" none): the shell plays it
	public final media = Graph.signal("");

	// the image shown (its decode, its path), the animation's frame
	public var shown(default, null):Null<Decoded> = null;
	public var shownPath(default, null) = "";
	public var frame(default, null) = 0;

	// how many neighbours each side are decoded ahead
	public var prefetch = 2;
	// Mod's name for the hints: Ctrl, or Cmd on macOS
	public var mod = "Ctrl";
	// the system's open dialog (Mod+O; the shell's: helder.os.FileDialog)
	public var openDialog:Null<Void->Void> = null;

	// (back in the browser: decodes landing show nothing)
	var closed = true;
	var frameAt = 0.0;
	var played = 0;
	var wheelAcc = 0.0;
	var wheelAt = -1.0;

	// a PDF shown (its pages in one column: PdfDoc, PdfView), null while none
	public final pdf:Signal<Null<PdfDoc>> = Graph.signal((null : Null<PdfDoc>));
	var doc:Null<PdfDoc> = null;

	// the PDF shown now (pdf's value before its signal's write lands)
	public function document():Null<PdfDoc>
		return doc;

	// a Markdown document shown (MarkdownDoc, MarkdownPage), null while none;
	// its text read by read (Explorer's: through its Files)
	public final markdown:Signal<Null<MarkdownDoc>> = Graph.signal((null : Null<MarkdownDoc>));
	var md:Null<MarkdownDoc> = null;
	public var read:(path:String, done:Null<String>->Void) -> Void = (_, done) -> done(null);
	// its pictures' sizes, as their headers say, before it is shown
	// (Explorer's: through its Files; null: not said)
	public var measure:(paths:Array<String>, done:Array<Null<{width:Int, height:Int}>>->Void) -> Void = (paths, done) -> done([for (_ in paths) null]);

	// the Markdown document shown now (markdown's value before its signal's write lands)
	public function markdownDoc():Null<MarkdownDoc>
		return md;
	// a file's or a PDF page's decode (Decode.key), the cache's; a document's images' (MarkdownPage: theirs to release)
	public final decode:(path:String, side:Int, done:Decoded->Void) -> Void;
	final sizes:(path:String, done:PdfSizes->Void) -> Void;

	// decode: a file's or a PDF page's decode at a side (Decode.key); sizes:
	// a PDF's pages' sizes (the shell's a job's; else at once)
	public function new(decode:(path:String, side:Int, done:Decoded->Void) -> Void, ?budget:Float, ?sizes:(path:String, done:PdfSizes->Void) -> Void) {
		this.decode = decode;
		this.sizes = sizes ?? (path, done) -> done(PdfPages.sizesOf(path));
		cache = new DecodeCache(decode, budget ?? 768 * 1048576.0);
		cache.onReady = p -> if (p == key()) show();
		empty();
	}

	// a file of a folder shown, the folder's files those (the browser's, in its order)
	public function view(dir:String, names:Array<String>, name:String) {
		closed = false;
		gotoOpen(false);
		setPage(0);
		setPages(1);
		folder.set(dir, names, name);
		refresh();
		if (onOpened != null) onOpened(FolderModel.join(dir, name));
	}

	// the folder's files again (the browser's watch, its order changed): the
	// one shown kept by name
	public function relist(names:Array<String>) {
		var shown = folder.name;
		if (!folder.relist(names)) return;
		if (folder.index < 0) {
			release();
			return;
		}
		if (folder.name != shown) {
			setPage(0);
			setPages(1);
		}
		refresh();
	}

	// files changed on disk: decoded again, a document read again
	public function modified(paths:Array<String>) {
		for (p in paths)
			cache.dropFile(p);
		if (md != null && paths.contains(md.path)) dropMarkdown();
		if (folder.current != null && paths.contains(folder.current)) refresh();
	}

	// back in the browser: the player stopped, nothing more shown, the
	// picture kept for the view's fade (release lets it go)
	public function close() {
		closed = true;
		media("");
		gotoOpen(false);
	}

	// the decodes let go (the browser left the folder)
	public function release() {
		closed = true;
		dropPdf();
		dropMarkdown();
		cache.clear();
		shown = null;
		shownPath = "";
		media("");
		empty();
		updateTitle();
	}

	// a file opened (the shell's recent files)
	public var onOpened:Null<String->Void> = null;

	public function next():Bool
		return go(folder.go(1));

	public function previous():Bool
		return go(folder.go(-1));

	public function first():Bool
		return go(folder.first());

	public function last():Bool
		return go(folder.last());

	function go(moved:Bool):Bool {
		if (moved) {
			setPage(0);
			setPages(1);
			refresh();
		}
		return moved;
	}

	// --- a PDF's pages: the next, the previous, the first, the last, one by its number (from 1)

	public function nextPage():Bool
		return toPage(page + 1);

	public function previousPage():Bool
		return toPage(page - 1);

	public function toPage(p:Int):Bool {
		var d = doc;
		if (d == null || p < 0 || p >= pages) return false;
		d.goTo(p);
		return true;
	}

	// the go-to-page card's number (from 1, clamped to the pages): taken, the card closed
	public function goToTyped(typed:String):Bool {
		var n = Std.parseInt(StringTools.trim(typed));
		gotoOpen(false);
		if (n == null) return false;
		return toPage(Std.int(Math.max(1, Math.min(n, pages))) - 1);
	}

	public static function isPdf(name:String):Bool
		return Kinds.extension(name) == "pdf";

	function setPage(p:Int) {
		page = p;
		pageSignal(p);
	}

	function setPages(n:Int) {
		pages = n;
		pagesSignal(n);
	}

	// the decode shown's key (its page's, a PDF's: Decode.key)
	public function key():Null<String>
		return folder.current == null ? null : Decode.key(folder.current, page);

	// (what is shown and what is decoded ahead: JPEGs at the view's size, its larger side)
	function refresh() {
		// (before the window's first frame its size is not known: a screen's)
		var side = Std.int(Math.max(camera.viewWidth, camera.viewHeight));
		cache.side = side <= 1 ? 1920 : side;
		cache.want(wanted());
		show();
	}

	// (the page shown, then a PDF's next and previous page, then the folder's neighbours' first)
	function wanted():Array<String> {
		var around = folder.around(prefetch);
		if (around.length == 0) return [];
		var cur = folder.path(around[0]);
		var out = !decoded(cur) ? [] : [cur];
		for (i in around.slice(1))
			if (decoded(folder.files[i])) out.push(folder.path(i));
		return out;
	}

	// (an image decoded by the cache: not a video, an audio file, a PDF nor a document)
	static function decoded(name:String):Bool
		return !FolderModel.isMedia(name) && !isPdf(name) && !FolderModel.isMarkdown(name);

	function show() {
		if (closed) return;
		var path = key();
		if (path == null) return;
		if (!FolderModel.isMarkdown(folder.name)) dropMarkdown();
		// (a video or an audio file: the shell's player shows it, nothing decoded here)
		if (FolderModel.isMedia(folder.name)) {
			shown = null;
			shownPath = path;
			state(Shown);
			message("");
			detail("");
			media(path);
			updateTitle();
			version(v -> v + 1);
			return;
		}
		media("");
		if (isPdf(folder.name)) {
			showPdf(path);
			return;
		}
		if (FolderModel.isMarkdown(folder.name)) {
			dropPdf();
			showMarkdown(path);
			return;
		}
		dropPdf();
		var d = cache.get(path);
		if (d == null) {
			if (shownPath != path) {
				shown = null;
				state(Loading);
				message("Loading " + folder.name + (page > 0 ? ", page " + (page + 1) : "") + "…");
				detail("");
			}
		} else if (d.error != null) {
			shown = null;
			shownPath = path;
			state(Failed);
			message(d.error);
			detail(folder.name + (d.format != "" ? " · " + d.format : "") + (d.fileSize > 0 ? " · " + size(d.fileSize) : ""));
		} else if (shown != d) {
			var same = shownPath == path;
			shown = d;
			shownPath = path;
			frame = 0;
			played = 0;
			frameAt = -1;
			if (!same) camera.setImage(d.width, d.height) else camera.setView(camera.viewWidth, camera.viewHeight);
			state(Shown);
			message("");
			detail("");
		}
		updateTitle();
		changed();
	}

	// (a PDF: its pages' sizes asked for, then its column shown)
	function showPdf(path:String) {
		if (doc != null && doc.path == path) {
			updateTitle();
			return;
		}
		dropPdf();
		shown = null;
		shownPath = path;
		state(Loading);
		message("Loading " + folder.name + "…");
		detail("");
		updateTitle();
		sizes(path, r -> {
			if (closed || folder.current != path || doc != null) return;
			if (r.error != null || r.sizes.length == 0) {
				state(Failed);
				message(r.error ?? "A damaged PDF: no pages");
				detail(folder.name + " · PDF");
				updateTitle();
				return;
			}
			var d = new PdfDoc(path, r.sizes, r.fileSize, decode);
			d.onPage = p -> {
				setPage(p);
				updateTitle();
			};
			doc = d;
			pdf(d);
			setPage(0);
			setPages(r.sizes.length);
			state(Shown);
			message("");
			detail("");
			updateTitle();
		});
	}

	// (a Markdown document: its text read and parsed, its pictures measured, then shown)
	function showMarkdown(path:String) {
		if (md != null && md.path == path) {
			updateTitle();
			return;
		}
		dropMarkdown();
		shown = null;
		shownPath = path;
		state(Loading);
		message("Loading " + folder.name + "…");
		detail("");
		updateTitle();
		read(path, text -> {
			if (closed || folder.current != path || md != null) return;
			if (text == null) {
				state(Failed);
				message("The file cannot be read");
				detail(folder.name + " · Markdown");
				updateTitle();
				return;
			}
			var d = new MarkdownDoc(path, text);
			measure(d.pictures, sizes -> {
				if (closed || folder.current != path || md != null) return;
				for (i => s in sizes) if (s != null) d.sizes.set(d.pictures[i], s);
				d.anchor = anchor;
				anchor = null;
				md = d;
				markdown(d);
				state(Shown);
				message("");
				detail("");
				updateTitle();
			});
		});
	}

	// a heading the next document opened shows first (a link's "#id")
	public var anchor:Null<String> = null;

	function dropMarkdown() {
		if (md == null) return;
		md = null;
		markdown(null);
	}

	function dropPdf() {
		if (doc == null) return;
		doc = null;
		pdf(null);
		setPage(0);
		setPages(1);
	}

	function empty() {
		state(Empty);
		message("No image open");
		detail("");
	}

	function updateTitle() {
		if (folder.index < 0) {
			title("Viewer");
			status("");
			return;
		}
		var n = folder.files.length, d = shown;
		var parts = [folder.name, '${folder.index + 1} / $n'];
		if (media.peek() != "") {
			if (mediaInfo != "") parts.push(mediaInfo);
			title(parts.join(" · "));
			status(parts.join(" · ") + (mediaStatus == "" ? "" : " · " + mediaStatus));
			return;
		}
		if (md != null) {
			title(parts.join(" · "));
			status('${Kinds.count(md.words)} words · Markdown · ${size(md.size)} · ${folder.index + 1} / $n');
			return;
		}
		var paged = doc != null ? 'page ${page + 1} / ${pages}' : "";
		if (paged != "") parts.push(paged) else if (d != null) parts.push('${d.width}×${d.height}');
		if (doc != null) {
			title(parts.join(" · "));
			status('${doc.percent()}% · $paged · PDF · ${size(doc.fileSize)} · ${folder.index + 1} / $n');
			return;
		}
		title(parts.join(" · "));
		if (d == null) {
			status(parts.join(" · "));
			return;
		}
		var pdf = d.format == "PDF";
		status('${camera.percent()}% · ' + (paged != "" ? paged : pdf ? "1 page" : '${d.width}×${d.height}') + ' · ${d.format}'
			+ (d.frames.length > 1 ? ' · ${d.frames.length} frames' : "")
			+ (!pdf && d.pixelsWidth < d.width ? ' · decoded at 1/${Math.round(d.width / d.pixelsWidth)}' : "") + ' · ${size(d.fileSize)} · ${folder.index + 1} / $n');
	}

	// (the camera or the frame moved: the view draws again; zoomed past the
	// pixels a smaller decode has, the whole of it asked for)
	function changed() {
		var d = shown;
		if (d != null && d.pixelsWidth < d.width && camera.scale * d.width / d.pixelsWidth > 1.01) {
			var need = Math.ceil(Math.max(d.width, d.height) * camera.scale);
			cache.refine(shownPath, need >= Math.max(d.width, d.height) ? 0 : need);
		}
		updateTitle();
		version(v -> v + 1);
	}

	// the media shown's size and what it is (the shell's, once its player loaded it)
	public var mediaInfo = "";
	public var mediaStatus = "";

	public function described(info:String, status:String) {
		mediaInfo = info;
		mediaStatus = status;
		updateTitle();
	}

	// --- zoom and pan (device pixels)

	public function fit() {
		if (doc != null) {
			doc.fit();
			updateTitle();
			return;
		}
		camera.fit();
		changed();
	}

	public function actual() {
		if (doc != null) {
			doc.actual();
			updateTitle();
			return;
		}
		camera.actual();
		changed();
	}

	public function zoomStep(dir:Int) {
		if (doc != null) {
			doc.step(dir);
			updateTitle();
			return;
		}
		if (shown == null) return;
		camera.step(dir);
		changed();
	}

	public function toggleZoom(x:Float, y:Float) {
		if (shown == null) return;
		camera.toggle(x, y);
		changed();
	}

	// a pinch's step: the zoom by factor about (x, y)
	public function pinch(factor:Float, x:Float, y:Float) {
		if (shown == null || doc != null) return;
		camera.zoomBy(factor, x, y);
		changed();
	}

	public function pan(dx:Float, dy:Float) {
		camera.pan(dx, dy);
		changed();
	}

	// the wheel or a trackpad at (x, y) by dy pixels: with Control (a pinch)
	// a zoom about the point; without, while fitted, the next or previous
	// image (a notch each, at most five a second), else a zoom
	public function wheel(x:Float, y:Float, dy:Float, control:Bool, now:Float) {
		if (dy == 0) return;
		if (control || (shown != null && !camera.fitted)) {
			if (shown == null) return;
			camera.zoomBy(Math.exp(-dy * Math.log(1.25) / 40), x, y);
			changed();
			return;
		}
		if (wheelAcc * dy < 0) wheelAcc = 0;
		wheelAcc += dy;
		if (Math.abs(wheelAcc) < 40 || (wheelAt >= 0 && now - wheelAt < 0.2)) return;
		wheelAt = now;
		var dir = wheelAcc > 0 ? 1 : -1;
		wheelAcc = 0;
		// (a PDF's pages first, then the folder's next or previous file)
		if (dir > 0) {
			if (!nextPage()) next();
		} else if (!previousPage()) previous();
	}

	// --- actions (ViewerActions: the keymap's and the menus'): true when taken

	public function perform(a:ViewerAction):Bool {
		switch a {
			case Open:
				if (openDialog != null) openDialog();
			case Next: next();
			case Previous: previous();
			case First: first();
			case Last: last();
			case ZoomIn: zoomStep(1);
			case ZoomOut: zoomStep(-1);
			case Fit: fit();
			case ActualSize: actual();
			case ToggleFullscreen: fullscreen(!fullscreen.peek());
			case LeaveFullscreen: fullscreen(false);
			case ToggleStatus: statusOn(!statusOn.peek());
			case NextPage: nextPage();
			case PreviousPage: previousPage();
			case FirstPage | LastPage if (md != null): md.end(a == FirstPage ? -1 : 1);
			case FirstPage: toPage(0);
			case LastPage: toPage(pages - 1);
			case ScrollDown | ScrollUp | LineDown | LineUp if (md != null):
				switch a {
					case ScrollDown: md.screens(1);
					case ScrollUp: md.screens(-1);
					case LineDown: md.lines(1);
					case _: md.lines(-1);
				}
			case ToggleSource:
				var m = md;
				if (m == null) return false;
				m.source(!m.source.peek());
			case ScrollDown | ScrollUp | LineDown | LineUp:
				var d = doc;
				if (d == null) return false;
				switch a {
					case ScrollDown: d.screens(1);
					case ScrollUp: d.screens(-1);
					case LineDown: d.lines(1);
					case _: d.lines(-1);
				}
			case GoToPage:
				if (pages < 2) return false;
				gotoText("");
				gotoOpen(true);
			case CloseGoTo: gotoOpen(false);
			case CloseAbout: aboutOpen(false);
			case _: return false;
		}
		return true;
	}

	// what a menu shows it as
	public function actionState(a:ViewerAction):helder.ui.actions.ActionState
		return switch a {
			case Next | Previous | First | Last: folder.index >= 0 ? Enabled : Disabled;
			case ZoomIn | ZoomOut | Fit | ActualSize: (state.peek() == Shown && md == null) || doc != null ? Enabled : Disabled;
			case FirstPage | LastPage if (md != null): Enabled;
			case NextPage | LastPage: page + 1 < pages ? Enabled : Disabled;
			case ScrollDown | ScrollUp | LineDown | LineUp: doc != null || md != null ? Enabled : Disabled;
			case ToggleSource: md == null ? Disabled : md.source.peek() ? Checked : Unchecked;
			case PreviousPage | FirstPage: page > 0 && pages > 1 ? Enabled : Disabled;
			case GoToPage: pages > 1 ? Enabled : Disabled;
			case CopyPath | ShowInFolder | OpenWithDefault: shownPath != "" || folder.current != null ? Enabled : Disabled;
			case PlayPause | StepForward | StepBack | ToggleMute: media.peek() != "" ? Enabled : Disabled;
			case ToggleFullscreen: fullscreen.peek() ? Checked : Unchecked;
			case ToggleStatus: statusOn.peek() ? Checked : Unchecked;
			case _: Enabled;
		}

	// --- the frame: an animation's next frame, a glide; true when it moved

	public function tick(now:Float, dt:Float):Bool {
		var moved = false;
		if (camera.gliding) {
			camera.glide(dt);
			moved = true;
		}
		var d = shown;
		if (d != null && d.frames.length > 1 && (d.repetitions < 0 || played <= d.repetitions)) {
			// (the first tick, or a clock that went back: from now)
			if (frameAt < 0 || now < frameAt) frameAt = now;
			var due = AnimatedImage.duration(d.frames[frame].delay);
			// (late by more than a frame: caught up, not raced through)
			while (now - frameAt >= due) {
				frameAt += due;
				if (now - frameAt > 1) frameAt = now;
				if (frame + 1 < d.frames.length) frame++ else if (d.repetitions < 0 || played < d.repetitions) {
					frame = 0;
					played++;
				} else {
					played++;
					break;
				}
				moved = true;
				due = AnimatedImage.duration(d.frames[frame].delay);
			}
		}
		if (moved) changed();
		return moved || (d != null && d.frames.length > 1) || camera.gliding;
	}

	public static function size(bytes:Int):String
		return bytes >= 1048576 ? Std.string(Math.round(bytes / 104857.6) / 10) + " MB" : bytes >= 1024 ? Math.round(bytes / 1024) + " KB" : bytes + " B";
}
