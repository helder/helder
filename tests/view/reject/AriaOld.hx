// What a node is to assistive technology is ARIA's attributes, as HTML
// writes them: helder's old names are errors naming them.
// expect: AriaOld.hx:7: characters 37-42
// expect: markup: label is aria-label (HTML's ARIA attribute)
class AriaOld implements helder.view.Markup {
	static function main() {
		helder.view.Render.render(<button label="Close"/>, new helder.ui.Node());
	}
}
