// A page's div is no ui element: natively an error naming the one meant (in TypeScript: tag-div.tsx).
// expect: markup: <div> is no ui element; did you mean <view>?
class RejectTagDiv implements helder.view.Markup {
	static function main() {
		helder.view.Render.render(<div/>, new helder.ui.Node());
	}
}
