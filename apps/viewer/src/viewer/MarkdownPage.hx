package viewer;

import haxe.io.Bytes;
import helder.image.Image;
import helder.markdown.MarkdownView;
import helder.ui.Clock;
import helder.ui.ImageNode;
import helder.ui.Node;
import helder.ui.code.CodeModel;
import helder.ui.code.CodeView;
import helder.view.*;

using StringTools;

// A Markdown document full size (MarkdownDoc): the document in a column
// (helder.markdown's MarkdownView, styled by the shell's look: its
// markdown parts), or its source in a read-only CodeView (Mod+U, the bar's
// button). Its links: "#id" scrolls to that heading, the rest are
// Explorer.follow's (a file the viewer shows, a folder, a web address);
// its images: a relative path decoded as the viewer decodes its files
// (through Files), at most the column's width, laid out at the size its
// header says before (MarkdownDoc.sizes: no shift once decoded); a remote
// one is not fetched (its alt text in its place).
class MarkdownPage implements Markup {
	// (an image decoded at most this large a side: the column's width on a 2x screen)
	static inline var SIDE = 1600;
	// (the column's text width in points: an image at most this wide, else its own pixels' width)
	public static inline var COLUMN = 680;

	public static function make(x:Explorer, d:MarkdownDoc):View {
		var view:Null<MarkdownView> = null;
		view = new MarkdownView({
			doc: d.doc,
			onLink: href -> if (href.startsWith("#")) view.scrollToHeading(MarkdownDoc.unescape(href.substr(1))) else x.follow(d.path, href),
			image: (src, alt) -> image(x, d, src)
		});
		d.view = view;
		var model = new CodeModel(d.text);
		model.readOnly = true;
		var code = new CodeView(model);
		code.currentLine = false;
		code.semantics.label = "Source";
		d.code = code;
		// (opened by a link to one of its headings: there once laid out)
		var first = d.anchor;
		d.anchor = null;
		if (first != null) Clock.add(_ -> {
			view.scrollToHeading(MarkdownDoc.unescape(first));
			false;
		});
		return <view tag="markdown-page" position="absolute" inset={0}>
			<view tag="markdown-doc" grow={1} min-height={0} display={d.source() ? "none" : "flex"}>{view}</view>
			<view tag="markdown-source" grow={1} min-height={0} display={d.source() ? "flex" : "none"}>{code}</view>
		</view>;
	}

	// (an image of the document's folder: at the size its header says, then
	// decoded, its pixels copied out; null: remote or missing, its alt text instead)
	static function image(x:Explorer, d:MarkdownDoc, src:String):Null<Node> {
		var path = d.local(src);
		var e = path == null ? null : x.files.stat(path);
		if (e == null || e.kind == Folder) return null;
		var n = new ImageNode();
		n.style.maxWidth = "100%";
		var s = d.sizes.get(path);
		if (s != null) size(n, s.width, s.height);
		x.viewer.decode(path, SIDE, dec -> {
			if (dec.error != null || dec.frames.length == 0) {
				Decode.release(dec);
				return;
			}
			var rgba = Bytes.alloc(dec.pixelsWidth * dec.pixelsHeight * 4);
			dec.frames[0].pixels.blitToBytes(0, rgba, 0, rgba.length);
			Decode.release(dec);
			size(n, dec.width, dec.height);
			n.image = new Image(dec.pixelsWidth, dec.pixelsHeight, rgba);
		});
		return n;
	}

	static function size(n:ImageNode, width:Int, height:Int) {
		n.style.width = Math.min(width, COLUMN);
		n.style.aspectRatio = width / height;
	}
}
