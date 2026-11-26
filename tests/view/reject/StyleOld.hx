// helder's old name of a style property CSS has is an error naming CSS's.
// expect: StyleOld.hx:6: characters 35-39
// expect: markup: grow is flexGrow (CSS's name, in camel)
class StyleOld implements helder.view.Markup {
	static function main() {
		helder.view.Render.render(<view grow={1}/>, new helder.ui.Node());
	}
}
