// A page's div is no ui element: natively an error naming the one meant.
// expect: TagDiv.hx:6: characters 30-33
// expect: markup: <div> is no ui element; did you mean <view>?
class TagDiv implements helder.view.Markup {
	static function main() {
		helder.view.Render.render(<div/>, new helder.ui.Node());
	}
}
