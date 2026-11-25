// HTML's names are elements of their own, no view: or text: before them (in TypeScript: tag-prefix.tsx).
// expect: markup: <view:button> is <button> (HTML's names, no prefix)
class RejectTagPrefix implements helder.view.Markup {
	static function main() {
		helder.view.Render.render(<view:button/>, new helder.ui.Node());
	}
}
