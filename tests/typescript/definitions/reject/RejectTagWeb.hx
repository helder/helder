// A name outside markup's table is web-only: natively an error when compiled (in TypeScript: tag-web.tsx).
// expect: markup: <table> is web-only (a page's, helder.web's DomRenderer): ui's elements are
class RejectTagWeb implements helder.view.Markup {
	static function main() {
		helder.view.Render.render(<table/>, new helder.ui.Node());
	}
}
