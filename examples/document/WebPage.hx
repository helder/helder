// title: Document
// summary: An HTML page in a window through helder's CSS engine: styled, laid out and painted live, scrolled on the compositor, hovered, selected, its links followed
// tags: ui, css, html
// demo: canvas 1024x768
import helder.canvas.Bitmap;
import helder.dom.Dom;
import helder.ui.box.DocumentNode;
import helder.ui.UiWindow;
import helder.ui.UiWindow.Surface;
import helder.view.*;

// An HTML page shown by helder's one CSS engine (helder.dom, helder.css,
// helder.ui.box) in a helder.ui window (DocumentNode in a scroller): the
// file given (its stylesheets and images read beside it, or by
// sheets.json's URLs to files, as tests/bench fetches the HTML Standard),
// else the page in SamplePage.hx. A link to "#id" scrolls to it; others are
// printed. In a window:
//
//   helder run examples/document -- page.html
class WebPage implements Markup {
	static function main() {
		var page = open(#if sys Sys.args() #else [] #end);
		var node:Null<DocumentNode> = null;
		node = DocumentNode.html(Dom.parse(page.html), {url: page.url, load: page.load, image: page.image});
		node.onLink = (url, a) -> {
			var hash = url.indexOf("#");
			var el = hash >= 0 && url.substr(0, hash) == page.url.split("#")[0] ? node.document.getElementById(url.substr(hash + 1)) : null;
			if (el != null) node.scrollTo(el) else Sys.println(url);
		};
		UiWindow.run(<Surface title="Document" width={1024} height={768}>
			<scroll flexGrow={1} minHeight={0} background="#ffffff">{node}</scroll>
		</Surface>);
	}

	// (the page: its HTML, URL, and the loaders of what it links)
	static function open(args:Array<String>):{html:String, url:String, load:String->Null<String>, image:String->Null<Bitmap>} {
		#if sys
		if (args.length > 0) {
			var file = sys.FileSystem.fullPath(args[0]), dir = haxe.io.Path.directory(file);
			// (beside it, sheets.json: URLs to files, as tests/bench/cascade.mjs fetches them)
			var known:haxe.DynamicAccess<String> = sys.FileSystem.exists('$dir/sheets.json') ? haxe.Json.parse(sys.io.File.getContent('$dir/sheets.json')) : {};
			function local(url:String):Null<String> {
				if (known.exists(url)) return known[url];
				var p = StringTools.startsWith(url, "file://") ? url.substr(7) : url;
				return sys.FileSystem.exists(p) ? p : null;
			}
			var html = sys.io.File.getContent(file);
			// (the page's own URL: its <link rel=canonical>'s when it was fetched, so its sheets' URLs resolve to sheets.json's)
			var canonical = ~/<link[^>]*rel="?canonical"?[^>]*href="([^"]+)"/;
			var url = canonical.match(html) ? canonical.matched(1) : 'file://$file';
			return {
				html: html,
				url: url,
				load: u -> {
					var p = local(u);
					p == null ? null : sys.io.File.getContent(p);
				},
				image: u -> {
					var p = local(u);
					p == null ? null : try Bitmap.fromImage(helder.image.Image.decode(sys.io.File.getBytes(p))) catch (_:Dynamic) null;
				}
			};
		}
		#end
		return {html: SamplePage.HTML, url: "https://example.com/sample.html", load: _ -> null, image: SamplePage.image};
	}
}
