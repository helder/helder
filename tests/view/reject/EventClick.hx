// A ui element's press is onPress (a click, Enter or Space): onClick, a
// page's, is an error naming it.
// expect: EventClick.hx:7: characters 37-44
// expect: markup: onClick is a page's; a ui element's press (a click, Enter or Space) is onPress
class EventClick implements helder.view.Markup {
	static function main() {
		helder.view.Render.render(<button onClick={() -> trace("x")}/>, new helder.ui.Node());
	}
}
