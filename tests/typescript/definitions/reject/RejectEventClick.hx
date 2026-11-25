// A ui element's press is onPress: onClick, a page's, names it (in TypeScript: event-click.tsx).
// expect: markup: onClick is a page's; a ui element's press (a click, Enter or Space) is onPress
class RejectEventClick implements helder.view.Markup {
	static function main() {
		helder.view.Render.render(<button onClick={() -> trace("x")}/>, new helder.ui.Node());
	}
}
