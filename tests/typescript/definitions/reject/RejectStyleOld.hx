// Helder's old name of a style property CSS has names CSS's (in TypeScript: style-old.tsx).
// expect: markup: grow is flexGrow (CSS's name, in camel)
class RejectStyleOld implements helder.view.Markup {
	static function main() {
		helder.view.Render.render(<view grow={1}/>, new helder.ui.Node());
	}
}
