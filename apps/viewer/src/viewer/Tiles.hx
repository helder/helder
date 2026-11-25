package viewer;

import helder.os.Settings;
import helder.image.Image;
import helder.ui.Node;
import helder.ui.controls.Look;
import helder.ui.UiWindow;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph;
import helder.view.graph.Read;
import helder.view.graph.Signal;
import viewer.Files;

// what a file's thumbnail is now: its picture once there, waiting while asked for
typedef Thumb = {image:Null<Image>, waiting:Bool};

// What stands for a file in the list and the grid: its thumbnail where
// there is one (thumbnail: Thumbnails' queue, newest asked first, the
// request cancelled when its cell goes; the last ones kept in memory),
// else its glyph (the folder's picture, a page with the file's extension,
// an image's, a video's, an audio file's, a PDF's), a Markdown document's
// page with its first heading; and the grid's cell.
@:renderer(helder.ui.view.NodeRenderer)
class Tiles implements Markup {
	// the grid's cells: a desktop's, the picture's box 90 points (a little
	// over Finder's 64-point icons), its name in two lines; a tablet's (a
	// finger's) the box 116
	public static inline var CELL_WIDTH = 112;
	public static inline var CELL_HEIGHT = 160;
	public static inline var TABLET_WIDTH = 136;
	public static inline var TABLET_HEIGHT = 184;
	// (a desktop's pictures to a tablet's)
	static inline var SMALL = 0.78;
	// (thumbnails kept in memory: 256 a side, at most about 256 KB each)
	static inline var KEEP = 300;
	static final RAW = ["dng", "cr2", "cr3", "nef", "arw", "raf", "orf", "rw2"];

	// the thumbnails asked for and not yet made (Timing's: the visible tiles' made)
	public static var waiting(default, null) = 0;

	static final kept = new Map<String, Image>();
	static final order:Array<String> = [];
	static var serial = 0;

	// a file's thumbnail, as it comes (none asked for: no Thumbnails, or a kind it has none of)
	public static function thumbnail(x:Explorer, e:Entry):Signal<Thumb> {
		var path = x.browser.path(e.name), key = path + "\x00" + e.size + "\x00" + e.modified;
		var have = kept.get(key), t = x.thumbnails, local = t == null ? null : t.of(x.files, path);
		var s = Graph.signalOf(({image: have, waiting: have == null && t != null && local != null && Kinds.viewable(e) && !FolderModel.isMarkdown(e.name)} : Thumb),
			{ownedWrite: true});
		if (!s.peek().waiting) return s;
		var pending = true;
		waiting++;
		var ticket = t.request(local, e.size, e.modified, Thumbnails.SIDE, -(++serial), img -> {
			if (pending) waiting--;
			pending = false;
			if (img != null) keep(key, img);
			s({image: img, waiting: false});
		});
		Graph.onCleanup(() -> {
			if (pending) waiting--;
			pending = false;
			t.cancel(ticket);
		});
		return s;
	}

	// a thumbnail already made (the inspector's while its preview comes, a drag's picture)
	public static function cached(x:Explorer, e:Entry):Null<Image>
		return kept.get(x.browser.path(e.name) + "\x00" + e.size + "\x00" + e.modified);

	// the thumbnails and titles kept let go (tests: each explorer's own)
	public static function forget() {
		kept.clear();
		order.resize(0);
		titles.clear();
	}

	// a thumbnail made for an entry, kept (the queue's; tests)
	public static function remember(x:Explorer, e:Entry, img:Image)
		keep(x.browser.path(e.name) + "\x00" + e.size + "\x00" + e.modified, img);

	static function keep(key:String, img:Image) {
		if (!kept.exists(key)) order.push(key);
		kept.set(key, img);
		while (order.length > KEEP)
			kept.remove(order.shift());
	}

	// the list's 20-point picture
	public static function mini(x:Explorer, e:Read<Entry>):View {
		return <view width={20} height={20} flexShrink={0} alignItems="center" justifyContent="center" opacity={x.zoom.flying() == x.browser.path(e().name) ? 0 : 1}
			ref={(n:Node) -> x.zoom.tile(n, x.browser.path(e().name))}>
			{() -> {
				var f = e();
				f.kind == Folder ? <image src={Glyphs.folder(Settings.dark())} width={18} height={15}/> : glyph(x, f);
			}}
		</view>;
	}

	static function glyph(x:Explorer, e:Entry):View {
		var t = thumbnail(x, e);
		return <>
			<Show when={t().image != null}><image src={t().image} width={20} height={15} objectFit="cover" borderRadius={2}/></Show>
			<Show when={t().image == null}><image src={Glyphs.get(Glyphs.of(Kinds.glyph(e)))} width={14} height={14} color={Look.ref.fg3}/></Show>
		</>;
	}

	// the grid's cell: the picture in its box, the name in two lines, cut
	// in its middle (its extension kept; an accent pill when selected), the
	// size (tablet: a tablet's sizes)
	public static function cell(x:Explorer, e:Read<Entry>, tablet = false):View {
		var b = x.browser, k = tablet ? 1.0 : SMALL, box = Math.round(116 * k), width = tablet ? TABLET_WIDTH : CELL_WIDTH;
		function on():Bool {
			b.selection.version();
			return b.selection.has(e().name);
		}
		// (a trackpad's pinch out on it: the file opened following the fingers, Flight)
		return <view slot="grid-tile" flexGrow={1} alignItems="center" rowGap={6} padding="4 4 8 4" ref={(n:Node) -> {
			DragOut.from(x, n, () -> e().name);
			Drops.folder(x, n, () -> e().kind == Folder ? b.path(e().name) : null);
		}} onWheel={ev -> if (x.zoom.tileWheel(e().name, ev)) ev.preventDefault()}>
			<view slot="thumb-box" data-selected={on() && e().kind == Folder} width={box} height={box} flexShrink={0} alignItems="center" justifyContent="center"
				opacity={x.zoom.flying() == x.browser.path(e().name) ? 0 : 1}>
				{() -> picture(x, e(), on, k)}
			</view>
			<Show when={b.renaming() == e().name}>{() -> <view width={width - 8} height={20} flexDirection="row">
				{NameField.field(e().name, t -> b.rename(e().name, t), () -> b.renaming(""), true)}
			</view>}</Show>
			<Show when={b.renaming() != e().name}>
				<text slot="name-pill" data-selected={on()} maxWidth={width - 8} lineClamp={2} textOverflow="middle" textAlign="center"
					direction={helder.ui.Dir.Ltr}>{e().name}</text>
			</Show>
			<text fontSize={11.5} color={Look.ref.fg3} marginTop={-5} lineClamp={1}>{e().kind == Folder ? "Folder" : Kinds.size(e().size)}</text>
		</view>;
	}

	static function picture(x:Explorer, e:Entry, on:Void->Bool, k:Float):View {
		inline function px(v:Float):Float
			return Math.round(v * k);
		if (e.kind == Folder) return <image src={Glyphs.folder(Settings.dark())} width={px(96)} height={px(78)}/>;
		var t = thumbnail(x, e), raw = RAW.contains(Kinds.extension(e.name)), side = px(108);
		return <>
			<Show when={t().image != null || t().waiting}>
				<view slot="photo" data-selected={on()} width={side} height={side} overflow="hidden" boxShadow="0 1px 3px rgba(0,0,0,0.35)"
					ref={(n:Node) -> x.zoom.tile(n, x.browser.path(e.name))}>
					<Show when={t().image != null}><image src={t().image} width={side} height={side} objectFit="cover"/></Show>
					<Show when={raw}>
						<text position="absolute" left={4} top={4} fontSize={9.5} fontWeight={700} padding="0 4" borderRadius={3} background="rgba(0,0,0,0.55)"
							color="#ffffff">RAW</text>
					</Show>
				</view>
			</Show>
			<Show when={t().image == null && !t().waiting}>{FolderModel.isMarkdown(e.name) ? document(x, e, k) : large(e, n -> x.zoom.tile(n, x.browser.path(e.name)), k)}</Show>
		</>;
	}

	// (the first headings of the documents seen, by file: read once)
	static final titles = new Map<String, String>();

	// a Markdown document's tile: a page with its first heading's text (the
	// name while it is read, or without one), over a few lines' shapes
	static function document(x:Explorer, e:Entry, k:Float):View {
		var title = heading(x, e);
		return <view tag="document-tile" width={Math.round(84 * k)} height={Math.round(108 * k)} borderRadius={6} background={Look.ref.raised} borderWidth={1} borderColor={Look.ref.edge}
			padding="11 9" rowGap={5} overflow="hidden" boxShadow="0 1px 2px rgba(0,0,0,0.25)" ref={(n:Node) -> x.zoom.tile(n, x.browser.path(e.name))}>
			<text tag="document-title" fontSize={9.5} fontWeight={700} lineHeight={1.2} lineClamp={4} textOverflow="ellipsis" color={Look.ref.fg}
				flexShrink={0}>{title}</text>
			{[for (w in ["100%", "88%", "94%", "62%", "90%", "76%"]) <view height={2.5} flexShrink={0} borderRadius={1} width={w} background={Look.ref.line}/>]}
			<text position="absolute" bottom={8} left={9} fontSize={8.5} fontWeight={700} color="#ffffff" padding="1 4" borderRadius={3}
				background={Kinds.tint("md")}>MD</text>
		</view>;
	}

	// (a document's first heading, its name until read)
	static function heading(x:Explorer, e:Entry):Signal<String> {
		var path = x.browser.path(e.name), key = path + "\x00" + e.size + "\x00" + e.modified;
		var fallback = haxe.io.Path.withoutExtension(e.name), have = titles.get(key);
		var s = Graph.signalOf(have ?? fallback, {ownedWrite: true});
		if (have != null) return s;
		var live = true;
		Graph.onCleanup(() -> live = false);
		x.read(path, text -> {
			// (its start alone: a title is near the top)
			var t = text == null ? null : MarkdownDoc.title(helder.markdown.Markdown.parse(text.length > 16384 ? text.substr(0, 16384) : text));
			if (Lambda.count(titles) > 2000) titles.clear();
			titles.set(key, t ?? fallback);
			if (live) s(t ?? fallback);
		});
		return s;
	}

	// a large picture: the folder's, or a page with the file's extension
	// (mark: its page's node, the zoom's tile; k: its size's factor)
	public static function large(e:Entry, ?mark:Node->Void, k = 1.0):View {
		if (e.kind == Folder) return <image src={Glyphs.folder(Settings.dark())} width={Math.round(96 * k)} height={Math.round(78 * k)}/>;
		var ext = Kinds.extension(e.name).toUpperCase();
		return <view width={Math.round(72 * k)} height={Math.round(92 * k)} borderRadius={7} background={Look.ref.raised} borderWidth={1} borderColor={Look.ref.edge} alignItems="center"
			justifyContent="center" boxShadow="0 1px 2px rgba(0,0,0,0.25)" ref={(n:Node) -> if (mark != null) mark(n)}>
			<image src={Glyphs.get(Glyphs.of(Kinds.glyph(e)))} width={24} height={24} color={Look.ref.fg3} marginTop={-12}/>
			<Show when={ext != ""}>
				<text position="absolute" bottom={10} fontSize={9.5} fontWeight={700} color="#ffffff" padding="1 5" borderRadius={3}
					background={Kinds.tint(ext.toLowerCase())}>{ext}</text>
			</Show>
		</view>;
	}
}
