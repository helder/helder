// A handler of another event than its renderer gives is an error at the
// attribute, naming both (a neutral element's events are ui's: NodeEvents).
// expect: HandlerType.hx:9: characters 20-51
// expect: markup: onPress's handler takes a String, but <button> (its events ui's, helder.ui.view.NodeEvents) gives onPress a helder.ui.Event: a function of a helder.ui.Event or of none
class HandlerType implements helder.view.Markup {
	static function main() {
		var said = "";
		helder.view.Render.render(<view>
			<button tag="b" onPress={(s:String) -> said = s}>b</button>
		</view>, new helder.ui.Node());
	}
}
