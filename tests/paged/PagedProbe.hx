// A program on pages (PagedView): fragmentation in its symbols, so that
// ScreenProbe's check checks something.
class PagedProbe {
	static function main() {
		var v = new helder.ui.box.PagedView(helder.dom.Dom.parse("<p>x</p>"));
		Sys.println(v.layout() > 0 ? "drawn" : "none");
	}
}
