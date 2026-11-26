// HTML's names are elements of their own, no view: or text: before them.
// expect: TagPrefix.hx:6: characters 30-41
// expect: markup: <view:button> is <button> (HTML's names, no prefix)
class TagPrefix implements helder.view.Markup {
	static function main() {
		helder.view.Render.render(<view:button/>, new helder.ui.Node());
	}
}
