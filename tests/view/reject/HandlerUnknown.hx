// An event its renderer does not declare is an error at its name, listing
// those it does (ui's: a neutral element's).
// expect: HandlerUnknown.hx:7: characters 35-41
// expect: markup: <view> has no event onPres; did you mean onPress?
class HandlerUnknown implements helder.view.Markup {
	static function main() {
		helder.view.Render.render(<view onPres={() -> trace("x")}/>, new helder.ui.Node());
	}
}
