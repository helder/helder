// A name outside markup's table is web-only (a page's element): natively
// an error when compiled, not a throw when it runs.
// expect: TagWeb.hx:7: characters 30-35
// expect: markup: <table> is web-only (a page's, helder.web's DomRenderer): ui's elements are
class TagWeb implements helder.view.Markup {
	static function main() {
		helder.view.Render.render(<table/>, new helder.ui.Node());
	}
}
