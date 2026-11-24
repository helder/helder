package viewer;

import helder.image.Image;
import helder.ui.Node;
import helder.ui.controls.Look;
import helder.ui.draw.UiWindow;
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
// an image's, a video's, an audio file's, a PDF's); and the grid's cell.
class Tiles implements Markup {
	public static inline var CELL_WIDTH = 136;
	public static inline var CELL_HEIGHT = 166;
	// (thumbnails kept in memory: 256 a side, at most about 256 KB each)
	static inline var KEEP = 300;
	static final RAW = ["dng", "cr2", "cr3", "nef", "arw", "raf", "orf", "rw2"];

	static final kept = new Map<String, Image>();
	static final order:Array<String> = [];
	static var serial = 0;

	// a file's thumbnail, as it comes (none asked for: no Thumbnails, or a kind it has none of)
	public static function thumbnail(x:Explorer, e:Entry):Signal<Thumb> {
		var path = x.browser.path(e.name), key = path + "\x00" + e.size + "\x00" + e.modified;
		var have = kept.get(key), t = x.thumbnails, local = x.files.localPath(path);
		var s = Graph.signalOf(({image: have, waiting: have == null && t != null && local != null && Kinds.viewable(e)} : Thumb), {ownedWrite: true});
		if (!s.peek().waiting) return s;
		var ticket = t.request(local, e.size, e.modified, Thumbnails.SIDE, -(++serial), img -> {
			if (img != null) keep(key, img);
			s({image: img, waiting: false});
		});
		Graph.onCleanup(() -> t.cancel(ticket));
		return s;
	}

	// a thumbnail already made (the inspector's while its preview comes, a drag's picture)
	public static function cached(x:Explorer, e:Entry):Null<Image>
		return kept.get(x.browser.path(e.name) + "\x00" + e.size + "\x00" + e.modified);

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
		return <view width={20} height={20} shrink={0} align-items="center" justify="center">
			{() -> {
				var f = e();
				f.kind == Folder ? <image src={Glyphs.folder(UiWindow.dark())} width={18} height={15}/> : glyph(x, f);
			}}
		</view>;
	}

	static function glyph(x:Explorer, e:Entry):View {
		var t = thumbnail(x, e);
		return <>
			<Show when={t().image != null}><image src={t().image} width={20} height={15} fit="cover" radius={2}/></Show>
			<Show when={t().image == null}><image src={Glyphs.get(Glyphs.of(Kinds.glyph(e)))} width={14} height={14} color={Look.ref.fg3}/></Show>
		</>;
	}

	// the grid's cell: the picture in a 116-point box, the name (an accent
	// pill when selected), the size
	public static function cell(x:Explorer, e:Read<Entry>):View {
		var b = x.browser;
		function on():Bool {
			b.selection.version();
			return b.selection.has(e().name);
		}
		return <view slot="grid-tile" grow={1} align-items="center" row-gap={6} padding="4 4 8 4" ref={(n:Node) -> DragOut.from(x, n, () -> e().name)}>
			<view slot="thumb-box" data-selected={on() && e().kind == Folder} width={116} height={116} shrink={0} align-items="center" justify="center">
				{() -> picture(x, e(), on)}
			</view>
			<text slot="name-pill" data-selected={on()} max-width={130} max-lines={1} text-overflow="ellipsis" dir={helder.ui.Dir.Ltr}>{e().name}</text>
			<text font-size={11.5} color={Look.ref.fg3} margin-top={-5} max-lines={1}>{e().kind == Folder ? "Folder" : Kinds.size(e().size)}</text>
		</view>;
	}

	static function picture(x:Explorer, e:Entry, on:Void->Bool):View {
		if (e.kind == Folder) return <image src={Glyphs.folder(UiWindow.dark())} width={96} height={78}/>;
		var t = thumbnail(x, e), raw = RAW.contains(Kinds.extension(e.name));
		return <>
			<Show when={t().image != null || t().waiting}>
				<view slot="photo" data-selected={on()} width={108} height={108} overflow="hidden" shadow="0 1px 3px rgba(0,0,0,0.35)">
					<Show when={t().image != null}><image src={t().image} width={108} height={108} fit="cover"/></Show>
					<Show when={raw}>
						<text position="absolute" left={4} top={4} font-size={9.5} font-weight={700} padding="0 4" radius={3} background="rgba(0,0,0,0.55)"
							color="#ffffff">RAW</text>
					</Show>
				</view>
			</Show>
			<Show when={t().image == null && !t().waiting}>{large(e)}</Show>
		</>;
	}

	// a large picture: the folder's, or a page with the file's extension
	public static function large(e:Entry):View {
		if (e.kind == Folder) return <image src={Glyphs.folder(UiWindow.dark())} width={96} height={78}/>;
		var ext = Kinds.extension(e.name).toUpperCase();
		return <view width={72} height={92} radius={7} background={Look.ref.raised} border-width={1} border-color={Look.ref.edge} align-items="center"
			justify="center" shadow="0 1px 2px rgba(0,0,0,0.25)">
			<image src={Glyphs.get(Glyphs.of(Kinds.glyph(e)))} width={24} height={24} color={Look.ref.fg3} margin-top={-12}/>
			<Show when={ext != ""}>
				<text position="absolute" bottom={10} font-size={9.5} font-weight={700} color="#ffffff" padding="1 5" radius={3}
					background={Kinds.tint(ext.toLowerCase())}>{ext}</text>
			</Show>
		</view>;
	}
}
