// A program that draws a document on a screen alone (DocumentView): the
// paged host's fragmentation (Breaks, BreakToken, PagedView) is not in its
// symbols, css-paged checks.
class ScreenProbe {
	static function main() {
		var png = helder.ui.box.DocumentView.png(helder.dom.Dom.parse("<p>x</p>"), 100, 100);
		Sys.println(png.length > 0 ? "drawn" : "none");
	}
}
