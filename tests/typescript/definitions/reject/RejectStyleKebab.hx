// A style property in CSS's kebab-case names the camel one markup writes (in TypeScript: style-kebab.tsx).
// expect: markup: flex-wrap is written flexWrap (camel, as CSS's and HTML's are in JavaScript)
class RejectStyleKebab implements helder.view.Markup {
	static function main() {
		helder.view.Render.render(<view flex-wrap="wrap"/>, new helder.ui.Node());
	}
}
