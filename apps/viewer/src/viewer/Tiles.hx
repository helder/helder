package viewer;

import helder.image.Image;
import helder.ui.controls.Look;
import helder.ui.draw.UiWindow;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Read;
import viewer.Files;

// What stands for a file in the list and the grid: its thumbnail where
// there is one (thumbnail: the one place they come from), else its glyph
// (the folder's picture, a document with its extension, an image's,
// a video's, an audio file's, a PDF's).
class Tiles implements Markup {
	// a file's thumbnail at side pixels, null while there is none (the
	// thumbnails' pipeline plugs in here; until then glyphs alone)
	public static function thumbnail(x:Explorer, e:Entry, side:Int):Null<Image>
		return null;

	// the list's 20-point picture
	public static function mini(x:Explorer, e:Read<Entry>):View {
		return <view width={20} height={20} shrink={0} align-items="center" justify="center">
			{e().kind == Folder ? <image src={Glyphs.folder(UiWindow.dark())} width={18} height={15}/> : glyph(x, e(), 20)}
		</view>;
	}

	static function glyph(x:Explorer, e:Entry, size:Float):View {
		var t = thumbnail(x, e, Std.int(size * 2));
		if (t != null) return <image src={t} width={size} height={size * 0.75} fit="cover" radius={2}/>;
		return <image src={Glyphs.get(Glyphs.of(Kinds.glyph(e)))} width={14} height={14} color={Look.ref.fg3}/>;
	}

	// a large picture for the inspector's box: the folder's, or a page with the file's extension
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
