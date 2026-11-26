// A style property in CSS's kebab-case is an error at its name, naming the
// camel one markup writes (as CSS's in JavaScript).
// expect: StyleUnknown.hx:7: characters 35-44
// expect: markup: flex-wrap is written flexWrap (camel, as CSS's and HTML's are in JavaScript)
class StyleUnknown implements helder.view.Markup {
	static function main() {
		helder.view.Render.render(<view flex-wrap="wrap"/>, new helder.ui.Node());
	}
}
