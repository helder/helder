// A ref is given its element's node: an image's ImageNode, which a
// function of a TextNode does not take.
// expect: RefType.hx:7: characters
// expect: helder.ui.ImageNode should be helder.ui.TextNode
class RefType implements helder.view.Markup {
	static function main() {
		helder.view.Render.render(<image ref={(t:helder.ui.TextNode) -> t.text = "x"}/>, new helder.ui.Node());
	}
}
