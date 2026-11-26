// An event given twice on one tag is an error naming one handler doing both
// (the renderer would keep one of them).
// expect: HandlerTwice.hx:7: characters 64-71
// expect: markup: onPress is given twice on <button>; one handler: onPress={e -> {a(); b();}}
class HandlerTwice implements helder.view.Markup {
	static function main() {
		helder.view.Render.render(<button onPress={() -> trace("a")} onPress={e -> e.stop()}/>, new helder.ui.Node());
	}
}
