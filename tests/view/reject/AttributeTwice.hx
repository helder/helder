// An attribute given twice, in two spellings of one name, is an error.
// expect: AttributeTwice.hx:6: characters 48-51
// expect: markup: for is given twice on <label>; one value
class AttributeTwice implements helder.view.Markup {
	static function main() {
		helder.view.Render.render(<label htmlFor="a" for="b">A</label>, new helder.ui.Node());
	}
}
